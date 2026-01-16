#!/bin/bash
#
# Teil 0: Icinga2 Custom Configs kopieren
# 
# Kopiert custom configs nach /data/etc/icinga2/conf.d/
# Muss vor den anderen Init-Scripten ausgeführt werden.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_DIR}/config/icinga2/conf.d"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

log_info "Kopiere Icinga2 Custom Configs..."

# Prüfe ob Container läuft
if ! docker ps --format '{{.Names}}' | grep -q "^icinga2$"; then
    log_warn "Icinga2 Container läuft nicht, überspringe..."
    exit 0
fi

# Warte bis Container bereit ist
sleep 5

# Kopiere Configs
for file in "$CONFIG_DIR"/*.conf; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file")
        docker cp "$file" "icinga2:/data/etc/icinga2/conf.d/${filename}"
        log_success "Kopiert: ${filename}"
    fi
done

# Validiere Config
log_info "Validiere Icinga2 Konfiguration..."
if docker exec icinga2 icinga2 daemon -C 2>&1 | grep -q "Finished validating"; then
    log_success "Konfiguration valide"
else
    log_warn "Konfiguration hat Warnungen (siehe oben)"
fi

# Restart Icinga2 um Configs zu laden
log_info "Starte Icinga2 neu..."
docker restart icinga2

log_success "Icinga2 Configs kopiert und geladen"
