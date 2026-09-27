# store-assets: Store-Screenshots und App Preview aus Code

> **Executor instruction:** Follow step by step, check each verify criterion before moving on.
> If a STOP condition occurs: stop and report, do not improvise.
>
> **Drift check (first):**
> `git -C /Users/rafael/Developer/claude/skills diff --stat 172bdc8..HEAD -- screens/`
> `git -C /Users/rafael/Developer/apps/events diff --stat 1e222f8b1..HEAD -- tests/Browser/Marketing/ native/store-assets/ resources/css/app.css`
> Any change in these paths: reconcile against live code; on mismatch, STOP.

## Meta
- Planned at: skills `172bdc8`, events `1e222f8b1`, 2026-09-27
- Status: Spec
- Challenge: 5 Dimensionen, 15 Concerns → 12 nach Dedupe, 11 eingearbeitet, 1 verworfen (siehe Ende)

## Problem
Store-Bilder für events (und künftig die anderen Apps) entstehen in Figma von Hand: Rahmen,
Headline, Hintergrund um automatisch erzeugte App-Screens legen, pro Sprache und Store exportieren.
Das kostet bei jedem App-Update Stunden, und ein App Preview-Video gibt es gar nicht.

## Goal
Ein wiederverwendbarer Skill `/store-assets` erzeugt aus einem Ordner App-Screens plus einer
Projekt-Config:
- **Meilenstein A (Stills):** iOS 1320×2868 (6.9"), Play-Phone 1440×2560, Play Feature Graphic
  1024×500, JPEG ohne Alpha, sRGB, pro Locale. Eigenständig nutzbar.
- **Meilenstein B (Video):** App Preview (15–30 s, H.264) aus denselben Szenen, plus 1920×1080 für YouTube.
- Look passt zur Brand des jeweiligen Projekts (Fonts, Farben, Logo aus dem Projekt, nie im Skill hartcodiert).

events ist der erste Nutzer. Die neuen events-Bilder sind visuell gleichwertig zu
`native/store-assets/ios-de/Slice 1.jpg` / `Slice 2.jpg` (Navy-Hintergrund, Holdstone-Headline,
Inter-Subline, schräges iPhone, Panorama über zwei Slices).

## Non-Goals
- Upload in die Stores (fastlane deliver/supply, APIs). Eigener Folgeplan.
- Erzeugen der App-Screens selbst: kommt vom Projekt (events: Pest-Browser-Test; native Apps: /screens-Katalog).
- iPad- und Tablet-Formate.
- AI-generierte Bilder.
- Config-Felder, die events nicht braucht (Panorama > 2 Slices, alternative Farbquellen). Erst mit App Nr. 2.

## Out of Scope (Files)
- `screens/templates/marketing.html`, `screens/bin/screens.mjs` Phase 6: unverändert in diesem Plan;
  Ablösung per Folgeplan (Step 12 legt ihn an).
- `events/tests/Browser/Marketing/AppStoreScreenshotTest.php`: liefert die Quell-Screens, wird nicht umgebaut.
- `video-generator/`: nur Referenz für HyperFrames-Setup (`composition/CLAUDE.md`), keine Änderung.

## Solution

### Approach
Eine Szenen-HTML (`scene.html`) pro Szene, gespeist aus `store-assets.json`: Hintergrund +
Headline + Subline + Gerät mit Screen. Layout verzweigt nach Seitenverhältnis (Hochformat für
iOS/Play-Phone, Querformat für Feature Graphic).
- **Stills:** Playwright-Screenshot von `scene.html` in exakter Pixelgröße.
- **Video:** `preview.html` ist eine HyperFrames-Komposition, die jede Szene per
  `data-composition-src="scene.html?..."` als Sub-Komposition einbindet (Mechanismus laut
  `video-generator/composition/CLAUDE.md`, Z. 49/83). Das Layout existiert damit nur einmal;
  `preview.html` enthält nur Timing, Übergänge und Scroll-Animation.

Warum HyperFrames statt Playwright `recordVideo`: HyperFrames rendert frame-genau (deterministisch,
keine Frame-Drops), `recordVideo` nimmt in Echtzeit mit fester Bitrate auf. Ob die Sub-Komposition
trägt, klärt der Spike in Step 3, bevor irgendetwas darauf aufbaut.

Gerät: iPhone- und Android-Rahmen als eigene SVGs im Skill (kein Apple-Marketing-Asset).
Schräglage und Panorama per CSS-Transform; Panorama = eine doppelt breite Leinwand, in 2 Slices geschnitten.

### Steps

**Meilenstein A: Stills**

1. **Skill-Gerüst** `/Users/rafael/Developer/claude/skills/store-assets/`: `SKILL.md` (Ablauf:
   Config lesen → Headlines-Gate → Muster-Gate → Vollrender → Validator → optional Video),
   `references/config-schema.md`, `references/store-specs.md` (Größen, Formate, Limits, Quellen-URLs,
   Stand 2026-09). Muster: `screens/`-Aufbau.
   → verify: `bash ~/.claude/hooks/sync-skills.sh`; `ls ~/.claude/skills/store-assets/SKILL.md` existiert.
2. **Config-Schema** `.store-assets/store-assets.json` im Projekt: `brand` (Font-Dateipfade,
   Farben als konkrete Werte, Logo-Pfad), `locales`, `formats` (`ios-6.9`, `play-phone`,
   `play-feature`), `scenes` (id, Quell-PNG je Locale/Theme, headline/subline je Locale mit
   `reviewed` + `reviewed_hash` = SHA-256 von headline+subline, device-Pose, optional
   `panorama_with: <scene-id>`), `video` (Szenenfolge, Dauer je Szene), `runtime.hyperframes`
   (exakte Version).
   → verify: `references/config-schema.md` beschreibt jedes Feld.
3. **Templates + HyperFrames-Spike:** `templates/scene.html` (Query-Params: scene, locale, format;
   `@font-face` aus Projektpfaden; Layout-Zweig Hoch/Quer), `templates/devices/iphone.svg`,
   `android.svg`. Direkt danach Spike: minimale `preview.html` bindet eine `scene.html` per
   `data-composition-src` ein und rendert 3 s mit `npx -y hyperframes@<exakte Version aus
   video-generator/node_modules/hyperframes/package.json> render`.
   → verify: Screenshot von `scene.html` zeigt Holdstone-Headline und Gerät; Spike-MP4 zeigt dieselbe Szene
   pixelgleich zum Still (Frame per `ffmpeg -ss 1 -frames:v 1` extrahieren, visuell neben Still).
   Spike scheitert → STOP für Meilenstein B; Meilenstein A (Steps 4–9) läuft unverändert weiter,
   `scene.html` braucht HyperFrames nicht. Befund im Report, Video-Ansatz neu planen.
4. **Renderer** `bin/render.mjs`: Pre-Flight (Config-Validierung, Fonts vorhanden, Quell-PNGs
   vorhanden, `reviewed_hash` stimmt sonst `reviewed=false`), dann Playwright-Screenshot je
   Szene × Locale × Format, Panorama-Schnitt, Ausgabe nach
   `<project>/native/store-assets/generated/<format>/<locale>/NN-<id>.jpg`, Konvertierung sRGB ohne
   Alpha (`sips -s format jpeg -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc"`).
   Runtime: Projekt-eigenes `@playwright/test` hat immer Vorrang (Version egal, kein Abgleich mit dem Pin), sonst `npx -y playwright@<pinned>` plus
   `npx playwright install chromium` mit `PLAYWRIGHT_BROWSERS_PATH=~/.cache/store-assets/browsers`
   (nur wenn dort nicht vorhanden). Schreibt `generated/index.html` (Kontaktbogen, markiert Warnungen
   wie abweichendes Seitenverhältnis sichtbar pro Bild).
   → verify: `node bin/render.mjs --project /Users/rafael/Developer/apps/events --scene 01 --format ios-6.9 --locale de` erzeugt Datei; kaputte Config → Exit ≠ 0 vor dem Render.
5. **Validator** `bin/validate.mjs`: je Datei exakte Maße laut `store-specs.md`, `hasAlpha: no`,
   Profil sRGB, Größe < 8 MB, Anzahl ≤ 10 (iOS) / ≤ 8 (Play-Phone), genau 1 Feature Graphic,
   alle `reviewed: true` mit passendem Hash.
   → verify: absichtlich falsche Datei (1290×2796 mit Alpha) → Exit ≠ 0 mit Meldung; echter Output → Exit 0.
6. **events-Config** `events/.store-assets/store-assets.json`: Fonts `resources/fonts/Holdstone.woff2`,
   `public/fonts/Inter.woff2`; Farben als Werte aus `resources/css/app.css` und dem Navy der aktuellen
   Slices; Logo aus `public/images/`. Quellen `tests/Browser/screenshots/marketing/appstore/<locale>/<theme>/*.png`
   (via `composer test:screenshots`). Szenenfolge nach Landingpage: Eventseite/Hero, Zusage +
   Erinnerung, Mitbringliste, Fahrgemeinschaft, Fotos, Terminumfrage, Aufgaben, Ausgaben. Szenen, für
   die kein Quell-PNG existiert (z. B. Fahrgemeinschaft, Terminumfrage), im Report nennen, nicht erfinden.
   → verify: Pre-Flight von `render.mjs` Exit 0; Report-Zeile `MISSING_SOURCE` listet jede Szene ohne PNG (oder "keine").
7. **Gate 1, Headlines:** Tabelle aller Headlines/Sublines de+en; Startpunkt sind die Texte der
   aktuellen Slices. Rafael gibt frei → `reviewed: true` + Hash.
   → verify: Validator-Teilcheck "reviewed" grün.
8. **Gate 2, Muster:** rendern und nebeneinander zeigen: iOS Szene 1+2 (Panorama) de, Play-Phone
   Szene 1 de, Feature Graphic de; daneben `Slice 1.jpg`/`Slice 2.jpg`. Rafael gibt Optik frei.
   → verify: Freigabe im Chat.
9. **Vollrender** alle Szenen × de/en × 3 Formate, Validator, Kontaktbogen zeigen.
   → verify: `validate.mjs` Exit 0; Rafael sieht `generated/index.html`. **Meilenstein A fertig.**

**Meilenstein B: Video**

10. **Video** `templates/preview.html` (auf Basis Spike): 20–25 s, Szenenfolge aus Config,
    Slide/Fade-Übergänge, Screen scrollt im Gerät; `bin/render-video.mjs` rendert App-Preview-Auflösung
    (vor Umsetzung gegen Apple-Doku prüfen, Wert + Quelle in `store-specs.md`) und 1920×1080.
    → verify: `ffprobe`: h264, 15–30 s, Auflösung laut Spec; Rafael gibt frei.

**Abschluss**

11. **Doku:** `store-assets/CLAUDE.md` (Commands), Root-`CLAUDE.md` Skill-Roster- und Wegweiser-Zeile, Root-`README.md` Skill-Liste (Repo-Regel "Adding a new skill"); SKILL.md-Frontmatter `model: inherit`, `effort: medium`; events
    `CLAUDE.md` Commands-Zeile; `events/docs/CAPACITOR-SETUP-GUIDE.md` §6.1 verweist auf `/store-assets`.
    → verify: `grep -n store-assets` trifft in allen drei Dateien.
12. **Folgeplan-Stub** `docs/plans/2026-10-xx-screens-phase6-retire.md`: Phase 6 von /screens durch
    store-assets ersetzen; Trigger: store-assets hat einen zweiten Projekt-Lauf ohne Codeänderung am Skill.
    → verify: Datei existiert.

### Affected Files
- `claude/skills/store-assets/**` — neu (SKILL.md, CLAUDE.md, references/, templates/, bin/render.mjs, bin/validate.mjs, bin/render-video.mjs)
- `claude/skills/CLAUDE.md` — Wegweiser-Zeile
- `claude/skills/docs/plans/2026-10-xx-screens-phase6-retire.md` — Stub
- `events/.store-assets/store-assets.json` — neu
- `events/native/store-assets/generated/**` — Output (committet; alte Slices bleiben bis Upload)
- `events/CLAUDE.md`, `events/docs/CAPACITOR-SETUP-GUIDE.md` — Verweis

### Conventions
- Skills-Repo: keine npm-Dependencies im Repo (Root-`CLAUDE.md` "Stack"). Playwright aus dem Projekt
  wie `screens/templates/render-marketing.mjs`, sonst npx mit exakter Version.
- SKILL.md unter 500 Zeilen, Details in `references/`, Skill-Texte Englisch, User-Strings Deutsch.
- Keine Brand-Werte im Skill; alles aus Projekt-Config (`rafael-design-system` gilt nicht für events).
- Keine Emojis, keine Gedankenstriche in User-Texten.

## Edge Cases
- Quell-PNG fehlt für Locale/Theme: Pre-Flight Exit ≠ 0 mit Liste.
- Quell-PNG mit anderem Seitenverhältnis als Geräte-Screen: `object-fit: cover` von oben, Warnung im Kontaktbogen am Bild.
- Font lädt nicht: Abbruch (`document.fonts.check`), kein Fallback-Font im Output.
- Headline zu lang: CSS-`clamp` bis Minimalgröße, darunter Fehler.
- Headline nach Freigabe geändert: Hash passt nicht → `reviewed=false` → Validator rot.
- Offline ohne Chromium-Cache: STOP-Meldung mit Install-Befehl.

## Known Costs
- Zwei Marketing-Wege (/screens Phase 6 und store-assets) bis zum Folgeplan.
- Config nur für events-Bedarf geschnitten; App Nr. 2 wird das Schema erweitern.
- `store-specs.md` veraltet still, wenn Apple/Google Formate ändern. SKILL.md lässt vor jedem
  Vollrender das `Stand`-Datum prüfen: älter als 6 Monate → Specs gegen die Quell-URLs neu verifizieren.

## Done Criteria
- [ ] `node store-assets/bin/validate.mjs --project /Users/rafael/Developer/apps/events` → Exit 0
- [ ] `ls events/native/store-assets/generated/ios-6.9/de | wc -l` ≥ 6, ebenso en und play-phone de/en; `play-feature/{de,en}` je 1
- [ ] `sips -g pixelWidth -g pixelHeight -g hasAlpha` je Format: 1320×2868 / 1440×2560 / 1024×500, `hasAlpha: no`
- [ ] Meilenstein B: `ffprobe` auf Preview: h264, 15–30 s
- [ ] `grep -rniE "holdstone|events" store-assets/templates store-assets/bin` → keine Treffer
- [ ] Rafael hat Gate 1, Gate 2 und Video freigegeben
- [ ] Folgeplan-Stub für /screens Phase 6 existiert (Step 12)

## STOP Conditions
- Spike Step 3: HyperFrames rendert `scene.html` nicht als Sub-Komposition oder nicht pixelgleich.
- Apple-/Google-Spezifikation weicht von `store-specs.md` ab.
- Ein Schritt würde eine npm-Dependency ins Skills-Repo bringen.
- `composer test:screenshots` schlägt fehl oder liefert keine PNGs.
- Chromium-Download scheitert (offline).

## Open Questions
- Keine offen. Annahmen: Playwright/HyperFrames per npx mit exakter Version, Browser-Cache unter `~/.cache/store-assets/`.

## Challenge-Ergebnis
- Eingearbeitet: HyperFrames-Spike vorgezogen + Sub-Komposition statt zweitem Layout (Architektur, Risiko, Produkt, Einfachheit, konvergent); Meilensteine A/B getrennt (Produkt); exakte HyperFrames-Version (Risiko); Chromium-Provisioning + STOP (Architektur); `reviewed_hash` (Architektur); Querformat-Layout + Play/Feature Graphic in Gate 2 (Design); Warnungen im Kontaktbogen (Design); eine Farbdarstellung (Einfachheit); Config-Validierung in `render.mjs` (Einfachheit); Folgeplan-Stub für Phase 6 (Produkt); Panorama auf 2 Slices begrenzt (Produkt).
- Evaluation (ready with changes, 4/4/4/3): Spike-Fallback für A, Playwright-Vorrang, MISSING_SOURCE-Check, Spec-Alterungscheck, Stub in Done Criteria, alle 5 eingearbeitet.
- Verworfen: Playwright `recordVideo` statt HyperFrames (Einfachheit). Grund: Echtzeitaufnahme mit Frame-Drops und fester Bitrate, widerspricht dem Qualitätsziel; der Spike deckt das Integrationsrisiko ab.
