# /audit benchmark cases

Five historical diffs with a known Critical, used on 2026-10-02 to decide the slim pre-push gate
(`security`, `privacy`, `architecture` plus the built-in `/code-review high`). They replace the
removed fixture suite `audit/evals/`. Run one with `bash audit/bench/run-case.sh <case-no> <repo> <base> <head> <out-dir>`.
Judge a run by whether the expected Critical shows up in the audit log at the right file:line.

| case | repo | base..head | files | expected Critical | fix commit |
|---|---|---|---|---|---|
| 1 | zeit | 260d39c7..51626ffa | 52 | security: `ModalManager.php:141`, the Locked-exemption lets a foreign `parentInvoiceId` through | not recorded |
| 2 | zeit | 638ef51f..9e5e8149 | 49 | security: `HasInvoiceDetail.php:203`, `confirmMailSent` without `authorize('send')`; architecture: `ManagesInvoiceSummary.php:73`, bypasses `InvoicePolicy` | not recorded |
| 3 | events | 002228587..310b842c7 | 7 | security: `GroupCreate.php:207`, `hero_image_path` not `#[Locked]`, arbitrary image delete | 1464ea881 (first later commit touching the file, unverified) |
| 4 | events | 5ba716362..6b5de3b8b | 13 | privacy: `app.js:68` / `event-map.js:46`, OSM tiles loaded without consent | not recorded |
| 5 | events | 7906e3804..2be064194 | 22 | architecture: migration `...add_entitlement_revoked_to_payments_table.php:14`, no backfill for Disputed payments | not recorded |

"Fix commit" is the commit that closed the finding; where it says not recorded, find it with
`git log --oneline <head>..HEAD -- <file>` in the repo.

Decision rule used: the gate must find all security/payments/privacy Criticals and at least 80% of
the rest.

## Results of the new gate (2026-10-02)

- All 5 testable Criticals were found at the right file:line.
- Case 1 was refused as HUGE (`diff-size-gate.sh`), after about 4 minutes; it counts as not testable.
- Two cases (the policy bypass in case 2 and the missing dispute backfill in case 5) first came back as
  Minor and were backlogged. Fixed by the severity floor (commit 897fa7a): a non-refuted
  security/privacy/payments finding is never Minor.
- Cost per run: 8.5-14.4 M weighted tokens, 13-19 minutes wall time (cases 2 to 5: 1150, 785, 771, 884 s).
- The built-in `/code-review high` alone found all 3 security Criticals and 1 of 2 architecture
  Criticals, missed the privacy one (OSM tiles) and one architecture policy bypass.
