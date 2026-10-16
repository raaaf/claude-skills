---
name: readiness
description: "Read-only production-readiness audit of one or more app repos against a grouped checklist (auth, data, security, operations, tests, billing, integrations, AI, UX, code, privacy policy and imprint). Detects the stack, marks irrelevant sections N.a., dispatches parallel Explore agents per area group with explicit repo paths, verifies every high-severity claim itself, then writes one collection-and-plan file per app plus an index with urgent gaps, cross-cutting gaps and open decisions. Fixes nothing; each plan package is a later /delegate run. Use when the user asks whether an app is production ready, wants a readiness or launch check across apps, or asks what an app needs beyond a prototype."
when_to_use: "/readiness, ist die App produktionsreif, Production-Readiness prüfen, was fehlt bis Produktion, Launch-Check, alle Apps gegen die Checkliste prüfen, was braucht die App jenseits vom Prototyp"
argument-hint: "<repo path> [<repo path> ...] [--light] [--out <dir>]"
model: inherit
effort: high
allowed-tools:
  - Agent
  - Bash
  - Read
  - Grep
  - Glob
  - Write
  - Edit
  - AskUserQuestion
---

# /readiness: Production-readiness audit

Checks one or more repos against `references/checklist.md`, read-only, with file:line evidence,
and writes per app a collection (what is in place, what is missing) and a plan (packages with a
check criterion). The orchestrator plans, briefs, verifies and writes; Explore agents read.

**Fixing is not part of this skill.** Each plan package is a later `/delegate` run; say so at the
end and stop.

## References

| File | Load when |
|---|---|
| `references/checklist.md` | Phase 1 (relevance) and Phase 2 (paste sections into briefs) |
| `references/agent-briefs.md` | Phase 2: group split per stack, brief template, dispatch settings |
| `references/output-format.md` | Phase 4: app file and index templates |
| `references/lessons.md` | Before Phase 2 (read-only traps) and Phase 4 (patterns for plan check criteria) |

## Hard rules

- **Read-only on every target repo.** No tests, no artisan, no migrations, no installs, no repo
  scripts, no worktrees, no copying `.env` anywhere. Reasons in `references/lessons.md`.
- **Absolute paths everywhere.** Agents get the absolute repo path and are told the repo is not
  their working directory. Never ask an agent to run a review skill (it reviews the session cwd).
  Shell commands on a repo use `git -C <abs path>` or `cd <abs path> && ...`, never `cd` followed
  by `;`.
- **No unverified high-severity finding gets written down.** Phase 3 is not optional.
- **The orchestrator writes all files.** Agents return text in the fixed format.

## Phase 0: Scope

1. Parse args: one or more repo paths (relative to the cwd or absolute), `--light` (one agent per
   app, sections A, C, D, H, K), `--out <dir>` (default: `docs/plans` under the cwd). No path given:
   use the cwd when it is a git repo, otherwise ask which repos to check.
2. Resolve every path to an absolute path and confirm it exists (`test -d`). A missing path is
   reported and skipped, never guessed.
3. Run directory: `<out>/<today>-production-readiness/`. If it exists, follow "Updating an
   existing run" in `references/output-format.md`.

## Phase 1: Profile each app (orchestrator, no agents)

Per repo, read only what decides relevance (root `CLAUDE.md`, `README.md`, manifest files, deploy
script name, a directory listing):

- **Stack**: Laravel/PHP (`composer.json` with `laravel/framework`), Bun/Hono or Node
  (`package.json`), Swift app (`*.xcodeproj`, `project.yml`, `Package.swift`), Cloudflare Worker
  (`wrangler.toml`/`wrangler.jsonc`), or a combination (native client plus backend directory).
- **Live and users**: deployed or not, who uses it (consumers, children, one client, the owner
  only), whether money or health/children's data is involved. Take this from the repo's own docs;
  if they do not say, ask the user once for all apps together.
- **Relevance**: apply the relevance rules in `references/checklist.md` and write down the N.a.
  list with one-line reasons now. A local tool without server or users is skipped and goes into
  the index as "Nicht geprüft".
- **Depth**: full check, or light check for small apps (few users, no payments) and when `--light`
  is set.

Report the profile table (app, stack, live/users, depth, N.a. count) to the user in a few lines
and continue; ask only when an app's users or live status cannot be derived.

## Phase 2: Dispatch Explore agents

Read `references/lessons.md` and `references/agent-briefs.md` first.

1. Per app, split the relevant checklist sections into groups using the table in
   `agent-briefs.md` (Laravel: three groups; native plus backend: two; light check: one).
2. Fill the brief template for each group: absolute repo path, app profile, N.a. list, the
   checklist items of that group pasted verbatim, the fixed return format, word cap, and "no
   recommendation without a concrete code location".
3. Dispatch all groups of an app in one message (`subagent_type: Explore`, `model: sonnet`).
   For several apps, keep about six agents in flight and start the next app when one finishes.

## Phase 3: Verify (orchestrator)

For every returned report:

1. Every `Konkrete Lücken` entry rated `hoch`, and every `OK` that makes a security claim (redirect
   safety, raw SQL, file access, authorization, webhook signatures): open the cited file:line
   yourself and read enough surrounding code to confirm. Check framework-level protections the
   agent may have missed (middleware, policies, framework helpers such as path-tampering guards).
2. Disproved: drop the gap, or move it to "Umgesetzt" marked "(selbst geprüft)". Confirmed: keep
   it, correct the location if the agent's line was off.
3. `mittel`/`niedrig` claims: spot-check at least one per agent; if it is wrong, check the rest of
   that agent's claims of the same kind.
4. Contradictions between two agents of the same app: resolve by reading the code, not by picking
   one.
5. Count how many agent claims were overturned; it goes into the final report.

## Phase 4: Write

Use the templates in `references/output-format.md`.

1. **App file** per app: header line (date, agent count, repo, stack), N.a. section, "Umgesetzt"
   (selection with evidence), "Lücken" (ID, gap, weight, location), "Plan" (packages sized for one
   `/delegate` run each, with an observable check criterion and what they need from the owner).
   Where a gap matches a pattern in `references/lessons.md` (session invalidation with Sanctum,
   deploy script, test gate location, dependency audit gate, per-device deletion), write that
   pattern into the package's check criterion.
2. **Index** (`README.md` in the run directory): status table, "Nicht geprüft" line, open
   decisions (`Produktentscheidung` gaps and anything only the owner can answer, numbered E1...),
   urgent list (`hoch` gaps on exposed or sensitive data, unbounded cost), cross-cutting table
   (same gap in two or more apps, one shared approach), rating scale and the grouped checklist.
3. Write prose in the user's language; keep status values (`OK`, `Teilweise`, `Fehlt`, `N.a.`)
   verbatim.

## Phase 5: Report

Reply in a few lines: run directory path, per app the number of gaps by weight, the urgent list,
how many agent claims Phase 3 overturned, and the open decisions count. Then: "Fixes laufen
paketweise per `/delegate`, beginnend mit den dringenden Paketen." Do not start fixing, and do not
commit the run directory unless the user asks.
