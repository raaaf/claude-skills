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
- IX. Test Runner & Test Determinism (iOS)
- X. SwiftUI Accessibility (a11y)
- XI. Async SwiftUI Views: Loading, Error, Empty State (Mandatory)
- XII. Lock State on Secondary Surfaces (Widget, Notification, Watch)
- XIII. Cancellation Before Persisting Side Effects (Swift Concurrency)
- XIV. Day Boundary: State That Outlives the Screen
- XV. Prove an Animation Renders Before Tuning It

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

**A red test is not a signal until the build is demonstrably fresh.** Hit twice in a single run (2026-07-27): a test bundle built before the fix still fails, and the failure reads exactly like an unfixed bug. Before treating any failure as real, confirm the run rebuilt — no `Building for testing` output, or a fix timestamp newer than the bundle, means re-run first and diagnose second. Same for the inverse: a test file created after the last build is not in the bundle and its absence looks like "passed".

**Hold the run's test COUNT against the expected count, every time.** A crashed or skipped suite reports FEWER failures, not more, so a silent runner problem reads as improvement. Note the number from the previous green run and compare; a drop with no deletions in the diff is a defect in the run, not a success.

**Untyped integer literals where `TimeInterval?`/`Double?` is expected (Swift).** `let gap: TimeInterval? = 20` is fine, but an untyped `20` handed to a parameter or comparison that infers `Int` silently changes the semantics, and the mismatch surfaces at runtime or as a puzzling test failure rather than at compile time. Give the literal an explicit type (`20.0`, `TimeInterval(20)`) wherever the target is an optional Double. Seen 2x in one file.

**MainActor isolation on `static` helpers extracted from SwiftUI `View` types.** A pure function pulled out of a `@MainActor` type inherits that isolation, so a `@Test` calling it from a nonisolated context fails to compile — and if the helper is reached through a Swift Testing trait, the runner can crash (`_applyScopingTraits`) and mask the whole suite as "fewer failures". Extracted pure helpers get `nonisolated static`; if it genuinely needs the main actor, it was not pure and does not belong in a unit test.

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

## XIV. Day Boundary: State That Outlives the Screen

**The most frequent correctness class in this project's history — five findings, never a guideline until now.** Precedents: `reminderHour = 0` treated as "not set" (2026-05-21), a widget lock deadline compared against build time (2026-06-23), a pending-anchor dead end at midnight (2026-07-22), sleep samples bucketed before overlapping intervals were merged so a night ending at 00:30 landed in the wrong day (2026-07-27 morning), a `chatStep` that survived the day change because the view was never rebuilt (2026-07-27 evening). Each was found on its own, filed as a one-off, and the class never escalated.

Every value that is read again after a relaunch, after a background stretch, or when a view reappears gets one question: **does it survive midnight, and should it?**

- **A "today" flag must be a DATE, not a Bool.** `hasPlayedToday = true` is yesterday's answer at 00:01. Store the day and compare.
- **A deadline is compared against the entry's own moment,** never against "now at build time" (see section XII).
- **A view that is not rebuilt keeps its state across the day change.** SwiftUI does not re-run `init` because the calendar moved. If a layout or routing rule reads such state, play the midnight case through explicitly: app open at 23:59, screen untouched, what does the rule return at 00:01?
- **Bucketing by day happens AFTER merging/normalizing,** not before. An interval that crosses midnight belongs to a rule you have written down, not to whichever end the code happens to look at first.
- **Zero and midnight are real values, not "unset".** Any `if value == 0` / `if hour == 0` on a time-of-day quantity is suspect: model absence as optional.
- **The overnight background case is separate from the relaunch case.** A process that stays alive across midnight never runs the launch-time recomputation that would have saved it.

Confidence: a day-scoped flag stored as a Bool -> Important. A layout/routing rule reading state that outlives its view, with no midnight handling -> Important. Day bucketing before interval merge -> Critical when it feeds a user-visible number.

### The fix side: what your rollover destroys

Everything above is the AUDIT side, and it was written after five findings. Two more arrived on 2026-08-13, and the second one is the reason this subsection exists.

**Sixth case, the continuously-foregrounded path.** A digest gate rescheduled its recheck timer only while the gate was closed. Once it opened, no timer ran for the rest of the night. Backgrounding or relaunching triggered a day reset, so the bug was invisible in every normal test; an app simply left open past midnight kept yesterday's step forever. The bullet above ("a process that stays alive across midnight never runs the launch-time recomputation") named the class, but nobody had walked the specific path where the recomputation is scheduled and then stops scheduling itself.

**Seventh case, and it was the FIX for the sixth.** The repair added a midnight-aware timer that reran the setup path. It could now fire while the user was mid-sentence in the composer: the reset cleared the pending recap and hid the input, defeating a documented cross-midnight protection elsewhere in the same file and dating the in-progress entry to the new day. The fix was strictly worse than the bug, and only the fix-verifier caught it.

So the rule has a second half, and it belongs to whoever writes the fix, not to whoever finds the bug:

- **A midnight reset needs a definition of "busy".** Before adding one, enumerate the in-progress states on that screen: unsaved input, an active edit of existing content, an open sheet, a playback in progress. Derive "busy" from the code, not from a guess, and name which state you used.
- **Defer, never skip.** A reset suppressed while busy must run once the work is committed or abandoned, otherwise the original bug is back in a narrower window. Point at the exact place where the deferred reset fires.
- **The protection may already exist somewhere else.** Before writing a new guard, grep the persistence path: a cross-midnight correction in the save function is a contract your reset can violate from the outside. Defer to it rather than duplicating it.
- **Check that exactly one timer is alive.** A self-rescheduling task plus a lifecycle observer that also schedules is the standard way to end up with two, and the second one is invisible until it fires at the wrong moment.

Confidence: a newly added rollover, reset or scheduled recomputation that can fire during an unsaved user action -> Critical when text or an entry's date is at stake, Important otherwise. This is the class the audit's own fix agents have now produced once; `agents/fix-agent.md` completion self-check 4 is the pre-flight for it.

## XV. Prove an Animation Renders Before Tuning It

Three consecutive rounds were spent adjusting the values of an animation that never ran (2026-07-27): a scale factor, then a sequenced swap, then a keyboard delay, each time reported as "I don't see it". The cause was structural, not aesthetic — the start state was set and overwritten inside the same main-actor cycle, so SwiftUI never rendered a frame with it. Two of the three rounds were value tuning on a no-op.

Order of questions, and it is not negotiable: **does it run at all** before **is it strong enough**.

- `withAnimation` on a value that is assigned and reassigned within one cycle animates nothing. The start state needs its own render pass (a `Task { }` hop, an explicit `await Task.yield()`, or a two-phase state machine).
- Before proposing new values for an existing animation, name the evidence that the current one renders: a visible intermediate state, a screenshot, a test on the state sequence. "The code says `withAnimation`" is not evidence.
- Same trap with a transition on a view that is inserted and removed in one pass, and with `.onAppear` setting the state it is supposed to animate from.

Confidence: animation whose start state cannot be observed in a rendered frame -> Important (it is dead code with a cost). A finding that proposes only new VALUES for an animation, with no statement that it currently renders -> the reviewer sends it back rather than fixing it.
