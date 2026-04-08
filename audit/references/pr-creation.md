# PR-Erstellung nach erfolgreichem Push

Nur ausführen wenn der Push erfolgreich war UND wir auf einem Feature-/Fix-Branch sind.

## Schritt 1 — Prüfen ob PR sinnvoll

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
```

Abbrechen wenn:
- `CURRENT_BRANCH` ist `main`, `master` oder `$DEFAULT_BRANCH`
- `gh pr view` zeigt bereits einen offenen PR für diesen Branch
- `gh auth status` schlägt fehl (nicht eingeloggt)

## Schritt 2 — Daten sammeln

```bash
# Commits seit Base-Branch
git log origin/$DEFAULT_BRANCH..HEAD --oneline

# Geänderte Dateien
git diff origin/$DEFAULT_BRANCH...HEAD --stat

# Plan-Doc suchen (falls vorhanden)
ls docs/plans/*.md 2>/dev/null
```

Falls ein Plan-Doc existiert das zum aktuellen Feature passt (Datum oder Thema im Dateinamen), den Inhalt als Kontext für die PR-Description nutzen.

## Schritt 3 — PR erstellen

Titel: Conventional Commit Stil, abgeleitet aus den Commits. Beispiele:
- `feat: add time entry bulk export`
- `fix: correct invoice calculation for partial hours`
- `refactor: extract billing service from controller`

Body via HEREDOC:

```bash
gh pr create --title "$TITLE" --body "$(cat <<'EOF'
## Summary
- Was wurde gemacht
- Warum
- Wichtige Details (optional)

## Changes
- **Added:** Neue Features/Dateien
- **Changed:** Geänderte Funktionalität
- **Fixed:** Behobene Bugs

## Test Plan
- [ ] Relevante Testschritte
- [ ] Edge Cases

## Breaking Changes
Beschreibung falls vorhanden

Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Leere Sections weglassen — nicht mit „Keine" füllen. Keine Breaking Changes? Section weglassen.

## Schritt 4 — PR-URL ausgeben

PR erstellt? URL anzeigen. Fehler? Melden und weitermachen — ein fehlgeschlagener PR blockiert nicht den Push.
