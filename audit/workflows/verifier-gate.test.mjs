// Pins the verifier-verdict bookkeeping in find.js.
//
// find.js is a workflow script: its body runs on import, so runDimension cannot
// be imported and called directly. This test therefore slices the verdict block
// out of the source verbatim and runs it with stubs. That keeps the test honest
// (it executes the shipped code, not a copy) at the cost of two string markers:
// if the block moves, the assertions below fail loudly rather than silently
// testing nothing.
//
// What it protects: a verifier that returns a verdict for an id nobody asked
// about must not mark the dimension `incomplete`. Coverage is enforced per
// finding, and a stray reply changes no finding's fate. Gating on it made a
// verifier's typo weigh more than a genuinely unverified Minor, which the
// 2026-09-16 rule deliberately lets pass. Real cost on 2026-09-18: a run with
// all 24 findings correctly verified lost its push marker and had to be
// re-marked by hand, twice.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(path.join(here, 'find.js'), 'utf8');

const START = '  const unverified = [];';
const END = '  // Stage 5: refuter';

function verdictBlock() {
  const start = src.indexOf(START);
  const end = src.indexOf(END);
  assert.ok(start > 0, `marker not found in find.js: ${START}`);
  assert.ok(end > start, `marker not found in find.js: ${END}`);
  return src.slice(start, end);
}

/** Runs the real block with stubbed collaborators and returns what it produced. */
function run(groups, results) {
  const uncovered = [];
  const logs = [];
  const validVerdict = (v) => v && typeof v.id === 'string' &&
    ['CONFIRMED', 'REFUTED', 'UNCERTAIN'].includes(v.verdict);
  const fn = new Function(
    'verifierGroups', 'verifierResults', 'uncovered', 'logFn', 'dimension', 'validVerdict',
    verdictBlock() + '\n return { uncovered, unverified, verdicts };'
  );
  const out = fn(groups, results, uncovered, (m) => logs.push(m), 'ui_design', validVerdict);
  return { ...out, logs };
}

const finding = (id, severity = 'Minor') => ({ id, severity });
const verdict = (id, v = 'CONFIRMED') => ({ id, verdict: v });

test('a stray verdict for an unknown id does not create a coverage gap', () => {
  const r = run([[finding('a'), finding('b')]], [[verdict('a'), verdict('b'), verdict('ghost')]]);

  assert.deepEqual(r.uncovered, [], 'uncovered gates the dimension; a stray reply must not land there');
  assert.deepEqual(r.unverified, [], 'both findings got exactly one valid verdict');
  assert.equal(r.verdicts.length, 2, 'the stray verdict is not adopted');
  assert.match(r.logs[0], /unknown ids \(ghost\)/, 'the stray is still surfaced, just not as a gate');
});

test('a missing verdict is still counted as unverified', () => {
  const r = run([[finding('a'), finding('b')]], [[verdict('a')]]);

  assert.deepEqual(r.unverified, ['b']);
  assert.deepEqual(r.uncovered, []);
});

test('a typo in a verdict id leaves the real finding unverified', () => {
  const r = run([[finding('a')]], [[verdict('a-typo')]]);

  assert.deepEqual(r.unverified, ['a'], 'the finding it was meant for is not covered');
  assert.match(r.logs[0], /a-typo/);
});

test('a null entry among the replies is reported but blocks nothing on its own', () => {
  const r = run([[finding('a')]], [[verdict('a'), null]]);

  assert.deepEqual(r.unverified, []);
  assert.deepEqual(r.uncovered, []);
  assert.match(r.logs[0], /null/);
});

test('an UNCERTAIN verdict still marks the finding unverified', () => {
  const r = run([[finding('a')]], [[verdict('a', 'UNCERTAIN')]]);

  assert.deepEqual(r.unverified, ['a']);
  assert.equal(r.verdicts.length, 1, 'the verdict is recorded even though it does not settle the finding');
});

test('two verdicts for the same finding do not count as verified', () => {
  const r = run([[finding('a')]], [[verdict('a'), verdict('a', 'REFUTED')]]);

  assert.deepEqual(r.unverified, ['a'], 'ambiguous coverage is no coverage');
  assert.deepEqual(r.verdicts, []);
});
