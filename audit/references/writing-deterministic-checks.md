# Writing Deterministic Checks (`audit/bin/*.sh`)

A deterministic check earns its place when a rule is mechanical, an LLM keeps
missing it, and the answer is the same every run. It is cheaper than a worker
and, unlike one, it cannot go idle or hallucinate. Two of them (duplicate lang
keys, `number_format()` locale arguments) each found real bugs on their first
live run.

They are also easy to get subtly wrong, in ways that look fine on the project
you wrote them against. What follows are mistakes actually made, not theory.

## Contract

Every check prints one machine-readable result line, then any findings:

```
CHECKNAME_RESULT=OK | <FINDING_STATE> | SKIP
```

`SKIP` when the project shape does not apply (no `lang/` directory, tool
missing, wrong framework). Skipping is not a failure and must never abort the
run. Take `PROJECT_ROOT` as `$1`, defaulting to the git toplevel.

Wire the check into `SKILL.md` Phase 1 with a comment stating what severity a
finding maps to, and whether it counts outside the diff.

## Pitfalls

**Parse structure with a parser, not a regex.** Duplicate array keys were found
by driving PHP's own `token_get_all`. A regex over the same file would have to
understand nesting, comments and interpolation, and would be wrong on all
three. If the language ships a tokenizer, pipe the file list into it.

**Counting arguments needs depth, not a comma count.** `number_format((float) $x, 2)`
defeats `[^)]*` because the cast contains a paren, and nested calls do the same.
Walk the string tracking paren depth and count separators at depth 1.

**A value can arrive as a variable.** The first version of the locale check only
accepted quoted separators, so `number_format($x, 2, $decSep, $thousSep)` was
reported as a violation across an entire PDF template. Assert the *shape* of the
call (how many arguments), not the literal spelling of the arguments.

**`$.` does not reset between files under `xargs`.** Line numbers accumulate
across the whole batch, so findings point at line 18681 of a 200-line partial.
In perl, `close ARGV if eof;` at the top of the loop fixes it. Any per-file
counter has the same trap.

**Exclude the cases the rule does not mean.** Zero decimals need no decimal
separator, so `number_format($rate, 0)` is not a locale bug. Without that carve
out the check cries wolf on every percentage in the codebase, and a check that
is usually wrong gets ignored.

## Before wiring it in

Run it against the whole project and read every hit:

- Zero findings on a project you know has the bug means the check is broken.
- Findings you have to argue away are false positives; fix the check, do not
  document the exception.
- Then plant the bug in a fixture and confirm it is caught. A check that has
  never gone red has not been tested.

Add the fixture under `audit/evals/fixtures/` with its expectation, so the LLM
path stays honest about the same class of bug.
