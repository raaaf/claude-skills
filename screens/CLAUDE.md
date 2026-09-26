# /screens internals

Rules and commands bound to `/screens`'s own tooling. Cross-cutting rules (`run-log.sh`,
`lib-orchestrator.sh`) live in the root `CLAUDE.md`.

## Commands

| Command | Purpose |
|---|---|
| `node --test screens/bin/` | Run the `/screens` CLI test suite (`screens.mjs`'s subcommand branches: plan, promote, guards, trust, affected, ...) |
| `node screens/bin/screens.mjs <plan\|up\|down\|promote\|marketing\|index\|trust\|affected\|migrate-layout\|migrate-output\|macos-export>` | `/screens`' deterministic CLI: `plan` diffs the manifest against fingerprints, `up`/`down` handle isolation lifecycle, `promote` byte-hash-compares captured PNGs into the catalog (resolved via `resolveScreensOutputRoot`: `config.output_dir` when set, else `~/Developer/screens/<project>/`, never inside the project) with an ImageMagick fuzz-tolerance fallback for rendering jitter, `marketing` renders store images, `index` regenerates the project's own `index.html` + `catalog.json` plus the top-level `~/Developer/screens/index.html`, `trust` checks the confirmed command hash, `affected --files <paths>` maps changed files to manifest entry ids (used by `/delegate`), `migrate-layout` moves an older output layout into the current device-class folders, `migrate-output` moves an existing project-local `screenshots/` tree into the resolved central output root once, `macos-export` pulls macOS screenshots (delivered as `XCTAttachment`s, since the macOS UI test runner is sandboxed and cannot write into the project directory) out of the `.xcresult` bundle via `xcrun xcresulttool export attachments` and renames them into `.screens/.incoming/macos/` (platform-apple.md "macOS: attachment export") |
