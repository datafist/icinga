# Icinga Monitoring Stack mit Grafana

Ein modernes, containerisiertes Monitoring-Setup mit Icinga 2, IcingaDB, Icinga Web 2, Grafana und Prometheus.

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                         Docker Network                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐    ┌───────────┐    ┌──────────┐                 │
│  │ Icinga 2 │───▶│   Redis   │◀───│ IcingaDB │                 │
│  │  :5665   │    │           │    │          │                 │
│  └────┬─────┘    └───────────┘    └────┬─────┘                 │
│       │                                │                        │
│       │         ┌────────────┐         │                        │
│       └────────▶│ PostgreSQL │◀────────┘                        │
│                 │            │                                  │
│                 └─────┬──────┘                                  │
│                       │                                         │
│  ┌────────────┐       │        ┌───────────┐                   │
│  │ Icinga Web │◀──────┴───────▶│  Grafana  │                   │
│  │   :8080    │                │   :3000   │                   │
│  └────────────┘                └─────┬─────┘                   │
│                                      │                          │
│                               ┌──────┴─────┐                   │
│                               │ Prometheus │                   │
│                               │   :9090    │                   │
│                               └────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Voraussetzungen

- Docker Engine 24+
- Docker Compose v2
- Git
- Bash (Linux/macOS/WSL)

### TL;DR - Schnellstart (Lokal)

```bash
# 1. Repository klonen
git clone git@github.com:datafist/icinga.git && cd icinga

# 2. Env-Datei erstellen
cp .env.example .env

# 3. Container starten
docker compose -f docker-compose.dev.yml up -d

# 4. Warten bis alle Container laufen (ca. 30-60 Sekunden)
docker compose -f docker-compose.dev.yml ps

# 5. Initialisierung ausführen (WICHTIG - einmalig nach erstem Start!)
./scripts/init.sh

# 6. Öffne http://localhost:8080 (Login: icingaadmin / admin)
```

> 📖 **Ausführliche Anleitung:** Siehe [Walkthrough](docs/WALKTHROUGH.md) für eine detaillierte Schritt-für-Schritt-Anleitung.

---

## 💻 Lokale Entwicklung

### Schritt 1: Repository klonen

```bash
git clone git@github.com:datafist/icinga.git
cd icinga
```

### Schritt 2: Umgebungsvariablen erstellen

```bash
cp .env.example .env
```

> **Hinweis:** Für lokale Entwicklung können die Standard-Passwörter aus `.env.example` verwendet werden.

### Schritt 3: Stack starten

```bash
docker compose -f docker-compose.dev.yml up -d
```

### Schritt 4: Initialisierung ausführen (einmalig!)

Führe das Script **im Projektordner** aus (nicht im Container):

```bash
# Im Projektordner (z.B. ~/icinga oder wo du das Repo geklont hast)
./scripts/init.sh
```

Das Init-Skript führt 3 Teile aus:
1. **01-director-kickstart.sh** - API-User, IcingaDB, Director-Migration
2. **02-director-objects.sh** - Templates, Data Fields, Service Sets
3. **03-director-deploy.sh** - Deployment der Konfiguration + Icinga2-Restart

> ⚠️ **Wichtig:** Ohne dieses Script funktioniert das Monitoring nicht!

### Schritt 5: Zugriff testen

| Service      | URL                        | Login                   |
|--------------|----------------------------|-------------------------|
| Icinga Web 2 | http://localhost:8080      | `icingaadmin` / `admin` |
| Grafana      | http://localhost:3000      | `admin` / `admin`       |
| Prometheus   | http://localhost:9090      | *(kein Login)*          |
| Icinga 2 API | https://localhost:5665     | `root` / `icinga`       |
| Icinga2 Exporter | http://localhost:9638  | *(kein Login)*          |
| PostgreSQL   | localhost:5432             | `icinga` / `icinga`     |

### Entwicklungs-Workflow

```bash
# Logs beobachten
docker compose -f docker-compose.dev.yml logs -f

# Container neustarten
docker compose -f docker-compose.dev.yml restart icinga2

# Stack stoppen (Daten bleiben erhalten)
docker compose -f docker-compose.dev.yml down

# Stack komplett löschen (inkl. Volumes)
docker compose -f docker-compose.dev.yml down -v
```

---

## 🚢 Production Deployment

### Unterschiede zur Entwicklung

| Aspekt | Development | Production |
|--------|-------------|------------|
| Compose-Datei | `docker-compose.dev.yml` | `docker-compose.yml` |
| SSL/TLS | Kein SSL (localhost) | Traefik mit Let's Encrypt |
| Ports | Alle Ports exponiert | Nur 5665 (Icinga API) |
| Domain | localhost | `icinga.florianbirkenberger.de` |
| PostgreSQL | Port 5432 exponiert | Nur intern erreichbar |

### Voraussetzungen auf dem Server

- Linux Server (Ubuntu/Debian empfohlen)
- Docker & Docker Compose installiert
- Domain mit DNS A-Record auf Server-IP
- **Traefik bereits als Reverse Proxy konfiguriert** (externes Netzwerk `traefik-public`)

### Schritt-für-Schritt Deployment

#### 1. Auf den Server verbinden

```bash
ssh user@your-server.example.com
```

#### 2. Repository klonen

```bash
git clone git@github.com:datafist/icinga.git ~/icinga-monitoring
cd ~/icinga-monitoring
```

#### 3. Umgebungsvariablen konfigurieren

```bash
cp .env.example .env
nano .env
```

**Sichere Passwörter setzen:**

```dotenv
# WICHTIG: Alle Passwörter ändern!
POSTGRES_PASSWORD=<sicheres-passwort>
ICINGADB_PASSWORD=<sicheres-passwort>
ICINGAWEB_ADMIN_PASSWORD=<sicheres-passwort>
ICINGAWEB_DB_PASSWORD=<sicheres-passwort>
DIRECTOR_DB_PASSWORD=<sicheres-passwort>
ICINGA_API_PASSWORD=<sicheres-passwort>
GRAFANA_ADMIN_PASSWORD=<sicheres-passwort>

# Domain anpassen falls nötig
GRAFANA_ROOT_URL=https://grafana.your-domain.com
```

> 💡 **Tipp:** Passwörter generieren mit `openssl rand -base64 24`

#### 4. Domain in docker-compose.yml anpassen (falls nötig)

Die Traefik-Labels in `docker-compose.yml` enthalten die Domains. Falls du andere Domains nutzen möchtest:

```bash
nano docker-compose.yml
# Suche nach "icinga.florianbirkenberger.de" und ersetze mit deiner Domain
```

#### 5. Stack starten

```bash
docker compose up -d
```

#### 6. Initialisierung ausführen

Führe das Script **im Projektordner auf dem Server** aus:

```bash
# Im Projektordner ~/icinga-monitoring
./scripts/init.sh
```

#### 7. Status prüfen

```bash
docker compose ps
docker compose logs -f
```

### Zugriff (Production)

| Service      | URL                                       | Login                      |
|--------------|-------------------------------------------|----------------------------|
| Icinga Web 2 | https://icinga.your-domain.com            | `icingaadmin` / *dein PW*  |
| Grafana      | https://grafana.your-domain.com           | `admin` / *dein PW*        |
| Prometheus   | https://prometheus.your-domain.com        | *(kein Login)*             |
| Icinga 2 API | https://your-server:5665                  | `root` / *dein API PW*     |

---

## ⚠️ Wichtige Hinweise

### Initialisierungs-Script

Das Script `./scripts/init.sh` muss **einmalig nach dem ersten Start** ausgeführt werden. Es besteht aus 3 Teilen:

| Teil | Script | Funktion |
|------|--------|----------|
| 1 | `01-director-kickstart.sh` | API-User, IcingaDB, Director-Migration & Kickstart |
| 2 | `02-director-objects.sh` | Templates, Data Fields, Host/Service Groups, Service Sets |
| 3 | `03-director-deploy.sh` | Director-Deployment + Icinga2-Restart + Status-Sync |

**Optionen:**
```bash
./scripts/init.sh              # Vollständige Initialisierung
./scripts/init.sh --skip-objects  # Nur Kickstart + Deploy (ohne Objekte)
```

### Wann welche Compose-Datei?

```bash
# Lokal entwickeln
docker compose -f docker-compose.dev.yml up -d

# Auf Server deployen (mit Traefik)
docker compose up -d
```

> **Hinweis:** Bei Grafana wirst du beim ersten Login aufgefordert, das Passwort zu ändern.

---

## 🔄 Director Konfiguration deployen

Wenn du Hosts oder Services im Director (Icinga Web 2) änderst, müssen diese Änderungen deployed werden.

### Option 1: Über die Web-Oberfläche

1. Gehe zu **Icinga Director** → **Konfiguration** → **Deployment**
2. Klicke auf **Deploy**

### Option 2: Per Kommandozeile

```bash
# Im Projektordner ausführen
docker exec icingaweb2 icingacli director config deploy
```

### Bei Problemen mit dem Deployment

Falls das Deployment im Web-Interface hängt oder fehlschlägt:

```bash
# Nur Deploy ausführen
./scripts/03-director-deploy.sh
```

## 📁 Projektstruktur

```
icinga/
├── docker-compose.yml          # Production-Konfiguration (mit Traefik)
├── docker-compose.dev.yml      # Development-Konfiguration (direkte Ports)
├── .env.example                # Beispiel-Umgebungsvariablen
├── .env                        # Aktuelle Umgebungsvariablen (nicht in Git)
├── .gitignore
├── README.md
├── scripts/
│   ├── init.sh                    # Runner-Skript (ruft 01/02/03 auf)
│   ├── 01-director-kickstart.sh   # API-User, IcingaDB, Director-Setup
│   ├── 02-director-objects.sh     # Templates, Data Fields, Service Sets
│   └── 03-director-deploy.sh      # Director-Deployment + Icinga2-Restart
├── init-db/
│   └── 01-init-databases.sql   # PostgreSQL Datenbank-Initialisierung
├── config/
│   ├── icinga2/
│   │   ├── conf.d/
│   │   │   └── api-users.conf  # API-User Konfiguration
│   │   └── features/           # IcingaDB Feature
│   ├── icingaweb2/
│   │   └── modules/director/   # Director-Konfiguration
│   ├── prometheus/
│   │   ├── prometheus.yml      # Prometheus Scrape-Config
│   │   └── targets/            # Externe Targets (http, tcp, icmp)
│   ├── blackbox/
│   │   └── blackbox.yml        # Blackbox Exporter Module
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/
│       │   │   └── datasources.yml
│       │   └── dashboards/
│       │       └── dashboards.yml
│       └── dashboards/
│           └── icinga-overview.json
└── docs/
    ├── HOST_HINZUFUEGEN.md
    ├── GRAFANA_DASHBOARD_HOWTO.md
    └── TROUBLESHOOTING.md
```

## 🔧 Konfiguration

### Director-basierte Konfiguration

Alle Host- und Service-Definitionen werden über den **Icinga Director** verwaltet. Der Director bietet:

- **Host-Templates:** `director-host`, `linux-host`, `windows-snmp-host`, `network-device`, `broadcast-device`, etc.
- **Service-Templates:** `director-service`, `critical-service`, `lowfreq-service`, etc.
- **Data Fields:** Anpassbare Variablen pro Host (Thresholds, Ports, etc.)
- **Deployment:** Automatisches Rollout der Konfiguration

**Hosts hinzufügen:** Über Director UI oder CLI - siehe [docs/HOST_HINZUFUEGEN.md](docs/HOST_HINZUFUEGEN.md)

**Grafana Dashboards:** JSON-Dateien unter `config/grafana/dashboards/` werden automatisch importiert. Siehe [docs/GRAFANA_DASHBOARD_HOWTO.md](docs/GRAFANA_DASHBOARD_HOWTO.md)

---

## 🔄 Wartung

### Logs anzeigen
```bash
# Development
docker compose -f docker-compose.dev.yml logs -f              # Alle Services
docker compose -f docker-compose.dev.yml logs -f icinga2      # Nur Icinga 2

# Production
docker compose logs -f
docker compose logs -f icinga2
```

### Container neustarten
```bash
# Development
docker compose -f docker-compose.dev.yml restart icinga2

# Production
docker compose restart icinga2
```

### Datenbank-Backup
```bash
# Backup erstellen
docker exec icinga-postgres pg_dumpall -U icinga > backup_$(date +%Y%m%d).sql

# Backup wiederherstellen
cat backup.sql | docker exec -i icinga-postgres psql -U icinga
```

### Updates
```bash
# Development
docker compose -f docker-compose.dev.yml pull
docker compose -f docker-compose.dev.yml up -d

# Production
docker compose pull
docker compose up -d
```

## 🛠️ Troubleshooting

Siehe [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 📚 Dokumentation

### Projekt-Dokumentation

- [**Walkthrough**](docs/WALKTHROUGH.md) - Schritt-für-Schritt Anleitung
- [Host hinzufügen](docs/HOST_HINZUFUEGEN.md) - Ausführliche Anleitung
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Problemlösung
- [Grafana Dashboards](docs/GRAFANA_DASHBOARD_HOWTO.md) - Dashboard-Erstellung

### Externe Dokumentation

- [Icinga 2 Dokumentation](https://icinga.com/docs/icinga-2/latest/)
- [Grafana Dokumentation](https://grafana.com/docs/)

## 📄 Lizenz

MIT License
