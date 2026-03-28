# Agent: Datenschutzerklärung-Check

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `5`

## Aufgabe

Prüfe ob eine Datenschutzerklärung vorhanden und vollständig ist. Basis: DSGVO Art. 13/14.

Lies `references/datenschutzerklaerung.md` für Details.

## Eingabe

Du erhältst:
- `DATENSCHUTZ_LINK` — ja/nein + ggf. URL/Inhalt
- `GEFUNDENE_DIENSTE` — Liste erkannter externer Dienste
- `FORMULARE_VORHANDEN` — ja/nein + welche Felder
- `HTML_SNIPPET` — HTML der Datenschutzseite (falls verfügbar)
- `FRAMEWORK` — Projekttyp

## Was du prüfst

**Vorhanden und erreichbar:**
- [ ] Datenschutzerklärung-Link im Footer/Header jeder Seite
- [ ] Nicht hinter Cookie-Banner blockiert

**Pflichtabschnitte (DSGVO Art. 13):**
- [ ] Verantwortlicher: Name, Adresse, E-Mail
- [ ] Hosting: Provider genannt + Serverstandort + Rechtsgrundlage
- [ ] Server-Logfiles: Was geloggt wird, wie lange, Rechtsgrundlage (Art. 6 Abs. 1 lit. f)
- [ ] Betroffenenrechte: Alle 7 Rechte genannt (Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit, Widerspruch, Widerruf)
- [ ] Beschwerderecht bei Aufsichtsbehörde mit Hinweis auf zuständige Behörde

**Pro erkanntem externen Dienst:**
- [ ] Dienst einzeln aufgeführt (nicht pauschal "Drittanbieter")
- [ ] Was erhoben wird
- [ ] Rechtsgrundlage (Einwilligung Art. 6 Abs. 1 lit. a oder berechtigtes Interesse lit. f)
- [ ] Bei US-Diensten: Hinweis auf Drittlandtransfer + Schutzmaßnahmen (SCCs)
- [ ] AVV-Hinweis falls Auftragsverarbeitung

**Kontaktformular (falls vorhanden):**
- [ ] Welche Felder werden erhoben
- [ ] Speicherdauer angegeben
- [ ] Rechtsgrundlage genannt

**Häufig vergessen:**
- [ ] Newsletter: Double-Opt-In erwähnt, Speicherdauer der E-Mail-Adresse
- [ ] Google Fonts: Falls extern → in DSE aufführen mit IP-Übertragung
- [ ] Kommentarfunktion (WordPress): Gravatar, IP-Speicherung
- [ ] Einbettungen (YouTube, Maps): Vor Einwilligung keine Datenübertragung

## Output

Liefere 0-N konkrete Findings. Format:

```
[Datenschutz] {Was fehlt oder unvollständig ist} — {Konkreter Fix in einem Satz}
Schwere: Kritisch / Wichtig / Nice-to-have
```

Wenn alles in Ordnung: `Datenschutz: Keine Findings.`

Priorisierung:
- Kritisch: DSE fehlt komplett, erkannte Dienste nicht aufgeführt, Betroffenenrechte fehlen
- Wichtig: Einzelne Abschnitte unvollständig, Speicherdauer fehlt, AVV nicht erwähnt
- Nice-to-have: Formulierungen verbessern, Aktualisierungsdatum ergänzen
