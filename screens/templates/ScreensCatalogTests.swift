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

    func test_screensCatalog() throws {
        guard let manifestPath = env["SCREENS_MANIFEST_PATH"],
              let manifestData = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        else {
            XCTFail("SCREENS_MANIFEST_PATH missing or unreadable (set as TEST_RUNNER_SCREENS_MANIFEST_PATH on the xcodebuild invocation)")
            return
        }
        guard let shotDir = env["SCREENSHOT_DIR"] else {
            XCTFail("SCREENSHOT_DIR missing (set as TEST_RUNNER_SCREENSHOT_DIR on the xcodebuild invocation)")
            return
        }

        let configPath = env["SCREENS_CONFIG_PATH"]
        let configData = configPath.flatMap { FileManager.default.contents(atPath: $0) }
        let config = configData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
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

            for state in states {
                for role in roles {
                    var args = launchPrefix
                    if let seed = seeds[state] { args += [seedFlag, seed] }
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
    /// `swipe_down`. `label` matches by accessibility label prefix (mirrors
    /// `UITestLauncher.openTab`'s BEGINSWITH pattern, needed because
    /// SwiftUI's `Tab` modifier does not propagate `.accessibilityIdentifier`
    /// down to the UITabBar button on iOS 26).
    private func perform(steps: [[String: String]], in app: XCUIApplication) {
        for step in steps {
            guard let action = step["action"] else { continue }
            let label = step["label"] ?? ""
            switch action {
            case "tap_tab":
                let button = app.tabBars.firstMatch.buttons.matching(
                    NSPredicate(format: "label BEGINSWITH %@", label)
                ).firstMatch
                if button.waitForExistence(timeout: 10) { button.tap() }
            case "tap":
                let element = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@", label)
                ).firstMatch
                if element.waitForExistence(timeout: 10), element.isHittable { element.tap() }
            case "wait":
                _ = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@", label)
                ).firstMatch.waitForExistence(timeout: 10)
            case "type":
                let field = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@", label)
                ).firstMatch
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
