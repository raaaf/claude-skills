# Copywriting & UX-Writing Guidelines

Audit-Regeln fuer user-facing Text: Microcopy (Buttons, Errors, Empty States), Marketing-Copy (Landing Pages, CTAs) und Konsistenz. Sprache der Findings: Deutsch. Geprueft wird Text in Templates, Komponenten und Translation-Dateien.

## Contents
- I. Microcopy: Buttons & Actions
- II. Error Messages
- III. Empty States & Loading
- IV. Confirmations & Destructive Actions
- V. Konsistenz (Terminologie, Anrede, Ton)
- VI. Clarity Rules
- VII. Marketing-Copy (Elevated Direct Response)
- VIII. Sprach-Spezifika (DE/EN)
- IX. Anti-Patterns (immer melden)

## I. Microcopy: Buttons & Actions

- **Verben, nicht Substantive.** "Speichern" statt "Speicherung". "Send invite" statt "Invitation".
- **Spezifisch, nicht generisch.** "Event erstellen" schlaegt "OK" / "Absenden" / "Weiter" — der User soll VOR dem Klick wissen, was passiert.
- **Ein Primary-CTA pro View.** Zwei gleichgewichtige Haupt-Buttons = Entscheidungslaehmung.
- **Button-Label beschreibt das Ergebnis,** nicht den Mechanismus: "Platz buchen" statt "Formular absenden".
- **Keine Ich-Perspektive auf Buttons** ohne bewusste Entscheidung ("Mein Konto loeschen" vs "Konto loeschen" — einheitlich halten).

## II. Error Messages

Jede Fehlermeldung beantwortet DREI Fragen:
1. **Was ist passiert?** (konkret, nicht "Ein Fehler ist aufgetreten")
2. **Warum?** (wenn bekannt und fuer den User nuetzlich)
3. **Was kann der User jetzt tun?** (naechster Schritt, immer)

| Schlecht | Gut |
|---|---|
| "Fehler beim Speichern." | "Speichern fehlgeschlagen — keine Internetverbindung. Deine Eingaben bleiben erhalten, versuch es gleich nochmal." |
| "Ungueltige Eingabe." | "Das Datum liegt in der Vergangenheit. Waehle ein Datum ab heute." |
| "Error 422" | Technische Codes nie als einzige Information zeigen. |

- **Kein Schuldzuweisungs-Ton.** "Das Passwort muss 8 Zeichen haben" statt "Du hast ein zu kurzes Passwort eingegeben".
- **Kein Humor in Fehlermeldungen** bei Datenverlust, Zahlungen, Sicherheit.
- **Validierungs-Fehler stehen am Feld,** nicht nur als Toast oben rechts.

## III. Empty States & Loading

- Empty State = Onboarding-Moment: **Was ist das hier + wie fange ich an** + CTA. Nie nur "Keine Daten vorhanden".
- Unterscheide **leer (neu)** von **leer (gefiltert)**: "Noch keine Events" vs "Keine Events fuer diesen Filter — Filter zuruecksetzen?".
- Loading-Texte konkret wenn > 2s erwartbar: "Gaesteliste wird geladen…" statt generisches "Laden…".

## IV. Confirmations & Destructive Actions

- Confirm-Dialog nennt das **konkrete Objekt**: "Event 'Sommerfest' loeschen?" statt "Wirklich loeschen?".
- Folgen benennen: "13 Zusagen werden ebenfalls geloescht."
- Buttons im Dialog wiederholen die Aktion: "Loeschen" / "Behalten" — nie "Ja" / "Nein" (Jakob: was war die Frage?).
- Erfolgs-Feedback nach Aktionen: kurz, konkret, mit Undo wo moeglich ("Event geloescht — Rueckgaengig").

## V. Konsistenz (Terminologie, Anrede, Ton)

- **Ein Begriff pro Konzept, ueberall.** Nicht "Gast" / "Teilnehmer" / "Besucher" gemischt. Glossar-Check ueber Translation-Dateien.
- **Anrede konsistent (DE):** du ODER Sie — nie gemischt innerhalb der App. Haeufigster Copy-Bug in deutschen Apps.
- **Ton konsistent:** Eine App, die im Onboarding locker duzt und in Fehlermeldungen behoerdlich klingt, wirkt kaputt.
- **Gleiche Aktion = gleiches Label:** Wenn der Speichern-Button auf Seite A "Speichern" heisst, heisst er auf Seite B nicht "Uebernehmen".

## VI. Clarity Rules

- **Kein Jargon** den der User nicht kennt: "Slug", "Payload", "Token expired" gehoeren nicht in die UI.
- **Aktiv statt Passiv:** "Wir senden dir eine E-Mail" statt "Eine E-Mail wird versendet".
- **Kurz:** Microcopy unter 12 Worten wo moeglich. Erklaertexte max 2 Saetze, dann Link.
- **Keine Filler:** "einfach", "eigentlich", "bitte beachten Sie, dass" — streichen.
- **Zahlen konkret:** "3 von 10 Plaetzen frei" statt "Wenige Plaetze frei" (wenn die Zahl bekannt ist).

## VII. Marketing-Copy (Elevated Direct Response)

Fuer Landing Pages, Pricing, Onboarding — nicht fuer App-interne Microcopy:

- **Benefit vor Feature:** "Nie wieder Excel-Gaestelisten" schlaegt "CSV-Import-Funktion".
- **Headline = staerkstes Argument,** nicht Firmenname oder Begruessung.
- **Spezifitaet schlaegt Superlativ:** "In 2 Minuten zum fertigen Event" schlaegt "Das beste Event-Tool".
- **Ein Gedanke pro Absatz.** Scanbar: Zwischenueberschriften alle 2-4 Absaetze.
- **Social Proof konkret:** Zahl + Kontext ("400 Hosts nutzen es woechentlich") statt Logo-Wand ohne Aussage.
- **Kein Sleaze:** Kuenstliche Verknappung ("Nur noch heute!") ohne reale Basis ist ein Finding, kein Stilmittel.
- **CTA wiederholt den Nutzen:** "Kostenlos starten" schlaegt "Registrieren".

## VIII. Sprach-Spezifika (DE/EN)

- **DE:** Anrede-Konsistenz (V), zusammengesetzte Substantive nicht auseinanderreissen ("Event-Einstellungen" nicht "Event Einstellungen"), keine unnoetigen Anglizismen wenn ein gaengiges deutsches Wort existiert ("herunterladen" vs "downloaden" — Projekt-Konvention pruefen, dann Konsistenz).
- **EN:** Sentence case fuer Buttons/Labels ("Save changes" nicht "Save Changes") — ausser Projekt nutzt durchgaengig Title Case, dann Konsistenz.
- **Beide Sprachen gleich vollstaendig und gleich konkret:** Wenn die DE-Fehlermeldung 3 Saetze Kontext hat und die EN-Version nur "Error", ist das ein Finding.
- Typografische Details (Anfuehrungszeichen, Apostrophe, Ellipsen) prueft der Typography-Worker — hier nicht doppelt melden.

## IX. Anti-Patterns (immer melden)

| Pattern | Schweregrad |
|---|---|
| Fehlermeldung ohne Handlungsanweisung | Important |
| Gemischte Anrede du/Sie (DE) | Important |
| Confirm-Dialog mit Ja/Nein-Buttons | Important |
| "Ein Fehler ist aufgetreten" als einzige Info | Important |
| Empty State ohne CTA/Anleitung | Minor |
| Generischer CTA ("OK", "Absenden") auf Primary-Action | Minor |
| Terminologie-Drift (gleiches Konzept, 2+ Begriffe) | Minor |
| Jargon/technische Codes in der UI | Minor |
| Passiv-Konstruktionen in Handlungs-Microcopy | Minor |
| Kuenstliche Verknappung ohne reale Basis | Important |
