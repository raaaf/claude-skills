'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { main, validate } = require('./codex-runner.cjs');
const schema = { type: 'object', properties: { value: { type: 'integer' } }, required: ['value'] };
function fixture(t, source) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-native-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const repo = path.join(root, 'repo');
  const prompts = path.join(root, 'prompts');
  fs.mkdirSync(repo); fs.mkdirSync(prompts);
  fs.writeFileSync(path.join(repo, 'index.js'), 'export const value = 1;');
  fs.writeFileSync(path.join(prompts, 'prompt.md'), 'Review files.');
  let run = main;
  if (source) {
    fs.copyFileSync(path.join(__dirname, 'codex-runner.cjs'), path.join(root, 'codex-runner.cjs'));
    fs.writeFileSync(path.join(root, 'find.js'), `export const meta = {};\n${source}`);
    fs.writeFileSync(path.join(root, 'fix.js'), `export const meta = {};\n${source}`);
    run = require(path.join(root, 'codex-runner.cjs')).main;
  }
  const runDir = path.join(root, 'run');
  const argsFile = path.join(root, 'input.json');
  const args = { repoRoot: repo, files: ['index.js'], scope: 'repo', dimensions: ['code_quality'], promptDir: prompts };
  async function init(kind = 'find', extra = {}) {
    fs.writeFileSync(argsFile, JSON.stringify({ ...args, ...extra }));
    return run(['init', kind, argsFile, runDir]);
  }
  async function submit(job, value) {
    const reply = path.join(root, 'reply.json');
    fs.writeFileSync(reply, JSON.stringify(value));
    return run(['submit', runDir, job.id, reply]);
  }
  return { root, repo, prompts, runDir, argsFile, args, run, init, submit, step: () => run(['step', runDir]) };
}
const parallelSource = `const replies = await parallel(['first','second'].map(name => () => agent(name, {agentType:'code-reviewer',model:'sonnet',schema:${JSON.stringify(schema)},phase:'Audit'}))); return {status: replies.every(Boolean) ? 'complete' : 'incomplete', replies};`;
const routedParallelSource = `const replies = await parallel([
  () => agent('scout', {agentType:'Explore',model:'sonnet',schema:${JSON.stringify(schema)},phase:'Scout'}),
  () => agent('specialist', {agentType:'security-auditor',model:'sonnet',schema:${JSON.stringify(schema)},phase:'Audit'})
]); return {status: replies.every(Boolean) ? 'complete' : 'incomplete', replies};`;
test('Codex dispatch maps Claude hints without changing cached request identity', async (t) => {
  const f = fixture(t, routedParallelSource);
  await f.init();
  const first = await f.step();
  assert.deepEqual(first.pending.map(({ phase, model, fork_turns, agent_type }) => ({ phase, model, fork_turns, agent_type })), [
    { phase: 'Scout', model: 'gpt-5.6-sol', fork_turns: 'none', agent_type: 'explorer' },
    { phase: 'Audit', model: 'gpt-5.6-sol', fork_turns: 'none', agent_type: 'security-auditor' },
  ]);
  for (const job of first.pending) {
    const request = JSON.parse(fs.readFileSync(job.requestPath));
    assert.equal(request.options.model, 'sonnet');
    assert.deepEqual(request.codex, { model: 'gpt-5.6-sol', fork_turns: 'none', agent_type: job.agent_type });
    delete request.codex;
    fs.writeFileSync(job.requestPath, JSON.stringify(request));
  }
  assert.deepEqual((await f.step()).pending.map((job) => job.id), first.pending.map((job) => job.id));
});
test('Codex dispatch maps the Critical refuter opus hint to Astra', async (t) => {
  const f = fixture(t, `await agent('Critical refuter', {agentType:'code-reviewer',model:'opus',schema:${JSON.stringify(schema)},phase:'Verify'}); return {};`);
  await f.init();
  const job = (await f.step()).pending[0];
  assert.deepEqual({ model: job.model, fork_turns: job.fork_turns, agent_type: job.agent_type }, { model: 'gpt-6-astra', fork_turns: 'none', agent_type: 'code-reviewer' });
  assert.equal(JSON.parse(fs.readFileSync(job.requestPath)).options.model, 'opus');
});
test('unknown Codex model hints fail instead of inheriting silently', async (t) => {
  for (const model of ['haiku', 'toString']) {
    const f = fixture(t, `await agent('unknown', {agentType:'code-reviewer',model:${JSON.stringify(model)},schema:${JSON.stringify(schema)},phase:'Audit'}); return {};`);
    await f.init();
    await assert.rejects(f.step(), new RegExp(`Unknown Codex model mapping: ${model}`));
  }
});
test('replay caches by content, regardless of completion order, across restart', async (t) => {
  const f = fixture(t, parallelSource);
  await f.init();
  const first = await f.step();
  assert.equal(first.pending.length, 2);
  await f.submit(first.pending[1], { value: 2 });
  const partial = await f.step();
  assert.deepEqual(partial.pending.map((j) => j.id), [first.pending[0].id]);
  const fresh = require(path.join(f.root, 'codex-runner.cjs')).main;
  assert.deepEqual((await fresh(['step', f.runDir])).pending, partial.pending);
  await f.submit(partial.pending[0], { value: 1 });
  const done = await f.step();
  assert.equal(done.status, 'complete');
  assert.deepEqual(JSON.parse(fs.readFileSync(done.outputPath)), { status: 'complete', replies: [{ value: 1 }, { value: 2 }] });
  assert.equal(fs.readdirSync(path.join(f.runDir, 'requests')).length, 2);
  assert.equal((await f.step()).pending.length, 0);
  await assert.rejects(f.submit(first.pending[0], { value: 9 }), /cannot be overwritten/);
});
test('invalid, corrupt and null replies never become cached success', async (t) => {
  const f = fixture(t, parallelSource); await f.init();
  const job = (await f.step()).pending[0];
  await assert.rejects(f.submit(job, { value: 'wrong' }), /expected integer/);
  await assert.rejects(f.submit(job, null), /expected object/);
  const corrupt = path.join(f.root, 'corrupt.json'); fs.writeFileSync(corrupt, '{');
  await assert.rejects(f.run(['submit', f.runDir, job.id, corrupt]), /JSON|property/);
  assert.equal((await f.step()).pending.length, 2);
});
test('explicit failures terminate as incomplete, even if program incorrectly says complete', async (t) => {
  const f = fixture(t, `await agent('one', {agentType:'code-reviewer',model:'sonnet',schema:${JSON.stringify(schema)},phase:'Audit'}); return {status:'complete'};`);
  await f.init(); const job = (await f.step()).pending[0];
  await f.run(['fail', f.runDir, job.id, 'Native worker unavailable']);
  const done = await f.step(); assert.equal(done.status, 'incomplete');
  assert.equal(done.failed[0].reason, 'Native worker unavailable');
  assert.deepEqual(done.cost, { status: 'unavailable', usd: null });
});
test('nested incomplete output blocks complete', async (t) => {
  const f = fixture(t, "return {dimensions:{security:{status:'incomplete'}}};");
  await f.init(); assert.equal((await f.step()).status, 'incomplete');
});
test('input contents travel on disk without truncation, and scope drift blocks replay', async (t) => {
  const f = fixture(t, 'return {length:args.fileContents[args.files[0]].length};');
  fs.writeFileSync(path.join(f.repo, 'index.js'), 'x'.repeat(600000));
  await f.init('find', { fileContents: { 'index.js': 'caller data is ignored' } });
  const done = await f.step(); assert.equal(JSON.parse(fs.readFileSync(done.outputPath)).length, 600000);
  fs.appendFileSync(path.join(f.repo, 'index.js'), 'changed');
  await assert.rejects(f.step(), /Scope content drift/);
});
test('missing, traversal, environment and escaping symlink inputs fail before run creation', async (t) => {
  for (const filename of ['missing.js', '../outside.js', '.env', 'nested/.env.secret', 'escape.js']) {
    const f = fixture(t, 'return {};');
    fs.writeFileSync(path.join(f.root, 'outside.js'), 'external');
    fs.symlinkSync(path.join(f.root, 'outside.js'), path.join(f.repo, 'escape.js'));
    await assert.rejects(f.init('find', { files: [filename] }));
    assert.equal(fs.existsSync(f.runDir), false);
  }
});
test('source, prompt and argument changes block dispatch', async (t) => {
  for (const kind of ['source', 'prompt', 'args']) {
    const f = fixture(t, parallelSource); await f.init();
    if (kind === 'source') fs.appendFileSync(path.join(f.root, 'find.js'), '\n// changed');
    if (kind === 'prompt') fs.appendFileSync(path.join(f.prompts, 'prompt.md'), 'changed');
    if (kind === 'args') fs.writeFileSync(path.join(f.runDir, 'args.json'), JSON.stringify(f.args));
    await assert.rejects(f.step(), /drift/);
  }
});
test('unsupported schema constraints are rejected explicitly', () => {
  assert.throws(() => validate({ value: 1 }, { ...schema, additionalProperties: false }), /Unsupported schema constraint/);
  assert.throws(() => validate({ value: 1.2 }, schema), /expected integer/);
});
test('real find program reaches specialists and finishes through native response bridge', async (t) => {
  const f = fixture(t); await f.init();
  const scout = await f.step(); assert.equal(scout.status, 'pending');
  for (const job of scout.pending) {
    assert.equal(job.model, 'gpt-5.6-sol'); assert.equal(job.fork_turns, 'none'); assert.equal(job.agent_type, 'explorer');
    const request = JSON.parse(fs.readFileSync(job.requestPath));
    await f.submit(job, request.options.schema.properties.clusters ? { clusters: [] } : { files: [{ path: 'index.js', tag: 'floor', reason: 'code' }] });
  }
  const specialists = await f.step(); assert.ok(specialists.pending.length);
  for (const job of specialists.pending) {
    assert.equal(job.model, 'gpt-5.6-sol'); assert.equal(job.fork_turns, 'none'); assert.equal(job.agent_type, 'code-reviewer');
    await f.submit(job, { findings: [{ id: 'CQ-1', severity: 'Important', confidence: 'high', files: [{ path: 'index.js', lines: '1' }], issue: 'Fixture issue', impact: 'Fixture impact' }], coverage: { status: 'complete', files: ['index.js'] } });
  }
  const verifier = (await f.step()).pending[0];
  assert.deepEqual({ model: verifier.model, fork_turns: verifier.fork_turns, agent_type: verifier.agent_type }, { model: 'gpt-5.6-sol', fork_turns: 'none', agent_type: 'code-reviewer' });
  await f.submit(verifier, { verdicts: [{ id: 'CQ-1', verdict: 'CONFIRMED', severity: 'Important', reason: 'Verified fixture' }] });
  assert.equal((await f.step()).status, 'complete');
});
test('real fix program caches authorized edits, then verifies and regresses', async (t) => {
  const f = fixture(t);
  await f.init('fix', { fixes: [{ file: 'index.js', findings: [{ id: 'CQ-1', severity: 'Important', issue: 'Wrong value' }] }], testCommand: 'node -c index.js', auditBin: path.resolve(__dirname, '../bin') });
  const fixer = (await f.step()).pending[0];
  assert.equal(fixer.phase, 'Fix');
  assert.deepEqual({ model: fixer.model, fork_turns: fixer.fork_turns, agent_type: fixer.agent_type }, { model: 'gpt-5.6-sol', fork_turns: 'none', agent_type: 'audit-fix-agent' });
  fs.writeFileSync(path.join(f.repo, 'index.js'), 'export const value = 2;');
  await f.submit(fixer, { fix_result: 'APPLIED', files: ['index.js'], diff_summary: 'Changed value', test: 'passed', tool_calls: 1 });
  const verifier = (await f.step()).pending[0]; assert.equal(verifier.phase, 'Verify'); assert.equal(verifier.model, 'gpt-5.6-sol'); assert.equal(verifier.agent_type, 'audit-fix-verifier');
  await f.submit(verifier, { verdict: 'VERIFIED', regressions: [], tests: 'passed' });
  const regression = (await f.step()).pending[0]; assert.equal(regression.phase, 'Regress'); assert.equal(regression.model, 'gpt-5.6-sol'); assert.equal(regression.agent_type, 'code-reviewer');
  await f.submit(regression, { findings: [], coverage: { status: 'complete', files: ['index.js'] } });
  assert.equal((await f.step()).status, 'complete');
  assert.equal(fs.readdirSync(path.join(f.runDir, 'requests')).length, 3);
  fs.appendFileSync(path.join(f.repo, 'index.js'), '\n// outside change');
  await assert.rejects(f.step(), /Scope content drift/);
});

test('failed fixer preserves partial edits and emits incomplete without replaying fixer', async (t) => {
  const f = fixture(t);
  await f.init('fix', { fixes: [{ file: 'index.js', findings: [{ id: 'CQ-1', severity: 'Important' }] }], auditBin: path.resolve(__dirname, '../bin') });
  const fixer = (await f.step()).pending[0];
  fs.appendFileSync(path.join(f.repo, 'index.js'), '\n// partial edit');
  await f.run(['fail', f.runDir, fixer.id, 'Interrupted after partial edit']);
  const done = await f.step();
  assert.equal(done.status, 'incomplete');
  assert.equal(done.pending.length, 0);
  assert.equal(fs.readdirSync(path.join(f.runDir, 'requests')).length, 1);
});

test('all thirteen dimensions execute through the same offline native bridge', async (t) => {
  const f = fixture(t);
  const dimensions = ['architecture', 'security', 'performance', 'code_quality', 'seo', 'a11y', 'typography', 'ui_design', 'ux', 'animation', 'docs_sync', 'copy', 'privacy'];
  await f.init('find', { dimensions });
  let result;
  for (let wave = 0; wave < 5; wave++) {
    result = await f.step();
    if (result.status !== 'pending') break;
    for (const job of result.pending) {
      const request = JSON.parse(fs.readFileSync(job.requestPath));
      const props = request.options.schema.properties;
      const response = props.clusters ? { clusters: [] } : props.coverage
        ? { findings: [], coverage: { status: 'complete', files: ['index.js'] } }
        : { files: [{ path: 'index.js', tag: 'scope', reason: 'fixture scope' }] };
      await f.submit(job, response);
    }
  }
  assert.equal(result.status, 'complete');
  assert.equal(result.pending.length, 0);
  assert.deepEqual(Object.keys(JSON.parse(fs.readFileSync(result.outputPath)).dimensions).sort(), dimensions.sort());
});

test('native worker binding persists across resume and cannot be replaced', async (t) => {
  const f = fixture(t, parallelSource);
  await f.init();
  const { pending } = await f.step();
  await f.run(['bind', f.runDir, pending[0].id, 'native-worker-1']);
  assert.equal((await f.step()).pending.find(job => job.id === pending[0].id).nativeWorkerId, 'native-worker-1');
  await f.run(['bind', f.runDir, pending[0].id, 'native-worker-1']);
  await assert.rejects(f.run(['bind', f.runDir, pending[0].id, 'native-worker-2']));
  await f.submit(pending[0], { value: 1 });
  await assert.rejects(f.run(['bind', f.runDir, pending[0].id, 'native-worker-1']));
  await f.run(['fail', f.runDir, pending[1].id, 'Worker aborted']);
  await assert.rejects(f.run(['bind', f.runDir, pending[1].id, 'native-worker-2']));
});
