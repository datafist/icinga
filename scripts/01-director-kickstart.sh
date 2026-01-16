#!/bin/bash
#
# Teil 1: Director Kickstart
# 
# - Konfiguriert API-User in Icinga 2
# - Aktiviert IcingaDB Feature
# - Führt Director Migration + Kickstart aus
# - Setzt Director-Timeouts
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

API_USER="${ICINGA_API_USER:-root}"
API_PASSWORD="${ICINGA_API_PASSWORD:-icinga}"

# PostgreSQL Container-Name ermitteln (postgres oder icinga-postgres)
get_postgres_container() {
    if docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
        echo "postgres"
    else
        echo "icinga-postgres"
    fi
}

POSTGRES_CONTAINER=$(get_postgres_container)

# === API User konfigurieren ===
configure_api_user() {
    log_info "Konfiguriere Icinga 2 API-User..."
    
    local current_pw
    current_pw=$(docker exec icinga2 grep -oP 'password = "\K[^"]+' /data/etc/icinga2/conf.d/api-users.conf 2>/dev/null || echo "")
    
    if [[ "$current_pw" == "$API_PASSWORD" ]]; then
        log_success "API-User bereits korrekt konfiguriert"
        return 0
    fi
    
    docker exec icinga2 bash -c "cat > /data/etc/icinga2/conf.d/api-users.conf << 'APIEOF'
/**
 * API User für Director und IcingaDB Web
 */
object ApiUser \"${API_USER}\" {
  password = \"${API_PASSWORD}\"
  permissions = [ \"*\" ]
}
APIEOF"
    
    log_success "API-User konfiguriert"
}

# === IcingaDB Feature aktivieren ===
configure_icingadb() {
    log_info "Konfiguriere IcingaDB Feature..."
    
    if docker exec icinga2 grep -q "icingadb-redis" /data/etc/icinga2/features-enabled/icingadb.conf 2>/dev/null; then
        log_success "IcingaDB Feature bereits konfiguriert"
        return 0
    fi
    
    docker exec icinga2 icinga2 feature enable icingadb 2>/dev/null || true
    
    docker exec icinga2 bash -c 'cat > /data/etc/icinga2/features-enabled/icingadb.conf << EOF
object IcingaDB "icingadb" {
  host = "icingadb-redis"
  port = 6379
}
EOF'
    
    log_success "IcingaDB Feature aktiviert"
}

# === Icinga 2 neustarten ===
restart_icinga2() {
    log_info "Starte Icinga 2 neu..."
    
    if ! docker exec icinga2 icinga2 daemon -C &>/dev/null; then
        log_warn "Icinga 2 Konfiguration ungültig!"
        docker exec icinga2 icinga2 daemon -C
        return 1
    fi
    
    docker restart icinga2
    sleep 10
    
    # Warte auf API
    local retries=0
    while ! curl -k -s -o /dev/null -u "${API_USER}:${API_PASSWORD}" https://localhost:5665/v1/status; do
        retries=$((retries + 1))
        [[ $retries -ge 30 ]] && return 1
        sleep 2
    done
    
    log_success "Icinga 2 neugestartet"
}

# === Director Migration ===
run_director_migration() {
    log_info "Führe Director-Migration aus..."
    
    local output
    output=$(docker exec icingaweb2 icingacli director migration run 2>&1) || true
    
    if echo "$output" | grep -qi "error"; then
        log_warn "Director-Migration: $output"
    else
        log_success "Director-Migration abgeschlossen"
    fi
}

# === Director Kickstart ===
run_director_kickstart() {
    log_info "Führe Director-Kickstart aus..."
    
    # Kickstart-Config schreiben
    docker exec icingaweb2 bash -c "cat > /etc/icingaweb2/modules/director/kickstart.ini << EOF
[config]
endpoint = icinga2
host = icinga2
port = 5665
username = ${API_USER}
password = ${API_PASSWORD}
EOF"
    
    local output
    output=$(docker exec icingaweb2 icingacli director kickstart run 2>&1) || true
    
    if echo "$output" | grep -q "already been imported"; then
        log_success "Director-Kickstart bereits durchgeführt"
    elif echo "$output" | grep -qi "error"; then
        log_warn "Director-Kickstart: $output"
    else
        log_success "Director-Kickstart abgeschlossen"
    fi
    
    # API-Passwort in Director-DB synchronisieren
    docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
        "UPDATE icinga_apiuser SET password = '${API_PASSWORD}' WHERE object_name = '${API_USER}';" &>/dev/null || true
    
    # Deployment-Timeouts setzen
    docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('deployment_timeout', '120') 
         ON CONFLICT (setting_name) DO UPDATE SET setting_value = '120';" &>/dev/null || true
    docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('config_sync_timeout', '30') 
         ON CONFLICT (setting_name) DO UPDATE SET setting_value = '30';" &>/dev/null || true
    
    log_success "Director-Einstellungen synchronisiert"
}

# === MAIN ===
configure_api_user
configure_icingadb
restart_icinga2
run_director_migration
run_director_kickstart

log_success "Director Kickstart abgeschlossen"
