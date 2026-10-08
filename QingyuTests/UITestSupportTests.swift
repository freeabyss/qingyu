import XCTest
@testable import Qingyu

#if DEBUG
final class UITestSupportTests: XCTestCase {

    // MARK: - Empty / no args

    func test_parse_noArguments_returnsAllFalse() {
        let support = UITestSupport.parse(arguments: ["Qingyu"])

        XCTAssertFalse(support.resetOnboarding)
        XCTAssertFalse(support.markOnboardingCompleted)
        XCTAssertFalse(support.mockScreenRecordingDenied)
        XCTAssertFalse(support.mockScreenRecordingAuthorized)
        XCTAssertFalse(support.skipShortcuts)
        XCTAssertFalse(support.largeText)
        XCTAssertFalse(support.skipScreenshotCapture)
        XCTAssertNil(support.triggerAction)
        XCTAssertNil(support.dataDirPath)
        XCTAssertFalse(support.isUITest)
    }

    // MARK: - Boolean flags

    func test_parse_resetOnboarding() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-reset-onboarding"])
        XCTAssertTrue(support.resetOnboarding)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_markOnboardingCompleted() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-mark-onboarding-completed"])
        XCTAssertTrue(support.markOnboardingCompleted)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_mockScreenRecordingDenied() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-mock-screen-recording-denied"])
        XCTAssertTrue(support.mockScreenRecordingDenied)
        XCTAssertFalse(support.mockScreenRecordingAuthorized)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_mockScreenRecordingAuthorized() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-mock-screen-recording-authorized"])
        XCTAssertTrue(support.mockScreenRecordingAuthorized)
        XCTAssertFalse(support.mockScreenRecordingDenied)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_skipShortcuts() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-skip-shortcuts"])
        XCTAssertTrue(support.skipShortcuts)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_largeText() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-large-text"])
        XCTAssertTrue(support.largeText)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_skipScreenshotCapture() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-skip-screenshot-capture"])
        XCTAssertTrue(support.skipScreenshotCapture)
        XCTAssertTrue(support.isUITest)
    }

    // MARK: - Value arguments

    func test_parse_triggerAction() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger", "openSearch"])
        XCTAssertEqual(support.triggerAction, "openSearch")
        XCTAssertEqual(support.validatedTriggerAction, .openSearch)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_triggerAction_startScreenshot() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger", "startScreenshot"])
        XCTAssertEqual(support.triggerAction, "startScreenshot")
        XCTAssertEqual(support.validatedTriggerAction, .startScreenshot)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_triggerAction_allValidActions() {
        for action in UITestTriggerAction.allCases {
            let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger", action.rawValue])
            XCTAssertEqual(support.validatedTriggerAction, action, "Failed for \(action.rawValue)")
        }
    }

    func test_parse_triggerAction_invalidValue() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger", "nonexistent"])
        XCTAssertEqual(support.triggerAction, "nonexistent")
        XCTAssertNil(support.validatedTriggerAction)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_triggerAction_missingValue_returnsNil() {
        // --uitest-trigger at end of args with no following value
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger"])
        XCTAssertNil(support.triggerAction)
        // isUITest is false because triggerAction is nil and no other --uitest-* args
        XCTAssertFalse(support.isUITest)
    }

    func test_parse_triggerAction_nextFlagAsValue_returnsNil() {
        // --uitest-trigger followed by another flag, not a value
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-trigger", "--uitest-skip-shortcuts"])
        XCTAssertNil(support.triggerAction)
        XCTAssertTrue(support.skipShortcuts)
    }

    func test_parse_dataDir() {
        let path = "/tmp/QingyuUITest/testCase"
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-data-dir", path])
        XCTAssertEqual(support.dataDirPath, path)
        XCTAssertEqual(support.dataDirURL?.path, path)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_dataDir_missingValue_returnsNil() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-data-dir"])
        XCTAssertNil(support.dataDirPath)
        XCTAssertNil(support.dataDirURL)
        XCTAssertFalse(support.isUITest)
    }

    func test_parse_dataDir_emptyString_returnsNil() {
        let support = UITestSupport.parse(arguments: ["Qingyu", "--uitest-data-dir", ""])
        // Empty string is not a valid path
        // Note: "" doesn't start with "--" so it IS parsed as the value,
        // but dataDirURL returns nil for empty path.
        XCTAssertEqual(support.dataDirPath, "")
        XCTAssertNil(support.dataDirURL)
    }

    // MARK: - Combined args

    func test_parse_multipleArgs() {
        let support = UITestSupport.parse(arguments: [
            "Qingyu",
            "--uitest-reset-onboarding",
            "--uitest-data-dir", "/tmp/test",
            "--uitest-skip-shortcuts",
            "--uitest-mock-screen-recording-denied"
        ])

        XCTAssertTrue(support.resetOnboarding)
        XCTAssertEqual(support.dataDirPath, "/tmp/test")
        XCTAssertTrue(support.skipShortcuts)
        XCTAssertTrue(support.mockScreenRecordingDenied)
        XCTAssertFalse(support.markOnboardingCompleted)
        XCTAssertFalse(support.mockScreenRecordingAuthorized)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_fullLaunchArgs() {
        // Simulates a typical XCUITest launch (cases.md §0.1)
        let support = UITestSupport.parse(arguments: [
            "Qingyu",
            "--uitest-reset-onboarding",
            "--uitest-data-dir", "/var/folders/xx/T/QingyuUITest/TC-UI-001",
            "--uitest-skip-shortcuts",
            "--uitest-mock-screen-recording-authorized"
        ])

        XCTAssertTrue(support.resetOnboarding)
        XCTAssertEqual(support.dataDirURL?.path, "/var/folders/xx/T/QingyuUITest/TC-UI-001")
        XCTAssertTrue(support.skipShortcuts)
        XCTAssertTrue(support.mockScreenRecordingAuthorized)
        XCTAssertTrue(support.isUITest)
    }

    func test_parse_TC_UI_013_launchArgs() {
        // Simulates TC-UI-013 launch (cases.md §TC-UI-013 前置条件)
        let support = UITestSupport.parse(arguments: [
            "Qingyu",
            "--uitest-mark-onboarding-completed",
            "--uitest-mock-screen-recording-denied",
            "--uitest-trigger", "startScreenshot",
            "--uitest-skip-screenshot-capture",
            "--uitest-data-dir", "/var/folders/xx/T/QingyuUITest/TC-UI-013",
            "--uitest-skip-shortcuts"
        ])

        XCTAssertTrue(support.markOnboardingCompleted)
        XCTAssertTrue(support.mockScreenRecordingDenied)
        XCTAssertEqual(support.validatedTriggerAction, .startScreenshot)
        XCTAssertTrue(support.skipScreenshotCapture)
        XCTAssertEqual(support.dataDirPath, "/var/folders/xx/T/QingyuUITest/TC-UI-013")
        XCTAssertTrue(support.skipShortcuts)
        XCTAssertTrue(support.isUITest)
    }

    // MARK: - Equatable

    func test_equality_sameArgs() {
        let a = UITestSupport.parse(arguments: ["--uitest-skip-shortcuts"])
        let b = UITestSupport.parse(arguments: ["--uitest-skip-shortcuts"])
        XCTAssertEqual(a, b)
    }

    func test_equality_differentArgs() {
        let a = UITestSupport.parse(arguments: ["--uitest-skip-shortcuts"])
        let b = UITestSupport.parse(arguments: ["--uitest-large-text"])
        XCTAssertNotEqual(a, b)
    }
}
#endif
