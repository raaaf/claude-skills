# Web Driver (Playwright)

Invoked by `/screens` `SKILL.md` Phase 5's driver step (plan step 5) when `.screens/config.json` has
a `web` platform and `screens/templates/capture.spec.ts` has been scaffolded into
`<project>/.screens/web/capture.spec.ts` (Phase 2 scaffold, "Per-project files" table).

## Invocation

From the target project root, after `screens.mjs up --platform web` reported `UP_RESULT=OK`:

```
cd <project root>
npx playwright test .screens/web/capture.spec.ts --workers=4 [--grep <pattern>]
```

`--grep <pattern>` narrows the run to the entry ids `screens.mjs plan`'s `PLAN_ENTRY <id>
{new|stale|missing_png}` lines named (skip `unchanged` ids); omit the flag on a first run or
`--full` (every entry is already planned). Build the pattern as an alternation of entry ids anchored
at the test name's start (test names are `${entry.id} ${state} ${role} ${viewport} ${theme}`, see
below), e.g. `--grep "^(dashboard|clients) "`.

The spec reads `.screens/config.json` and `.screens/manifest.json` from `process.cwd()` at
test-collection time, not per-project templating, so the same `screens/templates/capture.spec.ts`
file works unmodified for every Laravel/web pilot (repo `CLAUDE.md` "Reviewer: every generated
driver must read the manifest at runtime instead of hard-coding entries").

## What the spec does

- One Playwright `test()` per entry x state x role x viewport x theme (states/roles/viewports/themes
  default to `['filled']`/`['guest']`/`config.axes.viewports.web`/`config.axes.themes` when an entry
  omits them).
- `page.clock.setFixedTime('2026-05-12T09:41:00+02:00')` before navigation (topf-secret's
  `-ScreensFixedDate` convention, web equivalent).
- A CSS override disables all animations/transitions (`animation-duration`/`transition-duration:
  0s !important`).
- `context.route('**/*', ...)` allows only `localhost`/`127.0.0.1` requests, aborts everything else
  (no live third-party calls from a demo run; plan's "Dynamic content" edge case).
- Login: `role: "guest"` skips login; any other role posts `config.demo_logins[role]` /
  `config.demo_password` through `/login` (`input[name=email]`, `input[name=password]`, `button[type=submit]`),
  then `waitForLoadState('networkidle')`.
- Navigation: `page.goto(BASE_URL + entry.reach)`, `waitForLoadState('networkidle')`, then
  `entry.ready` (a CSS selector) via `waitForSelector` if set.
- `entry.mask` selectors are hidden (`visibility: hidden`) before the screenshot.
- Output: `.screens/.incoming/web/<entryId>__<state>__<role>__<viewport>__<theme>.png`, `fullPage:
  true`, matching the filename shape `screens.mjs promote` parses (`<entryId>__<rest>.png`).

## Preconditions

- `screens.mjs up --platform web` must have started the service and passed the DB guard;
  `BASE_URL` is `http://127.0.0.1:<config.web.port>` unless `SCREENS_BASE_URL` is set (override for
  a driver invoked outside the skill, e.g. manual debugging).
- Playwright must be a project devDependency (`npm i -D @playwright/test`, `npx playwright install
  chromium` once per machine; plan's "Per-project files" table, "Playwright devDependency where
  missing").

## Multi-step entries

A manifest entry with `steps[]` (Edge Cases: "view only reachable after a multi-step flow") is not
handled by this template; it navigates straight to `entry.reach` only. Multi-step replay is deferred
alongside the marketing renderer (stage c).
