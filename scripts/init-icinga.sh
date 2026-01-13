#!/bin/bash
#
# Icinga Stack Initialization Script
# 
# Dieses Script konfiguriert den Icinga-Stack nach dem ersten Start.
# Es ist idempotent - kann mehrfach ausgeführt werden ohne Probleme.
#
# Nutzung:
#   ./scripts/init-icinga.sh [--dev|--prod]
#
set -euo pipefail

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
API_PASSWORD="${ICINGA_API_PASSWORD:-icinga}"
MAX_RETRIES=30
RETRY_INTERVAL=5

# Parse Argumente
if [[ "${1:-}" == "--dev" ]]; then
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose.dev.yml"
    echo -e "${BLUE}[INFO]${NC} Verwende Development-Konfiguration"
elif [[ "${1:-}" == "--prod" ]]; then
    COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
    echo -e "${BLUE}[INFO]${NC} Verwende Production-Konfiguration"
fi

# Logging-Funktionen
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Prüfe ob Docker läuft
check_docker() {
    if ! docker info &>/dev/null; then
        log_error "Docker ist nicht erreichbar. Bitte Docker starten."
        exit 1
    fi
    log_success "Docker ist erreichbar"
}

# Prüfe ob Container laufen
check_containers() {
    log_info "Prüfe Container-Status..."
    
    local containers=("icinga2" "icingadb" "icingadb-redis" "icinga-postgres" "icingaweb2")
    
    for container in "${containers[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_error "Container '${container}' läuft nicht!"
            log_info "Starte mit: docker compose -f ${COMPOSE_FILE} up -d"
            exit 1
        fi
    done
    
    log_success "Alle Container laufen"
}

# Warte auf Service-Verfügbarkeit
wait_for_service() {
    local service=$1
    local check_cmd=$2
    local retries=0
    
    log_info "Warte auf ${service}..."
    
    while ! eval "$check_cmd" &>/dev/null; do
        retries=$((retries + 1))
        if [[ $retries -ge $MAX_RETRIES ]]; then
            log_error "${service} nicht erreichbar nach ${MAX_RETRIES} Versuchen"
            exit 1
        fi
        echo -n "."
        sleep $RETRY_INTERVAL
    done
    echo ""
    log_success "${service} ist bereit"
}

# Warte auf PostgreSQL
wait_for_postgres() {
    wait_for_service "PostgreSQL" \
        "docker exec icinga-postgres pg_isready -U icinga"
}

# Warte auf Redis
wait_for_redis() {
    wait_for_service "Redis" \
        "docker exec icingadb-redis redis-cli ping"
}

# Warte auf Icinga 2
wait_for_icinga2() {
    wait_for_service "Icinga 2" \
        "docker exec icinga2 icinga2 daemon -C"
}

# Warte auf Icinga 2 API
wait_for_icinga2_api() {
    wait_for_service "Icinga 2 API" \
        "curl -k -s -o /dev/null -w '%{http_code}' -u root:${API_PASSWORD} https://localhost:5665/v1/status | grep -q 200"
}

# Konfiguriere API-User
configure_api_user() {
    log_info "Konfiguriere Icinga 2 API-User..."
    
    # Prüfe ob bereits konfiguriert
    local current_password
    current_password=$(docker exec icinga2 grep -oP 'password = "\K[^"]+' /data/etc/icinga2/conf.d/api-users.conf 2>/dev/null || echo "")
    
    if [[ "$current_password" == "$API_PASSWORD" ]]; then
        log_success "API-User bereits konfiguriert"
        return 0
    fi
    
    # Setze API-Passwort
    docker exec icinga2 bash -c "cat > /data/etc/icinga2/conf.d/api-users.conf << 'EOF'
/**
 * API User für Director und IcingaDB Web
 * Generiert von init-icinga.sh
 */
object ApiUser \"root\" {
  password = \"${API_PASSWORD}\"
  permissions = [ \"*\" ]
}
EOF"
    
    log_success "API-User konfiguriert (Passwort: ${API_PASSWORD})"
}

# Aktiviere IcingaDB Feature
configure_icingadb() {
    log_info "Konfiguriere IcingaDB Feature..."
    
    # Prüfe ob bereits aktiviert
    if docker exec icinga2 test -f /data/etc/icinga2/features-enabled/icingadb.conf 2>/dev/null; then
        # Prüfe ob korrekt konfiguriert
        if docker exec icinga2 grep -q "icingadb-redis" /data/etc/icinga2/features-enabled/icingadb.conf 2>/dev/null; then
            log_success "IcingaDB Feature bereits konfiguriert"
            return 0
        fi
    fi
    
    # Aktiviere Feature
    docker exec icinga2 icinga2 feature enable icingadb 2>/dev/null || true
    
    # Konfiguriere Redis-Verbindung
    docker exec icinga2 bash -c 'cat > /data/etc/icinga2/features-enabled/icingadb.conf << EOF
/**
 * IcingaDB Feature Konfiguration
 * Generiert von init-icinga.sh
 */
object IcingaDB "icingadb" {
  host = "icingadb-redis"
  port = 6379
}
EOF'
    
    log_success "IcingaDB Feature aktiviert und konfiguriert"
}

# Starte Icinga 2 neu falls nötig
restart_icinga2_if_needed() {
    log_info "Prüfe ob Icinga 2 Neustart nötig..."
    
    # Validiere Konfiguration
    if ! docker exec icinga2 icinga2 daemon -C &>/dev/null; then
        log_error "Icinga 2 Konfiguration ungültig!"
        docker exec icinga2 icinga2 daemon -C
        exit 1
    fi
    
    # Neustart
    docker restart icinga2
    log_success "Icinga 2 neugestartet"
    
    # Warte bis API bereit ist (längere Wartezeit nach Neustart)
    sleep 10
    wait_for_icinga2_api
}

# Führe Director-Migration aus
run_director_migration() {
    log_info "Führe Director-Datenbankmigrationen aus..."
    
    # Warte kurz bis IcingaWeb2 bereit ist
    sleep 5
    
    # Migration ausführen
    if docker exec icingaweb2 icingacli director migration run 2>&1 | grep -q "error"; then
        log_warn "Director-Migration hatte Warnungen (möglicherweise bereits ausgeführt)"
    else
        log_success "Director-Migration abgeschlossen"
    fi
}

# Führe Director-Kickstart aus
run_director_kickstart() {
    log_info "Führe Director-Kickstart aus..."
    
    # Aktualisiere Kickstart-Konfiguration mit korrektem Passwort
    docker exec icingaweb2 bash -c "cat > /etc/icingaweb2/modules/director/kickstart.ini << EOF
[config]
endpoint = icinga2
host = icinga2
port = 5665
username = root
password = ${API_PASSWORD}
EOF"
    
    # Kickstart ausführen
    local output
    output=$(docker exec icingaweb2 icingacli director kickstart run 2>&1) || true
    
    if echo "$output" | grep -q "already been imported\|Trying to recreate"; then
        log_success "Director-Kickstart bereits ausgeführt"
    elif echo "$output" | grep -q "error\|Error"; then
        log_warn "Director-Kickstart: $output"
    else
        log_success "Director-Kickstart abgeschlossen"
    fi
    
    # Korrigiere API-Passwort in der Director-Datenbank
    # (Kickstart übernimmt das Passwort vom Icinga 2 Container, nicht von kickstart.ini)
    docker exec icinga-postgres psql -U icinga -d director -c \
        "UPDATE icinga_apiuser SET password = '${API_PASSWORD}' WHERE object_name = 'root';" &>/dev/null || true
    
    # Setze Director Deployment-Timeouts
    docker exec icinga-postgres psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('deployment_timeout', '120') ON CONFLICT (setting_name) DO UPDATE SET setting_value = '120';" &>/dev/null || true
    docker exec icinga-postgres psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('config_sync_timeout', '30') ON CONFLICT (setting_name) DO UPDATE SET setting_value = '30';" &>/dev/null || true
    
    log_success "Director API-Credentials und Timeouts synchronisiert"
}

# Deploye Director-Konfiguration
deploy_director_config() {
    log_info "Deploye Director-Konfiguration..."
    
    # Warte zusätzlich auf API nach Neustart
    log_info "Warte auf Icinga 2 API (nach Neustart)..."
    sleep 5
    wait_for_icinga2_api
    
    local output
    local retry=0
    local max_retries=3
    
    while [ $retry -lt $max_retries ]; do
        log_info "Deployment-Versuch $((retry + 1))/$max_retries..."
        
        # Deploy ohne timeout (macOS hat kein timeout)
        output=$(docker exec icingaweb2 icingacli director config deploy 2>&1) || true
        
        if echo "$output" | grep -qi "has been deployed\|Nothing to deploy\|matches last deployed\|Config matches"; then
            log_success "Director-Konfiguration deployed"
            return 0
        elif echo "$output" | grep -qi "Unable to authenticate"; then
            log_warn "API-Authentifizierung fehlgeschlagen, korrigiere Passwort..."
            docker exec icinga-postgres psql -U icinga -d director -c \
                "UPDATE icinga_apiuser SET password = '${API_PASSWORD}' WHERE object_name = 'root';" &>/dev/null
            retry=$((retry + 1))
            sleep 5
        elif echo "$output" | grep -qi "timeout\|timed out"; then
            log_warn "Deployment-Timeout, warte auf Icinga 2..."
            retry=$((retry + 1))
            sleep 10
        else
            # Wenn output leer oder unbekannt, zeige es an
            if [ -n "$output" ]; then
                log_warn "Unbekannte Antwort: $output"
            fi
            retry=$((retry + 1))
            sleep 5
        fi
    done
    
    log_error "Director-Deploy fehlgeschlagen nach $max_retries Versuchen"
    log_info "Das ist oft nur ein Timing-Problem. Führe manuell aus:"
    log_info "  docker exec icingaweb2 icingacli director config deploy"
    log_info ""
    log_info "Das Monitoring sollte trotzdem funktionieren!"
}

# Hilfsfunktion: Erstelle Host-Template im Director
create_host_template() {
    local name=$1
    local json=$2
    local output
    
    output=$(docker exec icingaweb2 icingacli director host create "$name" --json "$json" 2>&1) || true
    
    if echo "$output" | grep -q "has been created"; then
        log_success "Host-Vorlage '${name}' erstellt"
    elif echo "$output" | grep -qE "already exists|DuplicateKeyException"; then
        log_success "Host-Vorlage '${name}' existiert bereits"
    else
        log_warn "Host-Vorlage '${name}': $output"
    fi
}

# Hilfsfunktion: Erstelle Service-Template im Director
create_service_template() {
    local name=$1
    local json=$2
    local output
    
    output=$(docker exec icingaweb2 icingacli director service create "$name" --json "$json" 2>&1) || true
    
    if echo "$output" | grep -q "has been created"; then
        log_success "Service-Vorlage '${name}' erstellt"
    elif echo "$output" | grep -qE "already exists|DuplicateKeyException"; then
        log_success "Service-Vorlage '${name}' existiert bereits"
    else
        log_warn "Service-Vorlage '${name}': $output"
    fi
}

# Erstelle Director-Vorlagen (Templates)
create_director_templates() {
    log_info "Erstelle Director-Vorlagen..."
    
    # ═══════════════════════════════════════════════════════════════
    # BASIS HOST-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "director-host" \
        '{"object_type":"template","check_command":"hostalive","check_interval":"60","retry_interval":"30","max_check_attempts":3}'
    
    # ═══════════════════════════════════════════════════════════════
    # LINUX HOST-VORLAGE
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "linux-host" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Linux","enable_ssh":true,"enable_disk":true,"enable_load":true,"enable_procs":true,"enable_memory":true,"enable_users":true}}'
    
    # ═══════════════════════════════════════════════════════════════
    # WINDOWS HOST-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "windows-snmp-host" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Windows","snmp_community":"public","snmp_version":"2c","enable_snmp_cpu":true,"enable_snmp_memory":true,"enable_snmp_disk":true,"enable_snmp_uptime":true,"enable_snmp_interfaces":true}}'
    
    # ═══════════════════════════════════════════════════════════════
    # NETZWERK-GERÄTE VORLAGE
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "network-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Network","snmp_community":"public","snmp_version":"2c"}}'
    
    # ═══════════════════════════════════════════════════════════════
    # BROADCAST/STREAMING GERÄTE (Radio/TV)
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "broadcast-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Broadcast","device_type":"broadcast"}}'
    
    # ═══════════════════════════════════════════════════════════════
    # PEARL EPIPHAN GERÄTE
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "epiphan-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Epiphan","device_type":"epiphan","epiphan_api_port":80,"enable_epiphan_status":true,"enable_epiphan_channels":true,"enable_epiphan_recorder":true}}'
    
    # ═══════════════════════════════════════════════════════════════
    # AUDIO-GERÄTE VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_host_template "audio-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Audio","device_type":"audio"}}'
    
    create_host_template "dante-device" \
        '{"object_type":"template","imports":["audio-device"],"check_command":"hostalive","vars":{"device_type":"dante","dante_port":4440,"enable_dante_network":true}}'
    
    create_host_template "wireless-microphone" \
        '{"object_type":"template","imports":["audio-device"],"check_command":"hostalive","vars":{"device_type":"wireless-mic","enable_battery_check":true,"enable_rf_signal":true,"battery_warning":30,"battery_critical":10,"rf_warning":-70,"rf_critical":-80}}'
    
    # ═══════════════════════════════════════════════════════════════
    # BASIS SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "director-service" \
        '{"object_type":"template","check_interval":"60","retry_interval":"30","max_check_attempts":3}'
    
    create_service_template "critical-service" \
        '{"object_type":"template","imports":["director-service"],"check_interval":"30","retry_interval":"10","max_check_attempts":5}'
    
    create_service_template "lowfreq-service" \
        '{"object_type":"template","imports":["director-service"],"check_interval":"300","retry_interval":"60","max_check_attempts":3}'
    
    # ═══════════════════════════════════════════════════════════════
    # LINUX SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "linux-ssh" \
        '{"object_type":"template","imports":["director-service"],"check_command":"ssh"}'
    
    create_service_template "linux-disk" \
        '{"object_type":"template","imports":["director-service"],"check_command":"disk","vars":{"disk_wfree":"20%","disk_cfree":"10%"}}'
    
    create_service_template "linux-load" \
        '{"object_type":"template","imports":["director-service"],"check_command":"load","vars":{"load_wload1":"5","load_cload1":"10"}}'
    
    create_service_template "linux-memory" \
        '{"object_type":"template","imports":["director-service"],"check_command":"swap"}'
    
    create_service_template "linux-procs" \
        '{"object_type":"template","imports":["director-service"],"check_command":"procs"}'
    
    # ═══════════════════════════════════════════════════════════════
    # WINDOWS SERVICE-VORLAGEN (SNMP)
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "windows-cpu" \
        '{"object_type":"template","imports":["director-service"],"check_command":"snmp","vars":{"snmp_oid":"1.3.6.1.2.1.25.3.3.1.2"}}'
    
    create_service_template "windows-memory" \
        '{"object_type":"template","imports":["director-service"],"check_command":"snmp","vars":{"snmp_oid":"1.3.6.1.2.1.25.2.2"}}'
    
    create_service_template "windows-uptime" \
        '{"object_type":"template","imports":["lowfreq-service"],"check_command":"snmp-uptime"}'
    
    # ═══════════════════════════════════════════════════════════════
    # NETZWERK SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "http-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"http"}'
    
    create_service_template "https-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"http","vars":{"http_ssl":true}}'
    
    create_service_template "tcp-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"tcp"}'
    
    create_service_template "ping-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"ping4"}'
    
    # ═══════════════════════════════════════════════════════════════
    # BROADCAST/STREAMING SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "icecast-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"http","vars":{"http_uri":"/status-json.xsl","http_string":"icestats"}}'
    
    create_service_template "stream-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"http"}'
    
    # ═══════════════════════════════════════════════════════════════
    # APPLIKATIONS SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "vimp-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"http","vars":{"http_uri":"/api/health","http_ssl":true}}'
    
    create_service_template "panopto-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"http","vars":{"http_uri":"/Panopto/Pages/Home.aspx","http_ssl":true}}'
    
    create_service_template "mairlist-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"tcp","vars":{"tcp_port":9000}}'
    
    create_service_template "stereotool-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"tcp"}'
    
    create_service_template "micrompx-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"tcp"}'
    
    # ═══════════════════════════════════════════════════════════════
    # AUDIO/VIDEO DEVICE SERVICE-VORLAGEN
    # ═══════════════════════════════════════════════════════════════
    
    create_service_template "epiphan-webui" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"http","vars":{"http_uri":"/"}}'
    
    create_service_template "dante-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"tcp","vars":{"tcp_port":4440}}'
    
    create_service_template "mic-battery" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"snmp","vars":{"snmp_warn":"30:","snmp_crit":"10:"}}'
    
    create_service_template "process-check" \
        '{"object_type":"template","imports":["critical-service"],"check_command":"procs","vars":{"procs_warning":"1:","procs_critical":"1:"}}'
    
    log_success "Alle Director-Vorlagen erstellt"
}

# Entferne Standard-Localhost-Checks
remove_default_checks() {
    log_info "Entferne Standard-Localhost-Checks..."
    
    # Die benutzerdefinierten Konfigurationsdateien ersetzen die Standard-Hosts/Services
    # Diese werden über copy_custom_configs() kopiert
    
    log_success "Standard-Checks werden durch benutzerdefinierte Konfiguration ersetzt"
}

# Kopiere benutzerdefinierte Konfigurationsdateien
copy_custom_configs() {
    log_info "Kopiere benutzerdefinierte Konfigurationsdateien..."
    
    local config_dir="${PROJECT_DIR}/config/icinga2"
    # Icinga Docker Image lädt aus /etc/icinga2/conf.d (symlink nach /data/etc/icinga2/conf.d)
    # Wir kopieren in beide Pfade um sicherzugehen
    local icinga_conf_dir="/etc/icinga2/conf.d"
    local icinga_data_dir="/data/etc/icinga2/conf.d"
    
    # Dateien die kopiert werden sollen
    local config_files=("commands.conf" "templates.conf" "services.conf" "hosts.conf" "notifications.conf")
    
    for file in "${config_files[@]}"; do
        if [[ -f "${config_dir}/${file}" ]]; then
            docker cp "${config_dir}/${file}" "icinga2:${icinga_conf_dir}/${file}"
            docker cp "${config_dir}/${file}" "icinga2:${icinga_data_dir}/${file}" 2>/dev/null || true
            log_success "Kopiert: ${file}"
        fi
    done
    
    # Auch Dateien aus conf.d kopieren (falls vorhanden und nicht leer)
    if [[ -d "${config_dir}/conf.d" ]]; then
        for file in "${config_dir}/conf.d"/*.conf; do
            if [[ -f "$file" ]]; then
                local filename=$(basename "$file")
                # Nur kopieren wenn nicht die leeren Platzhalter
                if ! grep -q "Leere Datei\|werden über.*Director" "$file" 2>/dev/null; then
                    docker cp "$file" "icinga2:${icinga_conf_dir}/${filename}"
                    docker cp "$file" "icinga2:${icinga_data_dir}/${filename}" 2>/dev/null || true
                    log_success "Kopiert: conf.d/${filename}"
                fi
            fi
        done
    fi
    
    # Features kopieren
    if [[ -d "${config_dir}/features" ]]; then
        for file in "${config_dir}/features"/*.conf; do
            if [[ -f "$file" ]]; then
                local filename=$(basename "$file")
                docker cp "$file" "icinga2:/data/etc/icinga2/features-available/${filename}"
                log_success "Kopiert: features/${filename}"
            fi
        done
    fi
    
    log_success "Benutzerdefinierte Konfiguration kopiert"
}

# Zeige Status
show_status() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Icinga Stack erfolgreich initialisiert!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}Icinga Web 2:${NC}  http://localhost:8080"
    echo -e "  ${BLUE}Grafana:${NC}       http://localhost:3000"
    echo -e "  ${BLUE}Prometheus:${NC}    http://localhost:9090"
    echo ""
    echo -e "  ${BLUE}Login:${NC}         icingaadmin / admin"
    echo ""
    echo -e "  ${YELLOW}Host-Vorlagen erstellt:${NC}"
    echo "  - director-host      (Basis-Vorlage)"
    echo "  - linux-host         (Linux Server mit SSH, Disk, Load, etc.)"
    echo "  - windows-snmp-host  (Windows Server via SNMP)"
    echo "  - network-device     (Netzwerkgeräte via SNMP)"
    echo "  - broadcast-device   (Radio/TV Encoder, Streaming)"
    echo "  - epiphan-device     (Pearl Epiphan Encoder/Recorder)"
    echo "  - audio-device       (Audio-Geräte Basis)"
    echo "  - dante-device       (Dante Netzwerk-Audio)"
    echo "  - wireless-microphone (Funkmikrofone mit Batterie/RF)"
    echo ""
    echo -e "  ${YELLOW}Service-Vorlagen erstellt:${NC}"
    echo "  - director-service   (Basis-Vorlage)"
    echo "  - critical-service   (Kritische Services, 30s Check)"
    echo "  - lowfreq-service    (Seltene Checks, 5 Min.)"
    echo "  - linux-ssh/disk/load/memory/procs"
    echo "  - windows-cpu/memory/uptime"
    echo "  - http-check, https-check, tcp-check, ping-check"
    echo "  - icecast-check, stream-check"
    echo "  - vimp-check, panopto-check, mairlist-check"
    echo "  - stereotool-check, micrompx-check"
    echo "  - epiphan-webui, dante-check, mic-battery"
    echo "  - process-check"
    echo ""
    echo -e "  ${YELLOW}Nächster Schritt:${NC}"
    echo "  Host hinzufügen: siehe docs/HOST_HINZUFUEGEN.md"
    echo ""
}

# Hauptprogramm
main() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Icinga Stack Initialization${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    check_docker
    check_containers
    
    echo ""
    log_info "Warte auf Services..."
    wait_for_postgres
    wait_for_redis
    wait_for_icinga2
    
    echo ""
    log_info "Konfiguriere Icinga 2..."
    configure_api_user
    configure_icingadb
    remove_default_checks
    copy_custom_configs
    restart_icinga2_if_needed
    
    echo ""
    log_info "Konfiguriere Icinga Director..."
    run_director_migration
    run_director_kickstart
    create_director_templates
    deploy_director_config
    
    show_status
}

# Starte Hauptprogramm
main "$@"
