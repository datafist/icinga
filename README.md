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
./scripts/init-icinga.sh --dev
```

> ⚠️ **Wichtig:** Ohne dieses Script funktioniert das Monitoring nicht! Es konfiguriert API-User, aktiviert IcingaDB, führt Director-Migrationen durch und erstellt Vorlagen.

### Schritt 5: Zugriff testen

| Service      | URL                        | Login                   |
|--------------|----------------------------|-------------------------|
| Icinga Web 2 | http://localhost:8080      | `icingaadmin` / `admin` |
| Grafana      | http://localhost:3000      | `admin` / `admin`       |
| Prometheus   | http://localhost:9090      | *(kein Login)*          |
| Icinga 2 API | https://localhost:5665     | `root` / `icinga`       |
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
./scripts/init-icinga.sh --prod
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

Das Script `./scripts/init-icinga.sh` muss **einmalig nach dem ersten Start** ausgeführt werden. Es:

- ✅ Konfiguriert API-User mit korrektem Passwort
- ✅ Aktiviert IcingaDB Feature
- ✅ Führt Director-Datenbankmigrationen durch
- ✅ Startet Director-Kickstart
- ✅ Erstellt Host- und Service-Vorlagen
- ✅ Entfernt Standard-Localhost-Checks
- ✅ Führt erstes Deployment durch

### Wann welche Compose-Datei?

```bash
# Lokal entwickeln
docker compose -f docker-compose.dev.yml up -d

# Auf Server deployen (mit Traefik)
docker compose up -d
```

> **Hinweis:** Bei Grafana wirst du beim ersten Login aufgefordert, das Passwort zu ändern.

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
│   ├── init-icinga.sh          # Initialisierungsscript (nach erstem Start)
│   └── director-deploy.sh      # Director Deploy Fix (bei hängendem Ausrollen)
├── init-db/
│   └── 01-init-databases.sql   # PostgreSQL Datenbank-Initialisierung
├── config/
│   ├── icinga2/
│   │   └── conf.d/             # Icinga 2 Konfiguration (optional)
│   ├── icingaweb2/
│   │   └── modules/director/   # Director-Konfiguration
│   ├── prometheus/
│   │   └── prometheus.yml      # Prometheus Scrape-Config
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/
│       │   │   └── datasources.yml
│       │   └── dashboards/
│       │       └── dashboards.yml
│       └── dashboards/
│           └── icinga-overview.json
└── .github/
    └── workflows/
        ├── deploy.yml          # Deployment Pipeline
        └── backup.yml          # Backup Pipeline
```

## 🔧 Konfiguration

**Hosts und Services:** [docs/HOST_HINZUFUEGEN.md](docs/HOST_HINZUFUEGEN.md)

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

- [Host hinzufügen](docs/HOST_HINZUFUEGEN.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Icinga 2 Dokumentation](https://icinga.com/docs/icinga-2/latest/)
- [Grafana Dokumentation](https://grafana.com/docs/)

## 📄 Lizenz

MIT License
