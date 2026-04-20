---
name: dsgvo
description: "GDPR/DSGVO compliance check for German/EU websites. Detects external services (Google Fonts, Analytics, Tag Manager, Maps, YouTube, Facebook Pixel, Hotjar, CDNs) via curl and code scans, dispatches 5 parallel subagents (Impressum, Datenschutzerklärung, Cookies, External Services, Technical), and produces prioritized fixes plus ready-to-use legal texts."
when_to_use: "/dsgvo, DSGVO check, GDPR audit, privacy compliance, Datenschutzerklärung, Impressum, cookie banner, LG München Google Fonts, § 5 DDG"
argument-hint: "[url or project path]"
model: claude-sonnet-4-6
effort: medium
allowed-tools:
  - Agent
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
---

# /dsgvo — DSGVO-Compliance-Check

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Schritt 1 beginnen.**

## Anti-Patterns

- "Ich bin kein Anwalt und kann keine Rechtsberatung geben..." → Kein Disclaimer-Einleitungstext. Direkt loslegen.
- Auf alle Punkte gleichzeitig eingehen → Erst analysieren, dann priorisiert ausgeben.
- Generische Hinweise ("Sie sollten Datenschutz beachten") → Nur konkrete, umsetzbare Fixes.
- "Das hängt von Ihrem Einzelfall ab" → Immer eine konkrete Empfehlung geben, Ausnahmen danach nennen.

---

## Eingabe erkennen

```
Argument = URL?           → Website live analysieren (Schritt 1a)
Argument = Projektpfad?  → Lokalen Code analysieren (Schritt 1b)
Argument = beides?        → Beides kombinieren
Kein Argument?            → Frage nach URL oder Pfad via AskUserQuestion
```

---

## Schritt 1: Kontext ermitteln

### 1a — Live-URL analysieren

Rufe die URL auf und prüfe via Bash (curl + grep) sowie durch Lesen des HTML:

```bash
URL="{eingabe-url}"

# HTTP-Headers prüfen
curl -sI "$URL" | grep -iE "strict-transport|content-security|x-frame|referrer-policy|permissions-policy"

# HTML laden
HTML=$(curl -sL "$URL")

# Externe Ressourcen finden
echo "$HTML" | grep -oE '(src|href)="https?://[^"]*"' | grep -v "$(echo $URL | sed 's|https\?://||;s|/.*||')" | sort -u

# Google Fonts prüfen
echo "$HTML" | grep -i "fonts.googleapis\|fonts.gstatic"

# Google Analytics / GTM
echo "$HTML" | grep -iE "google-analytics|googletagmanager|gtag\(|ga\("

# Google Maps
echo "$HTML" | grep -i "maps.googleapis\|maps.google"

# YouTube
echo "$HTML" | grep -i "youtube.com/embed\|youtu.be"

# Facebook Pixel
echo "$HTML" | grep -i "connect.facebook\|fbq\("

# Hotjar
echo "$HTML" | grep -i "hotjar\|hj\("

# Externe CDNs
echo "$HTML" | grep -iE "cdnjs|jsdelivr|unpkg|stackpath|maxcdn|bootstrapcdn|jquery.*cdn"

# Formulare
echo "$HTML" | grep -i "<form"

# Cookie-Banner vorhanden?
echo "$HTML" | grep -iE "cookieconsent|cookie-banner|cookie-notice|usercentrics|cookiebot|klaro|tarteaucitron|borlabs"

# Impressum-Link
echo "$HTML" | grep -iE "impressum|imprint"

# Datenschutz-Link
echo "$HTML" | grep -iE "datenschutz|privacy|datenschutzerklärung"
```

### 1b — Lokaler Code

```bash
PROJECT_ROOT="{eingabe-pfad}"

# Externe Ressourcen in Templates/HTML/JS
grep -r "fonts.googleapis\|fonts.gstatic" "$PROJECT_ROOT" --include="*.html" --include="*.php" --include="*.blade.php" --include="*.vue" --include="*.tsx" --include="*.jsx" --include="*.js" -l 2>/dev/null

grep -r "google-analytics\|googletagmanager\|gtag(" "$PROJECT_ROOT" --include="*.html" --include="*.php" --include="*.blade.php" --include="*.vue" --include="*.tsx" --include="*.jsx" --include="*.js" -l 2>/dev/null

grep -r "maps.googleapis\|maps.google" "$PROJECT_ROOT" -l 2>/dev/null

grep -r "youtube.com/embed" "$PROJECT_ROOT" -l 2>/dev/null

grep -r "connect.facebook\|fbq(" "$PROJECT_ROOT" -l 2>/dev/null

grep -r "hotjar" "$PROJECT_ROOT" -l 2>/dev/null

grep -r "cdnjs\|jsdelivr\|unpkg\|maxcdn\|bootstrapcdn" "$PROJECT_ROOT" -l 2>/dev/null

# Cookie-Consent-Lösung?
grep -r "cookieconsent\|usercentrics\|cookiebot\|borlabs\|klaro" "$PROJECT_ROOT" -l 2>/dev/null

# Formulare
grep -r "<form" "$PROJECT_ROOT" --include="*.html" --include="*.php" --include="*.blade.php" --include="*.vue" --include="*.tsx" -l 2>/dev/null

# Impressum/Datenschutz-Seite vorhanden?
find "$PROJECT_ROOT" -name "*impressum*" -o -name "*imprint*" -o -name "*datenschutz*" -o -name "*privacy*" 2>/dev/null

# Hosting-Hinweise (without reading .env — check config files instead)
grep -r "APP_URL" "$PROJECT_ROOT/config/app.php" 2>/dev/null || grep "APP_URL" "$PROJECT_ROOT/.env.example" 2>/dev/null || echo "APP_URL not found in config"
```

### 1c — Projekttyp erkennen

```bash
[ -f "$PROJECT_ROOT/artisan" ] && echo "FRAMEWORK=laravel"
[ -f "$PROJECT_ROOT/wp-config.php" ] && echo "FRAMEWORK=wordpress"
[ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" && echo "FRAMEWORK=nextjs"
[ -f "$PROJECT_ROOT/nuxt.config.*" ] && echo "FRAMEWORK=nuxt"
```

---

## Schritt 2: Subagents parallel dispatchen

5 Subagents gleichzeitig dispatchen — jeder prüft einen Bereich:

```
Agent 1: agents/1-impressum.md
Agent 2: agents/2-datenschutz.md
Agent 3: agents/3-cookies.md
Agent 4: agents/4-externe-dienste.md
Agent 5: agents/5-technisch.md
```

Übergib jedem Agent:
- `GEFUNDENE_DIENSTE` (Liste aus Schritt 1)
- `FORMULARE_VORHANDEN` (ja/nein + welche Felder soweit erkennbar)
- `COOKIE_BANNER_VORHANDEN` (ja/nein + welche Lösung)
- `IMPRESSUM_LINK` (ja/nein)
- `DATENSCHUTZ_LINK` (ja/nein)
- `FRAMEWORK` (laravel/wordpress/nextjs/nuxt/generic)
- `URL` (falls vorhanden)
- `HTML_SNIPPET` (erste 200 Zeilen des HTML, falls vorhanden)

---

## Schritt 3: Ergebnis konsolidieren und ausgeben

### Ausgabe-Format

```
## DSGVO-Check — {URL oder Projektname}

### Kritisch (sofort fixen — Abmahnrisiko)
- [Bereich] Problem — Fix

### Wichtig (vor Launch fixen)
- [Bereich] Problem — Fix

### Nice-to-have (best practice)
- [Bereich] Empfehlung

### Sauber
- Bereich1, Bereich2, ...
```

**Priorisierung:**
- **Kritisch** — Klare Rechtsverstöße mit konkretem Abmahnrisiko: Google Fonts extern, kein Impressum, Analytics ohne Consent, Google Maps ohne Consent
- **Wichtig** — DSGVO-Verstöße die seltener abgemahnt werden, aber trotzdem Pflicht sind: fehlende Datenschutzerklärung-Abschnitte, fehlende Betroffenenrechte, kein AVV mit Dienstleistern
- **Nice-to-have** — Best Practices: HSTS, CSP-Header, Matomo statt GA, cookielose Analyse

---

## Schritt 4: Fixes und Texte generieren

### 4a — Code-Fixes direkt anbieten

Für jeden **Kritisch**- und **Wichtig**-Fund: konkreten Fix anbieten.

Beispiele:

**Google Fonts extern → lokal:**
```bash
# Font-Datei herunterladen
curl -o public/fonts/inter.woff2 "https://fonts.gstatic.com/s/inter/v13/..."
```
```css
/* Vorher */
@import url('https://fonts.googleapis.com/css2?family=Inter');

/* Nachher */
@font-face {
  font-family: 'Inter';
  src: url('/fonts/inter.woff2') format('woff2');
  font-display: swap;
}
```

**YouTube ohne Consent → Zwei-Klick-Embed:**
Generiere fertigen HTML-Code mit Vorschaubild-Placeholder der erst nach Klick lädt.

**Google Maps ohne Consent → statisches Bild + Link:**
Generiere Fallback-Lösung.

### 4b — Rechtstexte generieren

Nach den Code-Fixes frage via AskUserQuestion:

```
Fixes ausgegeben. Soll ich auch Rechtstexte generieren?

Erkannte Dienste: {Liste}
```

Optionen:
- **Datenschutzerklärung** — Vollständige DSE basierend auf erkannten Diensten
- **Impressum-Check** — Bestehendes Impressum prüfen oder neues draften
- **Cookie-Banner-Texte** — Einwilligungs- und Ablehnungstexte
- **Alle drei** — Vollpaket
- **Nein, danke** — Nur Code-Fixes reichen

### 4c — Rechtstexte ausgeben

**Wichtiger Hinweis am Anfang jedes generierten Rechtstexts:**
```
// Dieser Text basiert auf den erkannten Diensten und dem Stand der DSGVO (2026).
// Er ersetzt keine Rechtsberatung. Bei Unsicherheit: Anwalt oder e-recht24.de/usercentrics-Generatoren.
// Vor Veröffentlichung: auf Vollständigkeit und aktuelle Rechtslage prüfen.
```

Dann: vollständigen, einsatzbereiten Text ausgeben — kein Lückentext, keine Platzhalter ausser wo zwingend individuelle Angaben nötig (Name, Adresse, USt-IdNr.).

---

## Rechtstext-Wissen

Detaillierte Rechtsreferenzen sind in separate Dateien ausgelagert. Subagents und der Hauptskill lesen sie bei Bedarf:

| Thema | Datei |
|-------|-------|
| Impressum (§ 5 DDG) | `references/impressum.md` |
| Datenschutzerklärung (DSGVO Art. 13/14) | `references/datenschutzerklaerung.md` |
| Cookie-Consent | `references/cookie-consent.md` |
| Externe Dienste — Compliance-Status | `references/externe-dienste.md` |
| WordPress-spezifisch | `references/wordpress.md` |

Jeder Subagent liest die für seinen Bereich relevanten Dateien. Bei Rechtstext-Generierung (Schritt 4c) werden alle relevanten Referenzen geladen.

---

## Tonfall

Direkt und handlungsorientiert. Kein juristisches Kauderwelsch, kein Angst-Marketing.

Gut: "Google Fonts lädt von Google-Servern. Fix: Font-Datei einmal herunterladen, lokal einbinden. Dauert 5 Minuten."
Schlecht: "Im Hinblick auf die einschlägige Rechtsprechung des LG München I ist zu beachten, dass..."

Gut: "Kein Cookie-Banner gefunden, aber Google Analytics ist eingebunden. Das ist ein klarer DSGVO-Verstoß."
Schlecht: "Es könnte möglicherweise dazu kommen, dass gewisse Aspekte überprüft werden sollten."

---

Unabhängig vom Ergebnis aus Schritt 4 immer ausführen.

## Schritt 5: Logging und Learning

### DSGVO-Log schreiben

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$PROJECT_ROOT" ]; then
  DSGVO_LOG_DIR="$PROJECT_ROOT/.claude/dsgvo/logs"
else
  DSGVO_LOG_DIR="$HOME/.claude/dsgvo/logs"
fi
mkdir -p "$DSGVO_LOG_DIR"
DATUM=$(date +%Y-%m-%d)
```

Schreibe `$DSGVO_LOG_DIR/$DATUM-{domain-oder-projekt}.md`:

```markdown
# DSGVO-Check — {URL oder Projektname}

## Meta
- Datum: {DATUM}
- Framework: {FRAMEWORK}
- URL: {URL}

## Gefundene Dienste
- {Liste}

## Ergebnis
- Kritisch: {N} (gefixt: {X})
- Wichtig: {N} (gefixt: {X})
- Nice-to-have: {N}

## Generierte Texte
- Datenschutzerklaerung: ja/nein
- Impressum: ja/nein
- Cookie-Banner: ja/nein
```

### Learning-Agent dispatchen

```
Agent(
  prompt: Lies agents/learning-agent.md und führe den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen DSGVO-Logs}
  subagent_type: general-purpose
  mode: bypassPermissions
  run_in_background: true
)
```
