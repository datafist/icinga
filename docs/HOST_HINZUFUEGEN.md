# Host in Icinga Director hinzufügen

Nach der Initialisierung (`./scripts/init-icinga.sh`) sind bereits Vorlagen erstellt.

## 📋 Voraussetzungen

- Stack gestartet: `docker compose up -d`
- Initialisierung ausgeführt: `./scripts/init-icinga.sh`
- Zugriff: http://localhost:8080 (`icingaadmin` / `admin`)

---

## 🖥️ Host hinzufügen

**Navigation:** Icinga Director → Hosts → Hosts → Hinzufügen

| Feld | Beispiel | Beschreibung |
|------|----------|--------------|
| **Object name** | `webserver-prod-01` | Eindeutiger Name (keine Leerzeichen) |
| **Imports** | `director-host` | Vorlage auswählen |
| **Display name** | `Webserver Production` | Anzeigename (optional) |
| **Host address** | `192.168.1.100` | IP-Adresse oder FQDN |

**Optional:**
- **Groups**: `webservers`, `production`
- **Notes**: Beschreibung des Servers
- **Notes URL**: Link zur Dokumentation

→ **Speichern**

---

## 🔍 Services hinzufügen

**Navigation:** Icinga Director → Dienste → Dienste → Hinzufügen

### SSH Service

| Feld | Wert |
|------|------|
| **Object name** | `SSH` |
| **Imports** | `director-service` |
| **Host** | Deinen Host auswählen |
| **Check command** | `ssh` |

→ **Speichern**

### HTTP Service

| Feld | Wert |
|------|------|
| **Object name** | `HTTP` |
| **Imports** | `director-service` |
| **Host** | Deinen Host auswählen |
| **Check command** | `http` |

**Für HTTPS:** Unter "Fields" → `http_ssl` aktivieren, `http_port` = 443

→ **Speichern**

---

## ✅ Ausrollen (Deploy)

**WICHTIG:** Änderungen sind erst nach dem Ausrollen aktiv!

1. Klick auf gelben Button oben rechts (z.B. "3 Änderungen")
2. Button **"Ausrollen"** klicken
3. Warten bis "Konfiguration erfolgreich ausgerollt"

**Falls Ausrollen hängt:**
```bash
./scripts/director-deploy.sh
```

---

## 📊 Status prüfen

Nach 1-2 Minuten sollte der Host **UP** (grün) sein.

**Hosts:** Hauptseite → Hosts
**Services:** Hauptseite → Services

| Status | Bedeutung |
|--------|-----------|
| UP / OK (grün) | Alles funktioniert ✅ |
| DOWN / CRITICAL (rot) | Problem ❌ |
| WARNING (gelb) | Funktioniert mit Warnung ⚠️ |
| PENDING (blau) | Noch nicht geprüft (warten) ⏳ |

---

## 🐛 Probleme?

→ Siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md) für Lösungen.

---

## 📝 Checkliste

- [ ] Host angelegt (Object name, Imports, Host address)
- [ ] Services angelegt (SSH, HTTP, etc.)
- [ ] **Ausrollen durchgeführt**
- [ ] Status geprüft (sollte nach 1-2 Min. UP/OK sein)

---

## 💡 Best Practices

**Naming:** `server-typ-umgebung-nummer` (z.B. `webserver-prod-01`)

**Regelmäßig ausrollen** - nicht 10 Änderungen sammeln, sondern nach jeder Änderung.

**Dokumentation nutzen** - Notes und Notes URL Felder ausfüllen.
