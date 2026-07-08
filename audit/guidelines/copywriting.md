# Copywriting & UX Writing Guidelines

Audit rules for user-facing text: microcopy (buttons, errors, empty states), marketing copy (landing pages, CTAs), and consistency. Language of findings: German. Text is checked in templates, components, and translation files.

## Contents
- I. Microcopy: Buttons & Actions
- II. Error Messages
- III. Empty States & Loading
- IV. Confirmations & Destructive Actions
- V. Consistency (Terminology, Forms of Address, Tone)
- VI. Clarity Rules
- VII. Marketing Copy (Elevated Direct Response)
- VIII. Language Specifics (DE/EN)
- IX. Anti-Patterns (always report)

## I. Microcopy: Buttons & Actions

- **Verbs, not nouns.** "Speichern" instead of "Speicherung". "Send invite" instead of "Invitation".
- **Specific, not generic.** "Event erstellen" beats "OK" / "Absenden" / "Weiter" — the user should know what happens BEFORE clicking.
- **One primary CTA per view.** Two equally weighted main buttons = decision paralysis.
- **Button label describes the outcome,** not the mechanism: "Platz buchen" instead of "Formular absenden".
- **No first-person perspective on buttons** without a deliberate decision ("Mein Konto loeschen" vs "Konto loeschen" — keep it consistent).

## II. Error Messages

Every error message answers THREE questions:
1. **What happened?** (concrete, not "Ein Fehler ist aufgetreten")
2. **Why?** (if known and useful to the user)
3. **What can the user do now?** (next step, always)

| Bad | Good |
|---|---|
| "Fehler beim Speichern." | "Speichern fehlgeschlagen — keine Internetverbindung. Deine Eingaben bleiben erhalten, versuch es gleich nochmal." |
| "Ungueltige Eingabe." | "Das Datum liegt in der Vergangenheit. Waehle ein Datum ab heute." |
| "Error 422" | Never show technical codes as the only information. |

- **No blaming tone.** "Das Passwort muss 8 Zeichen haben" instead of "Du hast ein zu kurzes Passwort eingegeben".
- **No humor in error messages** for data loss, payments, security.
- **Validation errors appear at the field,** not only as a toast in the top right.

## III. Empty States & Loading

- Empty state = onboarding moment: **what is this + how do I get started** + CTA. Never just "Keine Daten vorhanden".
- Distinguish **empty (new)** from **empty (filtered)**: "Noch keine Events" vs "Keine Events fuer diesen Filter — Filter zuruecksetzen?".
- Loading text should be concrete when > 2s is expected: "Gaesteliste wird geladen…" instead of the generic "Laden…".

## IV. Confirmations & Destructive Actions

- Confirm dialog names the **concrete object**: "Event 'Sommerfest' loeschen?" instead of "Wirklich loeschen?".
- Name the consequences: "13 Zusagen werden ebenfalls geloescht."
- Dialog buttons repeat the action: "Loeschen" / "Behalten" — never "Ja" / "Nein" (Jakob: what was the question?).
- Success feedback after actions: short, concrete, with undo where possible ("Event geloescht — Rueckgaengig").

## V. Consistency (Terminology, Forms of Address, Tone)

- **One term per concept, everywhere.** Not "Gast" / "Teilnehmer" / "Besucher" mixed. Glossary check across translation files.
- **Form of address consistent (DE):** du OR Sie — never mixed within the app. The most common copy bug in German apps.
- **Tone consistent:** an app that's casual during onboarding and sounds bureaucratic in error messages feels broken.
- **Same action = same label:** if the save button on page A is called "Speichern", it isn't called "Uebernehmen" on page B.

## VI. Clarity Rules

- **No jargon** the user doesn't know: "Slug", "Payload", "Token expired" don't belong in the UI.
- **Active instead of passive:** "Wir senden dir eine E-Mail" instead of "Eine E-Mail wird versendet".
- **Short:** microcopy under 12 words where possible. Explanatory text max 2 sentences, then a link.
- **No filler:** "einfach", "eigentlich", "bitte beachten Sie, dass" — cut it.
- **Concrete numbers:** "3 von 10 Plaetzen frei" instead of "Wenige Plaetze frei" (when the number is known).

## VII. Marketing Copy (Elevated Direct Response)

For landing pages, pricing, onboarding — not for in-app microcopy:

- **Benefit before feature:** "Nie wieder Excel-Gaestelisten" beats "CSV-Import-Funktion".
- **Headline = strongest argument,** not company name or greeting.
- **Specificity beats superlative:** "In 2 Minuten zum fertigen Event" beats "Das beste Event-Tool".
- **One idea per paragraph.** Scannable: subheadings every 2-4 paragraphs.
- **Concrete social proof:** number + context ("400 Hosts nutzen es woechentlich") instead of a logo wall without a statement.
- **No sleaze:** artificial scarcity ("Nur noch heute!") without a real basis is a finding, not a stylistic device.
- **CTA repeats the benefit:** "Kostenlos starten" beats "Registrieren".

## VIII. Language Specifics (DE/EN)

- **DE:** consistent form of address (V), don't split compound nouns apart ("Event-Einstellungen" not "Event Einstellungen"), no unnecessary anglicisms when a common German word exists ("herunterladen" vs "downloaden" — check project convention, then consistency).
- **EN:** sentence case for buttons/labels ("Save changes" not "Save Changes") — unless the project uses Title Case throughout, then consistency.
- **Both languages equally complete and equally concrete:** if the DE error message has 3 sentences of context and the EN version is just "Error", that's a finding.
- Typographic details (quotation marks, apostrophes, ellipses) are checked by the typography worker — don't report them twice here.

## IX. Anti-Patterns (always report)

| Pattern | Severity |
|---|---|
| Error message without a call to action | Important |
| Mixed forms of address du/Sie (DE) | Important |
| Confirm dialog with yes/no buttons | Important |
| "Ein Fehler ist aufgetreten" as the only info | Important |
| Empty state without CTA/guidance | Minor |
| Generic CTA ("OK", "Absenden") on the primary action | Minor |
| Terminology drift (same concept, 2+ terms) | Minor |
| Jargon/technical codes in the UI | Minor |
| Passive constructions in action microcopy | Minor |
| Artificial scarcity without a real basis | Important |
