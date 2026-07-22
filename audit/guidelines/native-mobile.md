---
applies_to: \.(swift|kt|kts|dart|m|mm|h)$|/(ios|android)/|\.xcodeproj|\.pbxproj$|/values[^/]*/|\.lproj/|Podfile|build\.gradle
priority: mandatory
---

# Native Mobile Guidelines (iOS / Android / React Native / Flutter)

Platform-specific audit rules for native and cross-platform apps. Only relevant when `FRAMEWORK` = ios, android, react-native, or flutter. Web equivalents (WCAG/ARIA, CSP, INP) do NOT apply there — this file replaces them.

## Contents
- I. Accessibility (VoiceOver / TalkBack)
- II. Security (Storage, Transport, Deep Links, Privacy)
- III. Performance (Main Thread, Memory, Lists)
- IV. UI Conventions (HIG / Material)
- V. Native i18n & Typography
- VI. Release Hygiene
- VII. Audit Checklist
- VIII. Deprecated APIs (Apple / Android)

## I. Accessibility (VoiceOver / TalkBack)

| Rule | iOS (SwiftUI/UIKit) | Android (Compose/View) |
|---|---|---|
| Interactive elements need a label | `.accessibilityLabel("...")` on icon buttons | `contentDescription` / `Modifier.semantics` |
| Hide decorative elements | `.accessibilityHidden(true)` | `importantForAccessibility="no"` / `clearAndSetSemantics {}` |
| Dynamic Type / font scaling | system fonts or `@ScaledMetric`; NEVER fixed `.font(.system(size: 14))` without `relativeTo:` | `sp` for text (never `dp`), test `fontScale` |
| Touch targets | >= 44x44 pt | >= 48x48 dp |
| Grouping | `.accessibilityElement(children: .combine)` for cards | `mergeDescendants = true` |
| Announce status changes | `UIAccessibility.post(notification: .announcement, ...)` / `AccessibilityNotification` | `announceForAccessibility` / live region |
| Reduced Motion | respect `@Environment(\.accessibilityReduceMotion)` | `Settings.Global.ANIMATOR_DURATION_SCALE` |
| Range controls (Stepper/Slider/Custom Counter) | `.accessibilityAdjustableAction` with a step size that scales with the UI range — for a range of 1-999, a fixed step of 1 is unusable (999 swipes); tie the step size to visible increments or ~5% of the range | `ProgressBarRangeInfo` / `Modifier.progressSemantics`, `stateDescription` with the current value |

**Audit signal:** icon-only button without a label, text with a hardcoded pixel size, custom gestures without an alternative, adjustable control with a fixed step of 1 on a large range.

## II. Security (Storage, Transport, Deep Links, Privacy)

**Storage:**
- Tokens/credentials NEVER in `UserDefaults` / `SharedPreferences` — Keychain (iOS) / EncryptedSharedPreferences or Keystore (Android)
- No logging of tokens/PII (`print`/`Log.d` with session data = finding)
- Secrets not in `Info.plist`, `strings.xml`, or in the bundle — build-time injection or backend proxy

**Transport:**
- ATS (iOS) not globally disabled (`NSAllowsArbitraryLoads=true` = Critical without justification)
- `usesCleartextTraffic` (Android) not true in release
- Consider certificate pinning for auth/payment endpoints (medium confidence finding if missing)

**Deep Links / Intents:**
- Validate incoming URLs/intents before navigation or action (deep-link hijacking)
- `exported=true` activities/services (Android) need a permission or input validation
- Universal Links instead of custom schemes for sensitive flows

**Privacy:**
- `PrivacyInfo.xcprivacy` present and up to date (App Store requirement) — required-reason APIs declared
- Permission requests with a usage description (`NSCameraUsageDescription` etc.) — missing description = crash on review
- Android: `AndroidManifest` permissions minimal, runtime permissions with rationale

## III. Performance (Main Thread, Memory, Lists)

- **Main Thread:** network/disk/parsing NEVER synchronous on the main thread. iOS: async/await or a background queue. Android: coroutines with `Dispatchers.IO`. Audit signal: `try! Data(contentsOf:)`, synchronous DB calls in ViewModel init.
- **Retain Cycles (iOS):** `[weak self]` in escaping closures that reference self; delegates as `weak`. Audit signal: a closure property that captures self without weak/unowned.
- **Memory Leaks (Android):** don't hold an Activity/Context in singletons/companion objects; use `viewLifecycleOwner` instead of `this` for fragment observers.
- **Lists:** `LazyVStack`/`List` (SwiftUI), `LazyColumn` (Compose), `RecyclerView` with ViewHolder — never eager-render all items. Stable IDs for diffing.
- **Images:** downsample before display (no 4000px photo in a 100pt thumbnail), caching (Kingfisher/Coil/Glide instead of a homegrown solution).
- **App Start:** no blocking work in `application(didFinishLaunching)` / `Application.onCreate` — defer anything not needed for the first frame.

## IV. UI Conventions (HIG / Material)

- **Respect platform idioms:** don't break the iOS back-swipe, handle the Android back button/gesture correctly (Predictive Back from API 34).
- **Navigation:** iOS: NavigationStack/TabView conventions. Android: Jetpack Navigation, distinguish Up vs Back.
- **System components over custom builds:** native date pickers, share sheets, context menus — a custom build needs justification.
- **Safe Areas / Insets:** notch, Dynamic Island, gesture bars — `safeAreaInset` / `WindowInsets` correct, no content under system UI.
- **Dark Mode:** semantic colors (`Color.primary`, `?attr/colorOnSurface`) instead of hex values; both modes tested.
- **Haptics:** sparingly, system-compliant (`UIImpactFeedbackGenerator` / `HapticFeedback`), never in loops.

## V. Native i18n & Typography

- Strings in `Localizable.strings`/`String Catalog` (iOS) or `strings.xml` (Android) — hardcoded UI strings in code are findings (same rule as web, code-quality.md VI)
- Plurals via `stringsdict` / `plurals` — never `count == 1 ? "guest" : "guests"` in code
- Typographic characters apply natively too (typography.md): real apostrophes, ellipses, quotation marks in the string files
- Layout must work with 1.5x font scale and long translations (German!) — truncated labels = finding

## VI. Release Hygiene

- Debug flags/logging disabled in release builds (`#if DEBUG` / `BuildConfig.DEBUG` guards)
- No test/staging URLs in the release bundle
- Version/build number bump in the diff for a release PR
- ProGuard/R8 (Android): rules for reflection-used classes up to date

## VII. Audit Checklist

| Check | Severity |
|---|---|
| Token/PII in UserDefaults/SharedPreferences | Critical |
| `NSAllowsArbitraryLoads=true` / `usesCleartextTraffic=true` without justification | Critical |
| Icon button without accessibilityLabel/contentDescription | Important |
| Synchronous IO on the main thread | Important |
| Retain cycle (closure without weak self) | Important |
| Hardcoded UI strings instead of Localizable/strings.xml | Important |
| Fixed font size without Dynamic Type support | Important |
| `exported=true` without validation (Android) | Important |
| Missing permission usage description | Important |
| Eager rendering of long lists | Important |
| Hex colors instead of semantic colors (Dark Mode broken) | Minor |
| Custom component where a system component exists | Minor |

## VIII. Deprecated APIs (Apple / Android)

Apple deprecates aggressively at every WWDC; the App Store enforces builds with the current SDK. Outdated API usage is therefore a real finding — but with hallucination protection:

**Verification rule (MANDATORY):**
- Deprecation findings ALWAYS get a confidence label
- `high` only when the deprecation is reliably known (long deprecated, prominently documented)
- For `medium`/`low`: verify via context7 or Apple/Android docs BEFORE reporting. Not verifiable → DO NOT report
- NEVER auto-fix a deprecation without verification — a wrong "modernization" is worse than an old API

**Severity:**
- Minor: deprecated, but still compiles with no removal date
- Important: removal announced, minimum SDK version affected, or Xcode warns in the build

**Stable examples (patterns, not an exhaustive list — lists go stale themselves):**

| Deprecated | Replacement |
|---|---|
| `NavigationView` | `NavigationStack` / `NavigationSplitView` (iOS 16+) |
| `UIScreen.main` | `view.window.windowScene.screen` / trait-based |
| `UIApplication.shared.keyWindow` | `windowScene.keyWindow` |
| `.onChange(of:) { value in }` (1-param) | 2-param signature `{ old, new in }` (iOS 17+) |
| `.foregroundColor()` | `.foregroundStyle()` |
| `CTCarrier` | removed without replacement (iOS 16+) |
| `AsyncTask` (Android) | Kotlin Coroutines |
| `startActivityForResult` | Activity Result API |
| `Handler()` without Looper | `Handler(Looper.getMainLooper())` |

**Audit procedure:** watch for known deprecated patterns when reading native files. Grep build logs (if present in the diff/project) for deprecation warnings — these are deterministic and need no verification.

## IX. Test Runner & Test Determinism (iOS)

Native test suites have two pitfalls that an audit can misread as "tests missing" or "test failing":

**Swift Testing vs. XCTest when filtering.** `xcodebuild ... -only-testing:Target/Class` matches ONLY XCTest classes/methods, NOT Swift Testing `@Test` functions. A mixed suite can therefore report "all tests ran" even though the `@Test` cases were skipped. Two consequences for the audit:
- The `xcodebuild` summary `Executed N tests` counts only XCTest. Swift Testing reports separately as `✔ Test run with N tests in M suites passed`. Check both lines, otherwise a 117-case suite looks like 7 tests.
- To isolate individual Swift Testing cases, use `swift test --filter` or a test plan, not `-only-testing`.

**On-device model-dependent tests (FoundationModels / Apple Intelligence).** Tests whose code path calls the on-device model (e.g. on certain weekdays/conditions) are non-deterministic on devices/simulators WITH the model available. Correct fix: disable the model tier via an environment variable/launch flag (e.g. `JOURNAL_NO_AI=1`) and test the deterministic fallback (curated rotation) in isolation.
- **Do not** add such a test as "flaky" to `suppressions.json` if an env flag already makes it deterministic — that masks real regressions. Check the harness first (does the suite run with the disable flag?) before suggesting a flaky suppression.

## X. SwiftUI Accessibility (a11y)

- **Hide decorative image elements:** every purely decorative SwiftUI `Image` / `Image(systemName:)` / icon glyph in buttons, labels, or cards needs `.accessibilityHidden(true)`, otherwise VoiceOver reads out the SF Symbol name ("chevron right", "books vertical") as content. The accompanying text labels carry the meaning. In `accessibilityElement(children: .combine)` groups, hide the chevron BEFORE the `.combine`.
- **Respect Reduce Motion:** every continuous animation (`TimelineView(.animation)`, `withAnimation(...repeatForever)`, persistent offset/rotation loops) checks `@Environment(\.accessibilityReduceMotion)` and pauses or renders statically (e.g. `TimelineView(.animation(paused: reduceMotion))` + `t = reduceMotion ? 0 : context.date...`). Reduce position-based transitions under Reduce Motion to pure opacity. Decorative endless animations additionally get `.accessibilityHidden(true)`.
- Confidence: decorative icon without `accessibilityHidden` or continuous animation without an RM check demonstrable in the diff -> Important.

## XI. Async SwiftUI Views: Loading, Error, Empty State (Mandatory)

Every SwiftUI view that loads data asynchronously (`.task`, `await` fetch) needs all three states EXPLICITLY:

- **Loading state:** a visible indicator (ProgressView/placeholder) while the fetch is running, instead of a silent delay.
- **Error/offline state:** `try?` without UI feedback is a finding. On failure, show a subtle notice (+ retry if applicable). Do not silently show a fallback without signaling the state to the user.
- **Empty state:** an empty result (0 items) shows a message (+ a next-step/CTA if applicable), never an unexplained blank area.

Confidence: any of the three states demonstrably missing in an async view -> Important.

## XII. Lock State on Secondary Surfaces (Widget, Notification, Watch)

Recurring finding across three audits (2026-05-16, 2026-06-11, 2026-06-23): a widget, notification or watch surface reads the app-lock state ONCE, at build or render time, and then keeps showing protected content after the lock has since engaged.

The lock is time-based (a deadline after backgrounding), so a point-in-time read is structurally wrong. These processes never see the foreground lock event.

- A timeline/snapshot provider must evaluate the lock against the **entry's own date**, not against "now at build time", and it must emit an additional future entry at the lock deadline so the system swaps to the hidden state on its own.
- A notification whose body carries protected content must be re-evaluated or redacted when scheduled far ahead.
- The read-only bridge (`AppLockBridge` pattern) is the only correct source in extension contexts; a copy of the lock logic in the extension drifts.

Confidence: a secondary surface that renders protected content and reads the lock state only once -> Important. Same surface with no lock check at all -> Critical.

## XIII. Cancellation Before Persisting Side Effects (Swift Concurrency)

Recurring finding (two audits): inside a cancellable `Task`, a persisting side effect (`context.insert`, `context.save`, a file write, a network POST) runs after an `await` without checking whether the task was cancelled in the meantime. The user has long since navigated away, changed the setting, or triggered a newer run, and a stale value still lands in the store.

- Before every `insert` / `save` / persisting side effect that sits behind an `await` in a cancellable task: `try Task.checkCancellation()` or an equivalent guard.
- The deliberate exception is the case where the write MUST survive the view (e.g. persisting a generated result the user already waited for). Then the write goes BEFORE the cancellation check and a comment says why. Everything after that check is view-bound afterplay only.
- Watch for a task that is replaced by a newer one (`task?.cancel(); task = Task { ... }`): the old one keeps running to its next suspension point.

Confidence: persisting write behind an `await` in a cancellable task without a guard and without a justifying comment -> Important.
