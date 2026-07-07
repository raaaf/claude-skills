---
name: improve
disable-model-invocation: true
description: "Use when the user says /improve or wants to discover what the app could do better from a product perspective: feature gaps, growth opportunities, marketing, business potential, unfinished work. Thinks like a product owner, not a code reviewer. For code quality, performance, security, a11y, DX, modernization issues use /audit instead."
model: sonnet
effort: high
context: fork
allowed-tools:
  - Agent
  - Bash
  - Read
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
  - WebSearch
  - WebFetch
---

# Improve: Produkt-Potenzial entdecken

**SOFORT AUSFUEHREN — nicht erklaeren, nicht ankuendigen. Direkt mit Schritt 1 beginnen.**

## Abgrenzung zu /audit

| | /audit | /improve |
|---|---|---|
| **Fragt** | "Was ist kaputt oder schlecht am Code?" | "Was koennte die App als Produkt noch?" |
| **Perspektive** | Code-Reviewer / QA / Tech Lead | Product Owner / Growth Lead / Strategist |
| **Prueft** | Security, Performance, A11y, Code Quality, SEO, DX, Modernisierung | Feature Gaps, Growth, Marketing, Business, unfertige Features |
| **Output** | Findings + Auto-Fix | Priorisierter Report mit Ideen |
| **Fixt** | Ja, automatisch | Nein — User entscheidet |

**NICHT melden (das macht /audit):**
- Code-Qualitaet, DRY, Naming, Architecture
- Performance, N+1, Bundle Size, Caching
- Security, fehlende Validierung
- A11y, SEO (technisch), Typography, UI-Design, UX-Patterns
- Veraltete Dependencies, Modernisierung
- DX, Tooling, Tests, Docs, Setup

## Ablauf

### 1. Projekt-Kontext ermitteln

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Framework erkennen
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="app/ resources/ database/ routes/ config/"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="src/ app/ pages/ components/ lib/ public/"
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="components/ composables/ pages/ layouts/ server/ plugins/"
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
elif [ -f "$PROJECT_ROOT/Gemfile" ]; then
  FRAMEWORK="rails"
  SOURCE_DIRS="app/ config/ db/ lib/"
elif [ -f "$PROJECT_ROOT/wp-config.php" ] || ([ -f "$PROJECT_ROOT/style.css" ] && grep -q "Theme Name" "$PROJECT_ROOT/style.css" 2>/dev/null); then
  FRAMEWORK="wordpress"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -maxdepth 2 \( -name 'functions.php' -o -name 'style.css' \) -exec dirname {} \; | sort -u | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="src/ lib/ app/"
fi

echo "FRAMEWORK: $FRAMEWORK"
echo "---"
echo "Dateistruktur (Top-Level):"
ls -1 "$PROJECT_ROOT" | head -30
echo "---"

# Config/Dependency-Infos
for cfg in composer.json package.json requirements.txt Cargo.toml go.mod Gemfile pyproject.toml; do
  if [ -f "$PROJECT_ROOT/$cfg" ]; then
    echo "=== $cfg ==="
    cat "$PROJECT_ROOT/$cfg" 2>/dev/null | head -80
  fi
done
```

Erstelle:
- **FRAMEWORK:** Erkanntes Framework
- **SOURCE_DIRS:** Relevante Quellverzeichnisse
- **PROJECT_CONTEXT:** Lade `## Audit Context` aus der CLAUDE.md des Projekts:
  ```bash
  PROJECT_CLAUDE_MD="$(git rev-parse --show-toplevel)/CLAUDE.md"
  if [ -f "$PROJECT_CLAUDE_MD" ]; then
    PROJECT_CONTEXT=$(awk '/^## Audit Context$/{found=1; next} /^## /{found=0} found' "$PROJECT_CLAUDE_MD")
  fi
  ```
- **TECH_STACK:** Erkannte Technologien (DB, Cache, Queue, Frontend, CSS etc.)

### 2. Produkt-Analyse dispatchen

Dispatche **einen einzelnen Agent** via Agent-Tool.

Lies die Agent-Definition aus `agents/1-features.md` im Skill-Verzeichnis. Uebergib:
- FRAMEWORK, SOURCE_DIRS, TECH_STACK
- PROJECT_CONTEXT (falls vorhanden)

| Agent-Datei | Modell | Fragestellung |
|-------------|--------|---------------|
| `agents/1-features.md` | `opus` | "Was kann die App — und was koennte sie noch?" |

### 3. Report erstellen

Konsolidiere die Ergebnisse des Agents in folgender Struktur:

```
## Improve Report — {FRAMEWORK} Projekt

### Was die App aktuell kann
Kurze Zusammenfassung (Absatz). Was ist das Produkt, Kern-Features, User-Rollen.

### Quick Wins (< 1h Aufwand, hoher Impact)
1. [Perspektive] Beschreibung — Warum + erwarteter Nutzen
2. ...

### Empfohlene Features (1h-1d Aufwand)
1. [Perspektive] Beschreibung — Warum + erwarteter Nutzen
2. ...

### Strategische Ideen (> 1d Aufwand)
1. [Perspektive] Beschreibung — Warum + erwarteter Nutzen
2. ...

### Unfertige Features
- Feature X (Status: halb fertig) — Datei:Zeile
- ...

### Bereits gut umgesetzt
- Was das Projekt richtig macht
```

**Perspektive** ist jeweils: Produkt / Growth / Marketing / Business

**Priorisierungs-Kriterien:**
1. **Impact auf Endnutzer** > alles andere
2. **Aufwand vs. Nutzen** — Quick Wins zuerst
3. **Naheliegendes zuerst** — Features die zum bestehenden Produkt passen > neue Richtungen

**Keine Findings erfinden.** Wenn ein Bereich stark ist, unter "Bereits gut umgesetzt" listen.

### 4. Naechste Schritte anbieten

Frage den User nach dem Report:
> Soll ich eines dieser Findings direkt umsetzen? Du kannst mir auch eine Nummer nennen.

**WICHTIG: Nicht automatisch anfangen umzusetzen. Der User entscheidet.**
