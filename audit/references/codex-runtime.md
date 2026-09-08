# Shared native audit runtime (Claude and Codex)

- [Initialize](#initialize)
- [Native dispatch and responses](#native-dispatch-and-responses)
- [Completion and resume](#completion-and-resume)
- [Native learning](#native-learning)
- [Shared installation for Claude and Codex](#shared-installation-for-claude-and-codex)

Use this bridge for both `AUDIT_RUNTIME=claude` and `AUDIT_RUNTIME=codex`. The historical
filename `codex-runner.cjs` is retained for compatibility. Resolve `AUDIT_ROOT` from the
loaded `audit/SKILL.md`; for full-audit resolve its sibling audit directory. Set
`PROJECT_ROOT` to the current checkout. `AUDIT_DIR` is `$PROJECT_ROOT/.claude/audits`
in Claude and `$PROJECT_ROOT/.codex/audits` in Codex. Run the shared prechecks and
Phases 2 through 4. Do not call a provider CLI, external API, or `Workflow`; nested
Workflow resume has replayed completed agents. The disk bridge is the single execution
path, with native dispatch selected below. Claude retains its hook/accounting and
learning instructions; the Native learning section below applies only to Codex.

## Initialize

Write ordinary workflow arguments to an absolute JSON file, then invoke:

```sh
node "$AUDIT_ROOT/workflows/codex-runner.cjs" init find "$ARGS_FILE" "$RUN_DIR"
node "$AUDIT_ROOT/workflows/codex-runner.cjs" step "$RUN_DIR"
```

Use a fresh directory below `AUDIT_DIR` for each find or fix run. `init` refuses
an existing directory. Find arguments contain `repoRoot`, `scope`, `files`,
`dimensions`, `effort`, `promptDir`, `guidelinesDir`, `guidelines`, and optional
`dimensionDoc`, exactly as in the workflow contract. Use absolute prompt and
guideline directories. `promptDir` defaults to `AUDIT_ROOT/agents`. Pass every
scope file unchanged. Do not truncate the list or construct `fileContents` in
model context: init reads every listed file directly and stores its full contents
in the run's args.json, overriding any caller-supplied content map. Missing files,
parent traversal, environment files and symlinks escaping repoRoot are rejected.

Fix uses `init fix`, a different fresh directory, and arguments `repoRoot`,
`fixes: [{file, findings}]`, `promptDir`, `testCommand`, `baselineFailures`,
`budget`, and absolute `auditBin`. Preserve verified finding IDs and severities.
The core excludes Minor findings. Fixers own only their assigned file.

Record the checkout's HEAD and scope in the audit log. Before every resume, the
orchestrator checks HEAD again and starts a new find run if it changed. The bridge
executes no git or shell commands itself.

## Native dispatch and responses

`step` writes no model output to stdout. It returns compact JSON:

```json
{"status":"pending","pending":[{"id":"sha256","requestPath":"/absolute/run/requests/sha256.json","phase":"Scout","agentType":"Explore","model":"gpt-5.6-sol","fork_turns":"none","agent_type":"explorer"}],"failed":[],"outputPath":null,"cost":{"status":"unavailable","usd":null}}
```

Read each request file: `{id, prompt, options: {agentType, model, schema, phase}, codex:
{model, fork_turns, agent_type}}`. Older persisted requests may lack `codex`; use the same
fields derived in `step.pending`. The source `options` remain unchanged so presentation
metadata does not invalidate cached IDs.
Dispatch its prompt plus the JSON response contract below using the current runtime:

- Claude: use `Agent({subagent_type: options.agentType, model: options.model,
  description: options.phase, prompt: briefing, run_in_background: true})`.
  Preserve the source's `sonnet`/`opus` selection. Use the registered role when available;
  otherwise use `general-purpose` and include that role's worker instructions. The local
  Agent contract is documented in `write-a-skill/references/subagents.md` and
  `references/learning-phase.md`. `schema` is not an Agent parameter: include its complete
  JSON in the briefing and validate the returned final text through `submit`. Bind the
  returned native agent ID before waiting for its completion notification. Read its final
  response from that notification or the runtime's returned output location. Never treat
  launch acknowledgements or intermediate commentary as a final result.
- Codex: use native collaboration with the exact `model`, `fork_turns` and `agent_type`
  returned by the bridge. The bridge maps Claude `sonnet` to `gpt-5.6-sol`, and maps the
  `opus` hint used only by a Critical refuter to `gpt-6-astra`. It maps `Explore` to
  `explorer` and otherwise preserves the source role. For example:

  ```js
  spawn_agent({
    task_name: "audit_request_short_id",
    message: briefing,
    model: pending.model,
    fork_turns: pending.fork_turns,
    agent_type: pending.agent_type
  })
  ```

  Never pass Anthropic model IDs or `inherit`, and never omit the mapped model. An unknown
  mapping fails before dispatch. If Sol is unavailable, fail that job explicitly and report
  incomplete coverage. Do not substitute Astra automatically. Preserve the selected role's
  built-in reasoning effort. Bind the returned agent ID before waiting with native
  collaboration tools.

Use the actual session concurrency limit, not the workflow's historical limit
of 16. With four slots including the root, dispatch at most three workers at once;
other active workers consume slots too. Each worker must return exactly one JSON
object matching `options.schema`, without Markdown. This JSON contract overrides
legacy `FIX_RESULT`, `VERDICT` and prose output examples in worker Markdown. Ignore
embedded dispatch examples when they conflict with the runtime mapping above. Obey the source
worker's word limits. Add: "No recommendations without concrete code location."
For reviews require file:line references and no code snippets. Preserve the
no-commit, no-push, no-secrets and file ownership rules in every briefing.

The orchestrator writes the worker's JSON to a response file, or accepts a file
already produced by the worker. Submit the file, not a JSON string in shell:

```sh
node "$AUDIT_ROOT/workflows/codex-runner.cjs" submit "$RUN_DIR" "$JOB_ID" "$RESPONSE_FILE"
node "$AUDIT_ROOT/workflows/codex-runner.cjs" step "$RUN_DIR"
```

The bridge validates JSON and every schema constraint used by find/fix. Unsupported
schema constraints fail explicitly. Invalid replies remain pending and can be
corrected. Accepted responses are immutable. If a native agent fails, times out or
returns no usable result, record the failure explicitly:

```sh
node "$AUDIT_ROOT/workflows/codex-runner.cjs" fail "$RUN_DIR" "$JOB_ID" "Worker interrupted before a usable result"
```

Do not submit `null`, invent an empty finding list, or silently drop the job.
Failure returns null to the core and keeps the final run incomplete. Unexpected
program exceptions stop step with an error; they never become a successful run.
Call step after responses to discover the next frontier, then repeat dispatch.
Immediately after each native launch, persist its association before waiting:

```sh
node "$AUDIT_ROOT/workflows/codex-runner.cjs" bind "$RUN_DIR" "$JOB_ID" "$NATIVE_WORKER_ID"
```

`step.pending` includes `nativeWorkerId` for bound jobs. Binding the same ID is idempotent;
replacing an existing ID or binding a completed/failed job is rejected. On resume, recover
that worker's result or active status instead of redispatching. If a launch was interrupted
before `bind`, inspect native task history using the request ID included in the briefing
before launching anything. Include `Audit request ID: {id}` in every briefing. If the
worker cannot be recovered, record an explicit failure; do not relaunch a fixer whose
edits may already exist. There is no atomic transaction across native launch and disk
binding, so an unbound pending request alone is not proof that it was never launched.

## Completion and resume

Final step returns `status: complete|incomplete`, no pending jobs, and `outputPath`
pointing to the unchanged core result. Inspect both bridge status and core output.
Any failed job or nested incomplete core result blocks a clean completion marker.
Report incomplete coverage and unverified findings explicitly. In Codex, always
report cost unavailable (`usd: null`), never Claude prices or a fabricated zero.

Each step replays deterministic JavaScript with cached, schema-validated responses.
IDs depend on prompt, options, source and input fingerprints, not dispatch order.
The next unresolved frontier is gathered by draining cached promise continuations.
No models or shell commands are executed by the bridge. Completed fixers are never
repeated automatically. There is intentionally no automatic retry command. Explicitly failed jobs are terminal
for this run and stay incomplete on every step. If retry is required, inspect the current
diff and create a fresh run scoped to unresolved work; preserve completed findings and
fixes in the log. Do not clear cached responses or retry completed fixers.

Init snapshots bundled source, prompt/guideline trees and full input content.
Find resume rejects changes to source, prompts, arguments or scoped file contents
before dispatch. Files read by workers outside the explicit scope are not tracked:
restart after relevant external context changes. Git HEAD checks remain the
orchestrator's responsibility. Source snapshots execute only the bundled find/fix
programs with their initial export-meta declaration adapted to native JavaScript.

During a pending fixer, changes to its assigned file are allowed. Submit or explicit
failure checkpoints that file's current content; subsequent external changes block
resume. An external edit to the same file while its fixer is pending cannot be
distinguished from an authorized fix. Changes outside the declared fix files are
not detected by this bridge; inspect the git diff before accepting fixes. Fix files
must remain readable regular files. Deletion/rename requires a new scoped run.
State writes are atomic. A stale `.lock` after process termination requires checking
that no runner process is active before removing it; never delete a live lock.

Legacy i18n policy at `.claude/audits/i18n-locale-gated.txt` remains a read-only
compatibility input. Pass any `perf-measure:` command from resolved Codex guidelines
through `PERF_MEASURE_CMD` to the existing performance helper. Keep test-lock's
shared git directory lock unchanged so both runtimes serialize tests together.

## Native learning

When learning is enabled, dispatch with `agent_type: 'audit-learning-agent'` (or
`agent_type: 'default'` when that role is unavailable), `model: 'gpt-5.6-sol'`, and
`fork_turns: 'none'`. Provide the absolute
`AUDIT_ROOT/agents/learning-agent.md`, PROJECT_ROOT, the actual
audit log and confirmed verdicts. Override all legacy `.claude/audits` write paths
with AUDIT_DIR. The worker returns structured results; the orchestrator writes
learning-log.md and trends there. Preserve the existing explicit user-consent rule
for new suppressions. Never infer recurrence counts from a single current run.

The legacy Claude run ledger and `patterns-store.sh` recurrence backend are not
called in this runtime. Pass `PATTERNS_RECURRENCES=unavailable: Codex recurrence
backend not configured` and record that limitation in the log. The audit-log
template's patterns.json mtime check and the learning-phase recurrence-feed count
check are not applicable without that backend; write this explicitly in Incidents.
This compatibility limitation does not replace finding verification, waive a
failed native job, or justify a fabricated pattern entry. If the learning worker
is unavailable, record learning as unavailable separately from audit coverage.


## Shared installation for Claude and Codex

Install `audit` and `full-audit` together from one source checkout. The Claude paths are canonical
source links; Codex follows those links so both runtimes resolve to the same actual
files without independent copies:

- `~/.claude/skills/audit` points to `{SOURCE}/audit`.
- `~/.claude/skills/full-audit` points to `{SOURCE}/full-audit`.
- `~/.agents/skills/audit` points to `~/.claude/skills/audit`.
- `~/.agents/skills/full-audit` points to `~/.claude/skills/full-audit`.

Expand these home-directory paths to absolute paths when creating the symlinks.

Back up existing directories outside the active skills directories before linking.
Verify each pair resolves to the same actual `SKILL.md` and that both roots contain
the required sibling resources. Changes at SOURCE are immediately shared by both
runtimes; an already-running task may need to reload skill instructions.

On this machine, `~/.claude/hooks/sync-skills.sh` comes from
`/Users/rafael/Developer/claude/skills-personal/hooks/sync-skills.sh`. It honors explicit
symlink overrides only for these two skills, skips stale main-checkout copies and
reports broken targets as an error. Other skills keep their normal sync behavior.
Existing `.skill` ZIPs are distribution snapshots, not runtime sources; rebuild
those explicitly from SOURCE if distributing them.

When SOURCE is a worktree, keep that worktree available for as long as these links
are active. Do not remove it or assume a merge installed a replacement. To move the
shared source later, back up and update only the two canonical Claude links. The
Codex links follow automatically; verify both pairs still resolve to the intended
source files before removing the previous worktree.
No merge or commit is required to use the current worktree source. If the source is later
moved to a stable main checkout, new runs must initialize from that location. Existing runs
snapshot absolute source/prompt paths and are historical records after relocation; do not
rewrite their state to bypass drift checks. Start a fresh scoped run from the new source.
