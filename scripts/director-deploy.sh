#!/bin/bash
#
# Director Deploy Fix - Wenn Ausrollen im Web-Interface hängt
#
# Nutzung:
#   ./scripts/director-deploy.sh
#

set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Director Deploy - Quick Fix${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Prüfe ob Icinga 2 läuft
echo -e "${BLUE}[1/5]${NC} Prüfe Icinga 2 Status..."
if ! docker exec icinga2 icinga2 daemon -C &>/dev/null; then
    echo -e "${RED}✗${NC} Icinga 2 Konfiguration ungültig!"
    echo "Führe aus: docker exec icinga2 icinga2 daemon -C"
    exit 1
fi
echo -e "${GREEN}✓${NC} Icinga 2 Config ist valide"

# 2. Prüfe ob API erreichbar
echo -e "${BLUE}[2/5]${NC} Prüfe Icinga 2 API..."
if curl -k -s -u root:icinga "https://localhost:5665/v1/status" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Icinga 2 API erreichbar"
else
    echo -e "${YELLOW}⚠${NC} Icinga 2 API nicht erreichbar, warte 10 Sekunden..."
    sleep 10
fi

# 3. Prüfe Director Timeouts
echo -e "${BLUE}[3/5]${NC} Prüfe Director Timeout-Einstellungen..."
timeout=$(docker exec icinga-postgres psql -U icinga -d director -t -c \
    "SELECT setting_value FROM director_setting WHERE setting_name = 'deployment_timeout';" 2>/dev/null | tr -d ' \n' || echo "0")

if [ "$timeout" -lt "60" ]; then
    echo -e "${YELLOW}⚠${NC} Deployment-Timeout zu niedrig ($timeout), setze auf 120..."
    docker exec icinga-postgres psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('deployment_timeout', '120') ON CONFLICT (setting_name) DO UPDATE SET setting_value = '120';" &>/dev/null
    docker exec icinga-postgres psql -U icinga -d director -c \
        "INSERT INTO director_setting (setting_name, setting_value) VALUES ('config_sync_timeout', '30') ON CONFLICT (setting_name) DO UPDATE SET setting_value = '30';" &>/dev/null
    echo -e "${GREEN}✓${NC} Timeouts angepasst"
else
    echo -e "${GREEN}✓${NC} Timeouts OK (deployment_timeout: ${timeout}s)"
fi

# 4. Prüfe ob Deploy nötig ist
echo -e "${BLUE}[4/5]${NC} Prüfe ob Änderungen vorhanden..."
changes=$(docker exec icingaweb2 icingacli director config show 2>&1 || echo "")
if echo "$changes" | grep -q "No configuration available"; then
    echo -e "${YELLOW}⚠${NC} Keine Konfiguration zum Deployen"
    exit 0
fi

# 5. Deploy ausführen
echo -e "${BLUE}[5/5]${NC} Führe Deployment aus..."
echo ""
echo -e "${YELLOW}Hinweis:${NC} CLI wartet max 60 Sekunden auf Bestätigung"
echo ""

# Deploy mit Timeout
if timeout 60 docker exec icingaweb2 icingacli director config deploy 2>&1; then
    echo ""
    echo -e "${GREEN}✓${NC} Deployment erfolgreich!"
    
    # Zeige Deployment-Info
    echo ""
    echo -e "${BLUE}Deployment-Details:${NC}"
    docker exec icingaweb2 icingacli director deployment show --format json 2>/dev/null | head -20 || true
else
    exit_code=$?
    echo ""
    
    if [ $exit_code -eq 124 ]; then
        # Timeout
        echo -e "${YELLOW}⚠${NC} CLI-Timeout nach 60 Sekunden"
        echo ""
        echo "Das bedeutet NICHT dass der Deploy fehlgeschlagen ist!"
        echo "Icinga 2 könnte die Config noch laden..."
        echo ""
        echo -e "${BLUE}Warte 10 Sekunden und prüfe Icinga 2...${NC}"
        sleep 10
        
        if docker exec icinga2 icinga2 daemon -C &>/dev/null; then
            echo -e "${GREEN}✓${NC} Icinga 2 Config ist valide - Deploy vermutlich erfolgreich!"
            
            # Prüfe letztes Deployment
            echo ""
            echo -e "${BLUE}Letztes Deployment:${NC}"
            docker exec icingaweb2 icingacli director deployment show --format json 2>/dev/null | grep -E '"stage_name"|"start_time"|"duration_dump"' | head -5 || true
        else
            echo -e "${RED}✗${NC} Icinga 2 Config-Fehler nach Deploy!"
            echo ""
            echo "Führe aus um Details zu sehen:"
            echo "  docker exec icinga2 icinga2 daemon -C"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} Deploy fehlgeschlagen (Exit Code: $exit_code)"
        exit $exit_code
    fi
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deploy abgeschlossen!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Icinga Web 2: http://localhost:8080"
echo ""
