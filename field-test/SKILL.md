---
name: field-test
description: "Unattended QA pass over one repo: captures every surface at several widths, with touch emulation, on Slow 3G (web) and with Dynamic Type, dark mode and a throttled/offline backend (iOS), judges what is broken or feels off, fixes it on a local branch with one commit per fix, saves a before and after PNG per fix and writes report.md incrementally. Never asks questions, never pushes, never touches the main checkout. NOT for a full screenshot catalog (/screens) and NOT for pre-push review (/audit). Use when the user runs /field-test or wants a responsive, touch and slow-network test with fixes."
when_to_use: "/field-test, Feldtest, teste das in verschiedenen Breiten, mit Touch und langsamem Netz, Responsive-Test mit Fixes, Slow-3G-Test, über Nacht testen und fixen"
argument-hint: "<repo-path> [--out <dir>]"
model: inherit
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
---

# /field-test: responsive, touch and slow-network QA pass with fixes

Origin: "Test this in the browser at different widths, with touch emulation, and on a throttled 3G connection. Fix
anything that looks broken or feels off. Save a before and after screenshot for every fix and send me a summary
afterwards." Web and iOS products of Rafael. Plan: `docs/plans/2026-11-11-field-test.md`.

## Unattended rules (read first)

This skill runs overnight with nobody to answer. Hard rules:

- Never call `AskUserQuestion`. Decide from the repo, the design docs and this file; when something is missing, record
  `blocked: <reason>` in the report and move on.
- Never push, never open a PR, never merge, never switch branches or edit anything in the main checkout. All work happens
  in the worktree. The main checkout is read for paths and config only.
- Never start a connector that talks to a real account (family-assistant `connector/` is WhatsApp: never start it).
- Never use real user data: no AutoLogin against a real database, no production credentials. Screenshots stay on disk,
  never in git.
- Write `report.md` after every surface and every fix, so a context compaction or crash loses nothing.
- Every server, proxy and simulator you start is stopped before you finish, also on `blocked`.

## Arguments

`/field-test <repo-path> [--out <dir>]`

- `<repo-path>`: the main checkout. `REPO=$(basename <repo-path>)`. When the caller names a thread that differs from the
  directory (zeit lives in `apps/zeit/app`), use the thread name for `<thread>` and the git root for everything else.
- `--out`: output root. Default `~/Developer/field-test/<YYYY-MM-DD>/<repo-basename>/` (today's date). The orchestrator
  normally passes `--out ~/Developer/field-test/<date>/<thread>`. Below it: `report.md`, `shots/<surface>/...`
  (matrix output), `fixes/<id>-before.png` and `<id>-after.png`.
- Surfaces come from the caller's prompt (e.g. "web app, landing"); without them, discover: web routes from the
  router files, iOS from `*.xcodeproj`.
- Create `report.md` from `references/report-template.md` if it does not exist; otherwise update it in place.

Paths in this file: `$FT` = `~/.claude/skills/field-test`, `$AUDIT_BIN` = `~/.claude/skills/audit/bin`,
`$SCREENS_BIN` = `~/.claude/skills/screens/bin`.

## Worktree bootstrap

1. Git preflight in the main checkout: `git -C <repo> status --short` must be empty (else `BLOCKED: git`, nothing runs).
   `git -C <repo> commit --allow-empty --dry-run -m x` must succeed (a hook or signing prompt means `BLOCKED: git`).
2. Default branch: `git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||'`, fallback `main`,
   then `master` (sprachverliebt uses `master`).
3. `git -C <repo> worktree add ~/Developer/_worktrees/<REPO>-field-test -b fix/field-test-<YYYY-MM-DD> <default-branch>`.
   When the path or branch exists from an earlier run, reuse the worktree (`git -C <wt> status` must be clean or only
   contain your own commits); never delete another run's work.
4. `bash $AUDIT_BIN/worktree-setup.sh <worktree> <repo>` (`.env`, vendor, node_modules, public/build). Failure:
   `blocked: setup`.
5. Build assets when the project has a build step the setup did not run (`npm run build`, `bun run build`).
6. Override `.env` in the worktree only (never the main checkout): `APP_DEBUG=false`, `MAIL_MAILER=log`,
   `QUEUE_CONNECTION=sync`, and blank every third-party API key and webhook secret (Stripe, mail providers, OpenAI,
   WhatsApp, Sentry DSN). Never print `.env` contents in the report.
7. Start the server (next sections) and `curl` the base URL: HTTP 200 (or a 302 to a login page) is required, else write
   `blocked: setup` with the last error line for that surface and go on to the next surface.

All following edits, tests, captures and commits happen in the worktree.

## Headless /screens

`/screens` setup asks questions; field-test never does. Only when a surface needs `screens.mjs up` (isolated database)
or the iOS `ScreensCatalogTests`:

1. Write `<worktree>/.screens/config.json` and `manifest.json` yourself, following
   `~/.claude/skills/screens/references/config-schema.md` (copy the main checkout's `.screens/` files when they exist;
   the folder is gitignored, so it is not in the worktree). Web: `start_command`, `health_url`, `port`, `isolated_db`,
   `env`, `seed_command`. iOS: manifest entries with `id`, `platform`, `view`, `launch_args`, `steps`, `states`, `roles`.
2. `node $SCREENS_BIN/screens.mjs trust --confirm` from the worktree.
3. iOS only: the project needs the UI test target with `ScreensCatalogTests.swift`
   (`~/.claude/skills/screens/templates/`, `references/platform-apple.md`). When the target is missing, add it as the
   branch's first commit `chore: screens scaffolding [field-test]` (XcodeGen `project.yml` plus the template). Scaffolding
   that needs a decision you cannot derive: `blocked: no-test-code` for the iOS axes.
4. `.screens/` stays out of git.

Behavior of `screens.mjs up`, `trust` or the XCUITest filtering that differs from `config-schema.md` and
`platform-apple.md`: stop this surface and report the exact output.

## Server isolation and ports

- Use `node $SCREENS_BIN/screens.mjs up --platform web` when `.screens/config.json` has `start_command` and
  `isolated_db` (zeit: port 8734, database `zeit_screens`). Stop with `screens.mjs down`.
- Otherwise start the repo's documented start command (its CLAUDE.md) from the worktree on a free port: pick one with
  `python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'`, wait for it.
- Verify the listener belongs to the worktree: `lsof -nP -iTCP:<port> -sTCP:LISTEN -t` gives the pid, then
  `lsof -p <pid> | grep cwd` must show the worktree path. When it does not, a main-checkout server owns the port: pick another.
- Login: use the app's local dev login (`/_dev/login/{role}`, see the repo CLAUDE.md "Lokal anmelden") or a seeded demo
  account from the isolated database, passed to `web-matrix.mjs --login-url`. No login path available: capture public
  pages only and write `blocked: login` for the rest.
- Backends that two products default to (sprachverliebt and topf-secret both use :3001) only run while the simulator
  lock is held (`bash $FT/bin/lock.sh acquire`, `release`, `status`; stale when the owner PID is dead or after 120 min).

## Matrix

Web, per surface at most 15 views (landing: `/` plus every linked internal page, at most 10):

- Widths 320, 375, 768, 1024, 1440. Touch emulation (`hasTouch`, `isMobile`) for widths up to 1024. Dark only when the
  app has a dark mode (`--dark`). Slow 3G (400 kbit/s, 2000 ms latency) on 375 only (`--throttle`): time to content,
  layout shift, missing loading states.
- `node $FT/bin/web-matrix.mjs --base-url http://127.0.0.1:<port> --routes-file <file> --out <out>/shots/<surface>
  [--login-url <url> --role <role>] [--throttle] [--dark]`. Output: `<slug>__<width>__<theme>[__3g].png` and
  `metrics.json` (horizontal overflow, tap targets under 44 px, CLS, time to content).

iOS, at most 3 xcodebuild runs per product (run them with `run_in_background` and wait; xcodebuild goes through a global
shim that queues):

1. iPhone SE (3rd generation), content size `large`, light.
2. iPhone 17 Pro Max, `accessibility-extra-extra-extra-large`, dark.
3. One proxy run on iPhone 17 if feasible: `node $FT/bin/slow-proxy.mjs --listen <p> --target http://127.0.0.1:<backend>
   --latency 2000 --kbps 400`, then `--mode offline`. Only when the app takes a backend URL override (for example a
   UserDefaults key passed as launch argument `-<key> <url>` in the manifest entry) and the run uses no demo seed.
   Otherwise write `blocked: no-backend-override` (or `no-seed`), never `covered`.

- `bash $FT/bin/ios-matrix.sh --root <worktree> --xcodeproj <rel> --scheme <s> --ui-target <t> --product <name> --device
  "<name>" --size <size> --appearance light|dark --out <out>/shots/ios [--entries ids]`. It takes the simulator lock
  itself and removes the simulator it created. Exit 3 (device type missing): `blocked: no-device-type`, skip that cell.
  Exit 4: `blocked: sim-lock`.
- iPad only when the target supports it and `xcrun simctl list devicetypes` has the type. Landscape, keyboard-open and
  split view need test code that does not exist: report `blocked: no-test-code`.

## Judging

Load before judging: web `emil-ui-review`, `emil-mobile-native`, `emil-touch-and-accessibility`; iOS `apple-design`,
`write-swift`; plus `rafael-design-system` for products it governs. The repo's `DESIGN.md` and its tokens win over
generic advice; no raw values where tokens exist.

Read the PNGs and `metrics.json` and classify every finding:

- `broken`: horizontal overflow, clipped or overlapping content, unreachable controls, tap targets under 44 px,
  unreadable contrast, truncated text at large Dynamic Type, layout shift, no loading state on Slow 3G, blank or error
  state offline.
- `taste`: spacing, hierarchy, alignment or touch ergonomics that feel off but work.

Both classes are fixed, broken first, at most 20 fixes per repo. Anything that would change the design intent goes to
"Open taste notes" in the report instead.

## Fix loop

Per fix, in this order:

1. Keep the failing PNG as `<out>/fixes/<id>-before.png` (`F1`, `F2`, ...).
2. Edit in the worktree: smallest change, existing components and tokens.
3. Run only affected tests: `bash $AUDIT_BIN/affected-tests.sh <worktree> <default-branch> "<test command>"`, then the
   printed `AFFECTED_CMD`. `AFFECTED=full` means too broad for this loop: run the test files next to the files you
   touched, or skip tests and note it in the report. A test failing twice: undo the fix (`git diff > fix.patch`, then
   `git apply -R fix.patch`, delete the patch) and list it under "Not fixed".
4. Re-capture the same matrix cell (same route, width, theme, touch) as `<out>/fixes/<id>-after.png` and confirm the
   finding is gone; when it is not, undo and list under "Not fixed".
5. `git commit -m "fix(ui): <what> [field-test]"` in the worktree. One commit per fix so each can be dropped alone.
6. Append the row to the fixes table in `report.md` immediately.

## Report

`<out>/report.md` follows `references/report-template.md`: status line `NOT_STARTED|RUNNING|DONE|BLOCKED`, surfaces with
covered and blocked axes, fixes table (id, class, view, cell, before, after, commit), not fixed, open taste notes. Set
`RUNNING` at the start, update after every surface and every fix, set `DONE` only after the last surface closed and the
self-check passed: `git -C <worktree> log --oneline <default>..HEAD` matches the fixes table and
`git -C <repo> log origin/<default>..<default>` is unchanged. Paths in the report are absolute.

## Budgets

3 h per thread, 90 min per iOS product including lock wait. Over budget: finish the current fix, write the report, stop
(`blocked: budget` for what was not reached). 40 tool calls on one step without progress: record the blocker and move on.

## STOP rules

Stop the current surface (not the whole run) and report the exact error when: the server will not start or fails the
200 check (`blocked: setup`), `screens.mjs up`/`trust` or the `ScreensCatalogTests` filtering behave differently from the
schema docs, Playwright cannot be resolved by `web-matrix.mjs`, a fix would require editing `screens/**` or `audit/**`, or
a command would touch the main checkout or a remote. A git preflight failure stops the whole run (`BLOCKED: git`).

At the end: stop all servers, proxies and simulators you started, release the simulator lock when you hold it
(`bash $FT/bin/lock.sh status`), leave the worktree and branch in place, never push.
