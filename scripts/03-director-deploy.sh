#!/bin/bash
#
# Teil 3: Director Deploy
# 
# Führt Director-Deployment aus mit Retry-Logik.
#
set -euo pipefail

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

API_USER="${ICINGA_API_USER:-root}"
API_PASSWORD="${ICINGA_API_PASSWORD:-icinga}"

# PostgreSQL Container-Name ermitteln
get_postgres_container() {
    if docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
        echo "postgres"
    else
        echo "icinga-postgres"
    fi
}

POSTGRES_CONTAINER=$(get_postgres_container)

# === Deploy mit Retry ===
deploy_director_config() {
    log_info "Deploye Director-Konfiguration..."
    
    # Erst alte pending Deployments bereinigen
    docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
        "UPDATE director_deployment_log SET stage_collected = 'y', startup_succeeded = 'n' WHERE startup_succeeded IS NULL;" &>/dev/null || true
    
    local output
    local retry=0
    local max_retries=3
    
    while [ $retry -lt $max_retries ]; do
        log_info "Deployment-Versuch $((retry + 1))/$max_retries..."
        
        output=$(docker exec icingaweb2 icingacli director config deploy 2>&1) || true
        
        if echo "$output" | grep -qi "has been deployed\|Nothing to deploy\|matches last deployed\|Config matches"; then
            log_success "Director-Konfiguration deployed"
            
            # Warte kurz und prüfe ob Stage aktiviert wurde
            sleep 5
            
            # Prüfe ob Director-Package eine aktive Stage hat
            local packages_json
            packages_json=$(curl -k -s -u "${API_USER}:${API_PASSWORD}" \
                "https://localhost:5665/v1/config/packages" -H "Accept: application/json" 2>/dev/null) || true
            
            # Extrahiere active-stage für director package mit jq falls verfügbar, sonst grep
            local active_stage=""
            if command -v jq &>/dev/null; then
                active_stage=$(echo "$packages_json" | jq -r '.results[] | select(.name=="director") | .["active-stage"]' 2>/dev/null) || true
            else
                active_stage=$(echo "$packages_json" | grep -o '"name":"director"[^}]*' | grep -o '"active-stage":"[^"]*"' | cut -d'"' -f4) || true
            fi
            
            if [ -z "$active_stage" ] || [ "$active_stage" == "null" ]; then
                log_warn "Director-Stage noch nicht aktiv, starte Icinga2 neu..."
                docker restart icinga2 || true
                sleep 10
                
                # Aktualisiere Deployment-Status
                docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
                    "UPDATE director_deployment_log SET stage_collected = 'y', startup_succeeded = 'y' WHERE startup_succeeded IS NULL;" &>/dev/null || true
                
                log_success "Icinga2 neugestartet und Deployment-Status aktualisiert"
            else
                log_info "Director-Stage aktiv: $active_stage"
            fi
            
            return 0
        elif echo "$output" | grep -qi "Unable to authenticate"; then
            log_warn "API-Authentifizierung fehlgeschlagen, korrigiere Passwort..."
            docker exec "$POSTGRES_CONTAINER" psql -U icinga -d director -c \
                "UPDATE icinga_apiuser SET password = '${API_PASSWORD}' WHERE object_name = '${API_USER}';" &>/dev/null
            retry=$((retry + 1))
            sleep 5
        elif echo "$output" | grep -qi "timeout\|timed out"; then
            log_warn "Deployment-Timeout, warte..."
            retry=$((retry + 1))
            sleep 10
        else
            if [ -n "$output" ]; then
                log_warn "Antwort: $output"
            fi
            retry=$((retry + 1))
            sleep 5
        fi
    done
    
    log_error "Deploy fehlgeschlagen nach $max_retries Versuchen"
    log_info "Manuell ausführen: docker exec icingaweb2 icingacli director config deploy"
    return 1
}

# === MAIN ===
deploy_director_config
log_success "Director Deploy abgeschlossen"
