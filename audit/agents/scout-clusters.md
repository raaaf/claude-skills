# Scout: Cluster Scout

Dispatched for `architecture` and `docs_sync` (only scout) and `security` (second scout, alongside
`scout-files.md`). `agentType: 'Explore'`, `model: 'sonnet'`, `schema: SCOUT_CLUSTERS_SCHEMA`
(`references/finding-schema.md`).

## Why clusters

Naive 5-8 file chunks by directory found 0 Criticals on architecture and security in the
2026-09-05 measurement; cluster specialists on the same repo found 7 verified Criticals at equal
cost, and a "Guards" cluster (admin handlers and their capability checks, grouped across
directories) found 2 Security Criticals that every file-chunk scout missed.

## Task

Build a module map for `DIMENSION` across `SCOPE_FILES`: identify repeated structural patterns
(a guard/check that should apply uniformly, a naming or layering convention, a cross-cutting
concern like auth or escaping) and group the files that participate in each pattern into one
cluster, regardless of directory. For each cluster, record every occurrence
(`files[{path, count}]`) — `count` is how many times the pattern appears in that file (a guard
checked once vs. three times in the same file is a different signal). `why` states what makes the
cluster a real unit (shared symbol, shared responsibility, shared entry point) rather than a
coincidental directory grouping.

**Do not thin the list.** A cluster with fewer files than its actual membership hides the
comparison that makes clustering valuable in the first place (a guard present in 6 of 7
structurally identical files is only visible if all 7 are in the cluster).

A cluster names at least two files that share the pattern; a pattern that occurs in one file only
is not a cluster and is left out.

For `security`: focus cluster candidates on gates (auth/capability checks), escaping paths
(output-sink to escaping-call chains), and nonce/CSRF handlers — the file scout already covers
per-file XSS/injection sweeps, the cluster scout's job is the cross-file guard pattern the file
view cannot see.

For `architecture`: focus on layering (service vs. route-layer imports), repeated
traits/mixins/helpers and their call sites, and paired acquire/release patterns (locks, mutexes,
subscriptions).

For `docs_sync`: focus on cross-reference points — a fact repeated in multiple docs (a count, a
skill roster, a config key list) is a cluster of the doc files that state it plus the code files
that define the real value.

## Output

Reply with the scout-clusters schema: `clusters[{id, pattern, files, why}]`.
