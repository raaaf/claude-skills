# Site Auditor Agent

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `30`

Du audierst eine einzelne Live-Site via PageSpeed Insights API und SSL-Check. Du erstellst GitHub Issues für neue Findings und lernst aus dem `suppress`-Label.

## Input

Du bekommst:
- `SITE_URL` — z.B. `rafaelalex.de`
- `GITHUB_REPO` — z.B. `raaaf/portfolio-2025`
- `PSI_STRATEGY` — `["mobile", "desktop"]`
- `SKILL_DIR` — Pfad zum Skill-Verzeichnis
- `DESIGN_REFERENCE` — optional, z.B. `linear.app` (Feld `design_reference` in sites.json; leer = Schritt 5.5 entfällt)

## Ablauf

### Schritt 1: State + Suppressions laden

Lade `state.json` aus dem Repo:

```bash
gh api repos/{GITHUB_REPO}/contents/.claude/live-audit/state.json \
  --jq '.content' | base64 -d 2>/dev/null || echo '{"rollout_week":1,"last_run":null,"pending_findings":{}}'
```

Lade `suppressions.json`:

```bash
gh api repos/{GITHUB_REPO}/contents/.claude/live-audit/suppressions.json \
  --jq '.content' | base64 -d 2>/dev/null || echo '[]'
```

Lies `guidelines/thresholds.md` aus `$SKILL_DIR/guidelines/thresholds.md`.

Speichere: `ROLLOUT_WEEK`, `PENDING_FINDINGS` (Map: fingerprint → Anzahl gesehen), `SUPPRESSIONS` (Liste von fingerprints).

### Schritt 2: Suppress-Labels verarbeiten

Lies offene Issues mit Label `suppress` seit letztem Run:

```bash
gh issue list --repo {GITHUB_REPO} --label suppress --state open --json number,title,labels \
  --limit 50
```

Für jedes Issue mit `suppress`-Label:
- Extrahiere Fingerprint aus dem Titel (Format: `[live-audit] {site} | {fingerprint-id}`)
- Füge zur SUPPRESSIONS-Liste hinzu falls noch nicht vorhanden
- Entferne das `suppress`-Label (wird durch Suppression-Eintrag ersetzt):
  ```bash
  gh issue edit {NUMBER} --repo {GITHUB_REPO} --remove-label suppress
  ```

Wenn neue Suppressions: `suppressions.json` updaten (Schritt 8).

### Schritt 3: PSI API abrufen

**NIEMALS `WebFetch` fuer PSI benutzen.** WebFetch expandiert keine Shell-Variablen (der Key ginge als Literal `$GOOGLE_PSI_API_KEY` an die API) und liefert eine LLM-Zusammenfassung statt rohem JSON. Beides fuehrt dazu, dass keine echten Messwerte ankommen.

Fuer jede Strategy in `PSI_STRATEGY`, sequenziell mit 2s Delay, **per Bash**:

```bash
PSI_KEY="${GOOGLE_PSI_API_KEY:-$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude/settings.json')))['env'].get('GOOGLE_PSI_API_KEY',''))" 2>/dev/null)}"
# Dritter Fallback: 1Password als durable Kopie, damit ein verlorener Key in Env und
# settings.json die Pipeline nicht blind laufen laesst. Best effort: im headless Cron
# ohne entsperrtes op (oder ohne OP_SERVICE_ACCOUNT_TOKEN) faellt es still durch auf
# den no-key-Pfad unten.
[ -n "$PSI_KEY" ] || PSI_KEY=$(op read "op://development/seo-cli/GOOGLE_PSI_API_KEY" 2>/dev/null || true)
[ -n "$PSI_KEY" ] || { echo "PSI_ERROR=true reason=no-key"; exit 0; }

# curl MUSS direkt nach python3 gepipet werden. Der Umweg ueber eine Variable
# (RAW=$(curl ...); echo "$RAW" | ...) zerstoert die Backslash-Escapes im JSON
# und macht die Antwort unparsebar.
for STRATEGY in {PSI_STRATEGY als space-separierte Liste, z.B. mobile desktop}; do
  curl -s --max-time 120 \
    "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=https://{SITE_URL}&strategy=$STRATEGY&category=performance&category=accessibility&category=seo&key=$PSI_KEY" \
  | STRATEGY="$STRATEGY" python3 -c '
import json,os,sys
s=os.environ["STRATEGY"]
try: d=json.loads(sys.stdin.read())
except Exception: print("PSI_ERROR=true strategy=%s reason=unparseable"%s); sys.exit()
if "error" in d:
    msg=d["error"].get("message","")
    code=d["error"].get("code","")
    print("PSI_429=true strategy=%s"%s if code==429 or "Quota" in msg else "PSI_ERROR=true strategy=%s reason=%s"%(s,msg[:60]))
    sys.exit()
lr=d["lighthouseResult"]
def cat(c):
    v=lr["categories"].get(c,{}).get("score")
    return "NA" if v is None else round(v*100)
def num(a,div=1):
    v=lr["audits"].get(a,{}).get("numericValue")
    return "NA" if v is None else round(v/div,2)
print("PSI_OK strategy=%s finalUrl=%s perf=%s a11y=%s seo=%s lcp=%s fcp=%s cls=%s"%(
    s, lr.get("finalUrl","?"), cat("performance"), cat("accessibility"), cat("seo"),
    num("largest-contentful-paint",1000), num("first-contentful-paint",1000),
    num("cumulative-layout-shift")))
'
  sleep 2
done
```

Uebernimm **ausschliesslich** die Werte aus den `PSI_OK`-Zeilen dieser Ausgabe.

Bei `PSI_429=true`: Strategy skippen, weitermachen.
Bei `PSI_ERROR=true`: Strategy skippen, Flag setzen.

**Harte Regel, Messwerte werden nie erfunden.** Wenn fuer eine Strategy keine `PSI_OK`-Zeile vorliegt, gibt es fuer diese Strategy keine Werte: keine Schaetzung, keine Uebernahme aus einem frueheren Run, keine Uebernahme von einer anderen Site. Betroffene Metriken im Report als `n/a` melden und `PSI_429`/`PSI_ERROR` in `WARNINGS` ausgeben. Ein Finding darf ohne Messwert weder erstellt noch als behoben verbucht werden. Ein bestehender `pending_findings`-Eintrag bleibt in dem Fall unveraendert stehen.

(Am 2026-07-20 hat ein Site-Auditor die Werte einer anderen Site gemeldet und dadurch eine echte Performance-Regression faelschlich als "behoben" nach `state.json` geschrieben. Genau das verhindert diese Regel.)

### Schritt 4: SSL prüfen

**Auch hier kein `WebFetch`.** WebFetch kann kein HEAD absetzen und keine Zertifikatsdaten lesen. Der Check laeuft per Bash:

```bash
HOST="{SITE_URL}"   # ohne Schema

# 1. TLS-Validitaet: curl prueft Kette, Ablauf und Hostname-Match in einem Schritt.
CURL_ERR=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "https://$HOST" 2>&1); RC=$?
HTTP=$(printf '%s' "$CURL_ERR" | tr -dc '0-9' | tail -c 3)

# 2. Ablaufdatum separat aus dem Zertifikat lesen (fuer die 14-Tage-Warnung).
NOT_AFTER=$(echo | openssl s_client -servername "$HOST" -connect "$HOST":443 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

RC="$RC" HTTP="$HTTP" HOST="$HOST" NOT_AFTER="$NOT_AFTER" ERRTXT="$CURL_ERR" python3 -c '
import os,datetime,re
rc=int(os.environ["RC"]); host=os.environ["HOST"]; http=os.environ["HTTP"]
na=os.environ["NOT_AFTER"].strip(); err=os.environ["ERRTXT"]
days=None
if na:
    try:
        exp=datetime.datetime.strptime(na,"%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
        days=(exp-datetime.datetime.now(datetime.timezone.utc)).days
    except Exception: pass
if rc==60:
    kind="ssl-expired" if "expired" in err.lower() else "ssl-invalid"
    print("SSL_FAIL=%s host=%s reason=%s days_left=%s"%(kind,host,re.sub(r"\s+"," ",err)[:90],days))
elif rc!=0:
    print("SITE_UNREACHABLE=true host=%s curl_rc=%d reason=%s"%(host,rc,re.sub(r"\s+"," ",err)[:90]))
elif http and not http.startswith(("2","3")):
    print("SITE_UNREACHABLE=true host=%s http=%s"%(host,http))
else:
    state="ssl-expiring" if days is not None and days<14 else "ok"
    print("SSL_OK host=%s http=%s days_left=%s state=%s notAfter=%s"%(host,http,days,state,na or "unknown"))
'
```

Auswertung, ausschliesslich anhand dieser Ausgabe:

| Ausgabe | Finding | Severity | Toleranz-Band |
|---|---|---|---|
| `SSL_OK ... state=ok` | keins | | |
| `SSL_OK ... state=ssl-expiring` | `ssl-expiring` | important | ja |
| `SSL_FAIL=ssl-expired` | `ssl-expired` | critical | nein, sofort |
| `SSL_FAIL=ssl-invalid` | `ssl-invalid` | critical | nein, sofort |
| `SITE_UNREACHABLE=true` | `site-unreachable` | critical | nein, sofort |

Bei `SSL_FAIL` oder `SITE_UNREACHABLE`: PSI-Schritte fuer diese Site ueberspringen.

**Ein vorhandenes Zertifikat heisst nicht, dass es zu dieser Site gehoert.** Ein falsch konfigurierter vhost liefert das Default-Zertifikat des Hosters aus (bei `nonexistent-xyz.rafaelalex.de` z.B. `CN=*.webspaceconfig.de`). Deshalb entscheidet der curl-Exit-Code ueber die Gueltigkeit, nicht die blosse Existenz eines Zertifikats. `openssl` liefert hier nur das Ablaufdatum.

### Schritt 5: Findings gegen Thresholds prüfen

Erstelle Liste aller Findings nach Thresholds aus `guidelines/thresholds.md`.

Format pro Finding:
```
{
  "fingerprint": "{SITE_URL}|{metric-id}",
  "metric_id": "{metric-id}",
  "value": {aktueller Messwert},
  "threshold_important": {X},
  "threshold_critical": {Y},
  "severity": "critical|important|minor",
  "strategy": "mobile|desktop|ssl"
}
```

Ausnahmen ohne Toleranz-Band (sofort):
- `site-unreachable`
- `ssl-expired`

### Schritt 5.5: Design-Verdict (optional, fail-open)

Nur wenn `DESIGN_REFERENCE` gesetzt ist. Erzwungenes Ranking gegen eine benannte
echte Referenz-Site, kein Inspirations-Sammeln: das Verdict muss sich festlegen.

1. Screenshot-Tool laden: `mcp__chrome-devtools__navigate_page` + `take_screenshot`
   via ToolSearch. Nicht verfügbar (headless Cron ohne MCP): Schritt still
   überspringen, im Output `DESIGN_VERDICT: skipped reason=no-browser`.
2. Above-the-fold-Screenshot von `https://{SITE_URL}` und von
   `https://{DESIGN_REFERENCE}` aufnehmen (Desktop-Viewport, je 1 Frame — keine
   Capture-Serien).
3. Beide Frames vergleichen und EIN Verdict fällen, plus maximal 3 konkrete Gaps
   auf UNSERER Seite (nur was auf dem Frame sichtbar ist: Layout, Typo-Hierarchie,
   Spacing, Farbklima, Zustände — keine Code-Vermutungen):

   ```
   DESIGN_VERDICT: reference|ours|par | gap1; gap2; gap3
   ```

Regeln:
- Das Verdict erzeugt NIE ein GitHub Issue: es ist subjektiv und gehört nicht in
  die Threshold/Fingerprint-Maschinerie. Es landet nur im Audit-Log (Schritt 11)
  und im SITE_RESULT-Output; was daraus wird, entscheidet der User.
- Referenz-Look nie kopieren: Gaps benennen, was unserer Site fehlt, nicht wie
  die Referenz aussieht.
- Screenshots sind flüchtig — nie ins Repo oder in Issues schreiben.
- `ours` und `par` sind valide Ergebnisse, kein Weichzeichnen in Richtung
  "reference" aus Höflichkeit gegenüber der bekannten Marke.

### Schritt 6: Toleranz-Band anwenden

Für jedes Finding (außer Sofort-Exceptions):

1. Ist `fingerprint` in `SUPPRESSIONS`? → Finding überspringen.
2. War `fingerprint` im letzten Run in `PENDING_FINDINGS`?
   - Ja → Finding ist bestätigt → zur `CONFIRMED_FINDINGS`-Liste hinzufügen, aus `PENDING_FINDINGS` entfernen.
   - Nein → Finding zu `PENDING_FINDINGS` hinzufügen (wird nächste Woche bestätigt).
3. Ist `fingerprint` nicht mehr im aktuellen Run aber war in `PENDING_FINDINGS`? → Aus `PENDING_FINDINGS` entfernen (gefixt).

### Schritt 7: Rollout-Filter anwenden

Filtere `CONFIRMED_FINDINGS` nach `ROLLOUT_WEEK` aus `guidelines/thresholds.md`:
- Woche 1: nur `critical`
- Woche 2-3: `critical` + `important`
- Ab Woche 4: alle

### Schritt 8: Offene Issues laden + Deduplication

```bash
gh issue list --repo {GITHUB_REPO} --label audit --state open \
  --json number,title --limit 100
```

Für jedes Finding in `CONFIRMED_FINDINGS` (nach Rollout-Filter):
- Prüfe ob ein Issue mit Titel `[live-audit] {SITE_URL} | {metric-id}` bereits offen ist.
- Wenn ja: Issue existiert → nicht doppelt erstellen.
- Wenn nein: Issue erstellen (Schritt 9).

### Schritt 9: GitHub Issues erstellen

Für jedes neue Finding:

```bash
gh issue create \
  --repo {GITHUB_REPO} \
  --title "[live-audit] {SITE_URL} | {metric-id}" \
  --label "audit,{severity}" \
  --body "## Impact
{1-2 Sätze was betroffen ist — z.B. 'Langsamer LCP beeinträchtigt wahrgenommene Ladezeit für mobile Nutzer.'}

## Messwert
Aktuell: {value} {unit}
Threshold {severity}: {threshold}
Run: {DATUM} | Strategie: {strategy}
URL: https://{SITE_URL}

## Fix-Hinweis
{kurzer Hinweis aus thresholds.md oder Lighthouse-Audit-Beschreibung}

## Next
- [ ] Fix this
- [ ] Add to backlog
- [ ] Ignore — label this issue \`suppress\` and the system will skip it next run"
```

Zähle erstellte Issues → `NEW_ISSUES_COUNT`.

### Schritt 10: Suppressions + State schreiben

**suppressions.json updaten** (wenn neue Suppressions aus Schritt 2):

```bash
# Aktuelle Datei lesen, neue Einträge mergen, zurückschreiben
CONTENT=$(echo '{updated_array}' | base64)
SHA=$(gh api repos/{GITHUB_REPO}/contents/.claude/live-audit/suppressions.json --jq '.sha' 2>/dev/null)
gh api repos/{GITHUB_REPO}/contents/.claude/live-audit/suppressions.json \
  --method PUT \
  --field message="chore: update live-audit suppressions [$(date +%Y-%m-%d)]" \
  --field content="$CONTENT" \
  --field sha="$SHA" 2>/dev/null || true
```

**state.json updaten:**

```json
{
  "rollout_week": {min(ROLLOUT_WEEK + 1, 4)},
  "last_run": "{DATUM}",
  "pending_findings": {aktualisierte PENDING_FINDINGS Map}
}
```

Rollout-Woche erhöht sich bei jedem erfolgreichen Run um 1, Cap bei 4. Bei degraded Run (`PSI_429` oder `PSI_ERROR` gesetzt): state.json NICHT schreiben, `rollout_week` bleibt unverändert.

Schreibe state.json via `gh api` (wie suppressions.json oben).

### Schritt 11: Audit-Log schreiben

```bash
LOG_PATH=".claude/audits/live-$(date +%Y-%m-%d).md"
CONTENT=$(cat <<'EOF'
# Live Audit — {DATUM}

## Site: {SITE_URL}

### Messwerte
| Metrik | Mobile | Desktop |
|---|---|---|
| Performance Score | {score} | {score} |
| Accessibility Score | {score} | — |
| SEO Score | {score} | — |
| LCP | {value}s | — |
| CLS | {value} | — |
| FCP | {value}s | — |

### Findings
| Fingerprint | Severity | Status |
|---|---|---|
| {fingerprint} | {severity} | new issue / existing / suppressed / pending |

### Design-Verdict
{DESIGN_VERDICT-Zeile, oder "nicht konfiguriert" wenn DESIGN_REFERENCE leer}

### Neue Issues: {N}
### Suppressed: {N}
### Pending (Toleranz-Band): {N}
EOF
)
ENCODED=$(echo "$CONTENT" | base64)
SHA=$(gh api repos/{GITHUB_REPO}/contents/$LOG_PATH --jq '.sha' 2>/dev/null)
if [ -n "$SHA" ]; then
  gh api repos/{GITHUB_REPO}/contents/$LOG_PATH \
    --method PUT \
    --field message="chore: live-audit log $(date +%Y-%m-%d)" \
    --field content="$ENCODED" \
    --field sha="$SHA"
else
  gh api repos/{GITHUB_REPO}/contents/$LOG_PATH \
    --method PUT \
    --field message="chore: live-audit log $(date +%Y-%m-%d)" \
    --field content="$ENCODED"
fi
```

### Schritt 12: Heartbeat-Issue updaten

Das Heartbeat-Issue hat den Titel `[live-audit] Pipeline Status`. Finde es:

```bash
HEARTBEAT=$(gh issue list --repo {GITHUB_REPO} --label audit --search "[live-audit] Pipeline Status" \
  --json number --limit 1 --jq '.[0].number')
```

Füge einen Kommentar hinzu:

```bash
gh issue comment $HEARTBEAT --repo {GITHUB_REPO} \
  --body "**Run:** $(date +%Y-%m-%d %H:%M UTC)
**Status:** OK
**Neue Issues:** {NEW_ISSUES_COUNT}
**Suppressed:** {SUPPRESSED_COUNT}
**Pending (Toleranz-Band):** {PENDING_COUNT}
$([ "$PSI_429" = "true" ] && echo '**Warn:** PSI 429 — eine Strategy übersprungen')"
```

## Output an Orchestrator

Gib am Ende zurück:

```
SITE_RESULT_START
SITE: {SITE_URL}
REPO: {GITHUB_REPO}
PSI_MOBILE: {performance_score}/100
PSI_DESKTOP: {performance_score}/100
SSL: OK|WARN|ERROR
DESIGN_VERDICT: {reference|ours|par | gaps} | skipped reason=... | n/a
NEW_ISSUES: {N}
SUPPRESSED: {N}
PENDING: {N}
WARNINGS: {z.B. "PSI 429 für mobile" oder ""}
SITE_RESULT_END
```

## Fehlerbehandlung

- **Site nicht erreichbar** (`SITE_UNREACHABLE=true` aus dem curl/openssl-Check in Schritt 4, curl schlägt fehl oder liefert keinen 2xx/3xx-Status): `site-unreachable` Critical Issue erstellen, dann Schritt 3-7 überspringen, direkt zu Schritt 10.
- **gh nicht auth'd** (`GITHUB_TOKEN` fehlt): Output `SITE_RESULT_START ... ERROR: GITHUB_TOKEN missing SITE_RESULT_END`, abbrechen.
- **gh api write fehlschlägt**: Warnung in Output, nicht abbrechen. Audit-Log und state.json-Schreiben sind non-critical.
