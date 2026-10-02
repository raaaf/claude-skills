// node --test audit/bin/minor-split.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
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

test('a finding with duplicateOf goes to neither fix nor backlog and does not make its file a fix file', () => {
  const dup = { ...f('d', 'Important', 'y.js'), duplicateOf: { dimension: 'security', id: 'a' } };
  const dupMinor = { ...f('dm', 'Minor', 'z.js'), duplicateOf: { dimension: 'security', id: 'a' } };
  const r = split({ findings: [f('a', 'Important', 'x.js'), dup, dupMinor, f('m', 'Minor', 'y.js')],
    backlog: [{ key: 'k1', file: 'y.js' }] });
  assert.deepEqual(ids(r.fix), ['a']);
  assert.deepEqual(ids(r.toBacklog), ['m']);
  assert.deepEqual(ids(r.duplicates), ['d', 'dm']);
  assert.deepEqual(r.ridealongBacklog, []);
});

const d = (dimension, severity, verdict, ...paths) => ({ ...f(`${dimension}-1`, severity, ...paths), dimension, verdict });

test('a CONFIRMED security Minor and an UNCERTAIN payments Minor are fixed as Important, never backlogged', () => {
  const r = split({ findings: [d('security', 'Minor', 'CONFIRMED', 'a.js'), d('payments', 'Minor', 'UNCERTAIN', 'b.js')] });
  assert.deepEqual(ids(r.fix), ['security-1', 'payments-1']);
  assert.deepEqual(r.fix.map((x) => x.severity), ['Important', 'Important']);
  assert.deepEqual(r.toBacklog, []);
});

test('a REFUTED privacy finding stays discarded', () => {
  const r = split({ findings: [d('privacy', 'Minor', 'REFUTED', 'p.js')] });
  assert.deepEqual(r.fix, []);
  assert.deepEqual(r.toBacklog, []);
});

test('a code_quality Minor keeps its severity and goes to the backlog', () => {
  const r = split({ findings: [d('code_quality', 'Minor', 'CONFIRMED', 'c.js')] });
  assert.deepEqual(r.fix, []);
  assert.deepEqual(ids(r.toBacklog), ['code_quality-1']);
});

test('the CLI prints JSON when invoked through a symlink (import.meta.url is the realpath)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'minor-split-'));
  try {
    const link = join(dir, 'minor-split-link.mjs');
    symlinkSync(fileURLToPath(new URL('./minor-split.mjs', import.meta.url)), link);
    const out = execFileSync('node', [link], { input: '{"findings":[],"backlog":[]}' }).toString();
    assert.deepEqual(JSON.parse(out), { fix: [], ridealongBacklog: [], toBacklog: [], duplicates: [] });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
