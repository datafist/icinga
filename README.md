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

### ⚠️ Ist das Monitoring sofort startklar?

**Nein.** Nach `docker compose up -d` muss **einmalig** das Init-Script ausgeführt werden:

```bash
./scripts/init-icinga.sh --dev   # oder --prod
```

Erst danach ist das Monitoring einsatzbereit.

### Voraussetzungen

- Docker Engine 24+
- Docker Compose v2
- Git
- Bash (Linux/macOS/WSL)

### Installation

1. **Repository klonen:**
   ```bash
   git clone <repository-url>
   cd icinga
   ```

2. **Umgebungsvariablen konfigurieren:**
   ```bash
   cp .env.example .env
   # Passwörter in .env anpassen (für Produktion!)
   nano .env
   ```

3. **Stack starten:**

   **Development:**
   ```bash
   docker compose -f docker-compose.dev.yml up -d
   ```

   **Production:**
   ```bash
   docker compose up -d
   ```

4. **Initialisierung ausführen (einmalig nach erstem Start):**
   ```bash
   ./scripts/init-icinga.sh --dev   # Für Development
   # oder
   ./scripts/init-icinga.sh --prod  # Für Production
   ```

   Das Script führt automatisch aus:
   - ✅ API-User Konfiguration
   - ✅ IcingaDB Feature Aktivierung
   - ✅ Director-Datenbankmigrationen
   - ✅ Director-Kickstart
   - ✅ **Host- und Service-Vorlagen erstellen**
   - ✅ Entfernung der Standard-Localhost-Checks
   - ✅ Erstes Deployment

   ⚠️ **Wichtig:** Ohne dieses Script funktioniert das Monitoring nicht!

5. **Status prüfen:**
   ```bash
   docker compose ps
   ```

### Zugriff

| Service      | URL                        | Standard-Login        |
|--------------|----------------------------|-----------------------|
| Icinga Web 2 | http://localhost:8080      | `icingaadmin` / `admin` |
| Grafana      | http://localhost:3000      | `admin` / `admin`     |
| Prometheus   | http://localhost:9090      | *(kein Login)*        |
| Icinga 2 API | https://localhost:5665     | `root` / `icinga`     |

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

**Grafana Dashboards:** JSON-Dateien unter `config/grafana/dashboards/` werden automatisch importiert.

## 🚢 Deployment

### Manuelles Deployment

```bash
# Auf dem Server:
git clone <repository-url> ~/icinga-monitoring
cd ~/icinga-monitoring
cp .env.example .env
# .env anpassen
docker compose up -d
./scripts/init-icinga.sh --prod
```

## 🔄 Wartung

### Logs anzeigen
```bash
docker compose logs -f              # Alle Services
docker compose logs -f icinga2      # Nur Icinga 2
docker logs -f icinga2              # Live-Logs
```

### Container neustarten
```bash
docker compose restart icinga2
```

### Datenbank-Backup
```bash
docker compose exec postgres pg_dumpall -U icinga > backup.sql
```

### Updates
```bash
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
