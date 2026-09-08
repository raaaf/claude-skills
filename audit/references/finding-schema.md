# Finding Schema

JSON schemas for every stage of the per-dimension pipeline (`audit/workflows/find.js`,
`audit/workflows/fix.js`). Each schema is a plain object literal (`type`, `properties`,
`required`), supplied by the core in each bridge request's `options.schema`.
The native Agent/collaboration prompt includes this schema; it is not a native tool parameter.
The orchestrator submits the final JSON to `codex-runner.cjs`, which validates nested types,
required properties and enums before persisting the response. Invalid replies remain pending.

## Shared execution contract

Claude and Codex both execute the same find/fix programs through the disk bridge described
in `codex-runtime.md`. Native role mapping preserves worker tool grants. Accepted responses
are immutable and replayed by deterministic request ID, independent of dispatch order.
Explicit failures return `null` to the core and keep the run incomplete. Completed native
workers are not redispatched on resume; pending worker associations must be recovered.

The early three-agent Workflow spike did cache responses, but a later nested-parallel audit
replayed 52 completed specialist requests. That spike is not evidence for resumability of
this pipeline; do not use `Workflow({resumeFromRunId})` for audit execution.

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
