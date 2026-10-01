// node --test audit/bin/minor-split.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { split } from './minor-split.mjs';

const f = (id, severity, ...paths) => ({ id, severity, files: paths.map((path) => ({ path, lines: '1' })) });
const ids = (list) => list.map((x) => x.id);

test('Critical and Important always go to the fix wave, never to the backlog', () => {
  const r = split({ findings: [f('a', 'Critical', 'x.js'), f('b', 'Important', 'y.js')] });
  assert.deepEqual(ids(r.fix), ['a', 'b']);
  assert.deepEqual(r.toBacklog, []);
});

test('a Minor in a file that receives an Important fix rides along', () => {
  const r = split({ findings: [f('a', 'Important', 'x.js'), f('m', 'Minor', 'x.js')] });
  assert.deepEqual(ids(r.fix), ['a', 'm']);
  assert.deepEqual(r.toBacklog, []);
});

test('a Minor in a file without a Critical/Important goes to the backlog', () => {
  const r = split({ findings: [f('a', 'Important', 'x.js'), f('m', 'Minor', 'z.js')] });
  assert.deepEqual(ids(r.fix), ['a']);
  assert.deepEqual(ids(r.toBacklog), ['m']);
});

test('a multi-file Minor with one file outside the fix set goes to the backlog', () => {
  const r = split({ findings: [f('a', 'Important', 'x.js'), f('m', 'Minor', 'x.js', 'z.js')] });
  assert.deepEqual(ids(r.fix), ['a']);
  assert.deepEqual(ids(r.toBacklog), ['m']);
});

test('a multi-file Minor rides along when all its files are in the fix set', () => {
  const r = split({ findings: [f('a', 'Important', 'x.js'), f('b', 'Critical', 'z.js'), f('m', 'Minor', 'x.js', 'z.js')] });
  assert.deepEqual(ids(r.fix), ['a', 'b', 'm']);
});

test('a backlog entry rides along only for a file that receives a fix', () => {
  const backlog = [{ key: 'k1', file: 'x.js' }, { key: 'k2', file: 'q.js' }];
  const r = split({ findings: [f('a', 'Critical', 'x.js')], backlog });
  assert.deepEqual(r.ridealongBacklog.map((e) => e.key), ['k1']);
});

test('a Minor alone never makes its file a fix file for backlog entries', () => {
  const r = split({ findings: [f('m', 'Minor', 'x.js')], backlog: [{ key: 'k1', file: 'x.js' }] });
  assert.deepEqual(r.fix, []);
  assert.deepEqual(r.ridealongBacklog, []);
  assert.deepEqual(ids(r.toBacklog), ['m']);
});
