# Lessons from the first manual run

Collected from a 14-app readiness run (2026-10-15/16): the audit itself, and the fix round that
followed it. Each entry says what went wrong and what the skill does about it. The audit lessons
apply to every run; the fix-round lessons go into the "Plan" table as check criteria or notes, so
the later `/delegate` runs inherit them.

## Contents

- Audit: agent and path handling
- Audit: verifying findings
- Audit: commands that are not read-only
- Fix-round patterns to write into plans
- Deploy script patterns

## Audit: agent and path handling

- **The built-in code-review skill reviews the session cwd, not the target repo.** An agent told
  to `cd` somewhere and run `/code-review` reviewed the orchestrator's working directory. This
  skill never asks agents to invoke review skills; it dispatches Explore agents with an explicit
  absolute repo path and tells them to use absolute paths in every Read, Grep and Glob call.
- **Never run a command in a checkout after a failed `cd`.** `cd /path/that/moved; git status`
  silently runs in the previous directory. Chain with `&&`, or use `git -C <abs path>`.
- **Agents return, the orchestrator writes.** Explore agents cannot write files; give them a
  return format the orchestrator can paste into the app file without rewording.
- **Name the app's own stack in the brief.** An agent briefed with a generic checklist on a Swift
  app spent its turns on Laravel items. The brief lists the N.a. items explicitly.

## Audit: verifying findings

On the first run, three high-severity agent claims were wrong:

- An open-redirect finding: the redirect helper already rejected foreign hosts.
- A raw-SQL finding (`whereRaw`): the column name came from a whitelist.
- A download IDOR: the admin framework (Filament `preventFilePathTampering`) already blocked
  tampered paths.

Rule: every finding rated `hoch`, and every `OK` that carries a security claim, is opened by the
orchestrator at the cited file:line before it is written down. If the code does not show the gap,
the finding is dropped or moved to "Umgesetzt" with the note "selbst geprüft". Mark self-verified
entries so the reader knows which claims were checked.

## Audit: commands that are not read-only

The audit is read-only. These looked harmless and were not:

- **`composer test` may end with `migrate:fresh --seed`** against the dev database. Do not run a
  repo's test script during the audit; count tests with `find`/`grep` instead.
- **`php artisan --env=testing` may hit the dev database** when no `.env.testing` exists: Laravel
  falls back to `.env`. Never run artisan commands against a repo during the audit.
- **Never copy `.env` into a worktree for a client repo.** A deny rule blocks it for a reason;
  secrets of client projects stay in their checkout. The audit needs no worktree at all.
- **Do not run `npm install`, `composer install` or `bun install` to get an audit report.** Read
  the lockfile and, if a scan is needed, run `composer audit --locked`, `npm audit
  --package-lock-only` or `bun audit` only when they do not modify the tree, and say in the app
  file that the scan ran.

## Fix-round patterns to write into plans

When a gap matches one of these, put the pattern into the package's "Prüfkriterium" so the
`/delegate` run does not rediscover it:

- **Laravel `AuthenticateSession` in the `web` group breaks `auth:sanctum` routes** that share the
  session (SPA or PWA tokens): the middleware logs out a request whose guard is not the session
  guard. Use a guard-aware subclass that skips non-session guards, and test both a web route and a
  Sanctum route after a password change.
- **"End other sessions on password change"** needs a test with two sessions: change the password
  in one, the other is logged out. Personal access tokens (API, PWA) need their own decision.
- **Test gates belong in the ship gate** (`.claude/ship.md` `test-command:`), run locally before
  push, not on the production server. A deploy script that runs the suite on the server needs dev
  dependencies there and slows every deploy.
- **Dependency audit as a gate**: `composer audit` / `bun audit` before maintenance mode, blocking
  on high and critical only.
- **Per-device GDPR deletion** for apps without accounts: one script per backend with the same
  shape (device id in, every table and file for that device out, count printed).

## Deploy script patterns

Seen across several deploy scripts and fixed the same way each time. Use them as check criteria
for any "Deploy" package:

- Wrap the script body in a `main()` function called on the last line, so a script edited during
  a running deploy does not execute half-old, half-new lines.
- Restart services only when the previous step succeeded (guarded restart), never unconditionally
  at the end.
- Health check polls the real application port (or the public URL) with a timeout, not a fixed
  `sleep`.
- One restore function that every failure path calls, instead of per-step rollback snippets.
- Run the dependency audit gate before maintenance mode, so a blocked deploy never takes the site
  down.
- Do not append `|| echo 000` to `curl -w '%{http_code}'`: curl already prints `000` on connection
  failure, and the fallback produces `000000`, which no comparison matches.
