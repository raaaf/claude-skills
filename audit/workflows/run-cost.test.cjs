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
test('unknown paid model preserves tokens and marks total unavailable', t => {
  const f = fixture(t); f.write('session.jsonl', [turn('x', 'gpt-native')]);
  const { value } = f.run(); assert.equal(value.usd, null); assert.equal(value.status, 'unavailable'); assert.deepEqual(value.unknown_models, ['gpt-native']);
});
for (const [name, rows] of [['missing usage', [turn('x', 'claude-sonnet-5', 1, { usage: null })]], ['malformed tokens', [turn('x', 'claude-sonnet-5', 1, { usage: { input_tokens: 'bad', output_tokens: 2 } })]], ['malformed JSON', '{broken'], ['empty transcript', []]]) {
  test(name + ' cannot report successful zero cost', t => { const f = fixture(t); f.write('session.jsonl', rows); const { code, value } = f.run(); assert.notEqual(code, 0); assert.equal(value.usd, null); assert.equal(value.status, 'unavailable'); });
}
test('missing transcript reports unavailable JSON', t => { const f = fixture(t); const { code, value } = f.run(); assert.notEqual(code, 0); assert.equal(value.usd, null); });
test('stream without usage is superseded by final snapshot', t => { const f = fixture(t); f.write('session.jsonl', [turn('x', 'claude-sonnet-5', 1, { usage: null }), turn('x')]); assert.equal(f.run().code, 0); });
