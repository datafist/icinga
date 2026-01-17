#!/bin/bash
#
# Teil 2: Director Objects
# 
# Legt Director-Basisobjekte idempotent an:
# - Commands (NRPE, tcp, http)
# - Data Fields
# - Host/Service Templates
# - Host/Service Groups
# - Service Sets
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

# === Helper: Data Field erstellen via SQL ===
create_datafield() {
    local varname=$1
    local caption=$2
    local datatype=${3:-"Icinga\\\\Module\\\\Director\\\\DataType\\\\DataTypeString"}
    
    # Data Fields müssen via SQL erstellt werden, da kein CLI-Befehl existiert
    local result
    result=$(docker exec icinga-postgres psql -U icinga -d director -t -c \
        "INSERT INTO director_datafield (varname, caption, datatype) 
         VALUES ('${varname}', '${caption}', '${datatype}') 
         ON CONFLICT (varname) DO NOTHING 
         RETURNING varname;" 2>&1) || true
    
    if echo "$result" | grep -q "$varname"; then
        log_success "Data Field '${varname}' erstellt"
    else
        log_success "Data Field '${varname}' existiert bereits"
    fi
}

# === Helper: Host/Service Group erstellen ===
create_hostgroup() {
    local name=$1
    local display=$2
    director_create "hostgroup" "$name" "{\"object_name\":\"${name}\",\"display_name\":\"${display}\"}"
}

create_servicegroup() {
    local name=$1
    local display=$2
    director_create "servicegroup" "$name" "{\"object_name\":\"${name}\",\"display_name\":\"${display}\"}"
}

# ============================================================
# COMMANDS
# ============================================================
create_commands() {
    log_info "Erstelle Commands..."
    
    # NRPE Command (generisch)
    director_create "command" "check_nrpe" \
        '{"object_type":"object","command":"check_nrpe","methods_execute":"PluginCheck","arguments":{"--host":{"value":"$address$","order":1},"--command":{"value":"$nrpe_command$","order":2},"--args":{"value":"$nrpe_arguments$","skip_key":true,"repeat_key":false,"order":3}}}'
    
    # Die folgenden Commands existieren bereits als Built-ins, aber wir stellen sicher dass sie da sind
    # check_tcp und check_http sind in ITL bereits vorhanden
}

# ============================================================
# DATA FIELDS
# ============================================================
create_datafields() {
    log_info "Erstelle Data Fields..."
    
    # NRPE
    create_datafield "nrpe_command" "NRPE Command"
    create_datafield "nrpe_arguments" "NRPE Arguments"
    
    # Disk (konsistent mit ThresholdDefaults in templates.conf)
    create_datafield "disk_warning" "Disk Warning % (Default: 80)"
    create_datafield "disk_critical" "Disk Critical % (Default: 90)"
    create_datafield "disk_partition" "Disk Partition"
    
    # Load (konsistent mit ThresholdDefaults)
    create_datafield "load_warning" "Load Warning (Default: 5,4,3)"
    create_datafield "load_critical" "Load Critical (Default: 10,8,6)"
    
    # Memory (konsistent mit ThresholdDefaults)
    create_datafield "memory_warning" "Memory Warning % (Default: 80)"
    create_datafield "memory_critical" "Memory Critical % (Default: 90)"
    
    # Swap (konsistent mit ThresholdDefaults)
    create_datafield "swap_warning" "Swap Warning % (Default: 50)"
    create_datafield "swap_critical" "Swap Critical % (Default: 80)"
    
    # Procs (konsistent mit ThresholdDefaults)
    create_datafield "procs_warning" "Procs Warning (Default: 250)"
    create_datafield "procs_critical" "Procs Critical (Default: 400)"
    
    # Users
    create_datafield "users_warning" "Users Warning (Default: 5)"
    create_datafield "users_critical" "Users Critical (Default: 10)"
    
    # Ping/Network
    create_datafield "ping_wrta" "Ping Warning RTT ms (Default: 100)"
    create_datafield "ping_crta" "Ping Critical RTT ms (Default: 500)"
    create_datafield "ping_wpl" "Ping Warning Packet Loss % (Default: 5)"
    create_datafield "ping_cpl" "Ping Critical Packet Loss % (Default: 10)"
    
    # HTTP
    create_datafield "http_warn_time" "HTTP Warning Time s (Default: 5)"
    create_datafield "http_critical_time" "HTTP Critical Time s (Default: 15)"
}

# ============================================================
# HOST TEMPLATES
# ============================================================
create_host_templates() {
    log_info "Erstelle Host Templates..."
    
    # Basis-Template (bereits vorhanden, aber sicherstellen)
    director_create "host" "director-host" \
        '{"object_type":"template","check_command":"hostalive","check_interval":"60","retry_interval":"30","max_check_attempts":3}'
    
    # Linux Host Template mit Default-Thresholds (konsistent mit templates.conf)
    director_create "host" "tpl-host-linux" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Linux","disk_warning":"80","disk_critical":"90","load_warning":"5,4,3","load_critical":"10,8,6","memory_warning":"80","memory_critical":"90","swap_warning":"50","swap_critical":"80","procs_warning":"250","procs_critical":"400","users_warning":"5","users_critical":"10"}}'
    
    # Bestehende Templates beibehalten (importieren jetzt tpl-host-linux)
    director_create "host" "linux-host" \
        '{"object_type":"template","imports":["tpl-host-linux"],"vars":{"enable_ssh":true,"enable_disk":true,"enable_load":true,"enable_procs":true,"enable_memory":true}}'
    
    # Windows mit Default-Thresholds
    director_create "host" "windows-snmp-host" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Windows","snmp_community":"public","snmp_version":"2c","disk_warning":"80","disk_critical":"90","memory_warning":"80","memory_critical":"90"}}'
    
    director_create "host" "network-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Network","snmp_community":"public","snmp_version":"2c","ping_wrta":"100","ping_crta":"500"}}'
    
    director_create "host" "broadcast-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Broadcast","device_type":"broadcast","ping_wrta":"50","ping_crta":"200"}}'
    
    director_create "host" "epiphan-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Epiphan","device_type":"epiphan","http_warn_time":"3","http_critical_time":"10"}}'
    
    director_create "host" "audio-device" \
        '{"object_type":"template","imports":["director-host"],"check_command":"hostalive","vars":{"os":"Audio","device_type":"audio"}}'
    
    director_create "host" "dante-device" \
        '{"object_type":"template","imports":["audio-device"],"check_command":"hostalive","vars":{"device_type":"dante","dante_port":4440}}'
    
    director_create "host" "wireless-microphone" \
        '{"object_type":"template","imports":["audio-device"],"check_command":"hostalive","vars":{"device_type":"wireless-mic","battery_warning":30,"battery_critical":10}}'
}

# ============================================================
# SERVICE TEMPLATES
# ============================================================
create_service_templates() {
    log_info "Erstelle Service Templates..."
    
    # Basis
    director_create "service" "director-service" \
        '{"object_type":"template","check_interval":"60","retry_interval":"30","max_check_attempts":3}'
    
    director_create "service" "critical-service" \
        '{"object_type":"template","imports":["director-service"],"check_interval":"30","retry_interval":"10","max_check_attempts":5}'
    
    director_create "service" "lowfreq-service" \
        '{"object_type":"template","imports":["director-service"],"check_interval":"300","retry_interval":"60","max_check_attempts":3}'
    
# NRPE Service Templates
    director_create "service" "nrpe-disk" \
        '{"object_type":"template","imports":["director-service"],"check_command":"check_nrpe","vars":{"nrpe_command":"check_disk","nrpe_arguments":"-w $disk_warning$ -c $disk_critical$ -p $disk_partition$"}}'

    director_create "service" "nrpe-load" \
        '{"object_type":"template","imports":["director-service"],"check_command":"check_nrpe","vars":{"nrpe_command":"check_load","nrpe_arguments":"-w $load_warning$ -c $load_critical$"}}'

    director_create "service" "nrpe-memory" \
        '{"object_type":"template","imports":["director-service"],"check_command":"check_nrpe","vars":{"nrpe_command":"check_mem","nrpe_arguments":"-w $memory_warning$ -c $memory_critical$"}}'
    
director_create "service" "nrpe-swap" \
        '{"object_type":"template","imports":["director-service"],"check_command":"check_nrpe","vars":{"nrpe_command":"check_swap","nrpe_arguments":"-w $swap_warning$ -c $swap_critical$"}}'

    director_create "service" "nrpe-procs" \
        '{"object_type":"template","imports":["director-service"],"check_command":"check_nrpe","vars":{"nrpe_command":"check_procs","nrpe_arguments":"-w $procs_warning$ -c $procs_critical$"}}'
    
    # Bestehende Templates beibehalten
    director_create "service" "linux-ssh" \
        '{"object_type":"template","imports":["director-service"],"check_command":"ssh"}'
    
    director_create "service" "linux-disk" \
        '{"object_type":"template","imports":["director-service"],"check_command":"disk","vars":{"disk_wfree":"20%","disk_cfree":"10%"}}'
    
    director_create "service" "linux-load" \
        '{"object_type":"template","imports":["director-service"],"check_command":"load","vars":{"load_wload1":"5","load_cload1":"10"}}'
    
    director_create "service" "http-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"http"}'
    
    director_create "service" "https-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"http","vars":{"http_ssl":true}}'
    
    director_create "service" "tcp-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"tcp"}'
    
    director_create "service" "ping-check" \
        '{"object_type":"template","imports":["director-service"],"check_command":"ping4"}'
}

# ============================================================
# HOST GROUPS
# ============================================================
# Hinweis: linux-servers und windows-servers werden NICHT erstellt,
# da Icinga2 diese bereits in /etc/icinga2/conf.d/groups.conf definiert hat
# mit nützlichen "assign where" Regeln.
create_hostgroups() {
    log_info "Erstelle Host Groups..."
    
    # Diese Gruppen sind Icinga2-Standard, nicht im Director erstellen:
    # - linux-servers (assign where host.vars.os == "Linux")
    # - windows-servers (assign where host.vars.os == "Windows")
    
    create_hostgroup "network-devices" "Network Devices"
    create_hostgroup "webapps" "Web Applications"
    create_hostgroup "av-devices" "Audio/Video Devices"
}

# ============================================================
# SERVICE GROUPS
# ============================================================
create_servicegroups() {
    log_info "Erstelle Service Groups..."
    
    create_servicegroup "linux-system" "Linux System Checks"
    create_servicegroup "network-availability" "Network Availability"
    create_servicegroup "web-availability" "Web Availability"
}

# ============================================================
# SERVICE SETS
# ============================================================
create_service_sets() {
    log_info "Erstelle Service Sets..."
    
    local output
    
    # === Linux Base NRPE Set ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "linux-base-nrpe" --json \
        '{"object_name":"linux-base-nrpe","object_type":"template","description":"Basic Linux checks via NRPE"}' 2>&1) || true
    
    if echo "$output" | grep -q "has been created"; then
        log_success "Service Set 'linux-base-nrpe' erstellt"
    elif echo "$output" | grep -qE "already exists|DuplicateKeyException"; then
        log_success "Service Set 'linux-base-nrpe' existiert bereits"
    else
        log_warn "Service Set 'linux-base-nrpe': $output"
    fi
    
    # Services zum Set hinzufügen
    director_create "service" "Disk /" \
        '{"object_name":"Disk /","object_type":"object","imports":["nrpe-disk"],"service_set":"linux-base-nrpe","vars":{"disk_partition":"/"}}'
    
    director_create "service" "Load" \
        '{"object_name":"Load","object_type":"object","imports":["nrpe-load"],"service_set":"linux-base-nrpe"}'
    
    director_create "service" "Memory" \
        '{"object_name":"Memory","object_type":"object","imports":["nrpe-memory"],"service_set":"linux-base-nrpe"}'
    
    director_create "service" "Swap" \
        '{"object_name":"Swap","object_type":"object","imports":["nrpe-swap"],"service_set":"linux-base-nrpe"}'
    
    director_create "service" "Procs" \
        '{"object_name":"Procs","object_type":"object","imports":["nrpe-procs"],"service_set":"linux-base-nrpe"}'
    
    # === Linux Network Set ===
    output=$(docker exec icingaweb2 icingacli director serviceset create "linux-network" --json \
        '{"object_name":"linux-network","object_type":"template","description":"Linux network checks"}' 2>&1) || true
    
    if echo "$output" | grep -q "has been created"; then
        log_success "Service Set 'linux-network' erstellt"
    elif echo "$output" | grep -qE "already exists|DuplicateKeyException"; then
        log_success "Service Set 'linux-network' existiert bereits"
    else
        log_warn "Service Set 'linux-network': $output"
    fi
    
    director_create "service" "SSH" \
        '{"object_name":"SSH","object_type":"object","imports":["tcp-check"],"service_set":"linux-network","vars":{"tcp_port":22}}'
    
    director_create "service" "Ping" \
        '{"object_name":"Ping","object_type":"object","imports":["ping-check"],"service_set":"linux-network"}'
}

# === MAIN ===
create_commands
create_datafields
create_host_templates
create_service_templates
create_hostgroups
create_servicegroups
create_service_sets

log_success "Director Objects abgeschlossen"
