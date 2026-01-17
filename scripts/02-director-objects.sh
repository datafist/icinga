#!/bin/bash
#
# Teil 2: Director Objects
# 
# Legt Director-Basisobjekte idempotent an.
# Prinzipien:
# - Minimal: Nur was wirklich gebraucht wird
# - Konsistent: Einheitliche Namenskonventionen
# - Erweiterbar: Einfach neue Geräte hinzufügen
#
# Namenskonvention:
#   Host Templates:  tpl-<typ>         (z.B. tpl-linux, tpl-epiphan)
#   Service Templates: svc-<check>     (z.B. svc-nrpe-disk, svc-https)
#   Service Sets:    set-<zweck>       (z.B. set-nrpe, set-ping)
#   Host Groups:     grp-<kategorie>   (z.B. grp-pearls, grp-studio1)
#
set -euo pipefail

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# === Helper: Director CLI Wrapper ===
director_create() {
    local type=$1
    local name=$2
    local json=$3
    local output
    
    output=$(docker exec icingaweb2 icingacli director "$type" create "$name" --json "$json" 2>&1) || true
    
    if echo "$output" | grep -q "has been created"; then
        log_success "${type^} '${name}' erstellt"
    elif echo "$output" | grep -qE "already exists|DuplicateKeyException"; then
        log_success "${type^} '${name}' existiert bereits"
    else
        log_warn "${type^} '${name}': $output"
    fi
}

# === Helper: Data Field via SQL (kein CLI verfügbar) ===
create_datafield() {
    local varname=$1
    local caption=$2
    
    local result
    result=$(docker exec icinga-postgres psql -U icinga -d director -t -c \
        "INSERT INTO director_datafield (varname, caption, datatype) 
         VALUES ('${varname}', '${caption}', 'Icinga\\Module\\Director\\DataType\\DataTypeString') 
         ON CONFLICT (varname) DO NOTHING 
         RETURNING varname;" 2>&1) || true
    
    if echo "$result" | grep -q "$varname"; then
        log_success "Data Field '${varname}' erstellt"
    else
        log_success "Data Field '${varname}' existiert bereits"
    fi
}

# === Helper: Host Group erstellen ===
create_hostgroup() {
    local name=$1
    local display=$2
    director_create "hostgroup" "$name" "{\"object_name\":\"${name}\",\"display_name\":\"${display}\"}"
}

# ============================================================
# COMMANDS
# ============================================================
create_commands() {
    log_info "Erstelle Commands..."
    
    # NRPE Command - custom, um Konflikt mit ITL 'nrpe' zu vermeiden
    director_create "command" "check_nrpe_custom" \
        '{"object_type":"object","command":"check_nrpe","methods_execute":"PluginCheck","arguments":{"-H":{"value":"$address$","order":1},"-c":{"value":"$nrpe_command$","order":2}}}'
}

# ============================================================
# DATA FIELDS (nur was wirklich gebraucht wird)
# ============================================================
create_datafields() {
    log_info "Erstelle Data Fields..."
    
    # NRPE - wird in allen NRPE-Services verwendet
    create_datafield "nrpe_command" "NRPE Command Name"
    
    # Epiphan Pearl - für REST API Zugriff
    create_datafield "epiphan_user" "Epiphan API User"
    create_datafield "epiphan_pass" "Epiphan API Password"
    
    # Streaming - für Icecast/Shoutcast Checks
    create_datafield "stream_port" "Stream Port (z.B. 8000)"
    create_datafield "stream_mount" "Stream Mount (z.B. /live)"
    
    # Standort/Funktion - für automatische Host Group Zuweisung
    create_datafield "studio" "Studio Nummer (1 oder 2)"
    create_datafield "role" "Rolle (z.B. playout, encoder)"
}

# ============================================================
# HOST TEMPLATES (8 Templates - konsolidiert)
# Hierarchie: tpl-base → tpl-<os> oder tpl-<gerät>
# ============================================================
create_host_templates() {
    log_info "Erstelle Host Templates..."
    
    # === BASIS ===
    director_create "host" "tpl-base" \
        '{"object_type":"template","check_command":"hostalive","check_interval":"60","retry_interval":"30","max_check_attempts":"3"}'
    
    # === BETRIEBSSYSTEME ===
    # Linux Server - NRPE Agent
    director_create "host" "tpl-linux" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"os":"Linux"}}'
    
    # Windows Server - Icinga Agent
    # Für mAirList: vars.role = "playout" beim Host setzen
    director_create "host" "tpl-windows" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"os":"Windows"}}'
    
    # macOS Client - NRPE Agent
    director_create "host" "tpl-macos" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"os":"macOS"}}'
    
    # === NETZWERK ===
    director_create "host" "tpl-switch" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"device":"switch"}}'
    
    # === AV/BROADCAST GERÄTE ===
    # Generisch für: Shure, Maxhub, MicroMPX, etc.
    # Spezifischer device-Typ wird beim Host gesetzt
    director_create "host" "tpl-av-device" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"device":"av"}}'
    
    # Epiphan Pearl - HTTP + API Credentials
    director_create "host" "tpl-epiphan" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"device":"epiphan","epiphan_user":"admin","epiphan_pass":"admin"}}'
    
    # === STREAMING ===
    director_create "host" "tpl-stream" \
        '{"object_type":"template","imports":["tpl-linux"],"vars":{"device":"icecast","stream_port":"8000","stream_mount":"/live"}}'
    
    # === WEB ===
    director_create "host" "tpl-web" \
        '{"object_type":"template","imports":["tpl-base"],"vars":{"device":"web"}}'
}

# ============================================================
# SERVICE TEMPLATES
# Namenskonvention: svc-<protokoll>-<was> oder svc-<was>
# ============================================================
create_service_templates() {
    log_info "Erstelle Service Templates..."
    
    # === BASIS ===
    director_create "service" "svc-base" \
        '{"object_type":"template","check_interval":"60","retry_interval":"30","max_check_attempts":"3"}'
    
    director_create "service" "svc-critical" \
        '{"object_type":"template","imports":["svc-base"],"check_interval":"30","retry_interval":"10","max_check_attempts":"5"}'
    
    # === NRPE CHECKS ===
    # Nutzt check_nrpe_custom (unser Command), Thresholds in nrpe.cfg auf Host
    director_create "service" "svc-nrpe-disk" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"check_nrpe_custom","vars":{"nrpe_command":"check_disk"}}'

    director_create "service" "svc-nrpe-load" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"check_nrpe_custom","vars":{"nrpe_command":"check_load"}}'

    director_create "service" "svc-nrpe-memory" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"check_nrpe_custom","vars":{"nrpe_command":"check_mem"}}'
    
    director_create "service" "svc-nrpe-procs" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"check_nrpe_custom","vars":{"nrpe_command":"check_procs"}}'
    
    # === HTTP CHECKS ===
    director_create "service" "svc-http" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"http"}'
    
    director_create "service" "svc-https" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"http","vars":{"http_ssl":true}}'
    
    director_create "service" "svc-ssl-cert" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"http","vars":{"http_ssl":true,"http_certificate":"30"}}'
    
    # === STREAMING ===
    director_create "service" "svc-icecast" \
        '{"object_type":"template","imports":["svc-critical"],"check_command":"http","vars":{"http_port":"$stream_port$","http_uri":"$stream_mount$"}}'
    
    # === BASIC CHECKS ===
    director_create "service" "svc-ping" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"ping4"}'
    
    director_create "service" "svc-tcp" \
        '{"object_type":"template","imports":["svc-base"],"check_command":"tcp"}'
}

# ============================================================
# HOST GROUPS mit Assign Filter
# Filter basiert auf vars.device oder vars.studio
# ============================================================
create_hostgroups() {
    log_info "Erstelle Host Groups..."
    
    # Nach Gerätetyp - automatische Zuweisung via vars.device
    director_create "hostgroup" "grp-pearls" \
        '{"object_name":"grp-pearls","display_name":"Epiphan Pearls","assign_filter":"host.vars.device=%22epiphan%22"}'
    
    director_create "hostgroup" "grp-av-devices" \
        '{"object_name":"grp-av-devices","display_name":"AV Geräte","assign_filter":"host.vars.device=%22av%22"}'
    
    director_create "hostgroup" "grp-switches" \
        '{"object_name":"grp-switches","display_name":"Netzwerk Switches","assign_filter":"host.vars.device=%22switch%22"}'
    
    director_create "hostgroup" "grp-web" \
        '{"object_name":"grp-web","display_name":"Web Plattformen","assign_filter":"host.vars.device=%22web%22"}'
    
    director_create "hostgroup" "grp-streaming" \
        '{"object_name":"grp-streaming","display_name":"Streaming Infrastruktur","assign_filter":"host.vars.device=%22icecast%22"}'
    
    # Nach Standort - Zuweisung via vars.studio
    director_create "hostgroup" "grp-studio1" \
        '{"object_name":"grp-studio1","display_name":"Studio 1","assign_filter":"host.vars.studio=%221%22"}'
    
    director_create "hostgroup" "grp-studio2" \
        '{"object_name":"grp-studio2","display_name":"Studio 2","assign_filter":"host.vars.studio=%222%22"}'
    
    # OS-basierte Gruppen
    director_create "hostgroup" "grp-linux" \
        '{"object_name":"grp-linux","display_name":"Linux Server","assign_filter":"host.vars.os=%22Linux%22"}'
    
    director_create "hostgroup" "grp-windows" \
        '{"object_name":"grp-windows","display_name":"Windows Server","assign_filter":"host.vars.os=%22Windows%22"}'
    
    director_create "hostgroup" "grp-macos" \
        '{"object_name":"grp-macos","display_name":"macOS Clients","assign_filter":"host.vars.os=%22macOS%22"}'
}

# ============================================================
# SERVICE SETS
# Bündeln Services die zusammen auf Hosts angewendet werden
# ============================================================
create_service_sets() {
    log_info "Erstelle Service Sets..."
    
    local output
    
    # === NRPE Base (Linux/macOS) ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "set-nrpe" --json \
        '{"object_name":"set-nrpe","object_type":"template","description":"Standard NRPE Checks (Disk, Load, Memory, Procs)"}' 2>&1) || true
    if echo "$output" | grep -qE "created|exists"; then log_success "Service Set 'set-nrpe' OK"; fi
    
    director_create "service" "Disk" \
        '{"object_name":"Disk","object_type":"object","imports":["svc-nrpe-disk"],"service_set":"set-nrpe"}'
    director_create "service" "Load" \
        '{"object_name":"Load","object_type":"object","imports":["svc-nrpe-load"],"service_set":"set-nrpe"}'
    director_create "service" "Memory" \
        '{"object_name":"Memory","object_type":"object","imports":["svc-nrpe-memory"],"service_set":"set-nrpe"}'
    director_create "service" "Procs" \
        '{"object_name":"Procs","object_type":"object","imports":["svc-nrpe-procs"],"service_set":"set-nrpe"}'
    
    # === Ping Only (einfache Geräte) ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "set-ping" --json \
        '{"object_name":"set-ping","object_type":"template","description":"Nur Erreichbarkeit prüfen"}' 2>&1) || true
    if echo "$output" | grep -qE "created|exists"; then log_success "Service Set 'set-ping' OK"; fi
    
    director_create "service" "Ping" \
        '{"object_name":"Ping","object_type":"object","imports":["svc-ping"],"service_set":"set-ping"}'
    
    # === Web Plattform (HTTPS + SSL) ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "set-web" --json \
        '{"object_name":"set-web","object_type":"template","description":"HTTPS Erreichbarkeit + SSL Zertifikat"}' 2>&1) || true
    if echo "$output" | grep -qE "created|exists"; then log_success "Service Set 'set-web' OK"; fi
    
    director_create "service" "HTTPS" \
        '{"object_name":"HTTPS","object_type":"object","imports":["svc-https"],"service_set":"set-web"}'
    director_create "service" "SSL Zertifikat" \
        '{"object_name":"SSL Zertifikat","object_type":"object","imports":["svc-ssl-cert"],"service_set":"set-web"}'
    
    # === Epiphan Pearl ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "set-epiphan" --json \
        '{"object_name":"set-epiphan","object_type":"template","description":"Epiphan Pearl Web UI Check"}' 2>&1) || true
    if echo "$output" | grep -qE "created|exists"; then log_success "Service Set 'set-epiphan' OK"; fi
    
    director_create "service" "Web UI" \
        '{"object_name":"Web UI","object_type":"object","imports":["svc-http"],"service_set":"set-epiphan"}'
    
    # === Stream Server ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "set-stream" --json \
        '{"object_name":"set-stream","object_type":"template","description":"Icecast Stream Check"}' 2>&1) || true
    if echo "$output" | grep -qE "created|exists"; then log_success "Service Set 'set-stream' OK"; fi
    
    director_create "service" "Stream" \
        '{"object_name":"Stream","object_type":"object","imports":["svc-icecast"],"service_set":"set-stream"}'
}

# === MAIN ===
log_info "=== Director Objects Setup ==="
create_commands
create_datafields
create_host_templates
create_service_templates
create_hostgroups
create_service_sets

log_success "Director Objects abgeschlossen"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                    ONBOARDING CHEATSHEET"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "HOST TEMPLATES (8):                SERVICE SETS:"
echo "  tpl-linux    → Linux + NRPE        set-nrpe    (Disk,Load,Mem,Procs)"
echo "  tpl-windows  → Windows + Agent     set-ping    (nur Ping)"
echo "  tpl-macos    → macOS + NRPE        set-web     (HTTPS + SSL Cert)"
echo "  tpl-switch   → Netzwerk Switch     set-epiphan (Web UI)"
echo "  tpl-av-device→ AV Geräte           set-stream  (Icecast Check)"
echo "  tpl-epiphan  → Epiphan Pearl"
echo "  tpl-stream   → Stream Server"
echo "  tpl-web      → Web Plattform"
echo ""
echo "AUTOMATISCHE GRUPPIERUNG via vars:"
echo "  vars.device=\"epiphan\"  → grp-pearls"
echo "  vars.device=\"av\"       → grp-av-devices"
echo "  vars.device=\"switch\"   → grp-switches"
echo "  vars.device=\"web\"      → grp-web"
echo "  vars.device=\"icecast\"  → grp-streaming"
echo "  vars.studio=\"1\"        → grp-studio1"
echo "  vars.studio=\"2\"        → grp-studio2"
echo "  vars.os=\"Linux|Windows|macOS\" → grp-linux|windows|macos"
echo ""
echo "BEISPIEL - Host anlegen:"
echo "  Name: pearl-studio1-cam1"
echo "  Template: tpl-epiphan"
echo "  Address: 192.168.1.100"
echo "  Vars: studio=1"
echo "  Service Set: set-epiphan"
echo "  → Wird automatisch in grp-pearls UND grp-studio1 einsortiert"
echo "════════════════════════════════════════════════════════════════"
