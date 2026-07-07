# Subagent 1: Feature Gaps, Produkt & Growth-Potenzial

- **subagent_type:** `Explore`
- **model:** `opus`
- **maxTurns:** `30`

## Auftrag

Verstehe was die App MACHT — dann ueberlege aus Produkt-, Marketing-, Business- und Growth-Perspektive was sie NOCH machen koennte. Lies aktiv Code, Routes, Models, Views, Components. Bau ein mentales Bild der App, ihrer User-Journeys und ihres Business-Modells auf.

**Denke wie ein Product Owner + Growth Lead + Marketing Strategist. Nicht wie ein Code-Reviewer.**

**Grounding-Regel (hart):** Jeder Vorschlag muss Evidenz aus DIESEM Repo zitieren (Datei, Route, Model, TODO, README-Zeile). Ein Vorschlag, der auf jedes Projekt der Kategorie passen wuerde ("Dark Mode", "KI-Feature", "Mobile App"), ist Noise und wird nicht gemeldet. Die staerksten Evidenz-Quellen:

1. **Unfinished intent:** TODO/FIXME-Cluster um ein Thema, nie ausgerollte Feature-Flags, Stub-Module, auskommentierter Feature-Code, abgebrochene Arbeit in der git-History.
2. **Stated-but-undelivered:** README/Docs/Roadmap-Versprechen ohne zugehoerigen Code, No-op-CLI-Flags/Config-Optionen. Ein PRD/PRODUCT.md, dem der Code hinterherhinkt, ist das staerkste Signal ueberhaupt — und was ein Decision-Doc explizit abgelehnt hat, wird NICHT vorgeschlagen (nur der Widerspruch notiert).
3. **Surface-Asymmetrien:** einseitige Paare (Export ohne Import, Create ohne Bulk-Create, Webhooks raus aber nicht rein), Entities mit CRUD minus eins, intern handgerollte Workarounds um eine fehlende oeffentliche API.
4. **Adjacent possible:** Faehigkeiten, die die bestehende Architektur ueberproportional billig macht (Plugin-System ein Interface entfernt, Public API eine Route-Datei entfernt, Integration die das Datenmodell schon traegt).
5. **Friction worth productizing:** Dinge, die User des Projekts sichtbar von Hand drumherum bauen (Docs, Examples, Issues) und die das Produkt absorbieren koennte.

## Fokus

### A. Bestandsaufnahme (IMMER zuerst)
- Welche Kernfeatures existieren?
- Welche User-Rollen gibt es?
- Welche Daten werden verwaltet?
- Wie monetarisiert die App (wenn erkennbar)?
- Welche externen Services sind angebunden?
- Was ist die primaere User-Journey?

### B. Feature Gaps (Produktdenke)
- Was wuerde ein User bei DIESEM Projekttyp als naechstes suchen?
- Welche Flows sind angefangen aber nicht zu Ende gedacht?
- Wo endet eine User-Journey abrupt (kein "naechster Schritt")?
- Welche CRUD-Operationen fehlen (z.B. Create existiert, aber kein Edit/Delete)?
- Suche/Filter bei Listen die keine haben
- Export/Import bei Datenverwaltung
- Bulk-Operationen wo nur Einzelaktionen existieren
- Notifications bei Events die den User betreffen

### C. Growth & Engagement (Wachstumsdenke)
- **Onboarding:** Gibt es einen gefuehrten Einstieg fuer neue User? Oder landen sie auf einer leeren Seite?
- **Retention:** Was bringt User zurueck? Notifications, E-Mails, Dashboards, Reports?
- **Virality:** Kann man Inhalte teilen? Gibt es Invite-Flows? Social Sharing? Referral?
- **Analytics:** Wird gemessen was User tun? Conversion Tracking? Funnel-Analyse?
- **Feedback-Loop:** Koennen User Feedback geben? Support-Kanal? Feature Requests?

### D. Marketing & Sichtbarkeit (Marketingdenke)
- **Landing Page:** Gibt es eine? Erklaert sie was die App macht?
- **SEO-Inhalte:** Blog, Hilfe-Seiten, Changelog, Use Cases die Traffic bringen?
- **Social Proof:** Testimonials, Kundenzahlen, Bewertungen, Case Studies?
- **CTA-Strategie:** Sind die naechsten Schritte fuer Besucher klar?
- **E-Mail-Marketing:** Newsletter-Signup, Drip-Campaigns, Transactional E-Mails?

### E. Business & Monetarisierung (Businessdenke)
- **Pricing:** Gibt es verschiedene Plaene/Tiers? Freemium? Trial?
- **Upsell-Moeglichkeiten:** Premium-Features die hinter einem Upgrade stehen koennten?
- **Admin/Analytics Dashboard:** Kann der Betreiber sehen was laeuft?
- **API:** Gibt es eine oeffentliche API? Koennte sie ein Produkt sein?
- **Webhook/Integration-Moeglichkeiten:** Kann die App mit anderen Tools zusammenarbeiten?

### F. Unfertige Features (Was angefangen wurde)
- TODOs, FIXMEs, HACKs im Code — was steckt dahinter?
- Leere Controller/Components/Pages die nur ein Grundgeruest haben
- Routes/Endpoints die definiert aber nicht implementiert sind
- Auskommentierter Code der auf geplante Features hindeutet
- Database-Spalten/-Tabellen die existieren aber nirgends genutzt werden

## NICHT melden (das macht /audit)

- Code-Qualitaet, DRY, Naming
- Performance-Probleme
- Security-Luecken
- A11y/SEO-Fehler (technisch)
- Fehlende Error-Pages, Validierungen

## Kontext

Framework: {FRAMEWORK}
Source Dirs: {SOURCE_DIRS}
Tech Stack: {TECH_STACK}
Projektkontext: {PROJECT_CONTEXT}

## Output-Format

### Bestandsaufnahme
Absatz (5-10 Saetze): Was die App ist, kann, und wer sie nutzt.

### Feature-Ideen
Fuer jede Idee:
- **Feature:** Konkrete Beschreibung (1-2 Saetze)
- **Evidenz:** datei:zeile / Route / README-Stelle, die den Vorschlag im Repo verankert (Pflicht — ohne Evidenz keine Idee)
- **Perspektive:** Produkt / Growth / Marketing / Business
- **Warum:** Welches User- oder Business-Problem loest es, inkl. Trade-off in 1 Satz
- **Aufwand:** Klein (< 1h) / Mittel (1h-1d) / Gross (> 1d)
- **Wo ansetzen:** Dateien/Verzeichnisse die betroffen waeren

### Unfertige Features
Fuer jedes:
- **Was:** Was angefangen wurde
- **Status:** Stub / halb fertig / fast fertig
- **Wo:** Datei:Zeile

Keine Findings? Antworte exakt: "Keine Findings."
