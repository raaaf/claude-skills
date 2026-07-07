# Pre-Flight-Checks: Learning-Backlog + offene Issues/PRs

Wird von `audit/SKILL.md` Phase 0 geladen. Zwei Checks vor dem eigentlichen Audit.

## Learning-Backlog-Check (Phase 0)

Pruefe ob unverarbeitete Learning-Vorschlaege aus frueheren Audits offen sind:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

Wenn `>= 1`: User via `AskUserQuestion` fragen mit Optionen:

- **Vorschlaege jetzt umsetzen** → Vorschlaege auflisten, User waehlt welche, Orchestrator dispatcht passende Aenderungen an `audit/guidelines/*.md` oder `audit/agents/*.md`. **WICHTIG — ins Quell-Repo editieren:** `~/.claude/skills/*` kann ein Sync-Ziel sein (Symlink oder entpacktes `.skill`-Bundle), dessen Inhalt ueberschrieben wird. Vor dem ersten Edit Quelle aufloesen (`readlink` bzw. Skill-Quell-Repo finden, z.B. `~/Local Sites/claude-skills`) und DORT editieren — Edits in der entpackten Kopie gehen beim naechsten Sync verloren. Nach Umsetzung: `[ ]` zu `[x]` aendern in learning-log.md. Dann Audit weiter mit Phase 1.
- **Spaeter, Audit jetzt** → Phase 1 starten, Vorschlaege bleiben offen.
- **Nie wieder fragen fuer diese Audits** → `[skip]`-Marker an betroffene Zeilen anhaengen, sie zaehlen nicht mehr.

Wenn `0`: weiter ohne Frage.

## Offene Audit-Issues & PRs (Phase 0.2)

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

**Offene `audit-finding`-Issues vorhanden?** → AskUserQuestion (Liste kompakt zeigen):

- **Jetzt mitfixen** — ausgewaehlte Issues werden als verifizierte Findings in Runde 1 eingespeist (Fix-Agent + Fix-Verifier wie ueblich). Nach erfolgreichem Fix: `gh issue close {N} --comment "Fixed in audit {DATUM}, commit folgt im naechsten Push."`
- **Offen lassen** — Issues bleiben, Audit laeuft normal.

**`OPEN_PRS` nicht leer?** → Als Kontext merken (keine Frage):

- In Phase 3f-Dedup: kein neues Issue fuer etwas, das ein offener PR bereits adressiert.
- Wenn ein offener PR dieselben Dateien anfasst wie der aktuelle Diff: Hinweis im Audit-Log (`## Hinweise: PR-Ueberschneidung`) — Merge-Konflikt-Risiko.
