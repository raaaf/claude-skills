# Finding Schema

JSON schemas for every stage of the per-dimension pipeline (`audit/workflows/find.js`,
`audit/workflows/fix.js`). Each schema is a plain object literal (`type`, `properties`,
`required`), passed as the Workflow tool's `schema` option so the agent's reply comes back
already validated — no parsing in the workflow script.

## Workflow-Kontrakt, geprüft am 2026-09-05

Observations from the throwaway spike (`wf_0f7107d6-f3f`, 3 agents, 74s, 87k tokens), which
Steps 4-7 are built on:

1. **`agentType` is honored with its tool grants.** `Explore`, `security-auditor` and
   `code-reviewer` were all accepted as `agentType` values in `agent()` calls and each agent kept
   the tool grants of its registered definition (`agents/*.md`) — no separate tool config needed
   in the workflow script.
2. **`schema` returns a validated object directly.** A `schema` with nested objects, `enum` and
   `required` fields produced the already-validated JS object as the agent's result — no `JSON.parse`
   or manual validation needed in the calling script.
3. **A thrown/aborted agent in `parallel()` comes back as `null`.** The run itself completes
   normally; the failure reason appears in the `<failures>` block of the completion notification,
   not as a thrown exception in the workflow script. Callers must `.filter(Boolean)` parallel
   results rather than assuming every slot returned data.
4. **`resumeFromRunId` replays completed agents from cache.** A second start with the same script
   and `args` plus `resumeFromRunId` completed in 29ms with 0 tokens spent — all three agents came
   back from cache instead of re-running. A later nested-parallel audit replayed 52 completed
   specialist requests the same way; do not reintroduce a hand-rolled resume mechanism, the
   Workflow tool's own cache already covers it.

## Scout output — file scout (`scout-files.md`)

```js
{
  type: 'object',
  properties: {
    files: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          tag: { type: 'string', enum: ['floor', 'scope', 'context'] },
          reason: { type: 'string' }
        },
        required: ['path', 'tag', 'reason']
      }
    }
  },
  required: ['files']
}
```

`tag: 'context'` is only used at `SCOPE=diff`: up to 5 directly imported/calling files per
diff file, never a Floor file (Floor files are always `tag: 'floor'`).

## Scout output — cluster scout (`scout-clusters.md`, architecture/docs_sync/security)

```js
{
  type: 'object',
  properties: {
    clusters: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          pattern: { type: 'string' },
          files: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                count: { type: 'integer' }
              },
              required: ['path', 'count']
            }
          },
          why: { type: 'string' }
        },
        required: ['id', 'pattern', 'files', 'why']
      }
    }
  },
  required: ['clusters']
}
```

## Specialist output (all dimensions)

```js
{
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['Critical', 'Important', 'Minor'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          files: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                lines: { type: 'string' }
              },
              required: ['path', 'lines']
            }
          },
          issue: { type: 'string' },
          impact: { type: 'string' }
        },
        required: ['id', 'severity', 'confidence', 'files', 'issue', 'impact']
      }
    },
    coverage: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['complete', 'incomplete'] },
        files: { type: 'array', items: { type: 'string' } }
      },
      required: ['status', 'files']
    }
  },
  required: ['findings', 'coverage']
}
```

`id` carries the dimension prefix (e.g. `security-3`), per Prompt-Regel 1. `files` names every
involved file with lines, per Prompt-Regel 2. `coverage.files` must list every assigned
file, including every cluster member, and `coverage.status` must be `complete` for complete
coverage. Missing paths, an incomplete status or legacy prose coverage block completion.
Regression specialists in fix.js use the same structured coverage contract.

## Verifier output (`finding-verifier.md`)

```js
{
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'UNCERTAIN'] },
          severity: { type: 'string', enum: ['Critical', 'Important', 'Minor'] },
          reason: { type: 'string' }
        },
        required: ['id', 'verdict', 'severity', 'reason']
      }
    }
  },
  required: ['verdicts']
}
```

`severity` is the (possibly corrected) severity; unchanged from the finding when the verifier
does not correct it.

## Fixer output (`fix-agent.md`)

```js
{
  type: 'object',
  properties: {
    fix_result: { type: 'string', enum: ['APPLIED', 'PARTIAL', 'NOT_FOUND', 'SUPPRESSED', 'FAILED'] },
    files: { type: 'array', items: { type: 'string' } },
    diff_summary: { type: 'string' },
    test: { type: 'string' },
    tool_calls: { type: 'integer' }
  },
  required: ['fix_result', 'files', 'diff_summary', 'test', 'tool_calls']
}
```

## Fix-verifier output (`fix-verifier.md`)

```js
{
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['VERIFIED', 'PARTIAL', 'REJECT'] },
    regressions: { type: 'array', items: { type: 'string' } },
    tests: { type: 'string' }
  },
  required: ['verdict', 'regressions', 'tests']
}
```

## Wohlgeformtheits-Check (kein npm/pip, Repo-Regel)

```bash
node -e '
const schemas = require("./tmp-schemas.js"); // extracted objects above
for (const [name, s] of Object.entries(schemas)) {
  if (typeof s !== "object" || s.type !== "object") throw new Error(name + ": not type object");
  if (typeof s.properties !== "object") throw new Error(name + ": missing properties");
  if (!Array.isArray(s.required)) throw new Error(name + ": missing required");
  const keys = Object.keys(s.properties);
  if (!s.required.every(k => keys.includes(k))) throw new Error(name + ": required not subset of properties");
}
console.log("OK");
'
```
