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
    
    log_success "Director API-Credentials synchronisiert"
}

# Deploye Director-Konfiguration
deploy_director_config() {
    log_info "Deploye Director-Konfiguration..."
    
    local output
    output=$(docker exec icingaweb2 icingacli director config deploy 2>&1) || true
    
    if echo "$output" | grep -q "has been deployed\|Nothing to deploy\|matches last deployed"; then
        log_success "Director-Konfiguration deployed"
    elif echo "$output" | grep -q "Unable to authenticate"; then
        log_error "API-Authentifizierung fehlgeschlagen!"
        log_info "Versuche Passwort in Director-DB zu korrigieren..."
        docker exec icinga-postgres psql -U icinga -d director -c \
            "UPDATE icinga_apiuser SET password = '${API_PASSWORD}' WHERE object_name = 'root';" &>/dev/null
        # Retry
        output=$(docker exec icingaweb2 icingacli director config deploy 2>&1) || true
        if echo "$output" | grep -q "has been deployed\|Nothing to deploy\|matches last deployed"; then
            log_success "Director-Konfiguration deployed (nach Fix)"
        else
            log_warn "Director-Deploy: $output"
        fi
    else
        log_warn "Director-Deploy: $output"
    fi
}

# Entferne Standard-Localhost-Checks
remove_default_checks() {
    log_info "Entferne Standard-Localhost-Checks..."
    
    # Prüfe ob bereits leer
    local hosts_content
    hosts_content=$(docker exec icinga2 cat /data/etc/icinga2/conf.d/hosts.conf 2>/dev/null || echo "")
    
    if echo "$hosts_content" | grep -q "Director\|Hosts werden über"; then
        log_success "Standard-Checks bereits entfernt"
        return 0
    fi
    
    # Leere die Dateien
    docker exec icinga2 bash -c 'echo "// Hosts werden über Icinga Director verwaltet" > /data/etc/icinga2/conf.d/hosts.conf'
    docker exec icinga2 bash -c 'echo "// Services werden über Icinga Director verwaltet" > /data/etc/icinga2/conf.d/services.conf'
    
    log_success "Standard-Localhost-Checks entfernt"
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
    echo -e "  ${YELLOW}Nächste Schritte:${NC}"
    echo "  1. Öffne Icinga Web 2 und logge dich ein"
    echo "  2. Gehe zu 'Icinga Director' → 'Host Templates' → 'Add'"
    echo "  3. Erstelle Hosts und Services über den Director"
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
    restart_icinga2_if_needed
    
    echo ""
    log_info "Konfiguriere Icinga Director..."
    run_director_migration
    run_director_kickstart
    deploy_director_config
    
    show_status
}

# Starte Hauptprogramm
main "$@"
