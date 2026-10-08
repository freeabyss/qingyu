#if DEBUG
import Foundation

/// Launch argument constants for XCUITest hooks.
///
/// All `--uitest-*` arguments are parsed by `UITestSupport.parse()` and consumed
/// in `AppDelegate.applicationDidFinishLaunching`. The entire file is `#if DEBUG`
/// so Release builds contain zero hook code (review C-1).
enum UITestLaunchArg {
    static let resetOnboarding = "--uitest-reset-onboarding"
    static let markOnboardingCompleted = "--uitest-mark-onboarding-completed"
    static let mockScreenRecordingDenied = "--uitest-mock-screen-recording-denied"
    static let mockScreenRecordingAuthorized = "--uitest-mock-screen-recording-authorized"
    static let skipShortcuts = "--uitest-skip-shortcuts"
    static let trigger = "--uitest-trigger"
    static let dataDir = "--uitest-data-dir"
    static let largeText = "--uitest-large-text"
    static let skipScreenshotCapture = "--uitest-skip-screenshot-capture"
    /// Task 006：合成 N 个显示器拓扑供多屏叠层 UI 测试断言（后跟数量值）。
    static let screenshotDisplays = "--uitest-screenshot-displays"
}

/// Supported `--uitest-trigger` actions (design §5.5, cases.md §0.4).
enum UITestTriggerAction: String, CaseIterable {
    case openSearch
    case openClipboard
    case openSettings
    case openQuickLaunch
    case openAbout
    case openOnboarding
    case startScreenshot
}

/// Parsed launch arguments for UI testing.
///
/// Created once at app launch via `parse()` and stored on `AppDelegate`. When no
/// `--uitest-*` arguments are present, `isUITest` is `false` and all fields are
/// inert -- existing app behaviour is completely unchanged.
struct UITestSupport: Equatable {
    let resetOnboarding: Bool
    let markOnboardingCompleted: Bool
    let mockScreenRecordingDenied: Bool
    let mockScreenRecordingAuthorized: Bool
    let skipShortcuts: Bool
    let triggerAction: String?
    let dataDirPath: String?
    let largeText: Bool
    let skipScreenshotCapture: Bool

    /// `true` when any `--uitest-*` argument is present.
    var isUITest: Bool {
        resetOnboarding
            || markOnboardingCompleted
            || mockScreenRecordingDenied
            || mockScreenRecordingAuthorized
            || skipShortcuts
            || triggerAction != nil
            || dataDirPath != nil
            || largeText
            || skipScreenshotCapture
    }

    /// Resolved data-directory URL when `--uitest-data-dir <path>` is provided.
    var dataDirURL: URL? {
        guard let path = dataDirPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Validates the trigger action string against known values.
    var validatedTriggerAction: UITestTriggerAction? {
        guard let raw = triggerAction else { return nil }
        return UITestTriggerAction(rawValue: raw)
    }

    /// Parse launch arguments (defaults to `ProcessInfo.processInfo.arguments`).
    static func parse(arguments: [String] = ProcessInfo.processInfo.arguments) -> UITestSupport {
        UITestSupport(
            resetOnboarding: arguments.contains(UITestLaunchArg.resetOnboarding),
            markOnboardingCompleted: arguments.contains(UITestLaunchArg.markOnboardingCompleted),
            mockScreenRecordingDenied: arguments.contains(UITestLaunchArg.mockScreenRecordingDenied),
            mockScreenRecordingAuthorized: arguments.contains(UITestLaunchArg.mockScreenRecordingAuthorized),
            skipShortcuts: arguments.contains(UITestLaunchArg.skipShortcuts),
            triggerAction: value(for: UITestLaunchArg.trigger, in: arguments),
            dataDirPath: value(for: UITestLaunchArg.dataDir, in: arguments),
            largeText: arguments.contains(UITestLaunchArg.largeText),
            skipScreenshotCapture: arguments.contains(UITestLaunchArg.skipScreenshotCapture)
        )
    }

    /// Returns the value following a `--key value` pair, or `nil`.
    private static func value(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else {
            return nil
        }
        let next = arguments[index + 1]
        // Guard against the next token being another flag (missing value).
        guard !next.hasPrefix("--") else { return nil }
        return next
    }
}

/// Mock `PermissionServiceProtocol` for `--uitest-mock-screen-recording-*` hooks.
///
/// Returns a fixed screen-recording authorization state so `OnboardingViewModel`
/// can be tested without real TCC permissions. All other permissions default to
/// `.notDetermined` and system-settings / prompt calls are no-ops.
final class UITestMockPermissionService: PermissionServiceProtocol {
    private let screenRecordingAuthorized: Bool

    init(screenRecordingAuthorized: Bool) {
        self.screenRecordingAuthorized = screenRecordingAuthorized
    }

    func status(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return screenRecordingAuthorized ? .authorized : .denied
        case .accessibility:
            return .notDetermined
        }
    }

    func openSystemSettings(for permission: PermissionKind) {
        // no-op in UITest
    }

    func refreshStatuses() async -> [PermissionKind: PermissionStatus] {
        [.screenRecording: status(for: .screenRecording), .accessibility: .notDetermined]
    }

    @MainActor
    func requestScreenRecordingPrompt() -> Bool {
        screenRecordingAuthorized
    }

    @MainActor
    func onDemandAccessibilityCheck() -> Bool {
        false
    }
}

/// Posted by `ScreenshotWindowController.performCapture` when
/// `--uitest-skip-screenshot-capture` short-circuits the real capture, so
/// TC-UI-013 can assert "screenshot entry reached" without depending on TCC
/// permission or a full-screen overlay (cases.md §0.4 / TC-UI-013).
extension Notification.Name {
    static let uitestScreenshotTriggered = Notification.Name("QingyuUITestScreenshotTriggered")
}
#endif
