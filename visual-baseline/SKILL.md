---
name: visual-baseline
description: "Visual baseline capture and design review. Takes screenshots of all project pages (desktop + mobile, light + dark mode), compares against baseline via pixelmatch, runs multimodal design review (spacing, typography, colors, components, layout). Use when the user runs /visual-baseline, says 'visual audit', 'screenshot review', 'design QA', or wants to verify a visual change before merge. Use 'update' to refresh baseline, 'approve' to accept current state."
when_to_use: "/visual-baseline, visual audit, screenshot baseline, design review"
argument-hint: "[optional: update | approve | full]"
model: claude-sonnet-4-6
effort: medium
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
---

# Visual Baseline: Screenshot Capture & Design Review

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Schritt 0 beginnen.**

## Argumente

| Argument | Bedeutung |
|----------|-----------|
| (keins) | Initial-Capture: alle Seiten screenshoten, Baseline erstellen, Review |
| `update` | Inkrementell: nur geänderte Views neu screenshoten, Diff gegen Baseline |
| `approve` | Aktuelle Screenshots als neue Baseline übernehmen |
| `full` | Alles neu screenshoten (Baseline überschreiben) + Review |

---

## 0. Setup & Erkennung

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCREENSHOTS_DIR="$PROJECT_ROOT/.claude/screenshots"
MANIFEST="$SCREENSHOTS_DIR/manifest.json"
```

### Framework erkennen

```bash
bash "${CLAUDE_PROJECT_DIR:-$(dirname "$0")}/bin/detect-routes.sh" "$PROJECT_ROOT"
```

Ergebnis: `ROUTES_JSON` — Array von Route-Objekten:
```json
[
  {"slug": "homepage", "url": "/", "view_files": ["index.html"], "auth": false},
  {"slug": "blog-index", "url": "/blog", "view_files": ["blog.html"], "auth": false}
]
```

### Dev-Server prüfen

Prüfe ob der Dev-Server erreichbar ist:

```bash
# Versuche die Base-URL zu ermitteln
BASE_URL=""
if [ -f "$PROJECT_ROOT/.env" ]; then
  BASE_URL=$(grep -E '^APP_URL=' "$PROJECT_ROOT/.env" | cut -d= -f2- | tr -d '"' | tr -d "'")
fi
if [ -z "$BASE_URL" ]; then
  # Vite default
  BASE_URL="http://localhost:5173"
fi

# Health-Check
curl -sf "$BASE_URL" >/dev/null 2>&1
```

Wenn nicht erreichbar:
1. Prüfe CLAUDE.local.md — wenn dort steht "nie eigenen Server starten" o.ä., User fragen
2. Sonst: Dev-Server als Background-Prozess starten und am Ende wieder stoppen:
   ```bash
   npm run dev &
   DEV_PID=$!
   # Warten bis Server bereit
   for i in $(seq 1 30); do curl -sf "$BASE_URL" >/dev/null 2>&1 && break; sleep 1; done
   ```
3. Am Ende des Skills: `kill $DEV_PID 2>/dev/null` (nur wenn wir den Server selbst gestartet haben)

### Verzeichnisse anlegen

```bash
mkdir -p "$SCREENSHOTS_DIR"/{baseline,current,diffs}/{desktop,mobile}
```

### Prüfe ob pixelmatch verfügbar ist

```bash
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js wird benötigt für pixelmatch-Diffs."
  exit 1
fi

# pixelmatch + pngjs installieren falls nötig (im Skill-Verzeichnis)
SKILL_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
if [ ! -d "$SKILL_DIR/node_modules/pixelmatch" ]; then
  (cd "$SKILL_DIR" && npm install --save pixelmatch pngjs 2>/dev/null)
fi
```

### Auth (falls nötig)

Wenn Routes mit `"auth": true` existieren:

1. Prüfe ob ein Test-User existiert:
   - Laravel: `database/seeders/` nach User-Erstellung suchen, oder `.env` nach Test-Credentials
   - Next.js: Seed-Dateien oder `.env.local` prüfen
2. Login-Flow durchführen:
   - `navigate_page` → Login-URL
   - `fill_form` mit Test-Credentials
   - `click` Submit
   - Session-Cookie bleibt für alle weiteren Navigationen erhalten

---

## 1. Argument-Weiche

| Argument | Springe zu |
|----------|-----------|
| (keins) | Schritt 2 (Initial Capture) |
| `update` | Schritt 3 (Inkrementelles Update) |
| `approve` | Schritt 5 (Approve) |
| `full` | Schritt 2 (wie Initial, überschreibt Baseline) |

---

## 2. Capture: Screenshots erstellen

### Varianten-Matrix

Für jede Route werden folgende Varianten gescreenshotet:

| Variante | Viewport | Theme |
|----------|----------|-------|
| desktop-light | 1280x800 | light |
| desktop-dark | 1280x800 | dark |
| mobile-light | 375x812, mobile, touch | light |
| mobile-dark | 375x812, mobile, touch | dark |

### Ablauf: Puppeteer Headless Capture

Screenshots werden headless via Puppeteer erstellt (kein offenes Browser-Fenster nötig).

**Config-JSON erstellen** und an das Capture-Skript übergeben:

```bash
# Config zusammenbauen aus ROUTES_JSON und BASE_URL
cat > /tmp/visual-baseline-config.json <<EOF
{
  "baseUrl": "$BASE_URL",
  "outputDir": "$TARGET_DIR",
  "themeMechanism": "auto",
  "routes": $ROUTES_JSON
}
EOF

# Optional: Auth-Konfiguration hinzufügen wenn Routes mit auth:true existieren

# Capture starten
node "${SKILL_DIR}/bin/capture-screenshots.js" /tmp/visual-baseline-config.json
```

`TARGET_DIR` ist:
- Initial/Full: `$SCREENSHOTS_DIR/baseline`
- Update: `$SCREENSHOTS_DIR/current`

Das Capture-Skript:
- Erkennt automatisch den Theme-Mechanismus (data-theme, class-dark, prefers-color-scheme)
- Deaktiviert alle Animationen (GSAP, CSS transitions, CSS animations)
- Setzt Opacity auf 1 für alle animierten Elemente
- Konvertiert fixed/absolute Overlays zu static (für fullPage Screenshots von SPA-Modals)
- Wartet auf dynamischen Content (SPA-Seiten, Blog-Posts)
- Unterstützt `waitFor` Selector pro Route für spezifische Wartelogik
- Gibt JSON-Manifest auf stdout aus

### States (Empty, Modal, etc.)

Für Routes die verschiedene States haben, zusätzliche Route-Einträge in der Config anlegen:

1. **Default State** — immer screenshoten (Seite wie sie ist)
2. **Empty State** — eigene Route mit Suffix `-empty`, z.B. `{"slug": "dashboard-empty", "url": "/dashboard?empty=true"}`
3. **Modal State** — eigene Route mit Suffix `-modal-{name}`, per `waitFor` den Modal-Selector angeben
4. **Offcanvas/Menu** — eigene Route mit Suffix `-menu`, per `waitFor` den Menu-Selector angeben

States werden im Manifest unter ihrem Slug dokumentiert.

### Manifest schreiben

Nach dem Capture das Manifest aktualisieren:

```json
{
  "generated": "2026-04-13T14:00:00Z",
  "base_url": "http://localhost:5173",
  "framework": "vite",
  "theme_mechanism": "data-theme",
  "routes": {
    "homepage": {
      "url": "/",
      "auth": false,
      "view_files": ["index.html", "src/js/portfolio-page.js"],
      "screenshots": {
        "desktop-light": "baseline/desktop/homepage--light.png",
        "desktop-dark": "baseline/desktop/homepage--dark.png",
        "mobile-light": "baseline/mobile/homepage--light.png",
        "mobile-dark": "baseline/mobile/homepage--dark.png"
      },
      "captured_at": "2026-04-13T14:00:00Z"
    }
  }
}
```

Weiter mit Schritt 4 (Review).

---

## 3. Inkrementelles Update

```bash
# Geänderte View-Dateien seit letztem Commit
CHANGED_VIEWS=$(git diff --name-only HEAD~1 | grep -E '\.(blade\.php|html|vue|tsx|jsx|svelte|astro)$' || true)
```

Wenn `CHANGED_VIEWS` leer → "Keine View-Änderungen seit letztem Commit. Nichts zu tun."

Sonst: Manifest lesen, betroffene Routes ermitteln:

```
Für jede geänderte View-Datei:
  → Manifest durchsuchen: welche Route hat diese Datei in view_files?
  → Diese Route neu screenshoten → current/
```

Danach Diff:

```bash
node "${SKILL_DIR}/bin/diff-screenshots.js" "$SCREENSHOTS_DIR"
```

Ergebnis: `report.json` mit Diff-Prozent pro Screenshot + Diff-Bilder in `diffs/`.

Weiter mit Schritt 4 (Review) — aber nur für geänderte Routes.

---

## 4. Design Review

Für jeden Screenshot (oder nur geänderte bei `update`):

```
Agent(
  prompt: "Lies agents/review-agent.md und führe den Review aus.

    SCREENSHOTS: {Liste der Screenshot-Pfade}
    DIFF_IMAGES: {Liste der Diff-Bilder, falls vorhanden}
    DIFF_REPORT: {Inhalt von report.json, falls vorhanden}
    ROUTE: {Route-Slug}
    VARIANT: {desktop-light, desktop-dark, mobile-light, mobile-dark}
    FRAMEWORK: {Framework}
    PROJECT_ROOT: {PROJECT_ROOT}",
  subagent_type: general-purpose,
  model: sonnet
)
```

**WICHTIG:** Der Review-Agent muss die Screenshot-Dateien per Read-Tool lesen (multimodal). Er bekommt NICHT den Screenshot als Text, sondern liest die PNG-Datei direkt.

### Parallel dispatchen

Pro Route einen Review-Agent starten (max 4 parallel). Jeder Agent reviewed alle 4 Varianten seiner Route.

### Scoring

Der Review-Agent gibt pro Route Scores zurück:

| Kategorie | Score (1-10) | Beschreibung |
|-----------|-------------|--------------|
| Spacing | 1-10 | Konsistente Abstände, Padding, Margins |
| Typography | 1-10 | Schriftgrößen, Line-Heights, Lesbarkeit |
| Colors | 1-10 | Farbpalette, Kontrast, Konsistenz |
| Components | 1-10 | Buttons, Inputs, Cards — einheitlich? |
| Layout | 1-10 | Struktur, Alignment, Responsive |
| Dark Mode | 1-10 | Kontrast, Lesbarkeit, keine vergessenen Elemente |
| Mobile | 1-10 | Touch-Targets, kein Overflow, lesbar |
| Gesamt | Durchschnitt | Gewichteter Durchschnitt |

### Review-Report schreiben

```
.claude/screenshots/review-{DATUM}.md
```

Inhalt:
- Scores pro Route und Kategorie
- Findings (konkrete Probleme mit Screenshot-Referenz)
- Gesamt-Score
- Empfehlungen

### Review im Chat anzeigen

Den kompletten Review-Report als Markdown im Chat ausgeben.

---

## 5. Approve: Baseline aktualisieren

Wenn Argument `approve`:

```bash
# current/ wird zur neuen baseline/
rm -rf "$SCREENSHOTS_DIR/baseline"
mv "$SCREENSHOTS_DIR/current" "$SCREENSHOTS_DIR/baseline"
rm -rf "$SCREENSHOTS_DIR/diffs"
mkdir -p "$SCREENSHOTS_DIR"/{current,diffs}/{desktop,mobile}
```

Manifest aktualisieren: `captured_at` auf jetzt setzen.

Wenn **automatisch** (nach Review mit Gesamt-Score >= 7.0):

```
Alle Scores >= 7.0 — Baseline automatisch aktualisiert.
```

Wenn Score < 7.0:

```
Design-Score unter 7.0 — Baseline NICHT aktualisiert.
Findings im Review-Report. Bitte prüfen und ggf. /visual-baseline approve.
```

---

## 6. Gitignore

Stelle sicher dass Screenshots nicht ins Repo gelangen:

```bash
GITIGNORE="$PROJECT_ROOT/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qF '.claude/screenshots' "$GITIGNORE"; then
    printf '\n.claude/screenshots/\n' >> "$GITIGNORE"
  fi
fi
```

---

## Abschluss

```
Visual Baseline abgeschlossen.
- Seiten: {N_ROUTES}
- Screenshots: {N_SCREENSHOTS} ({N_DESKTOP} Desktop, {N_MOBILE} Mobile)
- Themes: Light + Dark
- Gesamt-Score: {SCORE}/10
- Review: .claude/screenshots/review-{DATUM}.md
```
