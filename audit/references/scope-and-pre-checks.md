# Scope & Pre-Checks (Phase 1 Detail)

Detail-Logik fuer Phase 1. Wird vom Orchestrator gelesen wenn Pre-Checks nicht-trivial sind.

## Diff-Size-Gate auswerten

| `DIFF_SIZE_RESULT` | Aktion |
|---|---|
| `OK` | Weiter. `MODEL_OVERRIDE=null` (Subagents nutzen ihre Default-Modelle). |
| `LARGE` (>2000 Zeilen ODER >20 Dateien) | Gezielte Escalation: Nur Architektur und Security laufen auf Opus. Ausgabe: "Diff ist gross ({LINES} Zeilen / {FILES} Dateien) — Architektur + Security laufen auf Opus fuer tieferes Reasoning." Setze `HEAVY_REASONING_OVERRIDE=opus`. Weiter. |
| `HUGE` (>5000 Zeilen; oder >50 Dateien UND >=1000 Zeilen) | Hard-Block: Abbrechen. "Diff zu gross fuer sinnvollen Audit. Bitte in mehrere Commits/PRs splitten." Kein Audit-Lauf. |

**Zweiachsige HUGE-Bewertung:** Ueberschreitet nur die Datei-Achse die Schwelle (>50 Dateien), liegen die Zeilen aber unter 20% der Zeilen-Schwelle (<1000), stuft das Script selbst auf `LARGE` herab und gibt `DIFF_SIZE_NOTE=...` aus. Die Note im Chat ausgeben (Warnung: viele kleine, logisch getrennte Aenderungen) und normal weiterlaufen — kein manueller Override noetig.

**Warum nur zwei Dimensionen escalieren:** Architektur (Code-Reasoning ueber mehrere Module) und Security (subtile Angriffsvektoren) profitieren messbar von Opus. Performance, Code Quality, SEO, A11y, Typography, UI, UX, Animation sind ueberwiegend regel- oder musterbasiert — Sonnet reicht. Triage- und Fix-Agents bleiben auf Haiku.

## Output von collect-scope.sh

`collect-scope.sh` liefert:
- `DEFAULT_BRANCH`, `BASE_REF`
- Klassifizierte Dateilisten: `---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`
- Deduplizierter Unified-Diff: `---DIFF---`

## Output von detect-framework.sh

Liefert: `FRAMEWORK`, `SOURCE_DIRS`.

## Output von pre-checks.sh

Drei Sektionen: `SECRET_SCAN_RESULT`, `LOCKFILE_DRIFT_RESULT`, `BINARY_ARTIFACTS_RESULT`.

## Pre-Check-Auswertung (sofort, vor jedem Subagent-Dispatch)

| Pre-Check | Ergebnis | Aktion |
|---|---|---|
| `SECRET_SCAN_RESULT=FINDINGS` | — | Als **Critical** ins Audit-Log. User sofort warnen. Push wird blockiert bis Secrets entfernt + History bereinigt sind. |
| `LOCKFILE_DRIFT_RESULT=DRIFT` | — | Als **Important** ins Audit-Log. Manifest-Konsistenz pruefen, ggf. Lockfile regenerieren. |
| `BINARY_ARTIFACTS_RESULT=FINDINGS` | — | Als **Important**. Vorschlag: aus Index entfernen, `.gitignore` ergaenzen. |

Wenn der Diff leer ist und alle Pre-Checks `CLEAN`: melden und beenden. Kein Git-Repo? Fehler melden.

## Variablen aus Script-Outputs ableiten

- **ALLE_DATEIEN:** Sektion `---FILES---` aus `collect-scope.sh`
- **FRONTEND_DATEIEN:** Sektion `---FRONTEND---`
- **TRANSLATION_DATEIEN:** Sektion `---TRANSLATIONS---`
- **VISUELL_RELEVANTE_DATEIEN:** `FRONTEND_DATEIEN` + Framework-spezifische Backend-Dateien (z.B. `app/Livewire/`, Controller mit `return view(...)`/`return Inertia::render(...)`). NICHT: reine Services, Models, Migrations, Commands, Jobs, Middleware — ausser sie aendern was an den View uebergeben wird.
- **UNIFIED_DIFF:** Sektion `---DIFF---` (geht nur an Triage, NICHT an Workers)
- **SUPPRESSIONS:** `$(git rev-parse --show-toplevel)/.claude/audits/suppressions.json` laden falls vorhanden, `pattern`-Felder extrahieren. Sonst `"Keine Suppressions"`.
- **PROJECT_CONTEXT:** `## Audit Context` aus `CLAUDE.md` (falls vorhanden), via `awk '/^## Audit Context$/{f=1;next} /^## /{f=0} f'`. Sonst `"Kein projektspezifischer Kontext."`

## Audit-Context-Check (PFLICHT bei fehlendem Context)

Wenn `PROJECT_CONTEXT` leer ist oder die `CLAUDE.md` keinen `## Audit Context`-Abschnitt hat, **vor dem ersten Subagent-Dispatch** User via `AskUserQuestion` fragen, ob ein Context-Abschnitt (Stack/Framework-Regeln, bewusste Architektur-Entscheidungen, Skalierungsziele, kritische Schnittstellen) entworfen und in `CLAUDE.md` ergaenzt werden soll. Optionen:

- **Ja, jetzt anlegen** → Repo-Struktur analysieren (`composer.json`/`package.json`, Routes, README), Vorschlag entwerfen, in `CLAUDE.md` einfuegen, dann Audit fortsetzen.
- **Nein, einmal ueberspringen** → Audit ohne Context fortsetzen.
- **Nie wieder fragen** → Marker `.claude/audit-no-context.flag` anlegen, Audit fortsetzen. Folge-Audits pruefen den Marker und ueberspringen die Frage.

Marker-Check vor der Frage:
```bash
[ -f "$(git rev-parse --show-toplevel)/.claude/audit-no-context.flag" ] && SKIP_CONTEXT_PROMPT=true
```

## Intent-Docs / Decided Tradeoffs (DECIDED_TRADEOFFS)

Bewusste, dokumentierte Entscheidungen duerfen nicht als Findings wiederaufgetischt werden. Deterministisch globben:

```bash
ROOT=$(git rev-parse --show-toplevel)
INTENT_DOCS=$( { ls "$ROOT"/docs/adr/*.md "$ROOT"/docs/adrs/*.md "$ROOT"/docs/decisions/*.md 2>/dev/null
                 ls "$ROOT"/DESIGN.md "$ROOT"/PRODUCT.md "$ROOT"/CONTEXT.md 2>/dev/null; } | sort -u )
```

- Treffer vorhanden → Dateien lesen (bei vielen ADRs: nur Titel + Status + Decision-Zeile je ADR) und als `DECIDED_TRADEOFFS` zusammenfassen: eine Zeile pro Entscheid ("ADR-007: sync-over-async Write in store.ts ist bewusst — Konsistenz vor Latenz"). Max 15 Zeilen.
- Keine Treffer → `DECIDED_TRADEOFFS="keine dokumentierten Entscheidungen gefunden"`.
- Wird an alle Worker durchgereicht (prompt-template.md Platzhalter). Worker-Regel dort: dokumentierte Tradeoffs nicht melden; Code-Drift vom Entscheid ist ein docs_sync-Finding ("stale ADR ist selbst ein Finding").
