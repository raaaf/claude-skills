const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const finding = (severity = 'Important') => ({ id: 'code_quality-0-1', severity, confidence: 'high', files: [{ path: 'app.js', lines: '10' }], issue: 'Broken behavior', impact: 'Data lost' });
const verdict = (severity = 'Important', result = 'CONFIRMED', id = finding().id) => ({ id, severity, verdict: result, reason: 'Checked code' });
async function run(name, replies, overrides = {}) {
  const script = fs.readFileSync(path.join(__dirname, `${name}.js`), 'utf8').replace('export const meta =', 'const meta =');
  const args = { repoRoot: '/fixture', scope: 'repo', files: ['app.js'], fileContents: { 'app.js': 'return null;' }, dimensions: ['code_quality'], promptDir: '/skills/audit/agents', auditBin: '/skills/audit/bin', fixes: [{ file: 'app.js', findings: [finding()] }], ...overrides };
  const calls = [];
  const agent = async (prompt) => { calls.push(prompt); const reply = replies.shift(); if (reply instanceof Error) throw reply; return reply; };
  const parallel = (jobs) => Promise.all(jobs.map(async (job) => { try { return await job(); } catch { return null; } }));
  const result = await new AsyncFunction('args', 'agent', 'parallel', 'log', script)(args, agent, parallel, () => {});
  return { result, calls };
}
const scout = { files: [{ path: 'app.js', tag: 'scope', reason: 'Relevant' }] };
const found = (severity) => ({ findings: [finding(severity)], coverage: { status: 'complete', files: ['app.js'] } });
const applied = { fix_result: 'APPLIED', files: ['app.js'], diff_summary: 'Fixed behavior', test: 'passed', tool_calls: 2 };
const verified = { verdict: 'VERIFIED', regressions: [], tests: 'passed' };
const clean = { findings: [], coverage: { status: 'complete', files: ['app.js'] } };
test('failed specialists never complete', async () => {
  const { result } = await run('find', [scout, null]);
  assert.equal(result.dimensions.code_quality.status, 'incomplete');
  assert.deepEqual(result.dimensions.code_quality.uncovered, ['app.js']);
});
test('failed scouts remain incomplete even with successful floor fallback', async () => {
  const { result } = await run('find', [null, clean]);
  assert.equal(result.dimensions.code_quality.status, 'incomplete');
});
test('successful empty scout legitimately skips when no floor matches', async () => {
  const { result } = await run('find', [{ files: [] }], { fileContents: { 'app.js': 'const n = 1;' } });
  assert.equal(result.dimensions.code_quality.status, 'skipped');
});
test('missing, duplicate, unknown and malformed verifier coverage cannot pass', async () => {
  for (const response of [null, { verdicts: [] }, { verdicts: [verdict(), verdict()] }, { verdicts: [verdict(), verdict('Important', 'CONFIRMED', 'unknown')] }, { verdicts: [ { id: finding().id } ] }, { verdicts: [verdict('Important', 'UNCERTAIN')] }]) {
    const { result } = await run('find', [scout, found(), response]);
    assert.equal(result.dimensions.code_quality.status, 'incomplete');
  }
});
test('unavailable or uncertain refutation cannot leave confirmed Critical actionable', async () => {
  for (const response of [null, { verdicts: [] }, { verdicts: [verdict('Critical', 'CONFIRMED', 'wrong')] }, { verdicts: [verdict('Critical', 'UNCERTAIN')] }]) {
    const { result } = await run('find', [scout, found('Critical'), { verdicts: [verdict('Critical')] }, response]);
    const dimension = result.dimensions.code_quality;
    assert.equal(dimension.status, 'incomplete');
    assert.deepEqual(dimension.unrefuted, [finding().id]);
    assert.equal(dimension.verdicts[0].verdict, 'UNCERTAIN');
  }
});
test('successful refutation retains disputed Important behavior', async () => {
  const { result } = await run('find', [scout, found('Critical'), { verdicts: [verdict('Critical')] }, { verdicts: [verdict('Critical', 'REFUTED')] }]);
  assert.equal(result.dimensions.code_quality.status, 'complete');
  assert.equal(result.dimensions.code_quality.verdicts[0].severity, 'Important');
  assert.equal(result.dimensions.code_quality.verdicts[0].disputed, true);
});
test('complete verifier coverage finishes normally', async () => {
  const { result } = await run('find', [scout, found(), { verdicts: [verdict()] }]);
  assert.equal(result.status, 'complete');
  assert.deepEqual(result.dimensions.code_quality.unverified, []);
});
test('scope content is validated before any dispatch', async () => {
  for (const fileContents of [undefined, {}, { 'other.js': '' }, { 'app.js': null }]) {
    await assert.rejects(run('find', [], { fileContents }), /fileContents/);
  }
});
test('fix success requires verification and clean regression', async () => {
  const { result, calls } = await run('fix', [applied, verified, clean]);
  assert.equal(result.status, 'complete');
  assert.equal(result.fixes[0].status, 'complete');
  assert.match(calls[0], /Read \/skills\/audit\/agents\/fix-agent.md/);
  assert.match(calls[1], /Read \/skills\/audit\/agents\/fix-verifier.md/);
});
test('failed fixer slots retain requested files as incomplete', async () => {
  for (const response of [null, new Error('aborted'), { ...applied, fix_result: 'FAILED', files: [] }, { ...applied, fix_result: 'NOT_FOUND', files: [] }, { ...applied, fix_result: 'SUPPRESSED', files: [] }]) {
    const { result } = await run('fix', [response]);
    assert.equal(result.status, 'incomplete');
    assert.equal(result.fixes[0].file, 'app.js');
    assert.equal(result.fixes[0].status, 'incomplete');
  }
});
test('missing or rejected fix verification stays incomplete', async () => {
  for (const response of [null, new Error('aborted'), { ...verified, verdict: 'PARTIAL' }, { ...verified, verdict: 'REJECT' }]) {
    const { result } = await run('fix', [applied, response, clean]);
    assert.equal(result.status, 'incomplete');
    assert.equal(result.fixes.length, 1);
  }
});
test('missing or blocking regression stays incomplete', async () => {
  for (const response of [null, new Error('aborted'), found()]) {
    const { result } = await run('fix', [applied, verified, response]);
    assert.equal(result.status, 'incomplete');
    assert.equal(result.fixes[0].status, 'incomplete');
  }
});
test('Minor findings never reach fix agents', async () => {
  const { result, calls } = await run('fix', [], { fixes: [{ file: 'app.js', findings: [finding('Minor')] }] });
  assert.equal(calls.length, 0);
  assert.equal(result.fixes[0].status, 'skipped');
  assert.deepEqual(result.excluded, [finding().id]);
});

test('partial verifier coverage exposes the precise missing finding', async () => {
  const second = { ...finding(), id: 'code_quality-0-2', files: [{ path: 'app.js', lines: '30' }] };
  const { result } = await run('find', [scout, { findings: [finding(), second], coverage: { status: 'complete', files: ['app.js'] } }, { verdicts: [verdict()] }]);
  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.dimensions.code_quality.unverified, [second.id]);
  assert.equal(result.dimensions.code_quality.verdicts.length, 1);
});
test('failed dimensions remain visible and cannot produce complete top-level status', async () => {
  const { result } = await run('find', [scout, { findings: [null], coverage: 'Malformed' }]);
  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.dimensions.code_quality.uncovered, ['dimension:failed']);
});

test('fix claims require the exact owned file before verification or success', async () => {
  for (const fix_result of ['APPLIED', 'PARTIAL']) {
    for (const files of [[], ['other.js'], ['app.js', 'other.js']]) {
      const { result, calls } = await run('fix', [{ ...applied, fix_result, files }, verified, clean]);
      assert.equal(result.status, 'incomplete');
      assert.equal(result.fixes[0].status, 'incomplete');
      assert.equal(calls.some((prompt) => prompt.includes('fix-verifier.md')), false);
    }
  }
});

test('specialist and regression coverage fail closed', async () => {
  for (const coverage of ['INCOMPLETE: unread', { status: 'incomplete', files: ['app.js'] }, { status: 'complete', files: [] }, { status: 'complete', files: ['other.js'] }]) {
    const response = { findings: [], coverage };
    assert.equal((await run('find', [scout, response])).result.status, 'incomplete');
    assert.equal((await run('fix', [applied, verified, response])).result.status, 'incomplete');
  }
});
test('invalid dimensions reject before dispatch', async () => {
  for (const dimensions of ['security', {}, ['unknown'], ['security', 'unknown']]) {
    await assert.rejects(run('find', [], { dimensions }), /dimensions/);
  }
});
test('invalid architecture clusters cannot complete', async () => {
  for (const files of [[{ path: 'app.js', count: 1 }], [{ path: 'app.js', count: 1 }, { path: 'app.js', count: 2 }], [{ path: '', count: 1 }, { path: 'app.js', count: 1 }]]) {
    const { result } = await run('find', [{ clusters: [{ id: 'c1', pattern: 'duplicate', why: 'test', files }] }], { dimensions: ['architecture'] });
    assert.equal(result.status, 'incomplete');
    assert.ok(result.dimensions.architecture.uncovered.length);
  }
});
test('scout scope tags cannot remove mandatory floor paths at cap', async () => {
  const files = Array.from({ length: 71 }, (_, i) => `file${i}.js`);
  const { result } = await run('find', [{ files: files.map(path => ({ path, tag: 'scope', reason: 'test' })) }], { files, fileContents: Object.fromEntries(files.map(path => [path, 'return null;'])) });
  assert.deepEqual(new Set(result.dimensions.code_quality.files), new Set(files));
});

test('cluster coverage requires every assigned path and preserves complete success', async () => {
  const cluster = { id: 'c1', pattern: 'duplicate', why: 'compare', files: [{ path: 'app.js', count: 1 }, { path: 'other.js', count: 1 }] };
  for (const paths of [['app.js'], ['app.js', 'other.js']]) {
    const { result } = await run('find', [{ clusters: [cluster] }, { findings: [], coverage: { status: 'complete', files: paths } }], { dimensions: ['architecture'] });
    assert.equal(result.status, paths.length === 2 ? 'complete' : 'incomplete');
  }
});
