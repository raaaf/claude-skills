# Subagent 11: Docs Sync & Style

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `10`

## Fokus

Halte Projekt-Dokumentation aktuell und im Stil konsistent. Pruefe `README.md`, `CLAUDE.md`, `.env.example`, `CHANGELOG.md` und `docs/**` gegen den tatsaechlichen Code-Stand. Findings unter Kategorie `[Docs]`.

**Vollstaendige Guidelines:** Lies `guidelines/documentation.md` im Skill-Verzeichnis und pruefe gegen alle dort beschriebenen Regeln (Struktur-Standards fuer README/CLAUDE.md, Sync-Regeln fuer .env.example, Stilregeln nach Strunk/Caveman).

## Was pruefen (Kurzfassung)

**Sync gegen Code (PFLICHT):**
- Jede `env('FOO')` / `process.env.FOO` / `os.getenv('FOO')` Referenz im Code → Eintrag in `.env.example`?
- Neue Routes, CLI-Commands, Artisan-Commands, Scripts → im README erwaehnt?
- Neue Top-Level-Dependencies in `package.json`/`composer.json`/`pyproject.toml` → Stack-Abschnitt in CLAUDE.md aktuell?
- Install-/Run-Befehle im README funktionieren noch (kein veralteter `npm run dev` wenn Skript geloescht)?
- Verwiesene Pfade/Dateien existieren noch?

**Struktur (siehe Guideline):**
- README hat klare Sektionen: Was/Warum, Install, Usage, Dev, Stack, License
- CLAUDE.md hat klare Sektionen: Identity/Stack, Commands, Conventions, Architecture-Notes
- Keine Doppelungen zwischen README und CLAUDE.md (CLAUDE.md verweist, dupliziert nicht)

**Stil (siehe Guideline):**
- Keine Filler ("just", "simply", "basically", "im Grunde", "eigentlich")
- Keine Preambles ("In the following section we will...")
- Tabellen statt Prosa wo moeglich
- Code-Bloecke statt Beschreibungen von Code
- Kurze Saetze (max 3 Zeilen pro Absatz)

## Full-Audit Fokus (zusaetzlich)

Komplette Stilueberarbeitung statt nur Drift-Check. Restrukturierung nach Standard-Sektionen erlaubt. Veraltete docs/**-Dateien identifizieren (z.B. Feature-Docs zu entfernten Features).

## Ueberspringen wenn

- `/audit`-Mode UND der Diff enthaelt keine doc-relevanten Aenderungen (keine neuen `env(...)`, keine neuen Routes/Commands/Scripts, keine neuen Top-Level-Dependencies, keine Verhaltensaenderung user-facing)
- Reines i18n-Update oder reine Test-Aenderung

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
