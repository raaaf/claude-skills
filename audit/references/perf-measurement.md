# Verify-by-Measurement (Performance-Findings)

Performance-Fixes werden nicht nur per Peer-Review (fix-verifier) beurteilt, sondern gegen
eine echte Messung verifiziert: Metrik vor dem Fix, Metrik nach dem Fix, Verdikt aus dem
Delta. Adaptiert von AvdLees Xcode-Build-Optimization-Skill (benchmark -> apply -> re-benchmark),
zugeschnitten auf den `/audit`-Fix-Loop.

## Aktivierung

Opt-in. Aktiv nur wenn ein Mess-Kommando deklariert ist:
- ENV `PERF_MEASURE_CMD`, oder
- Zeile in `.claude/audit-guidelines.md`:  `perf-measure: <command>`

Das Kommando MUSS genau eine Zeile `PERF_METRIC=<zahl>` ausgeben (niedriger = besser).
Beispiele:
- Bundle-Budget:  `perf-measure: npx size-limit --json | jq -r '"PERF_METRIC=\([.[].size]|add)"'`
- Build-Zeit:     `perf-measure: { /usr/bin/time -p npm run build; } 2>&1 | awk '/^real/{print "PERF_METRIC="$2}'`
- Query-Count:    ein Test, der `DB::enableQueryLog()` nutzt und die Anzahl als `PERF_METRIC=` druckt

Ohne deklariertes Kommando: kein Verhalten geaendert — Performance-Fixes laufen wie bisher durch
den fix-verifier (Peer-Review). Im Log dann `Verifikation: review` statt `measured`.

## Ablauf (Schritt E / E.5)

1. **Baseline (Schritt E, vor dem Fix-Agent):** Enthaelt die Runde >=1 `[Performance]`-Finding
   und ist `PERF_MEASURE_CMD` gesetzt, einmal pro Runde messen:
   `PERF_BASELINE=$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")`
2. Fix-Agents laufen wie ueblich.
3. **Re-Measure (Schritt E.5, nach allen Fixes der Runde):**
   `PERF_AFTER=$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")`
4. **Verdikt (deterministisch, kein LLM):** vergleiche die `PERF_METRIC`-Zahlen.
   - `AFTER <= BASELINE` (verbessert oder gehalten) -> Performance-Fixes `keep`,
     Log: `Verifikation: measured {BASELINE}->{AFTER}`.
   - `AFTER > BASELINE` (regrediert) -> Performance-Fixes der Runde sind Revert-Kandidaten:
     als Offenen Punkt melden ("Perf-Fix verschlechtert Metrik: {BASELINE} -> {AFTER}") und
     den fix-verifier zusaetzlich laufen lassen, um den Verursacher einzugrenzen.
   - `NA` (eine Seite Messung fehlgeschlagen) -> Fallback auf fix-verifier (review), im Log vermerken.

## Grenzen (ehrlich)

- Misst pro Runde aggregiert, nicht pro Finding. Bei mehreren Perf-Fixes in einer Runde und einer
  Regression ist der genaue Verursacher nicht eindeutig — daher zusaetzlich fix-verifier.
- Das Mess-Kommando prueft NUR die Metrik, nicht Korrektheit oder Regressionen in anderen
  Dimensionen. Verify-by-Measurement ersetzt den fix-verifier nur fuer die Metrik-Frage; bei
  Regression laeuft der Review weiter.
- Kosten: ein Mess-Lauf pro Runde mit Perf-Fixes. Bei teuren Builds entsprechend Laufzeit —
  deshalb opt-in und nicht per Default an.
