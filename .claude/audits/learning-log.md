# Audit Learning Log

Dieses Log wird automatisch nach jedem Audit aktualisiert.

## Trends (as of 2026-08-11)

| Metric | Value |
|---|---|
| Total audits | 7 (6 regular `/audit` + 1 `/full-audit`) |
| Critical trend (last 3 regular) | 0 -> 2 -> 0 (unchanged, no new regular audit since 2026-08-05) |
| Important trend (last 3 regular) | 9 -> 6 -> 6 (unchanged) |
| Top category (last 5 regular) | Docs/Docs-Sync (14x cumulative, 4th audit in a row top category) |
| Avg findings/audit (last 5 regular) | 11.6 |
| Full-audit outlier (2026-08-11) | 3 Critical / 51 Important / 35 Minor across 146 files, 5 batches (excluded from the trend and average above per methodology) |

**Repeat offenders (from `patterns-store.sh recurrences`, >=3):**
- 7x meta doc drift (CLAUDE.md / README / SKILL.md on skill or feature changes)
- 4x audit-owned infrastructure carries invisible defects, found only incidentally
- 3x self-tested-clean, verifier finds real bug


## Retro — 2026-07-07 — main (audit)

### Statistik
- Erster Audit im Projekt — noch keine Pattern-Erkennung moeglich

### Baseline
- Critical: 0, Important: 1, Minor: 4
- Saubere Dimensionen: Architektur, Security (Critical/Important), Code Quality, A11y, UI Design, UX (nach Fix), Docs Sync, Cross-Ref (nach Fix)
- Kontext: HUGE-Diff (64 Dateien, 2100 Zeilen) per User-Override als LARGE auditiert; SAUBER nach Runde 1 (Early-Exit)
- Routing-Floor-Override griff 4x (security, a11y, ui_design, ux) wegen Eval-Fixture blade.php als Frontend-Signal — Worker bestaetigten n/a

### Vorgeschlagene Verbesserungen
- [x] check-skips.sh: Dateien unter `audit/evals/fixtures/` nicht als Frontend-/Code-Signal fuer den Routing-Floor zaehlen (4 unnötige Worker-Dispatches in diesem Audit)

---

## Retro — 2026-07-08 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 2
- Haeufigste Finding-Kategorie: Docs-Sync (3x, in beiden Audits)

### Was lief gut
- Learning-Loop geschlossen: check-skips-Fixture-Filter aus Retro 07.07. umgesetzt, in diesem Audit verifiziert (Floor-Override leer statt 4 False Positives)
- Validator verwarf 1 falsche Praemisse (examples/audit-log.md) statt sie zu fixen

### Was lief schlecht
- Docs-Sync-Drift wiederholt sich (2/2 Audits): CLAUDE.md-Beschreibung stale (07.07.), plugin.json/marketplace.json ohne /delegate (08.07.)

### Was hat gefehlt
- {DECIDED_TRADEOFFS}-Platzhalter fehlte in der /full-audit-Sektion von prompt-template.md — Datei war am 07.07. im Scope und wurde als sauber gewertet (verpasster Fund)

### Erkannte Patterns
- Geteilte Templates/Sektionen mit mehreren Aufrufern: Aenderung fuer einen Aufrufer, Sibling-Sektion vergessen (2 Audits)
- Meta-Doku (plugin.json, marketplace.json, CLAUDE.md-Tabellen) driftet bei Skill-Aenderungen (2 Audits)

### Vorgeschlagene Verbesserungen
- [x] audit/agents/11-docs-sync.md: Checkliste um `.claude-plugin/plugin.json` + `marketplace.json` ergaenzen, wenn Skill-Roster oder Skill-Descriptions im Diff sind
- [x] eval-fixture: architecture/template-placeholder-missing-sibling-section — Platzhalter in geteiltem Template nur fuer einen von zwei Aufrufern ergaenzt ({DECIDED_TRADEOFFS}-Miss vom 07.07.)

---

## Retro — 2026-07-17 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 3
- Haeufigste Finding-Kategorie: Docs/Docs-Sync (8x ueber 3 Audits, in allen 3 vertreten)
- Durchschnittliche Findings/Audit: 7,7

### Was lief gut
- Learning-Loop erneut geschlossen: beide offenen Vorschlaege aus dem 08.07.-Retro (11-docs-sync.md plugin.json/marketplace.json-Regel, Eval-Fixture template-placeholder-missing-sibling-section) wurden umgesetzt und im Audit-Log als [x] bestaetigt
- Hallucination-Validator 11/11 verifiziert, 0 verworfen — sauberer Durchlauf ohne False Positives
- security/code_quality/typography/animation lieferten "Keine Findings." mit nachweislich echter Pruefung (u.a. Live-Injection/Race-Check auf dem neuen test-lock.sh), kein Lazy-Skip

### Was lief schlecht
- Docs-Sync-Drift eskaliert trotz Gegenmassnahme: 1 -> 2 -> 5 Findings ueber die 3 Audits. Die nach dem 08.07.-Audit ergaenzte 11-docs-sync.md-Regel (plugin.json/marketplace.json) deckte diesmal nicht die tatsaechlich drifteten Dateien ab (CLAUDE.md-Tabellen, README.md-Zahlen, SKILL.md-Formatkonvention) — die Regel war zu eng auf den einen zuvor gefundenen Fall zugeschnitten
- Neues Bash-Script (audit/bin/test-lock.sh) brauchte 3 Runden bis zur Konvergenz: Runde 1 TTL/WAIT_MAX-Logikfehler, Runde 2 verwaister Kindprozess bei Kill, Runde 3 set-u-Race mit dem TERM-Trap — jede Runde deckte einen neuen Concurrency-Bug im selben ~30-Zeilen-File auf

### Was hat gefehlt
- Kein generischer Checklisten-Punkt fuer neue Lock/Wait/Heartbeat-Bash-Skripte (Signal-Handling, set-u-Interaktion, Orphan-Cleanup bei Kill) — waere in Runde 1 pruefbar gewesen statt erst durch 2 weitere Fix-Verifier-Runden aufgedeckt zu werden

### Erkannte Patterns
- Meta-Doku-Drift (CLAUDE.md/README.md/SKILL.md faellt bei Skill-/Feature-Aenderungen auseinander): jetzt in allen 3 Audits (repeat offender, siehe Trends)
- Iteratives Haerten neuer Concurrency-Bash-Skripte ueber mehrere Runden: jede Runde findet einen neuen Edge-Case im selben File (test-lock.sh: 07-17, einzelner Beleg bisher, noch kein Repeat-Offender)

### Vorgeschlagene Verbesserungen
- [x] audit/agents/11-docs-sync.md: Checkliste ueber plugin.json/marketplace.json hinaus verallgemeinern — bei neuem/umbenanntem Skill, Feature oder Step: CLAUDE.md-Tabellen (Commands, Migrated-so-far, Skill-Roster), README.md-Zahlen/Listen und SKILL.md-Schrittnummerierung/Format explizit gegenchecken (3/3 Audits zeigen dieses Muster)
- [x] audit/guidelines/architecture.md: Checklisten-Punkt fuer neue Lock/Wait/Heartbeat-Bash-Skripte ergaenzen (explizite Pruefung von Signal-Traps x set -u, Orphan-Prozess-Cleanup bei Kill) — test-lock.sh brauchte 3 Runden genau dafuer

---

## Retro — 2026-08-04 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 4
- Haeufigste Finding-Kategorie: Docs/Docs-Sync (ca. 11x kumuliert ueber 4 Audits, weiterhin Repeat-Offender) — Architecture holt in diesem Audit stark auf (7x in diesem Lauf allein)
- Durchschnittliche Findings/Audit: 9,3

### Was lief gut
- Erster Lauf von Schritt D.7 (Verifikation vor Fix): 9 bestaetigt, 1 widerlegt, 0 unklar (von 10) in Runde 1, plus 1 weitere Bestaetigung mit Schweregrad-Korrektur im Cross-Ref-Pass. Die Widerlegung war substanziell — der Verifier verfolgte den echten Kontrollfluss und zeigte, dass die behauptete Push-Gate-Luecke nicht existiert
- Derselbe Verifier korrigierte zusaetzlich eine falsche Zeitangabe im Finding selbst (wann der Defekt eingefuehrt wurde)
- Beide offenen Vorschlaege aus dem vorigen Retro wurden vor Audit-Start umgesetzt und als [x] bestaetigt
- Validator 19/19 verifiziert, 0 halluziniert

### Was lief schlecht
- Die Routing-Floor uebersprang docs_sync in Runde 1 trotz eines Diffs mit CLAUDE.md, README.md und 18 SKILL.md-Dateien. Der Orchestrator musste manuell uebersteuern. Grund: performance/seo/animation/docs_sync waren komplett der inzwischen Opt-in gewordenen Triage ueberlassen und liefen bei keinem Standardlauf. In derselben Runde als Finding erkannt und in check-skips.sh gefixt
- 3 von 9 Important-Findings lagen in audit/evals/run-evals.sh. Zwei davon (verunreinigtes Skill-Argument, must_not_find-Regel) waren monatealt: die Eval-Suite hat unbemerkt falsch gescort, bis ein Vollaudit die Datei zufaellig traf

### Was hat gefehlt
- Keine gezielte Pruefung fuer die Audit-Infrastruktur selbst (run-evals.sh, check-skips.sh, fix-verifier-Dispatch). Alle drei bisherigen "vorbestehend seit Monaten"-Funde lagen in dieser Skriptklasse und wurden beilaeufig gefunden
- Nur ein Datenpunkt fuer die neue Kombination aus Coverage-Worker-Prompt und D.7 als Filter. 9/1/0 zeigt noch keinen Trend

### Erkannte Patterns
- Meta-Doku-Drift (Docs-Sync): 4/4 Audits, Umfang waechst. Diesmal traf es die Routing-Floor selbst
- Neu (1 Beleg): audit-eigene bin/*.sh-Skripte tragen ungetestet monatealte Bugs, die nur durch Zufallstreffer auffallen

### Vorgeschlagene Verbesserungen
- [x] Naechster Audit: bestaetigen, dass der Floor-Fix in check-skips.sh (has_docs/has_seo) docs_sync/performance/seo/animation auf einem echten Diff ausloest, ohne manuelle Uebersteuerung
- [x] audit/guidelines/code-quality-2026.md (nicht code-quality.md, die liegt bei 490 Zeilen): Abschnitt XVIII, Checklisten-Punkt fuer audit/bin/*.sh selbst — bei Aenderung pruefen, ob ein deterministischer Test oder eine eval-Fixture den Pfad abdeckt, da alle bisherigen Monate-alten Funde in dieser Klasse lagen
- [x] eval-fixture: docs/routing-floor-doc-drift (Verzeichnis-Fixture, deckt has_docs ab) — Diff mit vielen SKILL.md/CLAUDE.md/README.md-Aenderungen loeste docs_sync nicht ueber die Floor aus

---

## Retro — 2026-08-05 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 5
- Haeufigste Finding-Kategorie: Docs/Docs-Sync (~14x kumuliert). In diesem Lauf dominierte Security (4x, davon 2 Critical, die ersten Criticals in der Projekt-Historie)
- Durchschnittliche Findings/Audit: 10,2

### Was lief gut
- D.7 und die Fix-Verifikation arbeiteten ueber alle drei Runden wie entworfen: der Fix-Agent legte jede Runde eine saubere, selbst entworfene Testtabelle vor, und der unabhaengige Verifier fand mit eigenen Faellen trotzdem jedes Mal einen echten Defekt. Ohne diese Stufe waeren alle drei ausgeliefert worden
- Der Schema-Fehler wurde reproduziert statt behauptet: `Invalid hooks in skill 'audit'` im Debug-Log gegen eine erfolgreiche Registrierung einer Kontroll-Skill
- 10/10 bestaetigt, 0 widerlegt; der Verifier praezisierte dabei ein Finding selbst (der `--git-dir=`-Bypass galt nur fuer einen der beiden Guards)
- Nach dem letzten Fix wurde die deployte Kopie synchronisiert und live gegengetestet

### Was lief schlecht
- Dieselbe Sicherheitsmechanik war in der Vorsession schon einmal als gefixt gemeldet worden, nachdem nur die Skripte isoliert getestet wurden. Weder die Hook-Registrierung noch die Exit-Code-Semantik waren geprueft. Beide Defekte sind vollstaendig unsichtbar: keine Fehlermeldung, keine Logzeile, kein fehlgeschlagener Lauf
- Die Referenzdatei, die genau fuer solche Faelle existiert, behauptete selbst den falschen Exit-Code und widersprach dabei ihrer eigenen Zeile 33. Plausible Quelle des urspruenglich falschen Fixes
- Konvergenz nicht monoton (10, 1, 3), weil der Fix-Agent jede Runde nur gegen die eigene Tabelle prueft
- Abschnitt XVIII in code-quality-2026.md, gestern fuer genau diese Fehlerklasse geschrieben, griff nicht: sein Scope nennt audit/bin und audit/evals, der Defekt lag in audit/hooks und im Frontmatter

### Was hat gefehlt
- Ein Checklistenpunkt, der beim Patchen eines Shell-Guards die Standard-Bypass-Klassen (Case-Variation, Command-Substitution, Subshell- und Brace-Prefixe) VOR dem Verifier verlangt
- Eine Ende-zu-Ende-Pruefung fuer skill-deklarierte Hooks: isoliertes Skript-Testen kann eine vom Schema abgelehnte Deklaration nicht auffangen

### Erkannte Patterns
- Selbst-getestet-sauber, Verifier findet echten Bug: dreimal im selben Audit. Erster Beleg, dass das innerhalb eines Laufs wiederholt auftritt
- Audit-eigene Infrastruktur traegt unsichtbare Defekte: zweiter Beleg (04.08. run-evals.sh/check-skips.sh, 05.08. Hook-Registrierung und Exit-Code). Gleiche Ursache, andere Dateiklasse, Guideline-Scope zu eng
- Falsche Referenzdoku als Fehlerursache: erster Beleg

### Vorgeschlagene Verbesserungen
- [x] audit/guidelines/code-quality-2026.md Abschnitt XVIII: Scope explizit auf audit/hooks/*.sh und skill-deklarierte hooks:-Frontmatter erweitern, gleiches Fehlerbild, andere Dateiklasse
- [x] audit/agents/fix-agent.md: bei Fixes an Shell-basierten Security-Guards die Selbsttest-Tabelle verpflichtend um Case-Variation und Command-Substitution erweitern, beides wurde in jeder Runde uebersehen
- [x] write-a-skill/references/hooks-pitfalls.md: ergaenzen, dass isoliertes Skript-Testen eine schema-abgelehnte Deklaration nicht erkennt, der Debug-Log-Lauf gehoert dazu
- [x] eval-fixture: security/hook-frontmatter-flat-key-silently-ignored, jetzt audit/evals/fixtures/security/deploy-guard-skill.md (umbenannt, weil der alte Name seine eigenen Scoring-Keywords enthielt)
- [x] eval-fixture: security/pretooluse-exit-1-non-blocking, jetzt audit/evals/fixtures/security/db-command-guard.sh (umbenannt, weil der alte Name seine eigenen Scoring-Keywords enthielt)

---

## Retro — 2026-08-05 — main (audit, 02:00-Lauf)

### Statistik
- Audits insgesamt im Projekt: 6
- Haeufigste Finding-Kategorie: Docs/Docs-Sync (14x kumuliert, 4. Audit in Folge Top-Kategorie)
- Durchschnittliche Findings/Audit (letzte 5): 11,6

### Was lief gut
- D.7: 4 bestaetigt, 1 widerlegt (von 5). Die Widerlegung war werthaltig: der vorgeschlagene Fix haette Step C "konsistent" gemacht und dabei eine echte neue Inkonsistenz erzeugt
- Den subtilsten Fund der Nacht lieferte der Fix-Verifier, kein Worker: die zwei neuen Eval-Fixtures konnten korrekte von falschen Findings nicht unterscheiden, weil Findings `file:line` zitieren muessen und beide Fixture-Namen ihr eigenes Scoring-Keyword trugen. Bewiesen, indem er ein bewusst falsches Finding durch den echten Scorer schickte
- Die falsche Case-Behauptung wurde an allen vier Stellen korrigiert, an die sie sich verbreitet hatte: zwei Hook-Kommentare, die Selbsttest-Vorschrift und der vorige Audit-Log

### Was lief schlecht
- Dieser Audit existierte, weil die Umsetzung der eigenen fuenf Lernpunkte in 4 von 6 Important-Findings selbst defekt war: eine Beweisschwelle, die kein Worker erreichen kann, ein Sweep, der /full-audit ausliess obwohl CLAUDE.md bereits Abdeckung behauptete, und eine falsche Begruendung, die schon in drei Dateien plus einem committeten Log stand
- Abschnitt XVIII, vor zwei Tagen fuer genau diese Fehlerklasse geschrieben, musste binnen zwei Tagen zweimal korrigiert werden: erst zu enger Scope, dann eine Beweisschwelle, die mit Read/Grep/Glob unerreichbar ist

### Was hat gefehlt
- Keine Pruefung, ob eine frisch geschriebene Beweisschwelle mit dem Tool-Zugriff der Worker-Rolle erfuellbar ist, die sie lesen wird
- Kein Mechanismus, der die Umsetzung eigener Lernpunkte als normal risikobehafteten Diff behandelt statt als abgehakte Checkliste

### Erkannte Patterns
- Selbst-getestet-sauber, Verifier findet echten Bug: ~10x ueber drei Audits derselben Nacht
- Audit-eigene Infrastruktur traegt unsichtbare Defekte, nur beilaeufig gefunden: dritter Beleg, damit ueber der 3er-Schwelle
- Neu: die Umsetzung eines eigenen Lernpunkts ist nicht risikoaermer als eine gewoehnliche Aenderung

### Vorgeschlagene Verbesserungen
- [ ] audit/agents/fix-agent.md: korrigiert ein Fix eine Faktenbehauptung, die anderswo als Begruendung dient, vor "done" einen repo-weiten Grep auf die Kernformulierung verlangen, nicht nur die Zieldatei
- [ ] Guideline-Regel: eine Guideline, die Evidenz verlangt, muss benennen, welche Worker-Rolle sie liefern soll, gegengeprueft gegen die Tool-Grants in agents/*.md
- [x] eval-fixture: process/self-test-blind-spot, ein Durchlauf, der eine Shell-Guard-Aenderung nur gegen die selbst geschriebene Tabelle prueft
- [x] Bei jedem Fund der beiden neuen Muster `patterns-store.sh recur` aufrufen, der Zaehler startet bei 1 statt bei den beobachteten ~10 bzw. 3

## Retro — 2026-08-11 — main (full-audit)

### Statistics
- Total audits in the project: 7 (6 regular `/audit` + 1 `/full-audit`, this run)
- Most frequent finding category (this run): security/executable-layer correctness (guard bypasses, credential redaction, RCE-via-`@include`, unbounded network calls, races) — batch 1 (bash helpers + hooks) alone carried 2 of 3 Critical and 19 of 51 Important
- Average findings per audit (last 5 regular audits, this full-audit excluded per methodology): 11.6

### What went well
- The round-2 regression review caught 3 of round 1's own fixes with regressions, including a fail-open inversion produced by a fix that was correct in isolation (adding a `source` without guarding it). Composition of individually-correct fixes is a real regression source, not just single-fix errors.
- Every confirmed guard bypass this run was verified by direct reproduction (executing the exact bypass command), not by tracing code. Both refuted findings were pure read-only inferences — reproduction is now the clear differentiator between confirmed and refuted here.
- The orchestrator caught the scope-collection anomaly manually (`SOURCE_DIRS` output looked wrong during setup) and traced it to a real Critical bug instead of proceeding with a silently wrong scope.

### What went poorly
- `detect-framework.sh` emitted an un-evalable `SOURCE_DIRS`, so `eval "$(...)"` silently produced an EMPTY scope for every multi-source-dir framework in every prior run on such a repo. Nothing in the pipeline asserts the collected scope is non-empty before dispatching batches as clean.
- `/audit` Step 4a (the mandatory post-fix-wave cross-check added after the 2026-07-22 stash incident) read a file nothing in the pipeline ever wrote. The safety net was dead on arrival and no audit noticed until this one.
- Round-1 batch-1 workers exhausted their 20-tool-call budget after ~19 of 31 files, leaving files with zero coverage. Not caught by the pipeline itself — closed only because round 2 happened to be scoped to the unread files by design of the orchestrator, not by any rule.
- The previous retro's open item to call `patterns-store.sh recur` for two known patterns went unimplemented again; the live-feed gap was 2 retros old. Closed in this run (see recurrence counts).

### What was missing
- A deterministic assertion that scope collection actually found files before any batch is dispatched as clean.
- A way for a worker to report which of its assigned files it never reached, distinct from "read the file and found nothing".
- Verification that mandatory cross-file contracts (a step reads a file another step is supposed to write) are actually wired end to end, not just correct in isolation.

### Detected patterns
- Audit-owned infrastructure carries invisible defects, found only incidentally: 4th occurrence overall (2026-08-04 run-evals.sh/check-skips.sh, 2026-08-05 hook registration/exit-code, this run's detect-framework.sh scope bug and dead Step 4a safety net — two more hits in one run).
- Self-tested-clean, verifier finds real bug: recurs at a new granularity this run — previously within-round (fix agent vs fix-verifier), this time across rounds (round 1's own fixes vs round 2's dedicated regression review).
- New: read-only inference is a measurably weaker signal than reproduction for guard/hook findings in this pipeline (0 of 2 read-only findings confirmed, vs reproduction backing every confirmed guard bypass).
- New: a security-guard bug (whole-string grep instead of per-segment exemption evaluation) survived the 2026-08-05 hardening audit of the same file undetected — that audit hardened prefix and case-variation bypasses on `block-worktree-wide-git.sh` but not this one.

### Suggested improvements
- [x] `full-audit/SKILL.md` Phase 1 (scope collection): assert the collected file list is non-empty and not wildly smaller than `git ls-files | wc -l` before dispatching batches; abort loudly instead of proceeding. Mirror wherever `audit/SKILL.md` consumes `detect-framework.sh` output for scope.
- [x] `audit/agents/prompt-template.md`: a worker that stops before covering every assigned file (budget/turn exhaustion) must name the unread files explicitly in its reply, so the orchestrator can auto-schedule a follow-up round instead of relying on manual detection.
- [x] eval-fixture: security/guard-exemption-whole-string-grep — a bash guard whose exemption check greps the whole command string instead of evaluating per logical segment (`&&`/`;`/`$()`), letting one read-only mention (e.g. `git stash list`) disarm protection for a mutating command elsewhere in the same line.
