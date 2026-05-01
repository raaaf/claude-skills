# Dispatch Templates

Bash-Logik und Prompt-Templates fuer Phase 2.5 (Codebase-Kontext), Phase 3 (Challengen), Phase 3.5 (Evaluation).

## Phase 2.5: Codebase-Kontext sammeln

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# Framework und Source-Dirs erkennen
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="$PROJECT_ROOT/app/ $PROJECT_ROOT/resources/ $PROJECT_ROOT/database/ $PROJECT_ROOT/routes/ $PROJECT_ROOT/config/"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/app/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/components/ $PROJECT_ROOT/lib/"
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="$PROJECT_ROOT/components/ $PROJECT_ROOT/composables/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/layouts/ $PROJECT_ROOT/server/"
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/lib/ $PROJECT_ROOT/app/"
fi

find $SOURCE_DIRS -maxdepth 2 -type d 2>/dev/null | head -50
```

ZENTRALE_PATTERNS ermitteln:
- Lies CLAUDE.md und extrahiere Architektur-Konventionen (falls vorhanden)
- Falls keine CLAUDE.md: Analysiere die Verzeichnisstruktur auf Patterns (Services, Repositories, Traits, Mixins, Composables)
- Kompakt zusammenfassen in max 10 Zeilen

## Phase 3: Challenge-Dispatch

5 Subagents parallel.

**Product, Design, Simplicity** erhalten nur den Plan:
```
Agent(
  prompt: "Lies agents/challenge-{dimension}.md und pruefe diesen Plan:
    {PLAN_INHALT}",
  subagent_type: general-purpose,
  model: haiku
)
```

**Architecture, Risk** erhalten zusaetzlich den Codebase-Kontext:
```
Agent(
  prompt: "Lies agents/challenge-{dimension}.md und pruefe diesen Plan:
    {PLAN_INHALT}

    Codebase-Kontext:
    DATEISTRUKTUR: {DATEISTRUKTUR}
    ZENTRALE_PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}",
  subagent_type: general-purpose,
  model: sonnet
)
```

| Agent | Datei | Perspektive |
|---|---|---|
| Product | `agents/challenge-product.md` | CEO/Founder — loest das wirklich das Problem? |
| Architecture | `agents/challenge-architecture.md` | Senior Engineer — technisch solide? |
| Design | `agents/challenge-design.md` | Designer — wie fuehlt sich das an? |
| Risk | `agents/challenge-risk.md` | Skeptiker — was kann schiefgehen? |
| Simplicity | `agents/challenge-simplicity.md` | Minimalist — was kann weg? |

## Phase 3.5: Evaluation-Prompt

```
Agent(
  prompt: "Du bist ein erfahrener Tech Lead. Lies diesen Plan und bewerte ihn ehrlich.

    {PLAN_INHALT}

    Codebase-Kontext:
    DATEISTRUKTUR: {DATEISTRUKTUR}
    ZENTRALE_PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}

    Bewerte den Plan in diesen Dimensionen (je 1-2 Saetze, kein Filler):

    1. Vollstaendigkeit — Fehlen Schritte? Luecken zwischen 'was steht im Plan' und 'was muesste man tatsaechlich tun'?
    2. Reihenfolge — Stimmt die Abfolge? Abhaengigkeiten falsch oder gar nicht beruecksichtigt?
    3. Aufwand — Scope realistisch? Wird etwas unterschaetzt oder aufgeblaeht?
    4. Risiken — Was ist das groesste Risiko das der Plan nicht adressiert?
    5. Umsetzbarkeit — Kann ein Entwickler den Plan nehmen und direkt loslegen, oder fehlen konkrete Details?

    PFLICHT-Checkliste (knapp pruefen):
    - Monitoring/Alerting-Blindspots: Failure-Modi die der Plan nicht observable macht?
    - Bestehende Feature-Ueberlappungen: aehnliche Features in der Codebase die wiederverwendet werden sollten?
    - Optimierungs-Hebel: Parallelisierung, Caching, Batch-Processing — wo laesst sich Aufwand reduzieren?

    Am Ende: Ein Gesamturteil in EINEM Satz.
    Falls Aenderungen empfohlen: maximal 3 konkrete Vorschlaege.",
  subagent_type: general-purpose,
  model: sonnet
)
```
