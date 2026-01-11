# Grafana Dashboard - Hosts hinzufügen und Monitoring visualisieren

## 📋 Überblick

Wenn du einen neuen Host über Icinga Director hinzugefügt hast, wird dieser **automatisch** in der IcingaDB-Datenbank gespeichert. Um ihn im Grafana-Dashboard sichtbar zu machen, musst du:

1. **Icinga Dashboard öffnen** → Host und Services überprüfen
2. **Grafana Dashboard konfigurieren** → Queries anpassen oder neue Panel erstellen
3. Optional: **Neue Panels für den Host erstellen**

---

## 🔧 Schritt 1: Icinga Web Interface überprüfen

Bevor du zum Grafana-Dashboard gehst, stelle sicher, dass der Host korrekt in Icinga konfiguriert ist:

1. Öffne **Icinga Web 2**: `http://localhost:8080`
2. Gehe zu **Monitoring** → **Hosts**
3. Suche deinen neu hinzugefügten Host in der Liste
4. Klick auf den Host-Namen
5. **Überprüfe:**
   - ✅ Host-Status (UP/DOWN)
   - ✅ Services sind angehängt
   - ✅ Check-Ausführungen laufen

---

## 🎨 Schritt 2: Grafana Admin-Oberfläche öffnen

### Zugang zum Admin-Panel

1. Öffne **Grafana**: `http://localhost:3000`
2. Standard-Login:
   - **Benutzer:** `admin`
   - **Passwort:** `admin` (bitte nach First-Login ändern!)
3. Klick auf das **Zahnrad-Icon** ⚙️ im linken Menü
4. Wähle **Administration** → **Datasources**

---

## 📊 Schritt 3: Verfügbare Datenquellen überprüfen

Im Grafana Dashboard sind zwei Datenquellen verfügbar:

### **1. PostgreSQL-IcingaDB** (für Host/Service-Status)
- **Name:** PostgreSQL-IcingaDB
- **Typ:** PostgreSQL
- **Datenbank:** `icingadb`
- **Tabellen:** hosts, services, state_history, notifications, etc.
- **Nutzen:** Status-Informationen, historische Daten, Service-Details

### **2. Prometheus** (für Metriken & Performance-Daten)
- **Name:** Prometheus
- **Typ:** Prometheus
- **URL:** http://prometheus:9090
- **Metriken von:** Icinga2, Grafana, Prometheus selbst
- **Nutzen:** CPU, Memory, Latenz, Custom-Metriken

---

## 📈 Schritt 4: Existing Dashboard bearbeiten

Das Standard-Dashboard ist **`icinga-overview.json`** und nutzt PostgreSQL-Queries.

### Dashboard öffnen und bearbeiten:

1. Gehe zu **Dashboards** im linken Menü
2. Wähle **icinga-overview** (oder erstelle ein neues mit dem `+`-Button)
3. Klick **Edit** (Stift-Icon oben rechts)
4. Jetzt kannst du Panels bearbeiten oder neue hinzufügen

---

## 🛠️ Schritt 5: Panel bearbeiten oder erstellen

### Szenario A: Bestehende Panel anpassen (z.B. Host-Count)

1. Klick auf eine Panel im Edit-Mode
2. Klick **"Edit"** oder klick direkt auf die Panel
3. Im rechten Panel siehst du: **Query** Tab
4. Wechsel zur **Datasource: PostgreSQL-IcingaDB**
5. Bearbeite die SQL-Query:

#### **Beispiel 1: Anzahl aller Hosts (inkl. neuem Host)**
```sql
SELECT COUNT(*) as host_count
FROM hosts
WHERE state != 99  -- 99 = deleted
```

#### **Beispiel 2: Host nach Name filtern**
```sql
SELECT 
  name,
  state,
  state_type,
  check_attempt,
  max_check_attempts
FROM hosts
WHERE name = 'dein-neuer-hostname'  -- oder LIKE für Wildcard
```

#### **Beispiel 3: Alle Services eines Hosts**
```sql
SELECT 
  h.name as hostname,
  s.name as service_name,
  s.state,
  s.state_text
FROM hosts h
JOIN services s ON h.id = s.host_id
WHERE h.name = 'dein-neuer-hostname'
ORDER BY s.name
```

---

## 🎯 Schritt 6: Neue Panel für deinen Host erstellen

### Panel hinzufügen:

1. Im Edit-Mode: **+ Add Panel** (oben im Dashboard)
2. Wähle **Datasource → PostgreSQL-IcingaDB**
3. Gib eine **SQL-Query** ein

### Beispiel-Panel: Host Status Gauge

**Query:**
```sql
SELECT 
  CASE 
    WHEN state = 0 THEN 100  -- UP
    WHEN state = 1 THEN 0    -- DOWN
    ELSE 50                  -- UNKNOWN
  END as status_value
FROM hosts
WHERE name = 'mein-server-1'
LIMIT 1
```

**Panel-Konfiguration:**
- **Title:** "Server 1 Status"
- **Visualization:** Gauge
- **Thresholds:**
  - Green: 100 (UP)
  - Yellow: 50 (UNKNOWN)
  - Red: 0 (DOWN)

### Beispiel-Panel: Service Status Table

**Query:**
```sql
SELECT 
  s.name as "Service",
  CASE 
    WHEN s.state = 0 THEN 'OK'
    WHEN s.state = 1 THEN 'WARNING'
    WHEN s.state = 2 THEN 'CRITICAL'
    ELSE 'UNKNOWN'
  END as "Status",
  s.output as "Details"
FROM services s
JOIN hosts h ON s.host_id = h.id
WHERE h.name = 'mein-server-1'
ORDER BY s.name
```

**Panel-Konfiguration:**
- **Title:** "Server 1 Services"
- **Visualization:** Table
- **Sortierung:** Nach Status-Spalte

### Beispiel-Panel: Uptime History (Prometheus)

**Query (Prometheus):**
```promql
up{job="icinga2"}
```

**Panel-Konfiguration:**
- **Title:** "Icinga2 Verfügbarkeit"
- **Visualization:** Time Series (Zeitverlauf)

---

## 📝 Schritt 7: Panel speichern und Dashboard aktualisieren

1. Nach jeder Änderung: **Rechts oben → Save**
2. Dashboard-Name eingeben (oder Updated speichern)
3. **Save and Return**
4. Das Dashboard ist jetzt mit deinem neuen Host aktualisiert

---

## 🔄 Daten-Refresh einstellen

Damit dein Dashboard die neuesten Daten anzeigt:

1. **Dashboard öffnen** (nicht Edit-Mode)
2. **Refresh Rate** (oben rechts) einstellen:
   - `5s` - Sehr schnell (für Live-Überwachung)
   - `30s` - Standard
   - `1m` - Sparsam mit Ressourcen
3. Oder auf das **Reload-Icon** klicken zum manuellen Refresh

---

## 🗂️ Nützliche SQL Queries für IcingaDB

### Query: Alle Hosts mit Status übersicht
```sql
SELECT 
  name,
  display_name,
  CASE state
    WHEN 0 THEN 'UP'
    WHEN 1 THEN 'DOWN'
    ELSE 'UNKNOWN'
  END as status,
  last_state_change,
  output
FROM hosts
WHERE state != 99
ORDER BY name
```

### Query: Services mit Problemen
```sql
SELECT 
  h.name as hostname,
  s.name as service,
  CASE s.state
    WHEN 0 THEN 'OK'
    WHEN 1 THEN 'WARNING'
    WHEN 2 THEN 'CRITICAL'
    ELSE 'UNKNOWN'
  END as status,
  s.output
FROM services s
JOIN hosts h ON s.host_id = h.id
WHERE s.state > 0  -- Nur nicht-OK Services
ORDER BY h.name, s.name
```

### Query: Host Performance-Daten (Last Check Times)
```sql
SELECT 
  name,
  EXTRACT(EPOCH FROM (NOW() - last_check)) as seconds_since_last_check,
  check_interval,
  check_timeout
FROM hosts
WHERE name = 'mein-server-1'
```

---

## 🔐 Admin-Funktionen in Grafana

Wenn du mit Admin-Rechten arbeiten möchtest:

### 1. **Datasources verwalten**
- ⚙️ → **Administration** → **Datasources**
- Hier kannst du neue Datenquellen hinzufügen oder bestehende ändern

### 2. **Users & Teams**
- ⚙️ → **Administration** → **Users**
- Neue Benutzer hinzufügen, Rollen zuweisen

### 3. **Plugins**
- ⚙️ → **Administration** → **Plugins**
- Zusätzliche Visualisierungen installieren (z.B. Worldmap, Pie Charts, etc.)

### 4. **Settings/Preferences**
- ⚙️ → **Preferences**
- Theme, Sprache, und persönliche Einstellungen ändern

---

## ⚠️ Häufige Probleme & Lösungen

### Problem: Dashboard zeigt "No data"
**Lösung:**
1. PostgreSQL-Datasource testen: ⚙️ → Datasources → PostgreSQL-IcingaDB → Test
2. Überprüfe, ob der Host-Name in der Query korrekt ist (Case-sensitive!)
3. Öffne Icinga Web und prüfe, ob der Host dort sichtbar ist

### Problem: Host wird nicht angezeigt
**Lösung:**
1. Gehe zu **Icinga Web 2** → Monitoring → Hosts
2. Überprüfe, ob der Host dort sichtbar ist
3. Wenn nicht: Host-Konfiguration überprüfen und Director-Deployment neu ausführen

### Problem: Services zeigen alte Daten
**Lösung:**
1. Dashboard Refresh-Rate erhöhen
2. Icinga2 Service neu starten: `docker compose restart icinga2`
3. Datenbank-Verbindung überprüfen

### Problem: "PostgreSQL connection refused"
**Lösung:**
1. Überprüfe, ob alle Docker-Services laufen: `docker compose ps`
2. PostgreSQL Health-Check: `docker compose logs postgres`
3. Datasource-Einstellungen überprüfen (Host, Port, Passwort)

---

## 📚 Weitere Ressourcen

- **Icinga Web 2 Docs:** https://icinga.com/docs/icinga-web-2/latest/
- **Grafana SQL Queries:** https://grafana.com/docs/grafana/latest/datasources/postgres/
- **IcingaDB Schema:** Die Tabellen findest du mit:
  ```sql
  SELECT table_name FROM information_schema.tables 
  WHERE table_schema = 'public'
  ```

---

## ✅ Checkliste: Host ins Grafana-Dashboard bringen

- [ ] Host in Icinga Web 2 überprüfen (Status UP)
- [ ] Grafana-Dashboard öffnen
- [ ] Edit-Mode starten
- [ ] Bestehende Panel mit neuem Host anpassen ODER neue Panel erstellen
- [ ] Query testen (grüner "Test"-Button)
- [ ] Panel speichern
- [ ] Dashboard speichern
- [ ] Refresh-Rate einstellen
- [ ] Live-Daten überprüfen

---

**Fertig!** Dein Host ist jetzt im Grafana-Dashboard sichtbar und wird in Echtzeit überwacht. 🎉
