# Native Mobile Guidelines (iOS / Android / React Native / Flutter)

Plattformspezifische Audit-Regeln fuer native und cross-platform Apps. Nur relevant wenn `FRAMEWORK` = ios, android, react-native oder flutter. Web-Aequivalente (WCAG/ARIA, CSP, INP) gelten dort NICHT — diese Datei ersetzt sie.

## Contents
- I. Accessibility (VoiceOver / TalkBack)
- II. Security (Storage, Transport, Deep Links, Privacy)
- III. Performance (Main Thread, Memory, Lists)
- IV. UI-Konventionen (HIG / Material)
- V. i18n & Typography nativ
- VI. Release-Hygiene
- VII. Audit-Checkliste
- VIII. Deprecated APIs (Apple / Android)

## I. Accessibility (VoiceOver / TalkBack)

| Regel | iOS (SwiftUI/UIKit) | Android (Compose/View) |
|---|---|---|
| Interaktive Elemente brauchen Label | `.accessibilityLabel("...")` auf Icon-Buttons | `contentDescription` / `Modifier.semantics` |
| Dekoratives verstecken | `.accessibilityHidden(true)` | `importantForAccessibility="no"` / `clearAndSetSemantics {}` |
| Dynamic Type / Font-Scaling | System-Fonts oder `@ScaledMetric`; NIE fixe `.font(.system(size: 14))` ohne `relativeTo:` | `sp` fuer Text (nie `dp`), `fontScale` testen |
| Touch-Targets | >= 44x44 pt | >= 48x48 dp |
| Gruppierung | `.accessibilityElement(children: .combine)` fuer Karten | `mergeDescendants = true` |
| Status-Aenderungen ansagen | `UIAccessibility.post(notification: .announcement, ...)` / `AccessibilityNotification` | `announceForAccessibility` / Live-Region |
| Reduced Motion | `@Environment(\.accessibilityReduceMotion)` respektieren | `Settings.Global.ANIMATOR_DURATION_SCALE` |

**Audit-Signal:** Icon-only Button ohne Label, Text mit hartkodierter Pixel-Groesse, Custom-Gesten ohne Alternative.

## II. Security (Storage, Transport, Deep Links, Privacy)

**Storage:**
- Tokens/Credentials NIE in `UserDefaults` / `SharedPreferences` — Keychain (iOS) / EncryptedSharedPreferences oder Keystore (Android)
- Kein Logging von Tokens/PII (`print`/`Log.d` mit Session-Daten = Finding)
- Secrets nicht in `Info.plist`, `strings.xml`, oder im Bundle — Build-Time-Injection oder Backend-Proxy

**Transport:**
- ATS (iOS) nicht global deaktiviert (`NSAllowsArbitraryLoads=true` = Critical ohne Begruendung)
- `usesCleartextTraffic` (Android) nicht true in Release
- Certificate Pinning fuer Auth-/Payment-Endpoints erwaegen (medium confidence Finding wenn fehlt)

**Deep Links / Intents:**
- Eingehende URLs/Intents validieren bevor Navigation oder Aktion (Deep-Link-Hijacking)
- `exported=true` Activities/Services (Android) brauchen Permission oder Input-Validierung
- Universal Links statt Custom-Schemes fuer sensitive Flows

**Privacy:**
- `PrivacyInfo.xcprivacy` vorhanden und aktuell (App-Store-Pflicht) — Required-Reason-APIs deklariert
- Permission-Requests mit Usage-Description (`NSCameraUsageDescription` etc.) — fehlende Description = Crash bei Review
- Android: `AndroidManifest`-Permissions minimal, runtime-Permissions mit Rationale

## III. Performance (Main Thread, Memory, Lists)

- **Main Thread:** Netzwerk/Disk/Parsing NIE synchron auf dem Main Thread. iOS: async/await oder Background-Queue. Android: Coroutines mit `Dispatchers.IO`. Audit-Signal: `try! Data(contentsOf:)`, synchrone DB-Calls im ViewModel-Init.
- **Retain Cycles (iOS):** `[weak self]` in escaping Closures die self referenzieren; Delegates als `weak`. Audit-Signal: Closure-Property die self captured ohne weak/unowned.
- **Memory Leaks (Android):** Kein Activity/Context-Halten in Singletons/Companion Objects; `viewLifecycleOwner` statt `this` fuer Fragment-Observer.
- **Listen:** `LazyVStack`/`List` (SwiftUI), `LazyColumn` (Compose), `RecyclerView` mit ViewHolder — nie alle Items eager rendern. Stable IDs fuer Diffing.
- **Bilder:** Downsampling vor Anzeige (kein 4000px-Foto in 100pt-Thumbnail), Caching (Kingfisher/Coil/Glide statt Eigenbau).
- **App-Start:** Kein Blocking-Work in `application(didFinishLaunching)` / `Application.onCreate` — deferren was nicht fuer den ersten Frame noetig ist.

## IV. UI-Konventionen (HIG / Material)

- **Plattform-Idiome respektieren:** iOS-Back-Swipe nicht brechen, Android-Back-Button/Gesture korrekt behandeln (Predictive Back ab API 34).
- **Navigation:** iOS: NavigationStack/TabView-Konventionen. Android: Jetpack Navigation, Up vs Back unterscheiden.
- **System-Komponenten vor Eigenbau:** Native Date-Picker, Share-Sheets, Context-Menus — Eigenbau nur mit Begruendung.
- **Safe Areas / Insets:** Notch, Dynamic Island, Gesture-Bars — `safeAreaInset` / `WindowInsets` korrekt, kein Content unter System-UI.
- **Dark Mode:** Semantic Colors (`Color.primary`, `?attr/colorOnSurface`) statt Hex-Werte; beide Modi getestet.
- **Haptics:** Sparsam, systemkonform (`UIImpactFeedbackGenerator` / `HapticFeedback`), nie in Loops.

## V. i18n & Typography nativ

- Strings in `Localizable.strings`/`String Catalog` (iOS) bzw. `strings.xml` (Android) — hartkodierte UI-Strings im Code sind Findings (gleiche Regel wie Web, code-quality.md VI)
- Plurals via `stringsdict` / `plurals` — nie `count == 1 ? "Gast" : "Gaeste"` im Code
- Typografische Zeichen gelten auch nativ (typography.md): echte Apostrophe, Ellipsen, Anfuehrungszeichen in den String-Files
- Layout muss mit 1.5x Font-Scale und langen Uebersetzungen (DE!) funktionieren — abgeschnittene Labels = Finding

## VI. Release-Hygiene

- Debug-Flags/Logging in Release-Builds deaktiviert (`#if DEBUG` / `BuildConfig.DEBUG` Guards)
- Keine Test-/Staging-URLs im Release-Bundle
- Version/Build-Nummer-Bump im Diff wenn Release-PR
- ProGuard/R8 (Android): Rules fuer Reflection-genutzte Klassen aktuell

## VII. Audit-Checkliste

| Check | Schweregrad |
|---|---|
| Token/PII in UserDefaults/SharedPreferences | Critical |
| `NSAllowsArbitraryLoads=true` / `usesCleartextTraffic=true` ohne Begruendung | Critical |
| Icon-Button ohne accessibilityLabel/contentDescription | Important |
| Synchrone IO auf Main Thread | Important |
| Retain Cycle (Closure ohne weak self) | Important |
| Hartkodierte UI-Strings statt Localizable/strings.xml | Important |
| Fixe Font-Groesse ohne Dynamic-Type-Support | Important |
| `exported=true` ohne Validierung (Android) | Important |
| Fehlende Permission-Usage-Description | Important |
| Eager-Rendering langer Listen | Important |
| Hex-Farben statt Semantic Colors (Dark Mode kaputt) | Minor |
| Eigenbau-Komponente wo System-Komponente existiert | Minor |

## VIII. Deprecated APIs (Apple / Android)

Apple deprecated jede WWDC aggressiv; der App Store erzwingt Builds mit aktuellem SDK. Veraltete API-Nutzung ist daher ein echtes Finding — aber mit Halluzinations-Schutz:

**Verifikations-Regel (PFLICHT):**
- Deprecation-Findings bekommen IMMER ein Confidence-Label
- `high` nur wenn die Deprecation sicher bekannt ist (lange deprecated, prominent dokumentiert)
- Bei `medium`/`low`: VOR dem Melden via context7 oder Apple/Android-Doku verifizieren. Nicht verifizierbar → NICHT melden
- NIE eine Deprecation auto-fixen ohne Verifikation — falsche "Modernisierung" ist schlimmer als alte API

**Schweregrad:**
- Minor: deprecated, kompiliert aber noch ohne Termin
- Important: Removal angekuendigt, SDK-Mindestversion betroffen, oder Xcode warnt im Build

**Stabile Beispiele (Muster, keine erschoepfende Liste — Listen veralten selbst):**

| Veraltet | Ersatz |
|---|---|
| `NavigationView` | `NavigationStack` / `NavigationSplitView` (iOS 16+) |
| `UIScreen.main` | `view.window.windowScene.screen` / Trait-basiert |
| `UIApplication.shared.keyWindow` | `windowScene.keyWindow` |
| `.onChange(of:) { value in }` (1-Param) | 2-Param-Signatur `{ old, new in }` (iOS 17+) |
| `.foregroundColor()` | `.foregroundStyle()` |
| `CTCarrier` | entfernt ohne Ersatz (iOS 16+) |
| `AsyncTask` (Android) | Kotlin Coroutines |
| `startActivityForResult` | Activity Result API |
| `Handler()` ohne Looper | `Handler(Looper.getMainLooper())` |

**Audit-Prozedur:** Beim Lesen nativer Files auf bekannte deprecated Patterns achten. Build-Logs (falls im Diff/Projekt vorhanden) nach Deprecation-Warnings greppen — die sind deterministisch und brauchen keine Verifikation.
