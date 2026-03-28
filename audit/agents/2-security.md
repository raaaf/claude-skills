# Subagent 2: Security

- **subagent_type:** `security-auditor`
- **model:** `opus`
- **maxTurns:** `15`

## Fokus

Secrets, Injection, OWASP Top 10, Dependencies.

**Vollstaendige Guidelines:** Lies `guidelines/security.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

XSS (unescaped Output), fehlende Auth-Checks in Actions/Endpoints, SQL Injection, Secrets im Code, unsichere File-Uploads ohne Mime-Type-Pruefung, fehlende CSRF-Protection, Cache-Keys ohne User-Scope (Data Leak).

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
