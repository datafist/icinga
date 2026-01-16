# Troubleshooting

Häufige Probleme und Lösungen.

---

## 🔴 Director "Ausrollen" hängt

**Symptom:** Button "Ausrollen" läuft endlos, keine Rückmeldung.

**Lösung:**
```bash
./scripts/03-director-deploy.sh
```

Das Script:
- Prüft Icinga 2 Status
- Korrigiert Timeout-Einstellungen
- Führt Deploy mit Retry-Logik aus

**Alternativ CLI:**
```bash
docker exec icingaweb2 icingacli director config deploy
```

---

## 🔴 PostgreSQL Timeout

**Symptom:** `connection to server at "postgres" (...) timeout expired`

**Lösung:** Bereits in docker-compose.yml konfiguriert:
- `max_connections=200`
- `idle_in_transaction_session_timeout=30s`
- Persistente Connections aktiviert

**Verifizieren:**
```bash
docker exec icinga-postgres psql -U icinga -c "SHOW max_connections;"
# Sollte: 200
```

---

## 🔴 Template-Namenskonflikt

**Symptom:** `Error: Object 'generic-service' of type 'Service' re-defined`

**Ursache:** Director-Template kollidiert mit Icinga 2 Built-in.

**Verbotene Namen:**
- ❌ `generic-host`
- ❌ `generic-service`

**Erlaubte Namen:**
- ✅ `director-host`
- ✅ `director-service`

**Lösung bei bestehendem Konflikt:**
```bash
# Lösche konfliktierendes Template
docker exec icinga-postgres psql -U icinga -d director -c \
  "DELETE FROM icinga_host WHERE object_name='generic-host' AND object_type='template';"
```

---

## 🔴 API-Authentifizierung fehlgeschlagen

**Symptom:** `Unable to authenticate, please check your API credentials`

**Lösung:**
```bash
# Passwort synchronisieren
docker exec icinga-postgres psql -U icinga -d director -c \
  "UPDATE icinga_apiuser SET password = 'icinga' WHERE object_name = 'root';"

# Deploy erneut
./scripts/director-deploy.sh
```

---

## 🔴 Host bleibt "PENDING"

**Symptome:** Host zeigt dauerhaft blauen PENDING-Status.

**Lösungen:**
1. Warte 2-3 Minuten (erste Prüfung braucht Zeit)
2. Prüfe ob Deploy durchgeführt wurde
3. Icinga 2 neustarten: `docker restart icinga2`

---

## 🔴 Host ist "DOWN" aber Server läuft

**Ursache:** Firewall blockiert ICMP (Ping).

**Test:**
```bash
docker exec icinga2 ping -c 3 192.168.1.100
```

**Lösung:** Check Command auf `tcp` oder `dummy` ändern.

---

## 🔴 SSH Service "CRITICAL"

**Ursachen:**
- SSH-Port nicht 22
- Firewall blockiert
- SSH nicht installiert

**Test:**
```bash
docker exec icinga2 nc -zv 192.168.1.100 22
```

**Lösung:** Service → Fields → `ssh_port` = anderer Port.

---

## 🔴 HTTP "301 Moved Permanently"

**Ursache:** HTTP Redirect (HTTP→HTTPS).

**Lösung:** Service → Fields → `http_ssl` aktivieren.

---

## 🔧 Nützliche Befehle

### Logs anzeigen
```bash
docker logs -f icinga2          # Icinga 2 Live-Logs
docker logs -f icingaweb2       # Web-Interface Logs
docker compose logs -f          # Alle Services
```

### Icinga 2 Config prüfen
```bash
docker exec icinga2 icinga2 daemon -C
```

### Container neustarten
```bash
docker restart icinga2
docker restart icingaweb2
```

### Director-Status
```bash
docker exec icingaweb2 icingacli director health
```

### Datenbank-Connections
```bash
docker exec icinga-postgres psql -U icinga -c "SELECT count(*) FROM pg_stat_activity;"
```
