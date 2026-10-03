const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const script = path.resolve(__dirname, '../bin/run-cost.sh');
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-cost-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, write(name, rows) { const file = path.join(root, name); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, typeof rows === 'string' ? rows : rows.map(JSON.stringify).join('\n') + '\n'); }, run() { const r = spawnSync('bash', [script, root, 'session', '--json'], { encoding: 'utf8' }); return { code: r.status, value: JSON.parse(r.stdout) }; } };
}
function turn(id, model = 'claude-sonnet-5', output = 10, extra = {}) {
  return { type: 'assistant', message: { id, model, usage: { input_tokens: 100, output_tokens: output }, ...extra } };
}
test('counts nested actual-model turns, deduplicates snapshots, excludes journal and synthetic errors', t => {
  const f = fixture(t);
  f.write('session.jsonl', [turn('main', 'claude-opus-5', 1), turn('main', 'claude-opus-5', 50), turn('err', '<synthetic>', 0, { usage: { input_tokens: 0, output_tokens: 0 } })]);
  f.write('session/subagents/agent-a.jsonl', [turn('a'), turn('a', 'claude-sonnet-5', 30)]);
  f.write('session/subagents/agent-a/subagents/agent-b.jsonl', [turn('b', 'claude-haiku-4-5', 20)]);
  f.write('session/subagents/journal.jsonl', 'not a transcript');
  const { code, value } = f.run();
  assert.equal(code, 0); assert.equal(value.agents, 2); assert.equal(value.turns, 3);
  assert.equal(value.models['claude-opus-5'].output, 50); assert.equal(value.models['claude-sonnet-5'].output, 30);
  assert.deepEqual(value.unknown_models, []); assert.ok(Math.abs(value.usd - 0.00245) < 1e-10);
});
test('claude-opus-5-5 prices separately from claude-opus-5', t => {
  const f = fixture(t);
  f.write('session.jsonl', [turn('main', 'claude-opus-5-5', 100)]);
  const { code, value } = f.run();
  assert.equal(code, 0); assert.ok(value.models['claude-opus-5-5']); assert.equal(value.models['claude-opus-5'], undefined);
  assert.equal(value.models['claude-opus-5-5'].output, 100); assert.ok(Math.abs(value.usd - 0.0024) < 1e-10);
});
test('unknown paid model preserves tokens and marks total unavailable', t => {
  const f = fixture(t); f.write('session.jsonl', [turn('x', 'gpt-native')]);
  const { value } = f.run(); assert.equal(value.usd, null); assert.equal(value.status, 'unavailable'); assert.deepEqual(value.unknown_models, ['gpt-native']);
});
for (const [name, rows] of [['missing usage', [turn('x', 'claude-sonnet-5', 1, { usage: null })]], ['malformed tokens', [turn('x', 'claude-sonnet-5', 1, { usage: { input_tokens: 'bad', output_tokens: 2 } })]], ['malformed JSON', '{broken'], ['empty transcript', []]]) {
  test(name + ' cannot report successful zero cost', t => { const f = fixture(t); f.write('session.jsonl', rows); const { code, value } = f.run(); assert.notEqual(code, 0); assert.equal(value.usd, null); assert.equal(value.status, 'unavailable'); });
}
test('missing transcript reports unavailable JSON', t => { const f = fixture(t); const { code, value } = f.run(); assert.notEqual(code, 0); assert.equal(value.usd, null); });
test('stream without usage is superseded by final snapshot', t => { const f = fixture(t); f.write('session.jsonl', [turn('x', 'claude-sonnet-5', 1, { usage: null }), turn('x')]); assert.equal(f.run().code, 0); });
const run = args => { const r = spawnSync('bash', [script, ...args], { encoding: 'utf8' }); return { code: r.status, out: r.stdout }; };
const at = (iso, row) => ({ ...row, timestamp: iso });
const usageTurn = (id, model, usage, iso) => at(iso, { type: 'assistant', message: { id, model, usage } });
test('prices match the 2026-10-03 /usage check (cache write = 2 x input)', t => {
  const f = fixture(t);
  f.write('session.jsonl', [usageTurn('o', 'claude-opus-5-5', { input_tokens: 456, output_tokens: 137100, cache_read_input_tokens: 62800000, cache_creation_input_tokens: 638800 })]);
  assert.ok(Math.abs(f.run().value.usd - 20.41) < 0.02);
  const g = fixture(t);
  g.write('session.jsonl', [usageTurn('s', 'claude-sonnet-5-5', { input_tokens: 296000, output_tokens: 2100000, cache_read_input_tokens: 247000000, cache_creation_input_tokens: 18200000 })]);
  assert.ok(Math.abs(g.run().value.usd - 143.78) < 0.02);
});
test('--since counts only messages at or after the cutoff', t => {
  const f = fixture(t);
  const u = { input_tokens: 0, output_tokens: 100000 };
  f.write('session.jsonl', [usageTurn('old', 'claude-sonnet-5', u, '2026-10-01T10:00:00.000Z'), usageTurn('new', 'claude-sonnet-5', u, '2026-10-02T10:00:00.123Z')]);
  const since = String(Date.parse('2026-10-01T12:00:00Z') / 1000);
  const r = JSON.parse(run([f.root, 'session', '--since', since, '--json']).out);
  assert.equal(r.turns, 1); assert.ok(Math.abs(r.usd - 1) < 1e-9);
  const none = JSON.parse(run([f.root, 'session', '--since', String(Date.parse('2026-10-03T00:00:00Z') / 1000), '--json']).out);
  assert.equal(none.turns, 0); assert.equal(none.usd, 0);
});
test('--window sums all projects and agent transcripts, dedups ids, drops older messages', t => {
  const f = fixture(t);
  const u = { input_tokens: 0, output_tokens: 100000 };
  f.write('projA/s1.jsonl', [usageTurn('a', 'claude-sonnet-5', u, '2026-10-02T10:00:00.000Z'), usageTurn('gone', 'claude-sonnet-5', u, '2026-09-20T10:00:00.000Z')]);
  f.write('projA/s1/subagents/agent-x.jsonl', [usageTurn('a', 'claude-sonnet-5', u, '2026-10-02T10:00:00.000Z'), usageTurn('b', 'claude-sonnet-5', u, '2026-10-02T11:00:00.000Z')]);
  f.write('projB/s2.jsonl', [usageTurn('c', 'claude-sonnet-5', u, '2026-10-02T12:00:00.000Z')]);
  const since = String(Date.parse('2026-10-01T12:00:00Z') / 1000);
  assert.equal(run(['--window', f.root, since]).out.trim(), 'WINDOW sessions=2 usd=3.00');
  assert.deepEqual(JSON.parse(run(['--window', f.root, since, '--json']).out), { sessions: 2, usd: 3 });
});
test('orch_usage_report: audit window (session + audit-review dirs) and week window', t => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-usage-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const cwd = fs.realpathSync(home);
  const projects = path.join(home, '.claude/projects');
  const iso = s => new Date(Date.now() - s * 1000).toISOString();
  const row = (id, sec, tokens) => JSON.stringify(usageTurn(id, 'claude-sonnet-5', { input_tokens: 0, output_tokens: tokens }, iso(sec)));
  const put = (rel, rows) => { const p = path.join(projects, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, rows.join('\n') + '\n'); };
  put(cwd.replace(/\//g, '-') + '/sess.jsonl', [row('a', 0, 100000), row('b', 60, 200000)]);
  put('-private-var-folders-xx-audit-review-abc/rev.jsonl', [row('r', 0, 400000)]);
  put('-other-project/o.jsonl', [row('o', 0, 800000), row('old', 8 * 86400, 1600000)]);
  fs.writeFileSync(path.join(home, '.claude/usage-limits.conf'), 'WEEK_RESET_DOW=3\nWEEK_RESET_HOUR=12\nWEEK_RESET_TZ=Europe/Berlin\nWEEK_BUDGET_USD=1000\n');
  const lib = path.resolve(__dirname, '../bin/lib-orchestrator.sh');
  const sh = `. "${lib}"; AUDIT_USAGE_T0=$(( $(date +%s) - 30 )); orch_state_save AUDIT_USAGE_T0; orch_usage_report; orch_state_clear`;
  const r = spawnSync('bash', ['-c', sh], { cwd, encoding: 'utf8', env: { ...process.env, HOME: home, CLAUDE_SKILL_DIR: path.resolve(__dirname, '..') } });
  assert.equal(r.stdout.trim(), 'AUDIT_COST_USD=5.00 AUDIT_COST_WEEK_PCT=0.5 WEEK_USD=15.00 WEEK_PCT_EST=1.5');
});
test('orch_usage_report: finds the session by its usage mark when the audited repo is another directory', t => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-usage-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const cwd = fs.realpathSync(home);
  const projects = path.join(home, '.claude/projects');
  const iso = s => new Date(Date.now() - s * 1000).toISOString();
  const row = (id, sec, tokens) => JSON.stringify(usageTurn(id, 'claude-sonnet-5', { input_tokens: 0, output_tokens: tokens }, iso(sec)));
  const dir = path.join(projects, '-Users-someone-elsewhere');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'sess.jsonl'), [row('a', 0, 100000), JSON.stringify({ type: 'user', text: 'AUDIT_USAGE_MARK=audit-usage-test-mark' })].join('\n') + '\n');
  fs.writeFileSync(path.join(home, '.claude/usage-limits.conf'), 'WEEK_BUDGET_USD=1000\n');
  const lib = path.resolve(__dirname, '../bin/lib-orchestrator.sh');
  const sh = `. "${lib}"; AUDIT_USAGE_T0=$(( $(date +%s) - 30 )); AUDIT_USAGE_MARK=audit-usage-test-mark; orch_state_save AUDIT_USAGE_T0 AUDIT_USAGE_MARK; orch_usage_report; orch_state_clear`;
  const r = spawnSync('bash', ['-c', sh], { cwd, encoding: 'utf8', env: { ...process.env, HOME: home, CLAUDE_SKILL_DIR: path.resolve(__dirname, '..') } });
  assert.match(r.stdout.trim(), /^AUDIT_COST_USD=1\.00 AUDIT_COST_WEEK_PCT=0\.1 /);
});
