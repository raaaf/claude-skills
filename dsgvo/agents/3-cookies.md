# Agent: Cookie-Consent-Check

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `5`

## Aufgabe

Prüfe ob Cookie-Consent korrekt implementiert ist. Basis: DSGVO Art. 6 + ePrivacy-Richtlinie.

Lies `references/cookie-consent.md` für Details.

## Eingabe

Du erhältst:
- `COOKIE_BANNER_VORHANDEN` — ja/nein + welche Lösung (Cookiebot, Usercentrics, custom etc.)
- `GEFUNDENE_DIENSTE` — Liste erkannter externer Dienste (Analytics, Marketing etc.)
- `HTML_SNIPPET` — HTML der Seite inkl. Script-Tags
- `FRAMEWORK` — Projekttyp

## Was du prüfst

**Banner-Existenz:**
- [ ] Banner vorhanden wenn nicht-essentielle Dienste erkannt wurden
- [ ] Banner erscheint beim ersten Besuch (vor dem Setzen von Cookies)

**Gestaltung (kein Dark Pattern):**
- [ ] "Ablehnen" genauso prominent wie "Akzeptieren" — gleiche Schriftgröße, gleiche Sichtbarkeit
- [ ] Kein Pre-Checked-Häkchen für nicht-essentielle Kategorien
- [ ] Keine Verschachtelung: Zustimmung nicht versteckt hinter mehreren Klicks
- [ ] Impressum + Datenschutzerklärung im Banner oder darunter sichtbar/erreichbar

**Technische Umsetzung:**
- [ ] Scripts (Analytics, Tracking) laden technisch erst nach Einwilligung — nicht nur Cookie gesetzt
- [ ] Consent widerrufbar: Link "Cookie-Einstellungen" oder "Datenschutz" im Footer vorhanden
- [ ] Granulare Kategorien: Analytics ≠ Marketing ≠ Funktional (nicht alles in einen Topf)

**Essentielle Cookies (kein Consent nötig, aber in DSE erwähnen):**
- Session-Cookie, Login/Auth, Warenkorb, CSRF-Token, Load-Balancing

**Nicht-essentielle Cookies (Consent zwingend nötig):**
- Google Analytics, Hotjar, Facebook Pixel, Marketing/Retargeting, Personalisierung, A/B-Testing

**Häufige Fehler:**
- [ ] Google Analytics im `<head>` ohne Consent-Check → Kritisch
- [ ] Banner lädt selbst von US-Servern ohne Einwilligung (manche Consent-Tools machen das)
- [ ] YouTube-Einbettung ohne Zwei-Klick-Lösung
- [ ] Google Maps lädt beim Seitenaufruf statt nach Klick

## Output

Liefere 0-N konkrete Findings. Format:

```
[Cookies] {Was fehlt oder falsch ist} — {Konkreter Fix in einem Satz}
Schwere: Kritisch / Wichtig / Nice-to-have
```

Wenn alles in Ordnung: `Cookies: Keine Findings.`

Priorisierung:
- Kritisch: Kein Banner, aber Tracking erkannt; Analytics lädt vor Consent; Dark Pattern (Ablehnen versteckt)
- Wichtig: Kein Widerruf möglich; keine Granularität; Banner blockiert Impressum/DSE
- Nice-to-have: Formulierungspräzision, zusätzliche Kategorien
