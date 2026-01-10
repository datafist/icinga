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

### Installation

1. **Repository klonen:**
   ```bash
   git clone <repository-url>
   cd icinga
   ```

2. **Umgebungsvariablen konfigurieren:**
   ```bash
   cp .env.example .env
   # Passwörter in .env anpassen!
   nano .env
   ```

3. **Stack starten:**
   ```bash
   docker compose up -d
   ```

4. **IcingaDB Feature aktivieren (einmalig nach erstem Start):**
   ```bash
   # IcingaDB Feature aktivieren
   docker exec icinga2 icinga2 feature enable icingadb
   
   # IcingaDB Konfiguration anpassen
   docker exec icinga2 bash -c 'cat > /data/etc/icinga2/features-enabled/icingadb.conf << EOF
   object IcingaDB "icingadb" {
     host = "icingadb-redis"
     port = 6379
   }
   EOF'
   
   # Icinga 2 neustarten
   docker restart icinga2
   
   # Director-Datenbank migrieren
   docker exec icingaweb2 icingacli director migration run
   ```

5. **Status prüfen:**
   ```bash
   docker compose ps
   docker compose logs -f
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
├── docker-compose.yml          # Container-Konfiguration
├── .env.example                # Beispiel-Umgebungsvariablen
├── .env                        # Aktuelle Umgebungsvariablen (nicht in Git)
├── .gitignore
├── README.md
├── init-db/
│   └── 01-init-databases.sql   # Datenbank-Initialisierung
├── config/
│   ├── icinga2/
│   │   ├── hosts.conf          # Host-Definitionen
│   │   ├── services.conf       # Service-Checks
│   │   └── notifications.conf  # Benachrichtigungen
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

### Icinga Director (GUI-basierte Konfiguration)

Der **Icinga Director** ist bereits aktiviert und ermöglicht die komfortable Verwaltung von Hosts, Services und Templates über die Weboberfläche - ideal für Teams mit mehreren Administratoren.

#### Ersteinrichtung

1. **Öffne Icinga Web 2:** http://localhost:8080
2. **Navigiere zu:** Icinga Director → Kickstart Wizard
3. **Führe den Kickstart durch:**
   - Die API-Verbindung ist bereits vorkonfiguriert
   - Der Wizard importiert vorhandene Icinga 2-Objekte

#### Hosts über Director hinzufügen

1. **Navigiere zu:** Icinga Director → Hosts → Add Host
2. **Fülle die Pflichtfelder aus:**
   - **Host name:** Eindeutiger Name (z.B. `webserver-01`)
   - **Imports:** Wähle ein Host-Template (z.B. `generic-host`)
   - **Host address:** IP-Adresse oder Hostname
3. **Speichern** und **Deploy** klicken

#### Services über Director hinzufügen

1. **Navigiere zu:** Icinga Director → Services → Add Service
2. **Konfiguriere:**
   - **Service name:** Name des Checks
   - **Imports:** Service-Template (z.B. `generic-service`)
   - **Host:** Ziel-Host auswählen
   - **Check command:** z.B. `http`, `ping`, `ssh`
3. **Speichern** und **Deploy** klicken

#### Änderungen deployen

- Klicke auf **"Activity log"** → **"Deploy pending changes"**
- Der Director generiert die Icinga 2-Konfiguration und wendet sie an
- Alle Änderungen werden versioniert und sind nachvollziehbar

### Manuelle Konfiguration (Alternative)

Bearbeite `config/icinga2/hosts.conf`:

```icinga
object Host "webserver" {
  import "generic-host"
  address = "192.168.1.100"
  vars.os = "Linux"
  vars.http_vhosts["http"] = {
    http_uri = "/"
  }
}
```

Nach Änderungen:
```bash
docker compose restart icinga2
```

### Grafana Dashboards

Dashboards können unter `config/grafana/dashboards/` als JSON-Dateien abgelegt werden. Sie werden automatisch importiert.

## 🚢 Deployment

### GitHub Secrets konfigurieren

Folgende Secrets müssen in GitHub konfiguriert werden:

| Secret                    | Beschreibung                    |
|---------------------------|---------------------------------|
| `SSH_PRIVATE_KEY`         | SSH Key für Server-Zugriff      |
| `DEPLOY_HOST`             | Server-Hostname oder IP         |
| `DEPLOY_USER`             | SSH-Benutzer                    |
| `POSTGRES_PASSWORD`       | PostgreSQL Passwort             |
| `ICINGADB_PASSWORD`       | IcingaDB Passwort               |
| `ICINGAWEB_ADMIN_PASSWORD`| Icinga Web Admin Passwort       |
| `ICINGAWEB_DB_PASSWORD`   | Icinga Web DB Passwort          |
| `ICINGA_API_PASSWORD`     | Icinga API Passwort             |
| `GRAFANA_ADMIN_USER`      | Grafana Admin Benutzer          |
| `GRAFANA_ADMIN_PASSWORD`  | Grafana Admin Passwort          |
| `GRAFANA_ROOT_URL`        | Grafana Root URL                |

### Manuelles Deployment

```bash
# Auf dem Server:
git clone <repository-url> ~/icinga-monitoring
cd ~/icinga-monitoring
cp .env.example .env
# .env anpassen
docker compose up -d
```

## 🔄 Wartung

### Logs anzeigen
```bash
docker compose logs -f [service-name]
```

### Container neustarten
```bash
docker compose restart [service-name]
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

### Container startet nicht
```bash
docker compose logs [service-name]
docker compose ps
```

### Icinga Web zeigt keine Daten
1. Prüfe IcingaDB-Verbindung zu Redis
2. Prüfe PostgreSQL-Verbindung
3. Logs checken: `docker compose logs icingadb icingaweb2`

### Grafana zeigt keine Metriken
1. Datasource-Konfiguration prüfen
2. Prometheus-Verbindung testen: http://localhost:9090
3. Netzwerk-Konnektivität testen: `docker compose logs prometheus`

## 📚 Dokumentation

- [Icinga 2 Dokumentation](https://icinga.com/docs/icinga-2/latest/)
- [IcingaDB Dokumentation](https://icinga.com/docs/icinga-db/latest/)
- [Icinga Web 2 Dokumentation](https://icinga.com/docs/icinga-web/latest/)
- [Grafana Dokumentation](https://grafana.com/docs/)

## 📄 Lizenz

MIT License
