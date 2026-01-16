# 🚀 Walkthrough: Icinga Monitoring Stack Setup

Dieses Dokument führt dich Schritt für Schritt durch das komplette Setup des Icinga Monitoring Stacks.

## Inhaltsverzeichnis

1. [Voraussetzungen](#1-voraussetzungen)
2. [Installation](#2-installation)
3. [Erster Test](#3-erster-test)
4. [Host hinzufügen (Director)](#4-host-hinzufügen-director)
5. [Host hinzufügen (Konfiguration)](#5-host-hinzufügen-konfiguration)
6. [Grafana Dashboard](#6-grafana-dashboard)
7. [Thresholds anpassen](#7-thresholds-anpassen)

---

## 1. Voraussetzungen

### Benötigte Software

```bash
# Docker Version prüfen (min. 24.x)
docker --version

# Docker Compose Version prüfen (min. v2)
docker compose version

# Git prüfen
git --version
```

### Systemressourcen

- **RAM:** Mindestens 4 GB verfügbar
- **Disk:** Mindestens 10 GB frei
- **CPU:** 2+ Kerne empfohlen

---

## 2. Installation

### Schritt 2.1: Repository klonen

```bash
git clone git@github.com:datafist/icinga.git
cd icinga
```

### Schritt 2.2: Umgebungsvariablen

```bash
cp .env.example .env
# Optional: Passwörter anpassen
nano .env
```

### Schritt 2.3: Stack starten

```bash
docker compose -f docker-compose.dev.yml up -d
```

Warte bis alle Container laufen:

```bash
docker compose -f docker-compose.dev.yml ps
```

Erwartete Ausgabe:
```
NAME               STATUS
blackbox-exporter  running
grafana            running
icinga-postgres    running (healthy)
icinga2            running
icinga2-exporter   running
icingadb           running
icingadb-redis     running (healthy)
icingaweb2         running
prometheus         running
```

### Schritt 2.4: Initialisierung

**Warte 30-60 Sekunden** nach dem Start, dann:

```bash
./scripts/init.sh
```

Das Script führt 4 Phasen aus:
1. ✅ Kopiert Custom-Configs (Templates, Services, Thresholds)
2. ✅ Director Kickstart (API-User, IcingaDB, Migration)
3. ✅ Director Objects (Templates, Data Fields, Groups)
4. ✅ Director Deploy

> **Hinweis:** Warnungen bei "Data Fields" und "Service Sets" sind bekannte Limitierungen der CLI und können ignoriert werden.

---

## 3. Erster Test

### Icinga Web 2 öffnen

1. Öffne http://localhost:8080
2. Login: `icingaadmin` / `admin`
3. Du siehst das Dashboard mit 0 Hosts (noch keine Monitoring-Ziele)

### Grafana öffnen

1. Öffne http://localhost:3000
2. Login: `admin` / `admin` (erstes Mal Passwort ändern)
3. Gehe zu **Dashboards** → **NOC - Infrastructure Monitor**

### API testen

```bash
curl -ks -u root:icinga https://localhost:5665/v1/status | head -c 200
```

Erwartete Ausgabe: JSON mit Status-Informationen.

---

## 4. Host hinzufügen (Director)

Der Director ist die empfohlene Methode für die Host-Verwaltung.

### Schritt 4.1: Director öffnen

1. In Icinga Web 2 → **Icinga Director** → **Hosts**
2. Klicke auf **+ Add**

### Schritt 4.2: Host anlegen

| Feld | Wert |
|------|------|
| Hostname | `test-server` |
| Object Type | Host |
| Imports | `linux-host` (für Linux-Server) |
| Host address | `192.168.1.100` (oder IP deines Servers) |

### Schritt 4.3: Custom Variables (Optional)

Unter **Custom properties** kannst du Threshold-Variablen überschreiben:

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `disk_warning` | `70` | Warnung bei 70% Disk-Nutzung |
| `disk_critical` | `85` | Kritisch bei 85% |
| `load_warning` | `8,6,4` | Load 1/5/15 Minuten |

### Schritt 4.4: Speichern & Deployen

1. Klicke **Store**
2. Gehe zu **Activity log** (oben rechts, blaue Zahl)
3. Klicke **Deploy pending changes**

### Schritt 4.5: Host prüfen

1. Gehe zu **Overview** → **Hosts**
2. Der neue Host sollte erscheinen
3. Nach ca. 1 Minute werden die ersten Check-Ergebnisse angezeigt

---

## 5. Host hinzufügen (Konfiguration)

Alternative zur Director-Methode: Direkt in der Konfigurationsdatei.

### Schritt 5.1: Hosts-Datei bearbeiten

```bash
nano config/icinga2/conf.d/hosts.conf
```

### Schritt 5.2: Host hinzufügen

```icinga2
/* Neuer Linux-Server */
object Host "my-server" {
  import "linux-host"
  address = "192.168.1.100"
  
  /* Optional: Thresholds überschreiben */
  vars.disk_warning = 70
  vars.disk_critical = 85
  
  /* Optional: Zusätzliche Checks aktivieren */
  vars.http_vhosts["Main Website"] = {
    http_uri = "/"
  }
}
```

### Schritt 5.3: Konfiguration kopieren & neu laden

```bash
# Configs in Container kopieren
./scripts/00-copy-icinga-configs.sh

# Alternativ: Container neustarten
docker restart icinga2
```

### Schritt 5.4: Konfiguration prüfen

```bash
docker exec icinga2 icinga2 daemon -C
```

Erwartete Ausgabe: `Finished validating the configuration file(s).`

---

## 6. Grafana Dashboard

### Verfügbare Dashboards

| Dashboard | Beschreibung |
|-----------|--------------|
| NOC - Infrastructure Monitor | Übersichtsdashboard mit Status, Performance und Problemen |
| Icinga Overview | Detaillierte Icinga-Metriken |

### Dashboard anpassen

1. Öffne das Dashboard in Grafana
2. Klicke auf **Edit** (Stift-Icon)
3. Ändere Panels nach Bedarf
4. **Save dashboard** → **Save**

### Neues Dashboard erstellen

1. Klicke **+** → **New dashboard**
2. Füge Panels hinzu
3. Datenquellen:
   - **icingadb** (PostgreSQL) - für Status-Daten
   - **prometheus** - für Performance-Metriken

---

## 7. Thresholds anpassen

### Globale Defaults ändern

Bearbeite `config/icinga2/conf.d/templates.conf`:

```icinga2
const ThresholdDefaults = {
  disk_warning = 80      /* Standard: 80% */
  disk_critical = 90     /* Standard: 90% */
  load_warning = "5,4,3"
  load_critical = "10,8,6"
  /* ... weitere Werte */
}
```

Nach Änderung:

```bash
./scripts/00-copy-icinga-configs.sh
```

### Pro-Host Thresholds (Director)

1. Host im Director öffnen
2. **Custom properties** → Variable hinzufügen
3. z.B. `disk_warning` = `70`
4. Deploy

### Pro-Host Thresholds (Konfiguration)

```icinga2
object Host "critical-server" {
  import "linux-host"
  address = "192.168.1.50"
  
  vars.disk_warning = 60
  vars.disk_critical = 75
  vars.load_warning = "3,2,1"
  vars.load_critical = "5,4,3"
}
```

---

## Nächste Schritte

- [Host hinzufügen (ausführlich)](HOST_HINZUFUEGEN.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Grafana Dashboards erstellen](GRAFANA_DASHBOARD_HOWTO.md)

## Hilfe

Bei Problemen:

```bash
# Logs prüfen
docker compose -f docker-compose.dev.yml logs -f icinga2

# Stack neustarten
docker compose -f docker-compose.dev.yml restart

# Komplett neu starten
docker compose -f docker-compose.dev.yml down -v
docker compose -f docker-compose.dev.yml up -d
./scripts/init.sh
```
