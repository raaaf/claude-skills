# Subagent 2: Security

- **subagent_type:** `security-auditor`
- **model:** `opus`
- **maxTurns:** `15`

## Fokus

Secrets, Injection, OWASP Top 10, Dependencies.

**Vollstaendige Guidelines:** Lies `guidelines/security.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

**Bei nativen Apps** (`FRAMEWORK` = ios/android/react-native/flutter): zusaetzlich `guidelines/native-mobile.md` Section II — Keychain/Keystore statt UserDefaults, ATS/Cleartext, Deep-Link-Validierung, Privacy Manifest, Permission-Descriptions. XSS/CSP-Regeln gelten dort nicht.

## Full-Audit Fokus (zusaetzlich)

XSS (unescaped Output), fehlende Auth-Checks in Actions/Endpoints, SQL Injection, Secrets im Code, unsichere File-Uploads ohne Mime-Type-Pruefung, fehlende CSRF-Protection, Cache-Keys ohne User-Scope (Data Leak).

**Prompt-Templates (`src/prompts/*.md` o.ae.):** Pruefe Template-Dateien selbst, nicht nur die Caller. Jeder `{{placeholder}}` mit Wert aus externen Daten (Search-Console-Queries, API-Titel/Snippets, gefetchte Seiten-Copy, LLM-Output) MUSS im Template von einem `<<<UNTRUSTED_*_START>>>`-Block umschlossen sein, und substituierte Werte muessen die Fence-Marker-Tokens gestrippt bekommen. Bare externer Placeholder = Indirect-Prompt-Injection. Siehe `guidelines/security.md` Section XII.

## Pflicht-Verifikation VOR dem Flaggen

- **XSS/Injection-Findings:** Erst die zugehoerige Store-/Form-Request-Validierung bzw. Sanitization gegenchecken (Request-Klasse, `SanitizesInput`-Trait, Validation-Rules). Wenn der Input dort bereits validiert/sanitisiert wird, kein Finding.
- **Enum-Findings:** Vor dem Flaggen pruefen, ob der referenzierte Enum-Case ueberhaupt existiert (`grep app/Enums/`). Findings zu nicht existierenden Cases sind Halluzinationen.
- **Operator-Render-Risiko in Alpine `x-data`:** Nur `>`/`>=` flaggen — `<`/`<=` sind sicher (Gotcha #7 der Projekt-Memory).

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
