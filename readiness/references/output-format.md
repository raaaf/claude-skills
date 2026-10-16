# Output format

What the orchestrator writes: one file per app and one index (`README.md`) per run directory.
Headings and table columns below are the German defaults used by the first run; they are
user-facing output. Write prose in the user's language, keep the status values from
`checklist.md` verbatim.

## Contents

- Run directory
- App file template
- Light-check variant
- Index (README.md) template
- Updating an existing run

## Run directory

`<out>/<YYYY-MM-DD>-production-readiness/`, where `<out>` defaults to `docs/plans` under the
current working directory (workspace root when several repos are audited, the repo root when one
is). One file per app, named after the app (`events.md`); several small apps checked lightly may
share one file (`kleine-apps.md`), one `##` section per app. Related apps from one owner or client
may share a file with one `##` section each and a shared plan.

## App file template

```markdown
# <app>: Production readiness

Stand <YYYY-MM-DD>, read-only geprüft (<n> Agents, Stichproben, nicht jede Datei gelesen). Repo:
`<repo path relative to workspace>` (<stack in one line>). Bewertung und Checkliste:
[README.md](README.md). Nichts gefixt.

## Sammlung

### Nicht relevant (N.a.)

<Comma-separated list of N.a. items, each with its reason in parentheses where it is not obvious.>

### Umgesetzt (Auswahl mit Beleg)

| Bereich | Was | Beleg |
|---|---|---|
| A | <what is in place, concrete> | `<file>:<line>` |

### Lücken

| ID | Lücke | Gewicht | Ort |
|---|---|---|---|
| <P>1 | <the gap, concrete, one or two sentences> | hoch | `<file>:<line>` |

## Plan

Jedes Paket ist ein eigener `/delegate`-Lauf mit Repro-Test, wo Logik betroffen ist. Reihenfolge
nach Gewicht und Aufwand.

| # | Paket | Lücken | Prüfkriterium | Braucht |
|---|---|---|---|---|
| P1 | <what gets built> | <P>1, <P>3 | <observable check: a test, a curl, a log line> | <owner input, sudo, or -> |

Später oder nur nach Entscheidung: <gap IDs with one-phrase reason each>.
```

Rules for the tables:

- **Umgesetzt** is a selection, not an inventory: 8 to 16 rows, the ones a reader would otherwise
  doubt (auth, money, deletion, webhooks, headers, tests). Mark rows the orchestrator verified
  for a security claim with "(selbst geprüft)".
- **Lücken** IDs use a short app prefix (`L`, `Z`, `T`, `MB`) plus a number, unique across the
  run, so the index can cite `[henry.md](henry.md) K1`.
- **Gewicht** is one of `hoch`, `mittel`, `niedrig`, `Produktentscheidung`, `bewusst offen`.
  `hoch` means: exploitable, data loss, or unbounded cost. A `Produktentscheidung` gap goes into
  the decisions list, not into a package.
- **Ort** is a file:line or a directory; `-` only for "bewusst offen" rows.
- **Plan** packages are sized for one `/delegate` run each. Every package has a check criterion a
  reviewer can run. "Braucht" names what the agent cannot do alone (owner's sudo, a decision, a
  store console).

## Light-check variant

For small apps (see `checklist.md` relevance rules): per app a `##` section with "Umgesetzt" and
"Lücken" (no N.a. section, a one-line stack note instead), and one shared `## Plan` at the end.

## Index (README.md) template

```markdown
# Production readiness: <scope, e.g. "alle Apps">

<Two or three sentences: what was checked, read-only, with evidence; one file per app with
collection and plan; fixes come later per package via /delegate.>

## Reihenfolge und Stand

| App | Datei | Stand |
|---|---|---|
| <app> | [<app>.md](<app>.md) | Sammlung + Plan fertig, nichts gefixt |

Nicht geprüft (<reason>): <list>.

## Offene Entscheidungen

| # | App | Frage |
|---|---|---|
| E1 | <app or "alle"> | <one question the owner must answer> |

## Dringend (vor allem anderen)

| App | Lücke | Datei |
|---|---|---|
| <app> | <hoch gap in a few words> | [<app>.md](<app>.md) <ID> |

## Querschnitt: dieselbe Lücke in mehreren Apps

| Lücke | Apps | Ansatz |
|---|---|---|
| <gap shared by 2+ apps> | <apps> | <one shared pattern> |

## Bewertung

<The rating scale and relevance rules from checklist.md, in the user's language.>

## Checkliste (gruppiert)

<Sections A to L from checklist.md as one paragraph each, in the user's language.>
```

"Dringend" lists only `hoch` gaps that are exploitable now or touch children's, health or payment
data, plus open questions whose answer could make a gap `hoch` (an env flag nobody can see from
the code). "Querschnitt" lists a gap only when at least two apps share it and one pattern fixes
all of them.

## Updating an existing run

When the run directory already exists (same date, or the user names an earlier run):

- Never delete rows another session added. Add new apps to "Reihenfolge und Stand", extend
  "Querschnitt" app lists, append decisions with the next free `E` number.
- An app file that already exists is rewritten only when the user asked to re-audit that app;
  otherwise leave it and say so.
- A section such as "Umsetzung" added by a later fix round belongs to that round; leave it as is.
