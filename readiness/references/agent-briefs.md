# Agent briefs

How the checklist is split across Explore agents per stack, and the brief every agent gets.

## Contents

- Group split per stack
- Brief template
- Return format
- Dispatch settings

## Group split per stack

One agent per group, all groups of one app in one message so they run in parallel. Sections that
are N.a. for the app are dropped from the group, not handed to the agent with "skip this".

| Stack | Group 1 | Group 2 | Group 3 |
|---|---|---|---|
| Laravel / PHP web app | A Auth, F Billing, G Integrations | B Data, C Security | D Operations, E Tests, I UX, J Code, K Legal, L Web presence |
| Native app + own backend (Bun/Hono, Node, Workers) | Backend: A, B, C, G, H, plus "Native and device-backend additions" (server side) | D Operations, E Tests, iOS/macOS client: I, J, K, L, plus the additions (client side) | - |
| Worker / serverless only | A, B, C, G, H | D, E, I, J, K, L | - |
| Light check (small app) | A, C, D, H, K, L in one agent | - | - |

A Laravel app with AI features adds H to group 2. An app with a public API adds the API rows of G
to group 1. More than three groups costs more than it finds; split a group only when the repo is
large enough that one agent would run out of turns (for example two sub-apps in one repo).

## Brief template

Fill every `<...>`. The brief is self-contained: the agent sees nothing of this skill.

```text
Read-only production-readiness check of one app. Do not modify files, do not run tests, artisan,
migrations, installs or any repo script. Use absolute paths in every Read, Grep and Glob call;
the repo is NOT your working directory.

Repo: <absolute repo path>
App: <name>, <stack in one line>, <live: yes/no, users: who>
Out of scope (N.a., do not check): <list>

Check these items (section letter plus item):
<paste the checklist sections for this group from checklist.md>

For each item decide: OK (implemented, cite file:line), Teilweise (present with a concrete gap),
Fehlt (absent and relevant), N.a. (one-line reason). Read the code that implements the item; a
config key alone is not evidence of behaviour.

Output, exactly this shape, nothing before or after:

## Status
| ID | Punkt | Status | Beleg | Notiz |
|---|---|---|---|---|
(ID = section letter plus running number, e.g. A3. Beleg = file:line relative to the repo, or -
for Fehlt. Notiz max 15 words.)

## Konkrete Lücken
Max 6 entries, highest severity first:
- <ID> | hoch/mittel/niedrig | <gap in one sentence> | <file:line where the fix goes or the
  absence shows>

Rules: no recommendation without a concrete code location. No code snippets. Max <word cap>
words in total. If you run out of turns, return what you have with the unchecked IDs listed under
"Nicht geprüft".
```

Word cap: 700 for a full group, 500 for a light check.

## Return format

The two blocks map onto the app file (`output-format.md`):

- `Status` rows with `OK` and a strong Beleg feed "Umgesetzt" (selection, not all rows).
- `Status` rows with `N.a.` confirm or extend the N.a. section.
- `Konkrete Lücken` plus `Teilweise`/`Fehlt` rows feed "Lücken" after verification.

## Dispatch settings

- `subagent_type: Explore`, `model: sonnet`, foreground (`run_in_background: false`) when the
  orchestrator writes the app file in the same turn; background is fine across several apps if
  the orchestrator waits for all notifications before writing.
- Pass the repo path absolute, never relative to the session cwd.
- Several apps: dispatch per app (2 to 3 agents each), at most about 6 agents in flight at once,
  so verification keeps pace with the returns.
