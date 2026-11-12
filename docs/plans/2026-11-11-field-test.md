# /field-test: responsive, touch and slow-network QA pass with fixes

> **Executor instruction:** Follow step by step, check each verify criterion before moving on. If a
> STOP condition occurs: stop and report, do not improvise.
>
> **Drift check (first):** `git -C ~/Developer/claude/skills diff --stat 25a8b02..HEAD -- screens/ audit/bin/ field-test/`

## Meta
- Planned at: commit `25a8b02` (skills repo `~/Developer/claude/skills`), 2026-11-11
- Challengers: architecture + risk ran (always). Design skipped (judging uses the existing emil-* and
  apple-design skills). Product and simplicity skipped (user decided scope explicitly).
- Runs unattended overnight 2026-11-11/12. Nobody is available for questions.

## Problem
Emil's prompt ("Test this in the browser at different widths, with touch emulation, and on a
throttled 3G connection. Fix anything that looks broken or feels off. Save a before and after
screenshot for every fix and send me a summary afterwards.") should run over Rafael's products, web
and iOS. There is no repeatable skill; /screens covers widths, theme and roles but not touch,
throttling, Dynamic Type or orientation, and its first-run setup asks questions.

## Goal
`/field-test <repo-path>` runs unattended in one repo and leaves: a local branch
`fix/field-test-2026-11-12` with one commit per fix (no push), a before/after PNG pair per fix, and an
incrementally written `report.md`. A 07:00 task aggregates all reports into one summary Artifact.

## Non-Goals
Android, macOS apps, pushing/merging/PRs, changing /screens for its existing callers, rafaelalex.de.

## Decisions (user, 2026-11-11)
- All listed products tonight, no pilot. Taste fixes allowed; one commit per fix so each can be
  dropped. /screens scaffolding allowed on the fix branch as its own first commit.

## Product list (user, 2026-11-11)
One thread per repo; a thread walks its surfaces in the order given.

| Thread | Repo | Surfaces |
|---|---|---|
| zeit | apps/zeit/app | web app, landing (`resources/landing`) |
| events | apps/events | web app, landing (`resources/views/landing`) |
| family-assistant | apps/family-assistant | web app (`app/`); never start `connector/` (real WhatsApp) |
| dreierpack | apps/dreierpack | web (Hono SSR), iOS |
| sprachverliebt | apps/sprachverliebt | landing (`backend/src/web`), iOS |
| topf-secret | apps/topf-secret | landing (`backend/src/web`), iOS |

All six main checkouts are clean (`git status` 0 lines, 2026-11-11). sprachverliebt's default branch is
`master`.

## Solution

### Approach
New skill `field-test/` in the skills repo. Judging and fixing is agent work in SKILL.md; capture,
throttling, simulator handling and locking are scripts, so six threads behave the same.

- **Web capture: Playwright**, not the chrome-devtools MCP (parallel threads would share its Chrome
  profile). Touch via `hasTouch`/`isMobile` contexts; Slow 3G via CDP `Network.emulateNetworkConditions`
  (400 kbit/s, 2000 ms latency).
- **iOS throttling: `slow-proxy.mjs` in front of the local backend**, never Network Link Conditioner
  (Mac-wide, would throttle the Claude API). Only usable when the app accepts a backend URL override
  (e.g. a UserDefaults key passed as `-<key> <url>` launch argument, see mondbuch `Settings.swift:17`)
  and the run is without demo seed. Otherwise the axis is reported `blocked`, never as covered.
- **Headless /screens.** /screens setup asks questions (`screens/SKILL.md:100`, `:157-159`).
  field-test never calls `AskUserQuestion`; it writes `.screens/config.json` and `manifest.json`
  itself (schema `screens/references/config-schema.md`), then `screens.mjs trust --confirm`.
- **Isolated data.** Web servers run through `screens.mjs up` when `.screens/config.json` has
  `start_command`/`isolated_db` (zeit: port 8734, DB `zeit_screens`). Otherwise from the repo's
  documented start command on a free port, with `.env` overrides in the worktree only:
  `APP_DEBUG=false`, `MAIL_MAILER=log`, `QUEUE_CONNECTION=sync`, third-party API keys blanked. Never
  real user data via AutoLogin.
- **Ports.** Each thread picks a free port at runtime and verifies the listener's cwd is the worktree
  (`lsof -p <pid> | grep cwd`), so a main-checkout server on the usual port is never captured.
- **Simulator lock.** iOS parts take a machine-wide lock (`mkdir ~/Developer/field-test/.sim-lock`,
  removed via `trap`), so only one thread runs simulators at a time. Backends of sprachverliebt and
  topf-secret both default to :3001; the lock covers that too.

### Matrix (budgeted)
- Web, per surface max 15 views: widths 320, 375, 768, 1024, 1440; touch on for <= 1024; dark only if
  the app has dark mode; Slow 3G on 375 only (time-to-content, CLS, missing loading states). Landing
  pages: `/` plus every linked internal page, max 10.
- iOS, max 3 xcodebuild runs per product: (iPhone SE 3rd gen, `large`, light), (iPhone 17 Pro Max,
  `accessibility-extra-extra-extra-large`, dark), plus one proxy run (3G, then offline) on iPhone 17
  if feasible. iPad only if the target supports it and the type exists (`simctl list devicetypes`).
  Landscape, keyboard-open and split view need test code that does not exist: reported `blocked`.
- Wall clock: 3 h per thread, 90 min per iOS product including lock wait. Over budget: finish the
  current fix, write the report, stop.

### Judging and fixing
Load `emil-ui-review`, `emil-mobile-native`, `emil-touch-and-accessibility` (web) or `apple-design`,
`write-swift` (iOS) before judging, plus `rafael-design-system` for products it governs. Classes:
`broken` and `taste`; both are fixed, broken first, max 20 fixes per repo. Per fix: before PNG, edit,
affected tests only (`~/.claude/skills/audit/bin/affected-tests.sh`), after PNG at the same matrix
cell, commit `fix(ui): <what> [field-test]`. A test failing twice: revert, list as not fixed.
DESIGN.md and tokens win over generic advice; no raw values where tokens exist.

### Steps (executor)
1. `field-test/SKILL.md`: frontmatter like `screens/SKILL.md:1-20` (English body, German triggers,
   no `AskUserQuestion` in allowed-tools); sections: arguments, worktree bootstrap
   (`audit/bin/worktree-setup.sh`, then build assets, then HTTP 200 check, else `blocked: setup`),
   headless /screens, server isolation and ports, matrix, judging, fix loop, report, budgets, STOP
   rules, "never push, never touch main checkout" → verify: `grep -c '^## ' field-test/SKILL.md` >= 8;
   `grep -c AskUserQuestion field-test/SKILL.md` = 0 outside a "never" sentence.
2. `field-test/bin/web-matrix.mjs`: `--base-url --routes-file --out [--login-url --role] [--throttle]
   [--widths] [--dark]`; writes `<out>/<slug>__<width>__<theme>[__3g].png` and `metrics.json`
   (horizontal overflow px, tap targets < 44 px, CLS, time-to-content). Playwright pinned as in
   `screens/bin/ui-shots.mjs:29` → verify: against `python3 -m http.server` on a scratch page, 5 PNGs
   and numeric metrics.
3. `field-test/bin/slow-proxy.mjs`: `--listen --target --latency --kbps --mode normal|offline` →
   verify: `curl -w '%{time_total}'` with latency 1000 >= 1.0; offline returns 503.
4. `field-test/bin/ios-matrix.sh`: takes the lock, creates `field-test-<product>-<device>` simulators
   only for existing device types, sets appearance and content size, runs the product's
   `ScreensCatalogTests` with `SCREENS_MANIFEST_PATH` and `TEST_RUNNER_SCREENS_ENTRIES`
   (`screens/references/platform-apple.md`), copies PNGs to the out dir; `trap` shuts down and
   deletes only simulators it created and releases the lock → verify: `bash -n`; dry run on
   sprachverliebt for one entry on iPhone SE produces a PNG and leaves no `field-test-*` simulator.
5. `field-test/bin/lock.sh` (acquire/release/status, stale lock older than 2 h is broken) → verify:
   two concurrent acquires, second waits until release.
6. `field-test/references/report-template.md`: status line (`NOT_STARTED|RUNNING|DONE|BLOCKED`),
   surfaces with covered and blocked axes, fixes table (id, class, view, cell, before, after, commit),
   not fixed, open taste notes → verify: file exists.
7. Symlink `~/.claude/skills/field-test` → verify: `ls ~/.claude/skills/field-test/SKILL.md`.

### Run plan (orchestrator, after review of steps 1-7)
- Output root `~/Developer/field-test/2026-11-12/<thread>/`; the orchestrator pre-creates a
  `report.md` with `NOT_STARTED` per thread. Screenshots never enter git.
- Six threads via `create_threads`, each in a worktree of its repo, prompt `/field-test <repo>`.
- `caffeinate -dims` runs in the background for 10 h.
- 07:00 scheduled task: read all `report.md`, list threads not `DONE`, fall back to
  `git log --grep '\[field-test\]'` per repo, publish a summary Artifact with paths only, no embedded
  screenshots (they may show local data).

### Affected Files
All new: `field-test/SKILL.md`, `field-test/bin/{web-matrix.mjs,slow-proxy.mjs,ios-matrix.sh,lock.sh}`,
`field-test/references/report-template.md`; symlink in `~/.claude/skills/`.

## Out of Scope (Files)
`screens/**` and `audit/**` (shared with other skills, only called). Product repos are changed only by
the overnight runs on their fix branches.

## Edge Cases
- Server does not start or setup fails: `blocked: setup` in the report, next surface.
- No login path: public pages only, rest `blocked: login`.
- iOS thread waits on the lock beyond its budget: report `blocked: sim-lock`.
- Context compaction: report is updated after every surface and every fix.
- Commit hook or signing prompt: preflight `git commit --allow-empty --dry-run`; failing means
  `blocked: git`.

## Known Costs
- No pilot: a miscalibrated rule repeats in all six runs; mitigated by per-fix commits.
- Taste fixes: more commits to review in the morning.
- Landscape, keyboard and split view are not covered on iOS tonight.

## Done Criteria
- [ ] All files in Affected Files exist; steps 2-5 verify commands pass
- [ ] `bash -n field-test/bin/*.sh` → exit 0
- [ ] `xcrun simctl list devices | grep -c field-test-` → 0 after step 4
- [ ] `git -C ~/Developer/claude/skills status --short` → only `field-test/` and this plan

## STOP Conditions
- `ScreensCatalogTests` filtering or `screens.mjs up/trust` behave differently from the description.
- Playwright cannot be resolved via the pinned npx form.
- A step would require editing `screens/**` or `audit/**`.

## Challenge Result
- **Accepted:** headless /screens, no AskUserQuestion (risk 1); isolated DB and env overrides (risk 2,
  arch 6); worktree bootstrap with 200 check (arch 3, risk 3); ports from `.screens/config.json`, free
  port plus cwd check (arch 4, risk 4, convergent); web-matrix uses role login (arch 5); proxy only
  with backend override and without demo seed, else blocked (arch 2, risk 8, convergent); iOS matrix
  budget and timeouts (arch 7, risk 7, convergent); simulator trap, own simulators only, device-type
  check (arch 8, risk 9); affected-tests.sh named (arch 9); report stubs, caffeinate, git-log fallback
  (arch 10, risk 6, convergent); no screenshots in the Artifact, APP_DEBUG=false (risk 10).
- **Rejected:** deny `git push` via thread settings (risk 5): threads share the global settings and a
  repo hook would also affect the main checkout; the skill states "never push", nothing in it pushes,
  and the result is verified in the morning by `git log origin/<default>..` being unchanged.
- **Deferred:** landscape, keyboard-open, split view on iOS: revisit when a field-test-owned XCUITest
  exists.

## Delegate spec

## Task: Build the /field-test skill
**Goal:** the files in Affected Files exist and steps 1-7 verify.
**Context:** skills repo `~/Developer/claude/skills` at `25a8b02`. Exemplars: `screens/SKILL.md`
(frontmatter), `screens/bin/ui-shots.mjs:29` (Playwright pin), `screens/templates/capture.spec.ts`
(viewport :297, emulateMedia :286/:318, role login :99-111), `screens/references/platform-apple.md`
(filtering), `screens/bin/screens.mjs:383-527` (simulator create/boot), `audit/bin/worktree-setup.sh`.
Rules: English body, German only trigger phrases; no emojis, no em-dashes; no new dependencies beyond
the pinned Playwright via npx.
**Affected files:** see Affected Files.
**Out of Scope:** `screens/**`, `audit/**`, any product repo (except read-only dry runs in step 4).
**Steps:** 1-7 above, each with its verify.
**Done criteria (all):** see Done Criteria.
**STOP conditions:** see STOP Conditions.
