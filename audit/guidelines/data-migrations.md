---
applies_to: /migrations?/|/migrate/|\.migration\.|_migration\.|\.sql$
priority: non_negotiable
---

# Data-Migration Safety Guidelines

Rules for database migrations: destructive operations, locking, rollback, deploy order. Applies to Laravel migrations, but the principles are framework-agnostic (Django, Rails, raw SQL).

## Contents
- I. Destructive Operations
- II. Locking & Large Tables
- III. Rollback & Reversibility
- IV. Data Integrity
- V. Deploy Order (Expand-Contract)
- VI. Laravel Specifics
- VII. Audit Checklist

## I. Destructive Operations

- **Never `dropColumn` / `dropTable` in the same release as the code-removal PR.** Deploy the code that no longer uses the column first, wait one release, THEN drop it. Otherwise a code rollback breaks on a column that no longer exists.
- **Renames are drops in disguise.** `renameColumn` breaks running code between migration and deploy. Pattern: add new column → code writes both → backfill → code reads new → drop old column (separate release).
- **Every drop needs an explicit justification** in the migration comment: why is the data expendable, is there an export/backup reference?
- **`truncate` / `delete` without `where` in migrations:** always a critical finding.

## II. Locking & Large Tables

- **`ALTER TABLE` locks** (MySQL: depending on operation and version). On tables > ~100k rows: estimate lock duration, run the migration outside peak hours or use online DDL (`ALGORITHM=INPLACE`).
- **Index creation on large tables:** Postgres `CREATE INDEX CONCURRENTLY` (not in a transaction!), check MySQL online DDL.
- **Never run backfills as a single UPDATE:** `chunkById()` (Laravel) or a batch loop with a limit. An `UPDATE users SET ...` without chunking on 1M rows locks the table and blows up replication.
- **A backfill belongs in a command/job, not in the migration,** if it can run longer than ~30s. Migrations block the deploy.

## III. Rollback & Reversibility

- **`down()` must work, or be explicitly empty with a comment explaining why.** A `down()` that runs `dropColumn` on a column with data isn't a rollback, it's data loss — prefer `throw new RuntimeException('irreversible')` with a justification.
- **Testing `down()` is part of the review:** `migrate` + `migrate:rollback` + `migrate` must run cleanly.
- **Data migrations (UPDATE/INSERT in a migration) are almost never reversible** — mark them explicitly.

## IV. Data Integrity

- **NOT NULL on an existing column:** set a default or backfill first, then add the constraint. Check the order within the same migration file.
- **Foreign key on existing data:** clean up orphans BEFORE the constraint (otherwise the migration fails in prod, but not locally with clean test data).
- **Adding a unique constraint after the fact:** the duplicate check + cleanup strategy must run BEFORE the constraint.
- **Extend enum/status columns instead of rebuilding them:** adding new values is safe, removing values needs a data check.

## V. Deploy Order (Expand-Contract)

Zero-downtime base rule: **code versions N and N+1 must both work with the current schema.**

1. **Expand:** extend the schema additively (new column/table, nullable or with a default)
2. **Migrate:** deploy code that can do both (writes new, reads both)
3. **Backfill:** catch up old data (chunked, in a job)
4. **Contract:** remove the old schema (separate release, see I)

Audit signal: a migration AND a code change that immediately depends on it in the same diff → check whether an intermediate deploy state breaks.

## VI. Laravel Specifics

- **MySQL can't run DDL in transactions:** if statement 3 of several DDL statements in a migration fails → 1+2 are already applied, the migration is half-applied. Split large migrations.
- **`Schema::hasColumn()` / `hasTable()` guards** in migrations that run across multiple environments with drift.
- **`$withinTransaction = false`** for `CREATE INDEX CONCURRENTLY` (Postgres).
- **Avoid using models in migrations:** models change, migrations are frozen. `DB::table()` instead of `User::` — otherwise the migration breaks if the model later moves or gets a global scope.
- **`migrate:fresh` vs production reality:** a migration sequence that only works via `fresh` (not incrementally from the prod state) is broken.

## VII. Audit Checklist

| Check | Severity if violated |
|---|---|
| `dropColumn`/`dropTable`/`renameColumn` in the same diff as removing the code that uses it | Important |
| `truncate`/`delete` without `where` in a migration | Critical |
| Unchunked UPDATE/backfill on a potentially large table | Important |
| `down()` with data loss and no marking | Important |
| NOT NULL / FK / unique on existing data without cleanup beforehand | Important |
| Models instead of `DB::table()` in a migration | Minor |
| Multiple DDL statements in one migration (MySQL) | Minor |
| Backfill > 30s in a migration instead of a command/job | Important |
| Migration + dependent code in the same deploy without expand-contract | Important (medium confidence — consider deploy setup) |
