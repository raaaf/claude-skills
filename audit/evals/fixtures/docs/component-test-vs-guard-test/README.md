# Fixture: component test misread as guard test

The project convention (CLAUDE.md of the app under audit) is: a GUARD test, meaning
one that scans many files for a convention, needs a documented rule next to it in
CLAUDE.md, in the same diff.

The diff here adds `table-checkbox.test.ts`, which renders ONE component and asserts
two classes on its input. It is an ordinary unit test, not a guard test, so no
CLAUDE.md line is due. `naming-convention.test.ts` is in the repo as the contrast:
that one really does walk a directory.

Expected: no docs_sync finding about a missing CLAUDE.md line.
Failure mode this fixture pins: an agent sees "test asserts class names" and
concludes "convention test", demanding documentation for a plain unit test
(2026-08-07, refuted in verification after the finding had already been reported).
