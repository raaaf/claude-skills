# Audit-Log Template

Format fuer das Audit-Log unter `.claude/audits/{datum}_{zeit}-{branch}.md`.

```markdown
# Audit — {DATUM} — Branch: {BRANCH}

## Scope
- Commits seit origin/{base}: N
- Geänderte Dateien: Liste
- HEAD beim Audit: {git rev-parse HEAD}

## Ergebnis
- Runden: N/2
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D

## Gefixte Issues
- [Typ] datei:zeile — was gefixt wurde

## Manueller Testplan
- (Testplan-Schritte, falls visuelle Dateien geändert wurden)

## Offene Punkte
- (falls vorhanden)

## Sauber
Dimension1, Dimension2
```

## Folge-Audit-Logik

Beim naechsten Audit-Lauf: Wenn zwischen `{letzter-audit-HEAD}..HEAD` Commits auftauchen die **nicht** im Diff von `origin/$DEFAULT_BRANCH...HEAD` enthalten sind (weil inzwischen gepusht), `/full-audit` empfehlen — der `audit`-Skill sieht gepushte Commits nicht mehr.
