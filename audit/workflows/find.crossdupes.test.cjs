// Pins cross-dimension duplicate marking in find.js (markCrossDuplicates, 2026-10-02).
// Fixtures are the real findings of one audit run (files, issue and impact copied verbatim, nothing
// else), because the similarity threshold was derived from exactly this text. Measured Jaccard
// (issue + impact): port check 0.39 / 0.49 / 0.33 (0-1~1-1, 1-1~2-2, 0-1~2-2; one group through the
// chain), tenant gap 0.38, raw button 0.38, base-uri vs tenant gap 0.05.
//   node --test audit/workflows/find.crossdupes.test.cjs

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, 'find.js'), 'utf8');
const block = source.slice(
  source.indexOf('// BEGIN cross-dimension duplicate marking'),
  source.indexOf('// END cross-dimension duplicate marking')
);
assert.ok(block.length > 100, 'duplicate marking block not found in find.js');
// SEVERITY_RANK and toRepoRelative are the two find.js helpers the block uses; paths in the fixtures are
// already repo-relative, so the stub is the identity.
const prelude = "const SEVERITY_RANK = { Critical: 3, Important: 2, Minor: 1 }; const toRepoRelative = (p) => p;";
const markInRealm = vm.runInNewContext(`${prelude}\n${block}\n;markCrossDuplicates`, {});
// Objects built inside the vm context have a foreign prototype; round-trip through JSON so deepStrictEqual works.
const plain = (value) => JSON.parse(JSON.stringify(value));
const markCrossDuplicates = (results) => plain(markInRealm(results));

const REAL = {
  "architecture-0-1": {
    "dimension": "architecture",
    "id": "architecture-0-1",
    "severity": "Important",
    "files": [
      {
        "path": "src/Security.php",
        "lines": "379-393"
      },
      {
        "path": "src/Security.php",
        "lines": "333-340"
      },
      {
        "path": "src/Providers/AcfServiceProvider.php",
        "lines": "461-471"
      },
      {
        "path": "templates/flexible/newsletter.blade.php",
        "lines": "24"
      },
      {
        "path": "tests/Unit/SecurityTest.php",
        "lines": "172-190"
      }
    ],
    "issue": "isAllowedFormActionUrl() skips the port check that its sibling isAllowedEmbedHost() has (lines 333-340). CSP form-action emits portless origins, so a URL like https://x.list-manage.com:8443/ passes validation and the render gate, but the browser blocks the submit. The data provider has no port case.",
    "impact": "The predicate and the CSP, which the single constant is meant to keep in sync, disagree. An editor saves a 'valid' address and the form fails silently on the front end."
  },
  "architecture-1-1": {
    "dimension": "architecture",
    "id": "architecture-1-1",
    "severity": "Important",
    "files": [
      {
        "path": "src/Security.php",
        "lines": "379-393"
      },
      {
        "path": "src/Security.php",
        "lines": "333-340"
      },
      {
        "path": "tests/Unit/SecurityTest.php",
        "lines": "172-190"
      }
    ],
    "issue": "Sibling gate isAllowedFormActionUrl() does not get the explicit-port check that isAllowedEmbedHost() has (lines 333-340). A URL like https://sibforms.com:8443/x passes the gate, but form-action emits portless origins, so the browser blocks it. The docblock at 55-58 promises the gate accepts only what the CSP lets through. No port case in formActionAllowance.",
    "impact": "The newsletter layout renders a form the CSP silently blocks on submit. This is the same drift the embed gate was already fixed for, so the two gates now diverge."
  },
  "architecture-2-2": {
    "dimension": "architecture",
    "id": "architecture-2-2",
    "severity": "Important",
    "files": [
      {
        "path": "src/Security.php",
        "lines": "333-340"
      },
      {
        "path": "src/Security.php",
        "lines": "379-406"
      },
      {
        "path": "tests/Unit/SecurityTest.php",
        "lines": "172-191"
      }
    ],
    "issue": "The explicit non-443 port rejection added to isAllowedEmbedHost (333-340, commented as matching the portless CSP origin) was not rolled out to sibling isAllowedFormActionUrl. It accepts https://sibforms.com:8443/ although form-action emits portless hosts and the browser blocks it. The data provider has no port case.",
    "impact": "The newsletter layout renders a form the CSP silently blocks, the exact drift the embed gate was written to prevent."
  },
  "security-0-1": {
    "dimension": "security",
    "id": "security-0-1",
    "severity": "Important",
    "files": [
      {
        "path": "src/Security.php",
        "lines": "66-87,455-458"
      },
      {
        "path": "src/Providers/AcfServiceProvider.php",
        "lines": "222-280"
      },
      {
        "path": "docs/SECURITY.md",
        "lines": "26"
      }
    ],
    "issue": "form-action allowlist holds multi-tenant, attacker-registrable hosts (*.list-manage.com, *.activehosted.com, *.mailerlite.com, www.paypal.com). allowFormControlTags keeps form, input type=password/hidden and action through kses. A content editor without unfiltered_html can still save a credential-phishing form posting to their own tenant, or a PayPal form with their own business id. Docs overstate the protection.",
    "impact": "Stored phishing or payment-redirect form on the trusted site, reachable by low-privilege editors or multisite admins. form-action does not stop it as the docs claim."
  },
  "security-5-2": {
    "dimension": "security",
    "id": "security-5-2",
    "severity": "Important",
    "files": [
      {
        "path": "src/Providers/AcfServiceProvider.php",
        "lines": "250-261"
      },
      {
        "path": "src/Security.php",
        "lines": "66-87"
      }
    ],
    "issue": "allowFormControlTags permits form (action, target, method), input with type (password/hidden) and name/id in site-wide kses. The only compensating control, CSP form-action, allows multi-tenant provider hosts (*.list-manage.com, *.activehosted.com, *.mailerlite.com). The docblock does not cover that tenant gap.",
    "impact": "An editor without unfiltered_html (multisite or DISALLOW_UNFILTERED_HTML) can save a fake login form posting to an attacker-owned provider tenant, harvesting visitor or admin credentials. name/id also allow DOM clobbering."
  },
  "architecture-3-1": {
    "dimension": "architecture",
    "id": "architecture-3-1",
    "severity": "Important",
    "files": [
      {
        "path": "templates/flexible/newsletter.blade.php",
        "lines": "4,69-74"
      },
      {
        "path": "templates/components/button.blade.php",
        "lines": "30,250-257"
      }
    ],
    "issue": "Newsletter layout hand-writes a raw <button type=\"submit\"> with its own utility classes although x-button already renders a form button (type prop, variants, focus ring). The header comment claims x-button is used, but it is not. The raw <input> at lines 58-66 also skips x-input without an inline reason.",
    "impact": "Button styling, hover/active/disabled states and the attribute allowlist can drift from the design system. The raw button uses its own tokens and omits the shared 'button' class."
  },
  "architecture-6-1": {
    "dimension": "architecture",
    "id": "architecture-6-1",
    "severity": "Important",
    "files": [
      {
        "path": "templates/flexible/newsletter.blade.php",
        "lines": "4, 25, 58-66, 69-74"
      },
      {
        "path": "templates/search.blade.php",
        "lines": "26-36"
      }
    ],
    "issue": "Newsletter layout hand-writes a raw <input> and <button type=submit> with copied utility classes, although x-input and x-button (type=submit) exist and search.blade.php uses them. Header comment claims x-button is used. It is the only flexible layout with a raw input. uniqid() id replaces ComponentId.",
    "impact": "Radius, focus ring and hover styles diverge from the component tokens (--radius-md vs --button-radius, --input-md-radius). Component changes do not reach this form."
  },
  "security-0-2": {
    "dimension": "security",
    "id": "security-0-2",
    "severity": "Important",
    "files": [
      {
        "path": "src/Security.php",
        "lines": "447-461"
      }
    ],
    "issue": "The CSP has no base-uri directive and default-src does not cover it. A injected base tag could rebase relative script URLs. kses strips base today, so this is defense-in-depth only.",
    "impact": "Missing hardening layer against base-tag injection."
  }
};

// Builds {dimension: {findings, verdicts}} from fixture ids; verdict severity defaults to the finding's own.
function build(ids, verdictOverrides = {}) {
  const results = {};
  for (const id of ids) {
    const { dimension, ...finding } = REAL[id];
    const r = (results[dimension] = results[dimension] || { findings: [], verdicts: [] });
    r.findings.push({ ...finding });
    const o = verdictOverrides[id] || {};
    r.verdicts.push({ id, verdict: o.verdict || 'CONFIRMED', severity: o.severity || finding.severity, reason: 'x' });
  }
  return results;
}
const marked = (results) => Object.values(results).flatMap((r) => r.findings).filter((f) => f.duplicateOf).map((f) => f.id).sort();

test('port check reported by three architecture chunks collapses onto the first one', () => {
  const results = build(['architecture-2-2', 'architecture-0-1', 'architecture-1-1']);
  const duplicates = markCrossDuplicates(results);
  assert.deepEqual(duplicates, [{
    keep: { dimension: 'architecture', id: 'architecture-0-1' },
    dropped: [{ dimension: 'architecture', id: 'architecture-1-1' }, { dimension: 'architecture', id: 'architecture-2-2' }]
  }]);
  assert.deepEqual(marked(results), ['architecture-1-1', 'architecture-2-2']);
  assert.deepEqual(plain(results.architecture.findings.find((f) => f.id === 'architecture-1-1').duplicateOf),
    { dimension: 'architecture', id: 'architecture-0-1' });
});

test('tenant gap reported by two security chunks collapses', () => {
  const results = build(['security-5-2', 'security-0-1']);
  assert.deepEqual(markCrossDuplicates(results), [{
    keep: { dimension: 'security', id: 'security-0-1' }, dropped: [{ dimension: 'security', id: 'security-5-2' }]
  }]);
});

test('raw newsletter button collapses', () => {
  const results = build(['architecture-3-1', 'architecture-6-1']);
  assert.deepEqual(markCrossDuplicates(results), [{
    keep: { dimension: 'architecture', id: 'architecture-3-1' }, dropped: [{ dimension: 'architecture', id: 'architecture-6-1' }]
  }]);
});

test('base-uri finding stays separate from the tenant gap although both cite src/Security.php lines that overlap', () => {
  const results = build(['security-0-1', 'security-0-2', 'security-5-2']);
  const duplicates = markCrossDuplicates(results);
  assert.deepEqual(marked(results), ['security-5-2']);
  assert.equal(duplicates.length, 1);
});

test('across dimensions the higher verdict severity wins, then dimension order', () => {
  // Same text in security and architecture: a Minor verdict on the security one loses against Important.
  const a = build(['security-5-2'], { 'security-5-2': { severity: 'Minor' } });
  const b = build(['security-0-1']);
  b.architecture = { findings: [{ ...b.security.findings[0], id: 'architecture-0-9' }], verdicts: [{ id: 'architecture-0-9', verdict: 'CONFIRMED', severity: 'Important', reason: 'x' }] };
  const results = { security: a.security, architecture: b.architecture };
  const [d] = markCrossDuplicates(results);
  assert.deepEqual(d.keep, { dimension: 'architecture', id: 'architecture-0-9' });
  assert.deepEqual(d.dropped, [{ dimension: 'security', id: 'security-5-2' }]);

  // Equal severity: dimension order decides (security before architecture).
  const eq = build(['security-0-1']);
  eq.architecture = { findings: [{ ...eq.security.findings[0], id: 'architecture-0-9' }], verdicts: [{ id: 'architecture-0-9', verdict: 'CONFIRMED', severity: 'Important', reason: 'x' }] };
  const [e] = markCrossDuplicates(eq);
  assert.deepEqual(e.keep, { dimension: 'security', id: 'security-0-1' });
});

test('a Minor duplicate never wins against an Important one, whatever the id order', () => {
  const results = build(['architecture-0-1', 'architecture-1-1'], { 'architecture-0-1': { severity: 'Minor' } });
  const [d] = markCrossDuplicates(results);
  assert.deepEqual(d.keep, { dimension: 'architecture', id: 'architecture-1-1' });
  assert.deepEqual(d.dropped, [{ dimension: 'architecture', id: 'architecture-0-1' }]);
});

test('REFUTED findings never take part, neither as keeper nor as duplicate', () => {
  const results = build(['architecture-0-1', 'architecture-1-1'], { 'architecture-0-1': { verdict: 'REFUTED' } });
  assert.deepEqual(markCrossDuplicates(results), []);
  assert.deepEqual(marked(results), []);
});

test('output order is deterministic regardless of input order', () => {
  const ids = ['architecture-6-1', 'security-5-2', 'architecture-2-2', 'architecture-3-1', 'security-0-1', 'architecture-0-1', 'architecture-1-1'];
  const forward = markCrossDuplicates(build(ids));
  const backward = markCrossDuplicates(build(ids.slice().reverse()));
  assert.deepEqual(forward, backward);
  assert.deepEqual(forward.map((d) => d.keep.id), ['security-0-1', 'architecture-0-1', 'architecture-3-1']);
});

test('findings without line info on the shared file do not match on lines', () => {
  const results = build(['architecture-3-1', 'architecture-6-1']);
  for (const f of results.architecture.findings) f.files = f.files.map((x) => ({ path: x.path }));
  assert.deepEqual(markCrossDuplicates(results), []);
});

test('find.js result carries duplicates and marks the finding, dimension status stays complete', async () => {
  const workflowSource = source.replace(/^export const meta = /, 'const meta = ');
  const f = (id, severity) => ({ ...plain(REAL['architecture-3-1']), id, severity, confidence: 'high' });
  // Second finding cites lines 10 away from the first one's first line, so the per-dimension file+line
  // dedupe (5 lines) keeps both and only the cross-finding pass can mark it.
  const second = { ...f('architecture-0-2', 'Minor'), files: [{ path: 'templates/components/button.blade.php', lines: '40' }] };
  const found = [f('architecture-0-1', 'Important'), second];
  const context = {
    args: { repoRoot: '/r', scope: 'diff', files: ['templates/search.blade.php', 'templates/flexible/newsletter.blade.php'], dimensions: ['architecture'],
      promptDir: '/p', guidelinesDir: '/g', floorFiles: {}, dimensionFiles: {} },
    log: () => {}, performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((t) => t())),
    agent: async (prompt, options) => {
      if (options.phase === 'Scout') return { clusters: [{ id: 'c', pattern: 'p', why: 'w', files: [{ path: 'templates/search.blade.php', count: 1 }, { path: 'templates/flexible/newsletter.blade.php', count: 1 }] }] };
      if (options.phase === 'Audit') return { findings: found, coverage: { status: 'complete', files: ['templates/search.blade.php', 'templates/flexible/newsletter.blade.php'] } };
      return { verdicts: found.map((x) => ({ id: x.id, verdict: 'CONFIRMED', severity: x.severity, reason: 'r' })) };
    }
  };
  const result = plain(await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context));
  console.log(JSON.stringify(result.dimensions.architecture.uncovered), JSON.stringify(result.dimensions.architecture.unverified));
  assert.equal(result.dimensions.architecture.status, 'complete');
  assert.equal(result.status, 'complete');
  assert.deepEqual(result.duplicates, [{
    keep: { dimension: 'architecture', id: 'architecture-0-1' }, dropped: [{ dimension: 'architecture', id: 'architecture-0-2' }]
  }]);
  const marked = result.dimensions.architecture.findings.find((x) => x.id === 'architecture-0-2');
  assert.deepEqual(marked.duplicateOf, { dimension: 'architecture', id: 'architecture-0-1' });
  assert.equal(result.dimensions.architecture.verdicts.length, 2);
});
