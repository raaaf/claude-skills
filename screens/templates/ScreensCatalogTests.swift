import XCTest

/// Screenshot catalog for /screens (stage d, iOS + macOS). Reads
/// `.screens/manifest.json` at runtime and captures one PNG per
/// (entry, state, role) instead of hard-coding entries (repo CLAUDE.md
/// "Reviewer: every generated driver must read the manifest at runtime
/// instead of hard-coding entries"). Instantiated verbatim into the
/// project's UI test target by the Phase 2 scaffold
/// (`screens/references/platform-apple.md`); never edited per project.
///
/// Env contract, set on the xcodebuild invocation with a `TEST_RUNNER_`
/// prefix (platform-apple.md); Xcode strips that prefix before the test
/// process sees the variable (verified against `ScreenshotTourTests.swift`'s
/// own `SCREENSHOT_DIR`/`SCREENSHOT_VARIANT`: the invocation sets
/// `TEST_RUNNER_SCREENSHOT_DIR`, the test reads `SCREENSHOT_DIR`), so every
/// name below is read WITHOUT the prefix:
///   SCREENS_MANIFEST_PATH  absolute path to .screens/manifest.json
///   SCREENS_CONFIG_PATH    absolute path to .screens/config.json
///   SCREENS_ENTRIES        comma-separated entry ids to capture this run
///                          (stale-entry filter, see platform-apple.md
///                          "Filtering"); empty/unset = every entry for
///                          this platform
///   SCREENSHOT_DIR         host dir PNGs are written into (topf-secret's
///                          own convention)
///   SCREENS_THEME          "light"|"dark", informational only: the
///                          simulator's real appearance is set once per
///                          xcodebuild invocation via `simctl ui <udid>
///                          appearance` BEFORE this test runs, not by this
///                          file (platform-apple.md)
///   SCREENS_VIEWPORT_ID    device-class key for the filename (e.g.
///                          "iphone", "mac"); defaults per platform below
///   SCREENS_PROJECT_ROOT   absolute project root, used to expand a
///                          `${PROJECT_ROOT}` placeholder in manifest/config
///                          string values (e.g. a fixture path in
///                          `launch_args`, config-schema.md); unset expands
///                          to the empty string, so an unconfigured pilot
///                          simply leaves the placeholder unresolved rather
///                          than crashing
///
/// Per-entry manifest overrides (optional, in addition to `seeds`/`steps`):
///   `launch_args`  full launch-argument override (replaces
///                  `launch_args_prefix` + seed entirely), for a flow that
///                  needs its own master switch (e.g. topf-secret's
///                  `-UITestWelcome`)
///   `extra_args`   appended after the normal prefix + seed args (e.g.
///                  topf-secret's `-UITestReviewState`)
final class ScreensCatalogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    #if os(macOS)
    private let platformName = "macos"
    private let defaultViewportId = "mac"
    #else
    private let platformName = "ios"
    private let defaultViewportId = "iphone"
    #endif

    /// `${PROJECT_ROOT}` placeholder (config-schema.md): expands to
    /// `SCREENS_PROJECT_ROOT`, recursing through the whole parsed JSON tree
    /// once so every field (launch_args, extra_args, steps text/id/label,
    /// fixture paths) expands without a per-field call. An unknown `${X}`
    /// placeholder is left untouched.
    private func expandProjectRoot(_ value: Any, root: String) -> Any {
        if let s = value as? String {
            return s.replacingOccurrences(of: "${PROJECT_ROOT}", with: root)
        }
        if let arr = value as? [Any] {
            return arr.map { expandProjectRoot($0, root: root) }
        }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = expandProjectRoot(v, root: root) }
            return out
        }
        return value
    }

    func test_screensCatalog() throws {
        let projectRoot = env["SCREENS_PROJECT_ROOT"] ?? ""
        guard let manifestPath = env["SCREENS_MANIFEST_PATH"],
              let manifestData = FileManager.default.contents(atPath: manifestPath),
              let rawManifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        else {
            XCTFail("SCREENS_MANIFEST_PATH missing or unreadable (set as TEST_RUNNER_SCREENS_MANIFEST_PATH on the xcodebuild invocation)")
            return
        }
        let manifest = (expandProjectRoot(rawManifest, root: projectRoot) as? [String: Any]) ?? rawManifest
        guard let shotDir = env["SCREENSHOT_DIR"] else {
            XCTFail("SCREENSHOT_DIR missing (set as TEST_RUNNER_SCREENSHOT_DIR on the xcodebuild invocation)")
            return
        }

        let configPath = env["SCREENS_CONFIG_PATH"]
        let configData = configPath.flatMap { FileManager.default.contents(atPath: $0) }
        let rawConfig = configData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let config = (expandProjectRoot(rawConfig, root: projectRoot) as? [String: Any]) ?? rawConfig
        let platformConfig = config[platformName] as? [String: Any] ?? [:]
        let launchPrefix = (platformConfig["launch_args_prefix"] as? [String]) ?? ["-UITests"]
        let seedFlag = (platformConfig["seed_flag"] as? String) ?? "-UITestSeed"
        let fixedDate = platformConfig["fixed_date"] as? String

        let allEntries = (manifest["entries"] as? [[String: Any]] ?? [])
            .filter { ($0["platform"] as? String) == platformName }
        let requestedIds = Set((env["SCREENS_ENTRIES"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let entries = requestedIds.isEmpty
            ? allEntries
            : allEntries.filter { requestedIds.contains(($0["id"] as? String) ?? "") }

        let theme = env["SCREENS_THEME"] ?? "light"
        let viewportId = env["SCREENS_VIEWPORT_ID"] ?? defaultViewportId

        for entry in entries {
            guard let id = entry["id"] as? String else { continue }
            let states = (entry["states"] as? [String]) ?? ["filled"]
            let roles = (entry["roles"] as? [String]) ?? ["guest"]
            let steps = (entry["steps"] as? [[String: String]]) ?? []
            let seeds = (entry["seeds"] as? [String: String]) ?? [:]
            let launchArgsOverride = entry["launch_args"] as? [String]
            let extraArgs = (entry["extra_args"] as? [String]) ?? []

            for state in states {
                for role in roles {
                    var args = launchArgsOverride ?? launchPrefix
                    if launchArgsOverride == nil, let seed = seeds[state] { args += [seedFlag, seed] }
                    args += extraArgs
                    if let fixedDate { args += ["-ScreensFixedDate", fixedDate] }

                    let app = XCUIApplication()
                    app.launchArguments = args
                    app.launch()

                    perform(steps: steps, in: app)
                    capture(app: app, id: id, state: state, role: role, viewportId: viewportId, theme: theme, dir: shotDir)

                    app.terminate()
                }
            }
        }
    }

    // MARK: - Step vocabulary

    /// Minimal, generic navigation vocabulary a discoverer can target
    /// without knowing this file: `tap_tab`/`tap`/`wait`/`type`/`swipe_up`/
    /// `swipe_down`. Every step targeting an element takes either `label`
    /// (accessibility-label prefix match, mirrors `UITestLauncher.openTab`'s
    /// BEGINSWITH pattern, needed because SwiftUI's `Tab` modifier does not
    /// propagate `.accessibilityIdentifier` down to the UITabBar button on
    /// iOS 26) or `id` (exact `.accessibilityIdentifier` match, for an
    /// element whose stable identifier is not its visible text, e.g.
    /// topf-secret's `cookButton`).
    private func matchElement(_ app: XCUIApplication, _ step: [String: String]) -> XCUIElement {
        if let id = step["id"] {
            return app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", step["label"] ?? "")
        ).firstMatch
    }

    private func perform(steps: [[String: String]], in app: XCUIApplication) {
        for step in steps {
            guard let action = step["action"] else { continue }
            switch action {
            case "tap_tab":
                let button = app.tabBars.firstMatch.buttons.matching(
                    NSPredicate(format: "label BEGINSWITH %@", step["label"] ?? "")
                ).firstMatch
                if button.waitForExistence(timeout: 10) { button.tap() }
            case "tap":
                let element = matchElement(app, step)
                // A step targeting a possibly-absent optional affordance
                // (`optional: "true"`) is skipped silently instead of
                // stalling the whole entry for 10s when it never appears
                // (e.g. a "Weiter" step advance loop run past the last step).
                let optional = step["optional"] == "true"
                if element.waitForExistence(timeout: optional ? 2 : 10), element.isHittable {
                    element.tap()
                }
            case "wait":
                _ = matchElement(app, step).waitForExistence(timeout: 10)
            case "type":
                let field = matchElement(app, step)
                if field.waitForExistence(timeout: 10) {
                    field.tap()
                    field.typeText(step["text"] ?? "")
                }
            case "swipe_up":
                app.swipeUp()
            case "swipe_down":
                app.swipeDown()
            default:
                break
            }
        }
        // Let the last transition/animation settle before capturing, same
        // margin as topf-secret's own ScreenshotTourTests.
        Thread.sleep(forTimeInterval: 0.8)
    }

    // MARK: - Capture

    /// Filename shape matches `screens.mjs`'s `parseCaptureFilename`
    /// (`<entryId>__<state>__<role>__<viewport>__<theme>.png`); `promote`
    /// maps `viewportId` to the device-class folder the same way the web
    /// driver's real viewport does (Output layout, config-schema.md).
    private func capture(app: XCUIApplication, id: String, state: String, role: String, viewportId: String, theme: String, dir: String) {
        #if os(macOS)
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let filename = "\(id)__\(state)__\(role)__\(viewportId)__\(theme).png"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("failed to write screenshot for \(id) (\(state)/\(role)): \(error)")
        }
    }
}
