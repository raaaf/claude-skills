# Audit-Pipeline pro Dimension (Umbau von /audit und /full-audit)

Current status (2026-09-08): integrated into main and installed from the regular checkout for both runtimes. See the final integration section for current behavior; earlier runtime and temporary-source decisions below are historical.

> **Executor instruction:** Schritt für Schritt abarbeiten, jedes Verify-Kriterium prüfen, bevor es weitergeht. Bei einer STOP-Bedingung: anhalten und berichten, nicht improvisieren.
>
> **Drift check (zuerst):** `git diff --stat c171196..HEAD -- audit full-audit agents/audit-*.md`
> Hat sich eine In-Scope-Datei seit Planerstellung geändert: aktuellen Stand gegen den Plan abgleichen; bei Abweichung ist das eine STOP-Bedingung.

## Meta
- Planned at: commit `c171196`, 2026-09-05
- Schritt 0 (Workflow-Spike) am 2026-09-05 bestanden, siehe Schritt 0.
- Repo: `/Users/rafael/Developer/claude/skills` (Skill-Quelle; `~/.claude/skills` wird per Stop-Hook synchronisiert, nie direkt editieren)
- Messwerte, auf denen der Plan beruht: Testreihe vom 2026-09-05 auf `wordpress-starter-theme` (Basis 0367d622), drei Dimensionen (Security, A11y, Architektur), 31 Testagenten, 25 USD Gegenwert. Zusammenfassung im Abschnitt "Gemessene Parameter".

## Problem

Der Full-Audit vom 2026-09-04/05 auf `wordpress-starter-theme` brauchte 22 Stunden und rund 760 USD API-Gegenwert (Korrektur 2026-09-05 abends: die erste Zählung von 1.315 USD hatte Transkriptzeilen je Content-Block mehrfach gezählt; alle Messwerte der Testreihe sind mit derselben Methode entstanden und damit um denselben Faktor zu hoch, die Verhältnisse bleiben): 19 Batches à 15 Dateien, jeder Batch alle 3 Runden, 414 Agents, ein Fable-Orchestrator mit im Median 497k Kontext über 2.602 Turns, davon 576 Turns reine Nachrichtenempfänge (390 Idle-Notifications). 682 der 1.036 Findings waren Minor und wurden gefixt, 7 der 17 Criticals hat der Audit durch eigene Fixes selbst erzeugt. Die Findephase war billig, die Fix-Runden und der Orchestrator waren teuer.

## Ziel

Beide Skills laufen als eine Pipeline pro Dimension: Scout, Spezialisten, frischer Verifier, Orchestrator entscheidet, danach einmalige Fixphase pro Datei mit Fix-Verifier. Messbar auf demselben Repo bei Effort high:

- Findephase alle 13 Dimensionen plus Regressionsdurchgang: unter 100 USD Gegenwert, unter 60 Minuten Wall-Clock (Schätzung nach den Ergänzungen: 80 bis 90 USD).
- Recall gegen das Audit-Log vom 2026-09-05: mindestens 6 der 7 echten Criticals (die AUDIT-INTRODUCED zählen nicht).
- Orchestrator-Turns pro Lauf: unter 100.
- Kein Batch-State-File, keine Runden, keine Cross-Ref-Runde, kein Regressionspass.

## Nicht-Ziele

- Keine Änderung an den bestehenden deterministischen Skripten in `audit/bin/` (Secrets, Lockfile, i18n, Deps, Cache, Test-Lock, Run-Ledger, Docs-Claims). Sie werden aufgerufen wie bisher. Neu hinzu kommen genau zwei Skripte (Schritt 10c): `run-cost.sh` und `check-ci-hardening.sh`.
- Kein neuer Skill-Name. `/audit` und `/full-audit` bleiben die Einstiege, 12 Skills und 2 Hooks referenzieren sie.
- Keine Commits durch den Audit. Fixes bleiben im Working Tree, `/ship` committet.
- Kein Testplan-Abschnitt, keine GitHub-Issues, kein Incremental Cache (Entscheidung 2026-09-05; die Skripte `cache-check.sh`/`cache-write.sh` bleiben liegen, werden nicht aufgerufen).
- Design-Audit, Baseline-Check, Review, Improve werden nicht angefasst; sie referenzieren nur den Marker oder den Skill-Namen.

## Out of Scope (Dateien)

- `audit/bin/*.sh`: bestehende Checks unverändert. Ausnahmen: die Rosterliste in `verify-agents.sh` (Schritt 2) und die zwei neuen Skripte aus Schritt 10c.
- `~/.claude/settings.json`: der PreToolUse-Push-Hook prüft den Marker `/tmp/claude-audit-passed-{md5 cwd}`, der bleibt. Der Stop-Hook `audit-loop.sh` wird in Schritt 9 entschärft, nicht die settings.json.
- `agents/security-auditor.md`, `agents/code-reviewer.md`, `agents/ui-ux-reviewer.md`: generische Agent-Typen, von anderen Skills genutzt. Die Spezialisten-Prompts leben in `audit/agents/`, nicht dort.
- `live-audit/`, `design-audit/`: eigene Pipelines.

## Lösung

### Ansatz

Eine Engine in `audit/`, zwei dünne Einstiege. `/audit` ruft die Engine mit `SCOPE=diff` (Dateien seit `origin/{branch}` per `collect-scope.sh`) und setzt am Ende den Push-Marker. `/full-audit` ruft sie mit `SCOPE=repo` (alle getrackten Quelldateien per `collect-scope.sh --all`) und setzt keinen Marker.

Keine Argumente, keine Flags. Beide Skills stellen beim Start genau eine Frage-Runde per `AskUserQuestion` mit zwei Fragen, Vorauswahl jeweils markiert: (a) Dimensionen (Alle, Backend, Frontend, Auswahl), (b) Fixumfang (nur finden und loggen; Critical fixen; Critical und Important fixen). `CLAUDE_EFFORT` aus dem Frontmatter setzt nur die Vorauswahl von (b): low → nur finden, medium → Critical, high/xhigh → Critical und Important. Die Argumentform `/audit security` und `references/partial-audit.md` entfallen; eine Teilauswahl bei (a) setzt wie bisher keinen Marker. Für Automatisierung ohne Fragen (Eval-Harness `audit/evals/run-evals.sh --scoped`, CI) bleibt ausschließlich die bestehende ENV-Form `FULL_AUDIT_DIMENSIONS` (wird zu `AUDIT_DIMENSIONS`, beide Skills) plus neu `AUDIT_FIX_SCOPE=none|critical|all`; ist mindestens eine der beiden gesetzt, entfällt die Frage-Runde ganz und die andere nimmt ihren Default (alle Dimensionen bzw. Vorauswahl aus `CLAUDE_EFFORT`), damit ein Headless-Lauf nie an `AskUserQuestion` hängt. Keine CLI-Argumente.

Die Findephase ist ein Workflow-Skript (`audit/workflows/find.js`), das pro Dimension eine `pipeline()` fährt: Scout → Chunking (Code, kein Agent) → Spezialisten → Verifier. Rückgabe ist ein JSON-Objekt mit verifizierten Findings pro Dimension. Das Session-Modell startet den Workflow, wartet auf die Task-Notification, liest das JSON und entscheidet pro Finding: fixen, loggen, verwerfen. Es liest keinen Code.

Die Fixphase ist ein zweites Workflow-Skript (`audit/workflows/fix.js`): Findings nach Datei gruppiert, ein Fixer pro Datei mit allen Findings dieser Datei, dann ein Fix-Verifier je 3 bis 5 Fixes. Kein Worktree-Isolation nötig, die Fixer arbeiten auf disjunkten Dateien. Danach läuft die Test-Suite einmal im Session-Modell über `test-lock.sh`, dann Log (mit der Kostenzeile aus `run-cost.sh`) und Learning.

Warum Workflow statt Agent-Tool: das Agent-Tool liefert jede Rückmeldung als eigenen Turn mit dem vollen Session-Kontext, und Teammates bleiben nach ihrem Report idle. Der Workflow liefert ein Ergebnis in einer Notification, cached abgeschlossene Agents beim Resume (Session-Limit um Mitternacht kostete gestern einen halben Tag) und erlaubt `agentType` plus `schema`, sodass die bestehenden Agent-Typen `audit-fix-agent`, `audit-fix-verifier`, `security-auditor` weiterverwendet werden. Die Skill-Anweisung, den Workflow zu starten, gilt als Opt-in des Nutzers.

Warum Cluster für Architektur und Security: naive 7-Datei-Chunks fanden 0 Criticals, Cluster-Spezialisten 7 verifizierte Criticals bei gleichen Kosten, und der Cluster "Guards" fand zwei Security-Criticals (Admin-Handler ohne Capability-Check), die alle Security-Datei-Chunks übersehen hatten. architecture und docs_sync bekommen nur den Cluster-Scout; security bekommt beide Scouts (Datei-Chunks plus Cluster für Gates, Escaping-Pfade, Nonce-Handler); alle anderen den Datei-Scout.

Vier Ergänzungen nach der Prüfung der Nicht-Ziele (2026-09-05, Entscheidung des Nutzers): (1) `fix.js` endet mit einem Regressionsdurchgang, ein Spezialist je 5 bis 8 von Fixern geänderte Dateien, der nur die Diffs liest und über alle Dimensionen nach Regressionen fragt (gestern waren 7 von 17 Criticals durch eigene Fixes entstanden). (2) Bei `SCOPE=diff` darf der Datei-Scout je Diff-Datei bis zu 5 direkt importierte oder aufrufende Dateien als `context: true` aufnehmen; Spezialisten lesen sie mit, melden dort aber nur Findings, die der Diff verursacht. (3) Dimension 13 `privacy` (Consent-Gates für Drittinhalte, Tracking-Skripte, Cookies, IP-Speicherung und -Logging, Datenweitergabe, Impressums- und Datenschutzlinks, Formulardaten); Security-Spezialisten legen Consent-Fragen nicht mehr als "dokumentiert" beiseite, sondern lassen sie dieser Dimension. (4) Zwei neue deterministische Skripte, siehe Schritt 10c.

### Ablauf (Zielbild)

```
Session-Modell                         Workflow find.js (pro Dimension, parallel)
--------------                         ------------------------------------------
Phase 0  Pre-Checks (bin/*.sh)
Phase 1  Scope (collect-scope.sh)
         Dimensionen wählen
         Workflow find.js starten  -->  Scout (Sonnet, Explore)
                                        chunk() 5-8 Dateien / Cluster
                                        Spezialisten (Sonnet, agentType je Dim.)
                                        Verifier (Sonnet, 1 je 35-40 Findings)
Phase 2  JSON lesen, entscheiden   <--  {dimension: {files, findings[], verdicts[]}}
         fix / log / discard
         Workflow fix.js starten   -->  Fixer pro Datei (audit-fix-agent, Sonnet)
                                        Fix-Verifier je 3-5 Fixes (audit-fix-verifier)
Phase 3  Test-Suite (test-lock.sh) <--  {fixes[], verdicts[], regressions[]}
Phase 4  Audit-Log schreiben, Marker (/audit only), Run-Ledger
Phase 5  Learning-Agent (wie heute)
```

### Gemessene Parameter (Spezifikation)

| Parameter | Wert | Beleg 2026-09-05 |
|---|---|---|
| Scout-Modell | Sonnet, agentType Explore | Haiku gleicher Preis (0,42 vs 0,48 USD), 3 Critical-Dateien übersehen |
| Scout-Output | Dateiliste mit Relevanz-Tag, KEIN Ausdünnen ähnlicher Dateien | A11y-Scout hat 14 Layout-Varianten eigenmächtig weggelassen |
| Scout für architecture, docs_sync (nur Cluster) und security (Chunks plus Cluster) | Cluster-Karte: Module, wiederholte Muster mit Vorkommen pro Datei, Layering-Notizen | Cluster-Spezialisten 7 Criticals, Chunks 0; Guards-Cluster fand 2 Security-Criticals, die Chunks übersahen |
| Regressionsdurchgang nach den Fixes | 1 Spezialist je 5-8 geänderte Dateien, liest nur Diffs, alle Dimensionen | gestern 7 von 17 Criticals AUDIT-INTRODUCED, 19 Pässe à 0,50 USD |
| Kontext bei SCOPE=diff | bis zu 5 Importe/Aufrufer je Diff-Datei, `context: true`, keine eigenen Findings | Fix in A öffnet Loch über unverändertes B |
| Dimension privacy | 13. Dimension, agentType security-auditor, eigene Scout-Muster | Consent-Gate gestern Critical, heute als "dokumentiert" übergangen |
| Chunk-Größe | 5 bis 8 Dateien, zusammengehörige Dateien zusammen | 14 Dateien: XSS in gelesener Datei übersehen; 8: alles gefunden |
| Spezialist-Modell | Sonnet, agentType je Dimension | 8 Dateien Sonnet = 14 Dateien Opus an Treffern, ein Zehntel Preis. **Einschränkung, festgestellt im Review am 2026-09-06:** die Testprompts der Messreihe nannten die gesuchten Defektklassen wörtlich ("X-Forwarded-For, das den linken Eintrag nimmt", "SSRF ohne AAAA", "CSP ohne base-uri"). Gemessen wurde damit, ob ein Spezialist eine benannte Klasse in N Dateien bestätigt, nicht ungestützter Recall. Der ungestützte Wert steht erst nach Schritt 11 fest. |
| Verifier | Sonnet, adversarial, 1 je 35-40 Findings, liest CLAUDE.md zuerst | 22 % verworfen (A11y), 3 % (Architektur), 14 % Severity korrigiert |
| Fixer | audit-fix-agent, Sonnet, alle Findings einer Datei, Testkommando im Brief, Budget 25 Tool-Calls | 9 und 11 Calls, 0,39 und 0,54 USD, Tests geschrieben und grün |
| Fix-Verifier | audit-fix-verifier, Sonnet, 3-5 Fixes, gefilterte Tests plus Suite, Baseline-Failures im Brief | 10 Calls, 0,29 USD |
| Startfrage Fixumfang | nur finden / Critical / Critical und Important; Vorauswahl aus `CLAUDE_EFFORT` (low, medium, high) | Entscheidung 2026-09-05: keine Argumente, alles per Startfrage |
| Minor | nie fixen, immer loggen | 682 Minor-Fixes waren der Rundentreiber |
| Kosten pro Dimension | 7 bis 8 USD, 5 bis 8 Minuten | Security 67 Dateien, A11y 70 Dateien, Architektur 12 Cluster |

### Prompt-Regeln (aus den verworfenen Findings)

Gelten für Scout, Spezialist und Verifier, stehen einmal in `audit/agents/prompt-template.md`:

1. Jedes Finding hat eine ID der Form `{dimension}-{chunk}-{n}`, wobei `{chunk}` der Chunk-Index ist, den `find.js` im Briefing mitgibt. Nur ein Dimensionspräfix reicht nicht: im Trockenlauf am 2026-09-06 nummerierte jeder Spezialist ab 1, sodass dreimal `security-1` im selben Ergebnis stand und Verdicts nicht mehr eindeutig zuzuordnen waren.
2. Jedes Finding nennt ALLE beteiligten Dateien mit Zeilen. Diese Regel senkte die Verwerfungsrate von 22 % auf 3 %.
3. Verboten: "verified safe"-Listen, Watch-Items, "unverified, flagged for cross-check". Jede Zeile nennt einen Defekt. Das war die Hälfte aller Verwerfungen.
4. Severity ist an ein konkretes Kriterium gebunden (Security: Ausnutzbarkeit; A11y: WCAG-AA-Kriterium, AAA ist nie Important; Architektur: Critical nur bei zwei widersprüchlichen Quellen der Wahrheit).
5. Der Spezialist liest CLAUDE.md zuerst; dokumentierte Entscheidungen sind kein Finding.
6. Dem Fix-Verifier werden die Baseline-Failures der Suite mitgegeben (vor der Fixphase einmal messen; mein Brief sagte "eine", es waren sieben).

### Schritte

0. **Workflow-Spike.** ERLEDIGT 2026-09-05 in der Planungssession (Run `wf_0f7107d6-f3f`, 3 Agents, 74 s, 87k Token). Beobachtungen, die Schritt 1 wörtlich in `audit/references/finding-schema.md` unter "Workflow-Kontrakt, geprüft am 2026-09-05" übernimmt: (a) `agentType` `Explore`, `security-auditor` und `code-reviewer` werden angenommen und behalten ihre Tool-Grants; (b) `schema` mit verschachtelten Objekten, `enum` und `required` liefert das validierte Objekt direkt, kein Parsen; (c) ein werfender Thunk in `parallel()` kommt als `null` zurück, der Lauf endet normal, die Fehlermeldung steht im `<failures>`-Block der Notification; (d) ein zweiter Start mit `resumeFromRunId` und unverändertem Skript plus `args` lief in 29 ms mit 0 Token, alle drei Agents aus dem Cache. Zusatzbeobachtung für Schritt 2: der Spezialist mit einem dreizeiligen Prompt fand in zwei Dateien nur 1 der 3 bekannten Findings (Race Condition, nicht XSS und X-Forwarded-For); die Trefferquote hängt am Prompt aus `audit/agents/2-security.md`, nicht am Tool. Ursprüngliche Aufgabe: Bevor irgendetwas geschrieben wird: ein Wegwerf-Workflow (Inline-Skript, 3 Agents) prüft den Kontrakt, auf dem Schritt 4 bis 7 stehen: `agentType: 'security-auditor'` wird angenommen, `schema` erzwingt das Objekt, `parallel()` liefert `null` für einen absichtlich abgebrochenen Agent, und ein zweiter Aufruf mit `resumeFromRunId` liefert die abgeschlossenen Agents aus dem Cache (im Journal `<transcriptDir>/journal.jsonl` sichtbar). Ergebnis als Abschnitt "Workflow-Kontrakt, geprüft am {Datum}" in `audit/references/finding-schema.md`. → verify: der Abschnitt nennt die vier Punkte mit je einem Satz Beobachtung; schlägt einer fehl, ist das eine STOP-Bedingung, kein Workaround.

1. **Findings-Schema festlegen** in `audit/references/finding-schema.md`: JSON-Schema für Scout-Output (`files[{path, tag, reason}]` bzw. `clusters[{id, pattern, files[{path, count}], why}]`), Spezialist-Output (`findings[{id, severity, confidence, files[{path, lines}], issue, impact}]`, `coverage`), Verifier-Output (`verdicts[{id, verdict, severity, reason}]`), Fixer-Output (`fix_result, files, diff_summary, test, tool_calls`), Fix-Verifier-Output (`verdict, regressions, tests`). → verify: Datei existiert, jedes Schema hat `type: object`, `properties`, `required ⊆ properties`; ein Vanilla-Node-Einzeiler ohne Paket (`node -e` mit `typeof`, `Object.keys`, `required.every(k => k in properties)`) prüft die fünf Schemata auf Wohlgeformtheit; keine Abhängigkeit (Repo-Regel: no npm, no pip).

2. **Spezialisten-Prompts pro Dimension konsolidieren.** Die 12 Dateien `audit/agents/1-architecture.md` bis `12-copy.md` plus die neue `13-privacy.md` (Look-for-Liste: Consent vor Drittinhalten, Tracking und Analytics, Cookies und Storage, IP-Adressen in Logs und Rate-Limitern, Formulare und Datenweitergabe, Pflichtlinks; Severity: Critical = personenbezogene Daten gehen ohne Rechtsgrundlage an Dritte oder werden ohne Consent geladen) werden zu den Spezialisten-Prompts: je Datei ein Block "Look for" (aus der bisherigen Datei), ein Block "Severity" (Regel 4), ein Block "Output" (Schema aus Schritt 1). `w1-code.md`, `w3-frontend.md`, `w4-content.md`, `0-triage.md` und `agents/audit-content-worker.md`, `agents/audit-triage.md` werden gelöscht (kollabierte Worker gibt es nicht mehr). `prompt-template.md` wird auf die Prompt-Regeln 1 bis 6 plus die gemeinsame Kopfzeile (Repo-Root, CLAUDE.md zuerst, jede Datei ganz lesen) reduziert. → verify: `ls audit/agents/` zeigt genau `1-*.md` bis `13-*.md`, `scout-files.md`, `scout-clusters.md`, `finding-verifier.md`, `fix-agent.md`, `fix-verifier.md`, `learning-agent.md`, `prompt-template.md`; `grep -l "verified safe\|watch item" audit/agents/` leer; `grep -c "COVERAGE" audit/agents/[0-9]*.md` = 13.

2b. **Dimensionsprompts gegen bekannte Defektklassen kalibrieren.** Der Trockenlauf am 2026-09-06 zeigte: sechs Security-Dateien
vollständig gelesen (`COVERAGE: full`), keins der vier bekannten Findings gemeldet. Ursache, nachgewiesen per grep: `base-uri`,
`AAAA`, `X-Forwarded` kommen in `audit/agents/2-security.md` kein einziges Mal vor, in `audit/guidelines/security.md` nur
`base-uri` einmal. Was der Prompt nicht benennt, findet der Spezialist nicht. Für jede der 13 Dimensionen deshalb: die
Look-for-Liste muss die Defektklassen benennen, die in den Audit-Logs dieses und des Vorgängerprojekts tatsächlich als
Critical oder Important aufgetreten sind. Für `security` mindestens: CSP-Direktiven (`base-uri`, `object-src`, `form-action`,
`unsafe-inline` neben Nonce), Vertrauen in Weiterleitungs-Header (`X-Forwarded-For` linker statt rechter Eintrag,
`X-Forwarded-Proto` ohne Proxy-Gate), DNS und SSRF (`gethostbyname` löst nur A auf, AAAA ungeprüft, Rebinding), sowie
Attribut-Injektion durch String-Verkettung in PHP ausserhalb von Templates (Shortcode-Attribut in ein `class="..."`).
Quelle für die Klassen: `.claude/audits/2026-09-05-full-audit.md` Abschnitt `## Critical` plus die Cross-Ref-Zeile.
→ verify: `grep -c -i "base-uri\|AAAA\|X-Forwarded" audit/agents/2-security.md` >= 3; für jede Dimensionsdatei gilt, dass
jede in den Logs belegte Klasse dieser Dimension mit einem Stichwort vorkommt (Prüfliste im Commit-Body).

3. **Scout-Prompts schreiben**: `audit/agents/scout-files.md` (Datei-Scout, Parameter: Dimension, Suchmuster aus der Dimensionsdatei, Scope-Dateiliste als Filter) und `audit/agents/scout-clusters.md` (Cluster-Scout für architecture und docs_sync, Vorlage: der Architektur-Scout-Prompt vom 2026-09-05 mit Modul-Karte, Mustern mit Vorkommen, Layering-Notizen). Beide mit dem ausdrücklichen Verbot, Dateien als "near-duplicate" wegzulassen. Bei `SCOPE=diff` bekommt der Datei-Scout zusätzlich die Erlaubnis, je Diff-Datei bis zu 5 direkt importierte oder aufrufende Dateien mit `context: true` aufzunehmen (Schema aus Schritt 1). Der Datei-Scout bekommt zwei Listen: `SCOPE_FILES` (alles im Scope) und `FLOOR_FILES` (die Dateien, die der deterministische Boden aus `check-skips.sh`, per `FRONTEND_EXT_RE` und den Dimensionssignalen aus `lib-git-base.sh`, dieser Dimension ohnehin zuordnet); er darf hinzufügen, aber keine Floor-Datei weglassen, und `find.js` prüft das in Code nach (fehlende Floor-Dateien werden ergänzt und per `log()` gemeldet). Damit bleibt der Routing-Boden aus CLAUDE.md erhalten, nur auf Dateiebene statt auf Dimensionsebene. Guideline-Scoping bleibt ebenfalls: `match-guidelines.sh` läuft in Phase 1 wie heute, und jeder Spezialist bekommt nur die Guidelines, deren `applies_to` eine Datei seines Chunks trifft (Berechnung in `find.js`, Eingabe über `args.guidelines`). → verify: `grep -n "FLOOR_FILES" audit/agents/scout-files.md audit/workflows/find.js` trifft in beiden; beide Dateien enthalten den Satz "Do not thin the list" (oder gleichwertig), `grep -n "SCOPE_FILES" audit/agents/scout-files.md` trifft (der Scout bekommt die Scope-Liste und darf nur daraus wählen).

4. **Workflow `audit/workflows/find.js` schreiben.** Reines JavaScript, `meta` als Literal mit den Phasen Scout, Audit, Verify. Eingabe über `args`: `{repoRoot, scope: "diff"|"repo", files: [...], dimensions: [...], effort, promptDir}`. Pro Dimension eine `pipeline()`: Stage 1 `agent(scoutPrompt, {agentType: 'Explore', model: 'sonnet', schema: SCOUT_SCHEMA, phase: 'Scout'})`, für security zwei Scouts (Datei und Cluster), deren Ergebnisse in Stage 2 zusammenlaufen; Stage 2 Chunking in Code (Cluster übernehmen, Rest nach Verzeichnis in Gruppen von 5 bis 8, `log()` mit Dateizahl und Chunkzahl, `log()` bei 0 Dateien: Dimension übersprungen); Stage 3 `parallel()` der Spezialisten (`agentType` laut Tabelle unten, `model: 'sonnet'`, `schema: FINDINGS_SCHEMA`); Stage 4 Verifier, ein Agent je 35 bis 40 Findings (`agentType: 'code-reviewer'`, `schema: VERDICTS_SCHEMA`); Stage 5 Refuter nur für Verdicts mit Severity Critical (ein Agent je Critical, `model: 'opus'`, Prompt "try to refute", ein Widerspruch senkt auf Important und markiert `disputed`). Das ist zugleich die Neubewertung der CLAUDE.md-Invariante "Opus für Security": die Messung vom 2026-09-05 zeigt Sonnet bei 8 Dateien gleichauf mit Opus bei 14 (XSS, X-Forwarded-For, HSTS, Enumeration, Passwort-Mail alle gefunden, Opus fand zusätzlich einen Minor); Opus bleibt dort, wo Exploit-Reasoning am meisten zählt, beim Refuter der Criticals. Jeder `null`-Rückgabewert eines Agents (übersprungen, gestorben) wird per `log()` mit Dimension und Chunk gemeldet und als `uncovered` im Ergebnis geführt, nie stumm gefiltert; eine Dimension, deren Pipeline wirft, erscheint als `status: 'incomplete'` mit dem letzten erreichten Stage, die anderen zwölf laufen weiter. `log()` nach jedem Stage jeder Dimension ("security: scout 67 files, 11 chunks", "security: 3/11 specialists done"). Rückgabe `{dimensions: {[dim]: {status, files, chunks, findings, verdicts, uncovered}}, skipped: [...]}`. Concurrency: das Workflow-Tool fährt maximal 16 Agents gleichzeitig; bei 13 Dimensionen mit zusammen rund 125 Spezialisten heißt das Queueing. Dimensionen werden absteigend nach Dateizahl gestartet, damit die großen nicht am Ende allein laufen. Rechnung für das Ziel: 14 Scouts + 125 Spezialisten + 32 Verifier + rund 10 Regressionspässe ≈ 180 Agents à 1,5 Minuten bei 16 parallel ≈ 17 Minuten plus Stage-Latenz, also 25 bis 35 Minuten; das 60-Minuten-Ziel hält mit Reserve. Kein `Date.now()`, kein `Math.random()`. → verify: Syntaxcheck über den Async-Function-Wrapper (das Workflow-Tool führt das Skript als Body einer async-Funktion aus, `node --check` lehnt Top-Level-`return` neben `export` ab, Erkenntnis aus Review-Runde 1 am 2026-09-05): `node -e "const fs=require('fs');for(const f of process.argv.slice(1)){const src=fs.readFileSync(f,'utf8').replace(/^export const meta/m,'const meta');new (Object.getPrototypeOf(async function(){}).constructor)(src);console.log(f,'ok')}" audit/workflows/find.js audit/workflows/fix.js` druckt zweimal `ok`; Trockenlauf mit `args.dimensions=["security"]` auf dem Worktree `scratchpad/wst-base` liefert ein Objekt mit `dimensions.security.verdicts.length > 0` und der Run erscheint unter `/workflows`.

   agentType je Dimension: security, privacy → `security-auditor`; performance → `performance-auditor`; a11y, ui_design, ux, typography, animation → `ui-ux-reviewer`; architecture, code_quality, seo, docs_sync, copy → `code-reviewer`.

5. **Workflow `audit/workflows/fix.js` schreiben.** Eingabe `args: {repoRoot, fixes: [{file, findings: [...]}], testCommand, baselineFailures: [...], budget: 25}`. `pipeline(fixes, fixer, ...)` mit `agentType: 'audit-fix-agent'`, `schema: FIX_SCHEMA`; danach Fix-Verifier als `parallel()` über Gruppen von 3 bis 5 Fixes (`agentType: 'audit-fix-verifier'`); zuletzt der Regressionsdurchgang: `parallel()` über Gruppen von 5 bis 8 geänderten Dateien, ein `code-reviewer` je Gruppe mit dem `git diff` dieser Dateien und der Frage nach Regressionen in allen 13 Dimensionen, Output im Findings-Schema; Regressions-Findings mit Severity Critical oder Important gehen als offene Punkte ins Log und blockieren den Marker, sie werden im selben Lauf nicht mehr gefixt (keine zweite Runde). Fixer-Brief enthält: alle Findings der Datei mit Zeilen, Testkommando (`bash {AUDIT_BIN}/test-lock.sh {cmd}`), Baseline-Failures, "keine andere Datei anfassen, nicht committen", Budget. → verify: derselbe Async-Function-Wrapper-Check wie in Schritt 4 druckt `ok`; Trockenlauf mit den zwei verifizierten Security-Fixes vom Test (IconShortcode, RateLimiter) auf einem frischen Worktree von 0367d622 endet mit `verdict: VERIFIED` für beide.

6. **`audit/SKILL.md` neu schreiben** (Ziel unter 250 Zeilen): Phase 0 Pre-Checks (bestehende Bash-Blöcke übernehmen: `pre-checks.sh`, `detect-framework.sh`, `run-log.sh --start`), Phase 1 Scope (`collect-scope.sh`) und die Startfragen Dimensionen plus Fixumfang in einer `AskUserQuestion`-Runde (Vorauswahl aus `CLAUDE_EFFORT`; Frage (a) übernimmt die Presets aus `full-audit/references/dimension-selection.md`, die Datei wandert nach `audit/references/`), Phase 2 In-Progress-Marker claimen, `Workflow` starten mit `scriptPath` auf `find.js` und `args`; sofort nach dem Tool-Ergebnis den Log-Stub `.claude/audits/{datum}_{zeit}-{branch}.md` mit `runId`, Scope und Dimensionen schreiben (vor dem Warten, damit ein Session-Limit mitten im Workflow resumierbar bleibt); auf die Task-Notification warten, Marker erneut touchen, JSON lesen, Entscheidung pro Finding nach der Regel "fix / log / discard, Minor nie fixen". Phase 3 Baseline der Suite einmal über `test-lock.sh` messen, dann `fix.js` starten (zweite `runId` in den Stub), Marker erneut touchen, danach Suite genau einmal über `test-lock.sh`; die Fix-Verifier laufen nur die gefilterten Tests ihrer Dateien, nie die Suite. Phase 4 Log fertigstellen (`references/audit-log-template.md` gekürzt: Ergebnis, Findings pro Dimension, Fixes, Verworfen mit Grund, Uncovered, offene Punkte; die mechanischen Nachprüfungen aus dem bisherigen `post-loop.md` 3d.5 und die Chat-Anzeige 3e werden hier als Bullets aufgenommen), Marker nur wenn keine Critical offen und keine neuen Failures gegenüber der Baseline, In-Progress-Marker freigeben, `run-log.sh` mit `--counts`, Phase 5 Learning (unverändert `references/learning-phase.md`). Letzte Zeile jedes Laufs in Chat ist die feste Abschlusszeile `Audit: {C} Critical, {I} Important offen | Push {frei|blockiert|nicht zutreffend}` (nicht von einem Hook geparst; die Zeile `AUDIT_STATUS:` wird nicht mehr ausgegeben). → verify: `wc -l audit/SKILL.md` < 250; `grep -c "AUDIT_STATUS" audit/SKILL.md` = 0; `grep -n "scriptPath" audit/SKILL.md` trifft zweimal (find, fix); `grep -n "claude-audit-passed" audit/SKILL.md` trifft (Marker bleibt); `grep -c "AskUserQuestion" audit/SKILL.md` >= 1; `grep -n "command-args\|\$ARGUMENTS\|partial-audit" audit/SKILL.md` leer; `grep -c "claude-audit-in-progress" audit/SKILL.md` >= 3 (claim, touch nach find, touch nach fix); `grep -n "runId" audit/SKILL.md` trifft vor der ersten Erwähnung von "Notification"; `grep -c "^Audit: " audit/SKILL.md` = 1.

7. **`full-audit/SKILL.md` neu schreiben** (Ziel unter 120 Zeilen): dieselbe Startfrage-Runde wie `/audit` (Verweis), `collect-scope.sh --all` (oder das Äquivalent aus `references/scope-context-batching.md`, nur der Teil, der die Dateiliste baut), dann exakt die Phasen 2 bis 5 aus `audit/SKILL.md` per Verweis ("Phasen 2-5 wie audit/SKILL.md, mit SCOPE=repo, ohne Marker"). Löschen: `references/state-file.md`, `references/scope-context-batching.md` (bis auf den Scope-Block, der nach `references/scope.md` wandert), `references/fix-loop.md`, `references/pre-flight-phases.md` (Phasen 0.3 bis 0.45 sind mit `audit/references/pre-flight-checks.md` deckungsgleich, die bleibt die einzige Quelle), `bin/resume-check.sh`, `bin/status-line.sh`. Resume läuft über `Workflow({scriptPath, resumeFromRunId})`; die `runId` wird in Phase 2 in den Audit-Log-Kopf geschrieben. → verify: `wc -l full-audit/SKILL.md` < 120; `ls full-audit/references/` zeigt nur `scope.md`, `audit-log-and-issues.md` (`dimension-selection.md` liegt jetzt unter `audit/references/`); `grep -c "FULL_AUDIT_STATUS\|batch-" full-audit/SKILL.md` = 0.

8. **`audit/references/` aufräumen.** Löschen: `fix-loop.md` (Runden), `cross-reference.md`, `context-budget.md` (Compaction-Logik der Runden), `anti-patterns.md` (Inhalt in `prompt-template.md` Regeln 1-6 übernommen, Rest weg), `partial-audit.md` (Argumentform entfällt). Ebenfalls löschen: `post-loop.md` (Testplan und Issues entfallen, die verbleibenden 40 Zeilen wandern als Bullets in SKILL.md Phase 4, Schritt 6) und `testplan.md` (Nicht-Ziel). Behalten: `scope-and-pre-checks.md`, `pre-flight-checks.md`, `dimension-selection.md` (aus full-audit übernommen), `linters-and-tests.md`, `learning-phase.md`, `audit-log-template.md` (gekürzt), `writing-deterministic-checks.md`, `perf-measurement.md`, `mobile-impact.md`, `prose-gate.md`, `pr-creation.md`. → verify: `grep -rn "RUNDE\|MAX_RUNDEN\|round-state" audit/ full-audit/` leer; `grep -rln "testplan\|TESTPLAN" audit/SKILL.md full-audit/SKILL.md` leer.

9. **Stop-Hook entschärfen.** `skills-personal/hooks/audit-loop.sh` reagiert auf `AUDIT_STATUS: FIXES_APPLIED`; diese Zeile gibt es nicht mehr. Hook auf ein sofortiges `exit 0` mit Kommentar "obsolet seit 2026-09, siehe docs/plans/2026-09-05-audit-pipeline-rebuild.md" reduzieren, Eintrag in `settings.json` bleibt (Out of Scope). → verify: `bash skills-personal/hooks/audit-loop.sh <<< '{"last_assistant_message":"AUDIT_STATUS: FIXES_APPLIED | RUNDE 1/3"}'; echo $?` gibt 0.

10. **Verweise in anderen Skills prüfen.** `grep -rn "full-audit\|/audit" */SKILL.md` durchgehen: `ship` (Marker, Run-Ledger: bleibt gültig), `delegate` (nur Erwähnung), `design-audit`, `baseline-check`, `app-baseline`, `feature-audit`, `improve`, `review`, `handoff`, `write-a-skill`, `plan-it` (Erwähnungen). Nur Stellen ändern, die Runden, Batches oder `AUDIT_STATUS` beschreiben. → verify: `grep -rn "AUDIT_STATUS\|Runde\|batch" */SKILL.md | grep -v "^audit/\|^full-audit/"` zeigt keine Treffer, die sich auf den Audit-Loop beziehen (Treffer zu anderen Bedeutungen von "batch" sind erlaubt und werden im Verify-Kommentar aufgelistet).

10c. **Zwei deterministische Skripte.** `audit/bin/run-cost.sh <session-transcript-dir>` (Python-frei, bash 3.2 plus `jq`): summiert über Haupt-Transkript und `subagents/*.jsonl` Agents, Turns, Input-, Cache- und Output-Token je Modell und rechnet mit einer Preistabelle im Skript den API-Gegenwert; Ausgabe eine Zeile `COST agents=<n> turns=<n> usd=<x.xx>` und ein `--json`-Modus, den Phase 4 in `run-log.sh --counts` und in den Log-Kopf übernimmt. `audit/bin/check-ci-hardening.sh [root]`: prüft `.github/workflows/*.yml` auf `uses:` mit Tag statt 40-stelligem SHA und auf fehlenden `permissions:`-Block (Top-Level oder je Job), Ausgabe je Treffer eine Zeile `CI_HARDENING_HIT <file>:<line> <reason>` und `CI_HARDENING_RESULT=OK|HITS (N)|SKIP (reason)`; wird in Phase 0 der Pre-Checks aufgerufen, Treffer werden als Important-Findings der Dimension security ins Log übernommen, ohne Spezialist. Preistabelle im Skript (USD je Million Token: input / cache-write / cache-read / output): claude-fable-5-1 10 / 12.5 / 0.25 / 50; claude-opus-5 5 / 6.25 / 0.5 / 25; claude-sonnet-5 2 / 2.5 / 0.2 / 10; claude-haiku-4-5 1 / 1.25 / 0.1 / 5; Modell-IDs mit Datumssuffix werden auf den Präfix gemappt, unbekannte Modelle zählen mit 0 und werden als `unknown_models=<liste>` ausgegeben. Eingabe ist ein Session-Verzeichnis `<projects>/<session-id>.jsonl` plus `<projects>/<session-id>/subagents/*.jsonl`; gezählt werden nur `type: assistant`-Zeilen mit `message.usage`. → verify: `bash audit/bin/run-cost.sh /Users/rafael/.claude/projects/-Users-rafael-Local-Sites-wordpress 83e8f0d2-d4a3-41c1-8370-65b24887aa8c` liefert `usd` zwischen 700 und 780 (Referenz: rund 730 USD für den Full-Audit vom 2026-09-04/05 nach Deduplizierung je Message-ID, 1.889 Haupt-Turns, 444 Subagenten-Transkripte; die frühere Zahl 1.315 zählte jede Transkriptzeile eines Turns einzeln, ein Turn schreibt aber je Content-Block eine Zeile mit derselben Usage); `bash audit/bin/check-ci-hardening.sh <worktree 0367d622>` meldet `HITS` für `ci.yml` (kein permissions-Block) und die `@v4`-Actions; beide Skripte laufen unter `bash --posix` ohne `declare -A`.

10b. **Doku und Kontrakte nachziehen.** `CLAUDE.md` (Skill-Roster-Zeilen für /audit und /full-audit, Effort-Tabelle, Gotchas "Worker model routing", "/full-audit is a persistent goal-loop", "PreCompact hook", "Stop-hook additionalContext", Konventionen-Absatz "Contract identifiers": `RUNDE`, `MAX_RUNDEN`, `BEREITS_GEFIXT`, `{BATCH_DATEILISTE}` und `SAUBER|FIXES_APPLIED|NO_CONVERGENCE` verlieren ihren Kontraktstatus, `AKTUELLES_LOG`, `DATEISTRUKTUR`, `ZENTRALE_PATTERNS` und `"Keine Findings."` bleiben, weil Learning- und Challenge-Agents sie weiter bekommen) und `README.md` (Skill-Beschreibungen). `audit/evals/run-evals.sh --scoped` von der Argumentform auf `AUDIT_DIMENSIONS` umstellen. Der In-Progress-Marker `/tmp/claude-audit-in-progress-*` für `pre-compact.sh` wird run-scoped: claim vor `find.js`, erneuter touch nach der Notification (45-Minuten-Staleness), release nach dem Log. → verify: `bash audit/bin/check-docs-claims.sh .` ohne Treffer auf gelöschte Pfade; `grep -n "RUNDE\|FIXES_APPLIED" CLAUDE.md` nur noch im Absatz, der den Wegfall datiert; `grep -n "AUDIT_DIMENSIONS" audit/evals/run-evals.sh` trifft; `AUDIT_DIMENSIONS=security AUDIT_FIX_SCOPE= bash -c 'source audit/references/dimension-selection.md-Logik'` ist nicht testbar als Shell, deshalb stattdessen: in `audit/SKILL.md` steht die Regel "eine gesetzte Variable unterdrückt beide Fragen" wörtlich (`grep -n "suppresses both questions" audit/SKILL.md` trifft).

11. **Vergleichslauf.** DURCHGEFÜHRT 2026-09-06 (Run `wf_e6865d4f-fa6`, sauberer Worktree `wst-clean` auf `0367d622`, 203 Quelldateien, alle 13 Dimensionen). Ergebnis: 273 Agents, 2.599 Turns, 25,2 Mio. Token, 42 Minuten, 124 USD Gegenwert (Sonnet 116, Opus 8). 376 Findings, 373 verifiziert, 351 bestätigt, davon 6 Critical, 127 Important, 218 Minor. Recall gegen die Ground Truth: 6 der 7 Einträge gefunden (XSS Shortcode-Attribut als Critical, SVG-Upload-Gate als Critical, JSON-LD ohne JSON_HEX_TAG als Critical, Iframe ohne Consent als Critical der neuen Dimension `privacy`, llms.txt-Leak, e2e-Assertions in leerer Bedingung). Nicht gefunden: der ungetestete post-loop-Render. Damit ist der Recall-Gate bestanden (Schwelle 6 von 8), das Zeitziel gehalten (42 statt 60 Minuten) und das Kostenziel um 24 Prozent verfehlt (124 statt 100 USD).

**Ursache der Kostenüberschreitung, im Lauf belegt:** der Datei-Scout filtert nicht. Er lieferte für `security` 203 von 203 Dateien, für `performance` 209, für `code_quality` 199, was 30, 28 und 27 Chunks ergab. Grund war die Anweisung "Do not thin the list" aus Schritt 3, eine Überkorrektur nach einem früheren Scout, der Dateien weggelassen hatte. Behoben am 2026-09-06: eine Datei ausserhalb von `FLOOR_FILES` darf nur noch gelistet werden, wenn der Scout einen konkreten, tatsächlich gesehenen Auslöser aus der Look-for-Liste der Dimension benennt; dazu ein Cap `MAX_SCOUT_FILES = 70` in `find.js`, der Floor-Dateien nie verwirft. Erwartete Wirkung: etwa 180 statt 273 Agents. Der Effekt ist an einem Scout-Lauf gemessen, nicht an einem zweiten Vollvergleich, weil dieser 124 USD gekostet hätte.

**Zweiter Vergleichslauf, 2026-09-06** (Run `wf_3edbdaca-9ac`, gleiche 257 Dateien, nach der Scout-Verengung): 109 Agents, 27 Minuten, 73 USD, 143 Findings, 139 bestätigt, 3 Critical. Recall aber nur 5 der 8. Die beiden Läufe verfehlten unterschiedliche Criticals, zusammen hätten sie alle acht gefunden.

**Ursache, im Journal belegt:** ohne Datei-Floor wählt der Scout nicht reproduzierbar. In einer Einzelmessung nahm der Security-Scout `SeoServiceProvider.php` auf, im Lauf nicht, weshalb das JSON-LD-Critical nie von der zuständigen Dimension gelesen wurde; `tests/e2e/flexible-content.spec.ts` erreichte code_quality nie. Eine Scout-Auslassung ist unrettbar, genau dagegen war der Floor gedacht.

**Stand nach der Korrektur (Commit `fae8205`):** der Floor prüft jetzt Dateiinhalte statt Endungen (`FLOOR_CONTENT_SIGNALS`, Eingabe `args.fileContents`). Die vier zuvor verlorenen Dateien landen nachweislich im richtigen Floor. Die Signale sind aber noch zu breit kalibriert, deterministisch gemessen auf demselben Korpus: code_quality 213, typography 159, ui_design 159, copy 124, performance 119, ux 97, a11y 86; in vernünftiger Breite nur security 46, animation 48, privacy 29, seo 14, docs_sync 8.

**Einziger offener Punkt vor dem Merge.** Die breiten Signale verengen, dann den Floor deterministisch nachmessen (kostenlos, keine Modellaufrufe, Harness in `$TMPDIR/floor-test.js`), Zielband 20 bis 80 Dateien je Dimension:
- `code_quality`: `function |class |=> ` trifft praktisch jede Quelldatei. Ersetzen durch Signale für tatsächliche Defektklassen: wiederholte Blöcke, tote Exporte, verschluckte Fehler, etwa `catch\s*\([^)]*\)\s*\{\s*\}|return true;\s*\}\s*catch|@ts-ignore|eslint-disable`.
- `typography` und `ui_design` teilen sich dieselbe Liste und treffen deshalb identisch 159. Trennen: `typography` auf Textsatz-Signale (`font-|line-height|letter-spacing|&shy;|&nbsp;|['’]`), `ui_design` auf Token- und Abstandsliterale (`--\w+-|gap-|p[xy]?-\d|rounded-|shadow-`).
- `copy`: `>[A-Za-zÄÖÜäöüß][^<>]{12,}<` trifft jeden Fließtext. Auf Übersetzungs- und Label-Aufrufe beschränken (`__\(|_e\(|_x\(|placeholder=|aria-label=`).
- `performance` und `ux`: `foreach|while \(` bzw. `<form|loading` sind zu allgemein; auf Schleifen mit Query-Aufrufen im Rumpf und auf Zustandswechsel ohne Fehlerpfad einengen.
Danach ein Verifikationslauf; erwartet werden rund 130 bis 160 Agents und 80 bis 95 USD bei einem Recall von mindestens 6 der 8. Dieser Lauf steht noch aus (Nutzerentscheidung am 2026-09-06, Nutzungslimit).

**Calibration follow-up, 2026-09-06 (Codex).** Changed only `audit/workflows/find.js` in worktree `agent-ab7483ed26cb3229f`, based on `fae8205`; no commit, merge or push. The exact requested tracked-file filter reproduces 257 files at `0367d62253b65f49f73dd3c0cb50fac7f5713ee9` and all pre-calibration counts. After calibration:

| Dimension | Before | After |
|---|---:|---:|
| architecture | 0 | 0 |
| security | 46 | 46 |
| performance | 119 | 34 |
| code_quality | 213 | 56 |
| seo | 14 | 46 |
| a11y | 86 | 80 |
| typography | 159 | 48 |
| ui_design | 159 | 77 |
| ux | 97 | 29 |
| animation | 48 | 48 |
| docs_sync | 8 | 29 |
| copy | 124 | 64 |
| privacy | 29 | 29 |

All four required memberships remain present: Security includes SeoServiceProvider and MediaServiceProvider, code_quality includes `tests/e2e/flexible-content.spec.ts`, privacy includes `templates/flexible/embed.blade.php`. The temporary extraction harness `/private/tmp/audit-floor-calibrate.cjs` checks the band, memberships and 11 semantic cases; the reviewer repeated these checks successfully. Both workflow scripts pass the adapted AsyncFunction syntax check, and the diff passes whitespace validation. No model agents were used for the floor measurement.

Signals are risk surfaces, not proof of defects. Performance now requires a query inside a brace-bounded loop body; review caught and removed an expression that could cross an earlier closed loop. Typography ignores standalone programming-language quote delimiters. UI uses token declarations and spacing/shape utilities. Copy narrows `__()` to rendered or returned translations while preserving `_e()`, `_x()` and explicit labels; schema translations remain scout-eligible but are no longer guaranteed by the floor. UX checks missing error handlers at file scope, not through full control-flow analysis. SEO adds headings/title elements; docs_sync adds API references and public configuration surfaces to reach the requested lower bound.

**Comparison correction:** persisted workflow arguments for both `wf_e6865d4f-fa6` and `wf_3edbdaca-9ac` contain 214 files, not 257. Earlier prose alternates between 203 and 257. The new verification uses the actual 257-file filter, so changes in agents, cost and recall cannot be attributed exclusively to floor calibration.

**Verification dispatch:** local Claude CLI session `3845a479-9ef0-48d1-b7bb-9c882f53ad57`, exactly one Workflow call requested after all deterministic gates passed. `/private/tmp/audit-calibrated-verification.js` contains the unchanged calibrated workflow source with a literal argument bootstrap immediately after `meta`; this supplies the real 257-file content map without model transcription. Provenance and source SHA-256: `/private/tmp/audit-calibrated-verification-provenance.json`. Result pending; no second run authorized or started.

**Negative transport check:** the CLI initially lacked the handoff context and declined to launch; after reading the original user request it verified the source hash, clean corpus, 257 matching file contents and mandatory memberships. The Workflow tool then rejected the 2,322,782-byte literal-input wrapper against its 524,288-byte script limit, before a run or any audit agent started. No recall or audit-cost result exists from this attempt. The supported `workflow({scriptPath}, args)` child API can load data-only literal chunks without agents; the replacement transport is being checked offline before the single actual verification run. Current runtime documentation also requires an actual object for `args`, not a JSON-encoded string.

**Replacement transport verified, actual run blocked:** `/private/tmp/audit-calibrated-verification-small.js` is 40,505 bytes and uses ten data-only helpers under `/private/tmp/audit-verification-input/` (62,040 to 378,610 bytes each). `/private/tmp/build-audit-small-transport.cjs` reconstructs all 257 contents and proves deep equality with the original payload, source byte equality after removing the bootstrap, syntax validity and compliance with the size limit. Executor and reviewer both passed these offline checks. The CLI also checked the documented child-workflow API and confirmed the main algorithm and clean corpus.

Claude Code's auto-mode permission classifier then denied both its Bash inspection of the helper files and its Node reconstruction check, with only `Blocked by classifier` as the reason. The CLI stopped before launching the replacement Workflow. No permission mode or policy was changed. This leaves **zero actual verification runs, zero audit agents, no runId, and recall unmeasured**. The single actual verification remains outstanding, pending explicit permission for the blocked input inspection. The calibrated source remains uncommitted in the requested worktree; only this plan is updated in the main checkout.

Preparation cost measured by the existing `audit/bin/run-cost.sh`: **USD 1.1168557, 24 turns, 0 agents, no unknown models**, session `3845a479-9ef0-48d1-b7bb-9c882f53ad57`, transcript directory `/Users/rafael/.claude/projects/-Users-rafael-Developer-claude-skills--claude-worktrees-agent-ab7483ed26cb3229f`. This is orchestration/preflight cost, not audit verification cost. No second run, fixes, commit, merge or push occurred.

**User-approved continuation:** the user explicitly approved the blocked inspection and completion. The resumed CLI process uses default permission mode with explicit read, Node, Git and Workflow permissions; persistent settings remain unchanged. The actual single verification started as **`wf_66b24f0f-a18`**, task `w9188ep67`, in the same CLI session, with the smaller supported data-helper transport. Agent transcripts are under that session's `subagents/workflows/wf_66b24f0f-a18/`. Final metrics and recall pending.

**Measurement caveat discovered:** `audit/bin/run-cost.sh:67` uses a depth-1 transcript search and misses nested Workflow agent files. For this verification, account for every transcript in the specific run directory through an isolated flattened input directory, using the existing price calculation unchanged. Report audit-only usage separately from parent-session preparation overhead. Do not treat the uncorrected parent-only number as the verification cost.

**Streaming-accounting correction:** `run-cost.sh:93` also retains the first usage snapshot per message ID, which is often incomplete. At 77 agent transcripts and 749 unique API turns, 603 message IDs had increasing output usage (for example 3, 3, then 242 tokens); first snapshots summed to 19,033 output tokens, completed/highest snapshots to 475,179. Input/cache counts were identical between snapshots. The unchanged price calculation gives **USD 25.9180151**, versus the incomplete-snapshot USD 21.3565551. `/private/tmp/measure-audit-verification.cjs` normalizes snapshots into an isolated flat accounting directory, retains only message ID/model/usage, tests deduplication, rejects malformed complete JSONL lines and explicitly records skipped incomplete tails. `run-cost.sh:74` counts only parent turns, so agent turns are counted independently. No accounting script in the repo has been modified.

**Runtime interruption:** the print-mode CLI stopped background work after its default 600-second wait ceiling. Persisted `wf_66b24f0f-a18` status is `killed`, `result: null`, with 120 queued agent calls and 77 actual transcripts. No final recall is available from that partial execution. The documented process setting `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` removes the wait ceiling; continuation uses `resumeFromRunId: wf_66b24f0f-a18` with unchanged source and inputs to reuse completed steps, not start a fresh comparison run. The first continuation prompt was treated by the CLI agent as part of a background notification and did not invoke Workflow; a separate explicit continuation message follows.

**Checkpoint continuation accepted:** Workflow resumed with the same `wf_66b24f0f-a18` run ID and new task `wmj4l2cx2`, explicitly using `resumeFromRunId`. Cached completed steps were retained; interrupted in-flight work can add real cost. Final accounting includes every unique transcript/message in this run directory across the interruption. No fresh comparison run was launched.

**Correction to the cache assumption:** journal/transcript comparison proves that resume did not preserve all completed work. At 189 actual agent transcripts there were 127 distinct initial prompts and 62 repeat starts. Of these, **52 specialist prompts had already produced a result before the repeat start**, costing another **USD 10.6101501 and 292 API turns** in the measured snapshot. Ten repeats had no prior result and represent interrupted work. All 14 scout prompts ran only once. Identical specialist prompts received different journal cache keys; changing dispatch order under nested parallelism (`find.js:494,695`) is a hypothesis, not a proven runtime explanation. Evidence and per-agent timestamps/costs: `/private/tmp/audit-resume-review.json`; journal example: prior result at line 99, repeat start at line 260. The final execution metrics must include this overhead and must not be presented as a clean uninterrupted benchmark of the calibrated floor.

**Agent-count correction:** the run directory also contains `journal.jsonl`. Early transcript-count snapshots accidentally included it as one agent. Final counting and `/private/tmp/measure-audit-verification.cjs` now accept only `agent-*.jsonl`; explicit tests exclude `journal.jsonl` and `agent-*.meta.json`. Token/cost sums were unaffected because journal entries are not assistant messages.

**Concrete follow-up opportunities (reported, not implemented):**
- `audit/bin/run-cost.sh:67,74,93`: recursively collect workflow transcripts, count agent turns, and select completed streaming usage before deduplication. All three failures are reproduced in this verification's accounting.
- `audit/SKILL.md:101`: document and validate a deterministic content-data transport rather than having the session model reproduce the full corpus as tool arguments. Headless callers must also account for the default background wait ceiling.
- `audit/workflows/find.js:663`: validate content-map completeness. One present key currently enables the content floor while absent scope files silently become empty strings; the warning only covers a wholly empty map. This run's payload was complete and separately verified, so this does not invalidate its floor measurement.

**Final outcome, 2026-09-06: calibration passed, verification NOT passed.** The resumed run exhausted the Claude weekly allowance during verification: `You've hit your weekly limit`, reset reported as **2026-09-10 12:00 Europe/Berlin**. All 13 verifier groups failed and three security specialist chunks failed. The runtime persisted a nominal `completed` journal, but there are **zero verdicts**. Treat the audit as **incomplete**, regardless of the stored status; no verified-recall or completed-run efficiency claim can be made. No further model calls, fresh comparison run or fixes were launched after the limit failure.

Final journal: `/Users/rafael/.claude/projects/-Users-rafael-Developer-claude-skills--claude-worktrees-agent-ab7483ed26cb3229f/3845a479-9ef0-48d1-b7bb-9c882f53ad57/workflows/wf_66b24f0f-a18.json`. Result covers all 13 dimensions with **134 unverified findings: 6 Critical, 50 Important, 78 Minor**. Security has 3 uncovered chunks; all other specialist groups returned, but no semantic verification completed and no Critical refutation completed.

| Reference case | Candidate evidence | Candidate severity | Verified? |
|---|---|---|---|
| Icon shortcode class XSS | `security-4-1`, IconShortcodeServiceProvider:58,62 | Critical | No |
| SVG client-MIME upload gate | `security-3-1`, MediaServiceProvider:44-81 | Critical | No |
| Article JSON-LD without JSON_HEX_TAG | `security-4-3`, SeoServiceProvider:330 | Critical | No |
| Breadcrumb JSON-LD without JSON_HEX_TAG | Same finding explicitly includes SeoServiceProvider:410 | Critical | No |
| Iframe without consent | `privacy-1-1`, flexible/embed.blade.php:38-52 | Critical | No |
| llms.txt protected-page disclosure | `seo-0-1`, LlmsTxtProvider:199-232 | Important | No |
| Untested post-loop render | No matching candidate | Not found | No |
| Conditional e2e assertions | `code_quality-6-2`, flexible-content.spec.ts:9-234 | Minor | No |

This is **7/8 candidate coverage only**, not the required confirmed recall of at least 6/8. Counting the two JSON-LD sinks separately follows the specified ground truth; both line 330 and line 410 are explicitly listed in the candidate. `Options.php` and audit-introduced defects remain excluded.

**Final measured execution:** 189 actual agent starts, 127 distinct prompts, including 52 repetitions of completed specialist work and 10 interrupted repeats. There are 1,292 real model-response IDs plus 16 synthetic limit-error records; synthetic records carry zero input/cache/output usage. Audit-only cost is **USD 49.688109**; normalized parent orchestration/preflight adds **USD 1.3975228**, yielding **USD 51.0856318 total** under the plan's fixed Sonnet price table. This total includes failed/interrupted work and supersedes earlier partial or first-snapshot numbers. No unknown paid model usage exists: the only unknown model label is the zero-token `<synthetic>` error placeholder. Final accounting: `/private/tmp/audit-verification-accounting-final.json`, detailed normalized report `/private/tmp/audit-normalized-accounting-QhPUTB/report.json`, combined normalized inputs `/private/tmp/audit-verification-accounting-total/`.

The first actual launch was 09:46:43.656 UTC; final persistence was 10:14:12.419 UTC, **27m 29s wall time including the interruption/continuation gap**. The resumed segment alone reports 647.770 seconds; do not mistake that for the full attempt. Agent and duration targets cannot be scored as a successful benchmark because the verifier stage failed. The completed verification remains outstanding after the allowance reset; this result is deliberately not marked done or merge-ready.

**Important pipeline-status defect exposed by the failure:** `audit/workflows/find.js:534-537` logs and filters out null verifier groups, but `:565` derives completion only from specialist coverage. Hence 12 dimensions incorrectly say `complete` despite zero verdicts. The early return at `:522` also says complete when all specialists fail and yield no findings. Before relying on completion status, track uncovered finding IDs and failed verifier groups, and test both total-verifier failure and total-specialist failure. Reported to the user; source remains unchanged beyond the authorized floor calibration. Resume cache stability is another follow-up: 52 completed prompts received new cache keys after continuation, as independently documented above.

11-alt. (ursprüngliche Fassung) `/full-audit` bei Effort high auf dem sauberen Worktree `scratchpad/wst-clean` (`0367d622`, keine Fremdänderungen), alle 13 Dimensionen. Ergebnis gegen das Log vom 2026-09-05 abgleichen (Criticals-Liste im Abschnitt "## Critical"). **Ground Truth, am 2026-09-06 gegen den Basis-Commit geprüft** (sauberer Worktree `scratchpad/wst-clean` auf `0367d622`, ohne die zwei Fixes der Testreihe): von den neun nicht-AUDIT-INTRODUCED Criticals des Logs sind acht am Basis-Commit tatsächlich vorhanden und damit auffindbar: XSS über das Shortcode-Attribut (kein `esc_attr` in IconShortcodeServiceProvider), SVG-Upload-Gate auf `$file['type']` (MediaServiceProvider:57), zweimal JSON-LD ohne `JSON_HEX_TAG` (SeoServiceProvider), Iframe ohne Consent (embed.blade.php), llms.txt ohne Schutz geschützter Seiten (LlmsTxtProvider), post-loop ohne Render-Test, e2e-Assertions in einer leeren Bedingung. Nicht wertbar ist der neunte (`Options.php`, die Datei existiert am Basis-Commit noch nicht). → verify: mindestens 6 dieser 8 Criticals im neuen Log; Run-Ledger-Zeile mit `duration_s < 3600`; API-Gegenwert aus `run-cost.sh` (Schritt 10c) unter 150 USD inklusive Fixphase und Regressionsdurchgang.

**Hinweise für den Executor (Schritte 1 bis 10c sind Executor-Arbeit; 11 und 12 laufen in einer Claude-Session mit Skill- und Workflow-Zugriff und gehören dem Reviewer bzw. dem Nutzer):** Die Verify-Kriterien "Trockenlauf" in Schritt 4 und 5 brauchen das Workflow-Tool, das ein Subagent nicht hat; der Executor liefert dort `node --check` und markiert den Trockenlauf als "deferred to review", der Reviewer führt ihn aus. Schritt 9 betrifft `skills-personal/hooks/audit-loop.sh` im Nachbar-Repo `/Users/rafael/Developer/claude/skills-personal`; die Datei wird dort direkt bearbeitet (absoluter Pfad), nicht committet, und im Report unter FILES CHANGED mit vollem Pfad genannt. `node` ist auf dem Rechner vorhanden (`node --check`), `jq` ebenfalls; die Bin-Skripte bleiben bash 3.2 (`/bin/bash --version` ist 3.2 auf macOS), kein `declare -A`, kein `readarray`, kein `${var,,}`.

12. **Learning-Log-Eintrag und Sync.** Ergebnis des Vergleichslaufs als Retro in `audit/references/learning-phase.md`-Format ins Projekt-Learning-Log des Theme-Repos; Skill-Repo committen ("feat(audit): per-dimension pipeline replaces batch rounds"), Stop-Hook `sync-skills.sh` synchronisiert nach `~/.claude/skills`. → verify: `diff -r audit ~/.claude/skills/audit` leer nach dem Sync; `git log -1 --format=%s` enthält "per-dimension".

### Aufwand

L (3 bis 5 Tage Arbeit; Kalenderzeit bis zum validierten Ergebnis inklusive Vergleichsläufen und den zwei Folge-Audits eher 1,5 bis 2 Wochen). Größter Posten: Schritt 6, das Neuschreiben von `audit/SKILL.md` mit dem Übergang von 1.900 Zeilen Runden-Logik auf eine lineare Phasenfolge, ohne die Pre-Checks, den Marker und die Learning-Phase zu beschädigen.

### Betroffene Dateien

- `audit/SKILL.md`: Neuschrieb, Phasen 0 bis 5 linear, Workflow-Aufrufe.
- `audit/workflows/find.js`, `audit/workflows/fix.js`: neu.
- `audit/references/finding-schema.md`: neu.
- `audit/agents/scout-files.md`, `audit/agents/scout-clusters.md`: neu.
- `audit/agents/1-architecture.md` bis `12-copy.md`: um Severity- und Output-Block ergänzt.
- `audit/agents/prompt-template.md`: auf Regeln 1-6 plus Kopfzeile reduziert.
- `audit/agents/finding-verifier.md`, `fix-agent.md`, `fix-verifier.md`: Output auf das Schema umgestellt, Fixer-Budget und Baseline-Failures aufgenommen, Rundenbezüge entfernt.
- `audit/agents/w1-code.md`, `w3-frontend.md`, `w4-content.md`, `0-triage.md`: gelöscht.
- `agents/audit-content-worker.md`, `agents/audit-triage.md`: gelöscht.
- `audit/references/fix-loop.md`, `cross-reference.md`, `context-budget.md`, `anti-patterns.md`, `partial-audit.md`: gelöscht.
- `audit/references/dimension-selection.md`: aus `full-audit/references/` verschoben, um die Fixumfang-Frage ergänzt.
- `audit/references/audit-log-template.md`: gekürzt; `post-loop.md`, `testplan.md`: gelöscht (Rest von post-loop in SKILL.md Phase 4).
- `full-audit/references/pre-flight-phases.md`: gelöscht (Duplikat von `audit/references/pre-flight-checks.md`).
- `full-audit/SKILL.md`: Neuschrieb.
- `full-audit/references/state-file.md`, `scope-context-batching.md`, `fix-loop.md`, `dimension-selection.md` (verschoben), `bin/resume-check.sh`, `bin/status-line.sh`: gelöscht; `references/scope.md`: neu (Scope-Block).
- `skills-personal/hooks/audit-loop.sh`: auf exit 0 reduziert.
- `audit/bin/verify-agents.sh`: Rosterliste.
- `audit/bin/run-cost.sh`, `audit/bin/check-ci-hardening.sh`: neu.
- `audit/agents/13-privacy.md`: neu.
- `audit/evals/run-evals.sh`: `--scoped` über `AUDIT_DIMENSIONS` statt Argument.
- `CLAUDE.md`, `README.md`: Roster, Effort-Tabelle, Gotchas, Kontrakt-Absatz.
- `docs/plans/2026-09-05-audit-pipeline-rebuild.md`: dieser Plan.

### Konventionen

- Skill-Bodies, Agents, Referenzen auf Englisch (CLAUDE.md-Regel); deutsche Strings nur in Trigger-Phrasen und Nutzer-Ausgaben. Exemplar: `ship/SKILL.md`.
- Bash-Blöcke in SKILL.md sind jeweils eine frische Shell: Pfade werden in jedem Block neu aufgelöst, wie in `ship/SKILL.md:169-171` (`RUN_LOG`-Suche). Genau so für `AUDIT_BIN` und `scriptPath`.
- Run-Ledger: `run-log.sh --start` vor der ersten Arbeit, `run-log.sh --skill audit --outcome ... --counts ...` am Ende, wie in `plan-it/SKILL.md` Phase 0.5 und 4.
- Agent-Typen aus `agents/*.md` werden per `agentType` im Workflow referenziert, nicht dupliziert. Neue Typen nur, wenn ein Prompt nicht in einen bestehenden Typ passt.
- Workflow-Skripte: `export const meta` als reines Literal, kein TypeScript, kein `Date.now()`, `parallel()`-Ergebnisse mit `.filter(Boolean)`, `log()` bei jeder Auslassung (0-Datei-Dimension, gekappte Chunks). Referenz: `workflow-authoring`-Skill.

<!-- Challenge 2026-09-05: 14 Concerns, 12 nach Dedupe, alle eingearbeitet; Evaluation: 3 Vorschläge eingearbeitet (Routing-Boden und Guideline-Scoping in den Scout, Opus-Neubewertung als Critical-Refuter, verwaiste Referenzdateien); konvergent: Workflow-Kontrakt/Resume (Architektur + Risiko), Teilausfall pro Dimension (Architektur + Design). -->

## Edge Cases

- **Scout liefert 0 Dateien** (Animation im Backend-Repo): Dimension wird übersprungen, `log()` und Eintrag "übersprungen: keine relevanten Dateien" im Audit-Log. Kein Spezialist, kein Verifier.
- **Scout liefert über 60 Dateien**: Chunking in Gruppen von 5 bis 8 ohne Obergrenze; bei über 15 Chunks `log()` mit der Zahl. Kein stilles Kappen.
- **Dieselbe Datei in mehreren Dimensionen** (Security und A11y hatten 8 gemeinsam): gewollt in der Findephase; in der Fixphase werden die Findings pro Datei zusammengeführt, ein Fixer bekommt alle.
- **Zwei Findings widersprechen sich** (Security will Attribut entfernen, A11y will es behalten): der Fixer-Brief listet beide, der Orchestrator entscheidet vorher und markiert das unterlegene Finding als "discard: Konflikt mit {id}".
- **Findings ohne Verdicts** (Verifier gestorben, etwa am Session-Limit): die Dimension gilt als `incomplete`, nicht als sauber. Nichts wird gefixt (die Regel "nur CONFIRMED" greift), der Marker wird nicht gesetzt, das Log nennt die Zahl unverifizierter Findings.
- **Verifier verwirft ein Critical**: verworfen, mit Begründung im Log. Bestätigt der Verifier ein Critical, läuft zusätzlich genau ein Refuter (Stage 5); widerspricht er, wird das Finding als Important mit `disputed` gefixt bzw. geloggt, nie stumm gesenkt. Kein Voting mit drei Stimmen: Criticals sind selten (17 von 1.036 gestern), ein Refuter kostet pro Lauf unter 5 USD.
- **Laufende Kostenkontrolle**: `find.js` und `fix.js` loggen nach jedem Stage die Zahl gestarteter Agents ("agents: 84/160"); der Fortschritt ist unter `/workflows` sichtbar. Ein hartes Kostenlimit gibt es nur über das `budget`-Objekt des Workflow-Tools, das der Nutzer per "+500k"-Direktive setzt; der Skill erzwingt keins.
- **Eine Dimension bleibt hängen oder wirft**: die anderen elf laufen zu Ende, die Dimension erscheint im JSON als `incomplete` mit dem letzten Stage und im Log als eigener Abschnitt "Nicht abgeschlossen"; der Marker wird nicht gesetzt. Kein indefinites Warten: das Workflow-Tool liefert die Notification, sobald das Skript zurückkehrt, und ein einzelner toter Agent liefert `null` statt zu blockieren.
- **Fixer meldet PARTIAL oder FAILED**: Finding bleibt als offener Punkt im Log, kein zweiter Versuch im selben Lauf.
- **Fix-Verifier meldet REJECT**: Diff dieser Datei per `git checkout -- {file}` verwerfen (nur, wenn die Datei vor dem Lauf unverändert war; sonst `git diff` der Datei ins Log und offener Punkt), Finding bleibt offen.
- **Test-Suite hat Baseline-Failures** (gestern sieben): vor der Fixphase einmal messen, Liste an alle Fix-Verifier; nur neue Failures zählen. Marker wird trotzdem nur bei "keine neuen Failures" gesetzt.
- **Session-Limit während des Workflows**: `runId` steht im Audit-Log-Kopf; Wiederaufnahme mit `Workflow({scriptPath, resumeFromRunId})`, abgeschlossene Agents kommen aus dem Cache.
- **Paralleles Arbeiten im selben Tree** (gestern 6 Fremd-Commits): Phase 1 pinnt `HEAD`; vor der Fixphase `git rev-parse HEAD` erneut prüfen, bei Abweichung STOP mit Hinweis. Kein Re-Scope, kein Re-Pin.
- **Workflow-Tool nicht verfügbar** (Headless, andere Umgebung): STOP mit Meldung "audit needs the Workflow tool"; kein Agent-Tool-Fallback (Entscheidung 2026-09-05, keine doppelte Dispatch-Logik).
- **Teilauswahl in der Startfrage** (nur Security): nur die gewählten Dimensionen im `args.dimensions`; Teil-Audits setzen wie heute keinen Marker, das Log nennt die nicht geprüften Dimensionen.
- **Nutzer drückt bei den Startfragen nur Enter**: Vorauswahl gilt (alle Dimensionen, Fixumfang aus `CLAUDE_EFFORT`). Die Fragen dürfen den Lauf nicht verlängern; keine weitere Rückfrage bis zum Log.

## Done Criteria

Alle müssen gelten:
- [ ] Async-Function-Wrapper-Syntaxcheck (Schritt 4) → `ok` für beide Skripte; `Workflow({scriptPath: find.js})` wird vom Tool angenommen (kein "Invalid workflow script")
- [ ] `wc -l audit/SKILL.md full-audit/SKILL.md` → unter 250 bzw. 120
- [ ] `grep -rn "AUDIT_STATUS\|FULL_AUDIT_STATUS\|RUNDE\|MAX_RUNDEN\|round-state\|batch-[0-9]" audit/ full-audit/` → keine Treffer
- [ ] `ls audit/agents/` → exakt die Liste aus Schritt 2
- [ ] `test ! -e full-audit/bin/status-line.sh -a ! -e full-audit/references/state-file.md` → exit 0
- [ ] Vergleichslauf (Schritt 11): neues Log enthält mindestens 6 der 7 Criticals aus `.claude/audits/2026-09-05-full-audit.md` des Theme-Repos; Run-Ledger `duration_s < 3600`
- [ ] `bash skills-personal/hooks/audit-loop.sh <<< '{"last_assistant_message":"AUDIT_STATUS: FIXES_APPLIED | RUNDE 1/3"}'` → exit 0
- [ ] `git status --short` zeigt nur Dateien aus "Betroffene Dateien"

## STOP-Bedingungen

Anhalten und berichten, wenn:
- Der Stand an den genannten Stellen nicht den Beschreibungen entspricht (Repo ist gedriftet, siehe Drift check).
- Ein Verify-Kriterium nach einem ernsthaften Korrekturversuch zum zweiten Mal fehlschlägt.
- Ein Fix eine Out-of-Scope-Datei anfassen müsste (`audit/bin/*`, `settings.json`, generische `agents/*.md`).
- Das Workflow-Tool `agentType` oder `schema` nicht so unterstützt, wie in `workflow-authoring` beschrieben (Kernannahme von Schritt 4 und 5).
- Der Trockenlauf in Schritt 4 endet mit `status: incomplete` oder liefert für eine Dimension Findings ohne Verdicts (Verifier tot) und das bleibt bei einem zweiten Lauf so. (Die frühere Fassung dieser Bedingung verlangte 3 der 4 Findings aus dem 4-Datei-Test; sie wurde am 2026-09-06 gestrichen, weil dieser Test mit gestützten Prompts entstand und die Pipeline-Prompts diese Klassen nicht nennen. Der gültige Recall-Gate ist Schritt 11.)

## Validierung der Wette

**Zirkularität, festgehalten am 2026-09-06:** Schritt 2b speist die Defektklassen aus genau den drei Audit-Logs, gegen die Schritt 11 und der zweite Vergleichslauf messen (`wordpress-starter-theme`, `topf-secret`, `sprachverliebt`). Das ist als Engineering richtig, eine Prüfliste soll bekannte Klassen benennen, aber es macht beide Läufe zu einer Prüfung der Umsetzung, nicht des ungestützten Recalls. Für die unabhängige Zahl dient `casa` (`/Users/rafael/Developer/apps/casa/.claude/audits/2026-06-11-full-audit.md`, 15 nummerierte Findings, floss nicht in die Kalibrierung ein): dort zählt, wie viele der dortigen Critical- und Important-Findings die Pipeline ohne vorherige Kenntnis findet. Erst diese Zahl entscheidet über die Wette.

- **Trägt, wenn:** der Vergleichslauf (Schritt 11) bis 2026-09-19 die Done-Kriterien erfüllt, der unabhängige `casa`-Lauf mindestens die Hälfte der dortigen Criticals findet, ein zweiter Vergleichslauf auf einem strukturell anderen Repo mit eigenem Full-Audit-Log als Ground Truth (`topf-secret` bei Basis 9e497ce, Log vom 2026-08-27: 28 Criticals in der Ledger-Zeile, Log unter `.claude/audits/2026-08-27-full-audit.md`) mindestens 80 % der dort verifizierten Criticals findet, und die zwei darauffolgenden echten `/audit`-Läufe (Pre-Push, beliebiges Repo) im Run-Ledger unter 15 Minuten und ohne offene Critical enden.
- **Rollback, wenn:** der Vergleichslauf unter 5 der 7 Criticals findet oder über 300 USD Gegenwert kostet. Dann `git revert` des Umbau-Commits im Skill-Repo; die alten Skills sind im Git-Verlauf vollständig.

## Wartungshinweise

- Die Messwerte-Tabelle ist die Spezifikation. Wer Chunk-Größe, Modelle oder Verifier-Quote ändert, misst vorher auf demselben Worktree (`0367d622`) gegen dieselbe Criticals-Liste.
- Neue Dimension: eine Datei `audit/agents/{n}-{name}.md` mit den drei Blöcken, ein Eintrag in der agentType-Tabelle in `find.js`, ein Eintrag in `dimension-selection.md`. Nichts sonst. `13-privacy.md` ist das erste Beispiel dafür.
- Jeder Lauf schreibt seine Kosten (`run-cost.sh`) in Log-Kopf und Run-Ledger; das Kostenziel dieses Plans wird damit pro Lauf geprüft, nicht nur im Vergleichslauf.
- Die registrierten Subagent-Definitionen unter `agents/*.md` (YAML-Frontmatter, `name` = `agentType`) bleiben die Dispatch-Ziele; die Worker-Specs unter `audit/agents/*.md` (Überschrift `# Subagent N`, Bullet-Liste) sind das, was die Definitionen referenzieren. Beide Formen nicht vermischen (CLAUDE.md-Konvention).
- Die Prose-Gate (`classify-diff.sh`) bleibt als Pre-Check: `DIFF_CLASS=prose` beschränkt die Vorauswahl der Dimensionsfrage auf docs_sync und copy und setzt den Fixumfang auf "nur finden".
- Der Learning-Agent liest weiterhin Audit-Logs; das Log-Format (Schritt 6) muss die Abschnitte behalten, die `learning-agent.md` grept (vor dem Kürzen prüfen: `grep -n "##" audit/agents/learning-agent.md`).
- Bewusst vertagt: Refuter-Voting mit mehreren Stimmen (ein Refuter pro Critical ist drin), Incremental Cache (Entscheidung 2026-09-05), Agent-Tool-Fallback ohne Workflow.
- Schritt 9 (`audit-loop.sh`) ist nach Schritt 6 fast ein No-op, weil der Hook ohne `AUDIT_STATUS:`-Zeile ohnehin `exit 0` liefert; er bleibt im Plan, damit niemand den Hook später als lebendigen Kontrakt liest.
- Reviewer prüft im PR: kein Bash-Block in SKILL.md verlässt sich auf Variablen aus einem früheren Block; `find.js` gibt bei 0 Dateien `skipped` zurück statt zu werfen; der Marker wird nur im `/audit`-Pfad gesetzt.


## Codex delivery and shared installation, 2026-09-06

User-authorized follow-up supersedes the earlier Workflow-only STOP and deferred native-runtime decision. Both runtimes now execute the same find.js and fix.js programs. Claude retains Workflow; Codex uses the bundled Node request/response bridge and native collaboration agents. No provider CLI or API key is used by the bridge.

### Delivered and verified

- Fail-closed scout, specialist, verifier, Critical refuter, fixer and regression stages. Missing, duplicate, unknown or uncertain verdicts cannot pass. Minor findings never reach fix agents. Fix claims require exactly the owned file.
- Native persistent requests, immutable schema-valid responses, content-derived IDs, source/prompt/input drift checks and direct full-content file loading. Explicit failures remain incomplete. Native cost remains unavailable/null.
- Current-checkout audit state, native role mapping and runtime-specific learning. Claude recurrence storage is explicitly unavailable in native mode; this limitation is logged independently of finding coverage.
- 36 automated pipeline/bridge/accounting tests passed, including all 13 dimensions offline, 600 KB input, replay order, invalid replies and partial failed edits. Two sync-hook regression tests passed. Bash syntax, agent-resource checks and diff whitespace checks passed.
- Native live smoke at `/private/tmp/audit-live-smoke-eedu81wn`: repo-scope code-quality scout found the quantity omission in billing.cjs; independent verifier confirmed Important severity; fixer corrected the module; fresh fix verifier and regression reviewer completed. Six actual native jobs, all completed. The meaningful test changed from 350 versus 950 failure to 1/1 passing. The installed Codex runner resumed the completed fix with zero new requests. This is a controlled functional smoke, not a recall benchmark.
- Floor calibration rechecked against the unchanged 257-file WordPress corpus: all bands, four required memberships and 11 semantic probes still pass.
- Corrected run-cost.sh reproduces USD 51.0856318 for the historical Claude session, 189 agent transcripts and 1,323 actual model responses. This accounting result does not turn that quota-interrupted audit into a successful benchmark. The full Claude benchmark remains incomplete because its verifier requests hit the weekly limit.

### Installed source and synchronization

The active shared source is `/Users/rafael/Developer/claude/skills/.claude/worktrees/agent-ab7483ed26cb3229f`. Keep this worktree available while installed.

- `~/.claude/skills/audit` points to the source audit directory.
- `~/.claude/skills/full-audit` points to the source full-audit directory.
- `~/.agents/skills/audit` follows `~/.claude/skills/audit`.
- `~/.agents/skills/full-audit` follows `~/.claude/skills/full-audit`.

Both runtime pairs were verified as the same physical SKILL.md files. The active Stop sync hook is the symlinked `/Users/rafael/Developer/claude/skills-personal/hooks/sync-skills.sh`; it now preserves only these two explicit link overrides and reports broken targets instead of restoring stale main-checkout copies. Tests prove that unrelated skill synchronization is preserved.

Previous four installed copies are backed up at `/Users/rafael/.codex/backups/audit-shared-20260906-130205`, with installation.json recording every link and resolved target. Repointing the two canonical Claude links later also moves Codex to the same source. No commits, merges or pushes were performed. Pre-existing unrelated skills-personal edits were preserved.

### Remaining optimization opportunities

- Full-scale Claude recall/performance verification is still separate from functional readiness and must not be reported as passed before the outstanding benchmark completes.
- The native recurrence backend and actual native usage accounting are explicit unavailable integrations, not fabricated metrics.
- Native scope entries must be existing readable files. Missing/deleted paths currently stop initialization; deletion-aware diff input remains an improvement for a later scoped change.


## Final integration and durable delivery, 2026-09-08

This delivery supersedes the earlier temporary-worktree installation and Workflow-only runtime decisions. The user explicitly authorized the three final packages: fail-closed correctness, reliable resume, and committed integration into the regular source.

- Fixed false-success cases for incomplete specialist/regression coverage, incorrectly tagged mandatory floor files, unknown dimensions and invalid architecture clusters. Coverage is now a structured status plus exact reviewed paths. All assigned paths must be covered; legacy string coverage fails closed.
- Both Claude and Codex now use the same persistent bridge. Claude dispatches through its native Agent tool, Codex through native collaboration. Both submit schema-validated responses to content-addressed jobs. Native worker IDs are bound persistently, accepted results are immutable, completed jobs are replayed without redispatch. The old Claude Workflow cache is no longer the execution path.
- The non-atomic launch/bind interval is documented: recover native task history before redispatch; unresolved outcomes become explicit failures. There is no claim of automatic exactly-once execution across an unrecoverable process failure.
- Integrated all current main-branch learning changes. Restored the worker still used by design-audit and corrected its shared prompt reference. Preserved Swift validation lessons, concrete refutation evidence, visual sibling comparisons and mandatory verification incidents without restoring an old verifier bypass.
- Verified 42 pipeline/bridge/accounting tests plus two sync-hook tests (44 total), agent-resource presence, staged whitespace checks and the unchanged WordPress floor calibration (257 files, four mandatory memberships, 11 semantic probes). Tests were rerun after integration. The broad docs-claim checker also reports existing context-relative/out-of-scope references, so it is not recorded as a clean gate.
- Source commits: 9fd2300 (coverage/shared runtime), 3965b6b (integration with main). Main was fast-forwarded to the integrated branch. Personal sync commit: b888c2f. No push was performed.
- Permanent source is now `/Users/rafael/Developer/claude/skills` (main checkout). Canonical `~/.claude/skills/{audit,full-audit}` links point there; `~/.agents/skills/{audit,full-audit}` still follow the Claude links. Both pairs were checked as identical physical SKILL.md files. The temporary worktree is no longer required by the installation and was not removed.
- Previous link targets are recorded in `/Users/rafael/.codex/backups/audit-source-move-20260908-161347/links.json`; the older full-copy backup remains intact.
- Pre-existing and concurrently arriving unrelated edits were left untouched and unstaged, including main learning-log changes and separate personal hook/sync work.

The expensive live Claude recall benchmark was not rerun. Its historical incomplete result remains a measurement limitation, not evidence against or proof of the new bridge's live recall. Native recurrence/accounting and deletion-aware scope handling remain separately documented limitations outside these three final packages.

2026-09-10: Codex-Pfad entfernt. Die Bridge (`codex-runner.cjs`, `codex-runtime.md`) und alle Runtime-Weichen sind zurückgebaut, Claude nutzt wieder ausschließlich das Workflow-Tool. Behalten wurden die Floor-Kalibrierung in `find.js`, die Robustheitsänderungen in `fix.js`, `run-cost.sh` mit Test und `w3-frontend.md` für /design-audit.
