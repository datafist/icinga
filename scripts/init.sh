#!/bin/bash
#
# Icinga Stack Initialization Runner
# 
# Ein einziger Einstiegspunkt für die Stack-Initialisierung.
# Führt die Teil-Skripte in Reihenfolge aus.
#
# Nutzung:
#   ./scripts/init.sh              # Vollständige Initialisierung
#   ./scripts/init.sh --skip-objects  # Ohne Director-Objekte
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Konfiguration aus Umgebung
export ICINGA_API_USER="${ICINGA_API_USER:-root}"
export ICINGA_API_PASSWORD="${ICINGA_API_PASSWORD:-icinga}"
export MAX_RETRIES="${MAX_RETRIES:-30}"
export RETRY_INTERVAL="${RETRY_INTERVAL:-5}"

# Flags
SKIP_OBJECTS=false

for arg in "$@"; do
    case $arg in
        --skip-objects) SKIP_OBJECTS=true ;;
        --help|-h)
            echo "Nutzung: $0 [--skip-objects]"
            echo ""
            echo "Optionen:"
            echo "  --skip-objects  Überspringe Director-Objekte (nur Kickstart)"
            exit 0
            ;;
    esac
done

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# Warte auf Service
wait_for() {
    local name=$1
    local cmd=$2
    local retries=0
    
    log_info "Warte auf ${name}..."
    while ! eval "$cmd" &>/dev/null; do
        retries=$((retries + 1))
        if [[ $retries -ge $MAX_RETRIES ]]; then
            log_error "${name} nicht erreichbar nach ${MAX_RETRIES} Versuchen"
            exit 1
        fi
        echo -n "."
        sleep "$RETRY_INTERVAL"
    done
    echo ""
    log_success "${name} bereit"
}

# Prüfe Docker
check_docker() {
    if ! docker info &>/dev/null; then
        log_error "Docker nicht erreichbar"
        exit 1
    fi
}

# Prüfe Container
check_containers() {
    local containers=("icinga2" "icingadb" "icingadb-redis" "postgres" "icingaweb2")
    for c in "${containers[@]}"; do
        # Erlaube auch icinga-postgres als Alias
        if ! docker ps --format '{{.Names}}' | grep -qE "^${c}$|^icinga-${c}$"; then
            log_error "Container '${c}' läuft nicht"
            exit 1
        fi
    done
    log_success "Alle Container laufen"
}

# Führe Teil-Skript aus
run_part() {
    local script=$1
    local name=$2
    
    if [[ ! -x "$script" ]]; then
        log_error "Skript nicht gefunden oder nicht ausführbar: $script"
        exit 1
    fi
    
    log_step "$name"
    if ! "$script"; then
        log_error "$name fehlgeschlagen"
        exit 1
    fi
    log_success "$name abgeschlossen"
}

# === MAIN ===
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Icinga Stack Initialization${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

check_docker
check_containers

# Warte auf Services
wait_for "PostgreSQL" "docker exec postgres pg_isready -U icinga 2>/dev/null || docker exec icinga-postgres pg_isready -U icinga"
wait_for "Redis" "docker exec icingadb-redis redis-cli ping"
wait_for "Icinga 2" "docker exec icinga2 icinga2 daemon -C"

# Konfiguriere API-User mit bekanntem Passwort
log_info "Konfiguriere API-User..."
docker exec icinga2 sh -c "cat > /data/etc/icinga2/conf.d/api-users.conf << 'EOF'
/**
 * API User mit bekanntem Passwort für Director und Scripte
 */
object ApiUser \"root\" {
  password = \"icinga\"
  permissions = [ \"*\" ]
}
EOF"
docker exec icinga2 icinga2 daemon -C &>/dev/null && docker exec icinga2 pkill -SIGHUP icinga2 || docker restart icinga2
sleep 5
log_success "API-User konfiguriert"

wait_for "Icinga 2 API" "curl -k -s -o /dev/null -w '%{http_code}' -u ${ICINGA_API_USER}:${ICINGA_API_PASSWORD} https://localhost:5665/v1/status | grep -q 200"
wait_for "IcingaWeb2" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 | grep -qE '200|302'"

# Prüfe ob Director-Daemon Container läuft (wichtig für Deployment-Status)
if docker ps --format '{{.Names}}' | grep -q "director-daemon"; then
    log_success "Director-Daemon Container läuft"
else
    log_info "Director-Daemon Container wird gestartet..."
    # Ermittle welche compose-Datei verwendet wird
    if [[ -f "${SCRIPT_DIR}/../docker-compose.dev.yml" ]]; then
        (cd "${SCRIPT_DIR}/.." && docker compose -f docker-compose.dev.yml up -d director-daemon) &>/dev/null || true
    else
        (cd "${SCRIPT_DIR}/.." && docker compose up -d director-daemon) &>/dev/null || true
    fi
    sleep 5
    if docker ps --format '{{.Names}}' | grep -q "director-daemon"; then
        log_success "Director-Daemon Container gestartet"
    else
        log_info "Director-Daemon nicht verfügbar - Deployment-Status wird manuell gesetzt"
    fi
fi

# Teil 1: Director Kickstart
run_part "${SCRIPT_DIR}/01-director-kickstart.sh" "Director Kickstart"

# Teil 2: Director Objects (optional)
if [[ "$SKIP_OBJECTS" == "false" ]]; then
    run_part "${SCRIPT_DIR}/02-director-objects.sh" "Director Objects"
fi

# Teil 3: Director Deploy
run_part "${SCRIPT_DIR}/03-director-deploy.sh" "Director Deploy"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Initialisierung abgeschlossen!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}Icinga Web 2:${NC}  http://localhost:8080"
echo -e "  ${BLUE}Grafana:${NC}       http://localhost:3000"
echo -e "  ${BLUE}Prometheus:${NC}    http://localhost:9090"
echo ""
echo -e "  ${BLUE}Login:${NC}         icingaadmin / admin"
echo ""
