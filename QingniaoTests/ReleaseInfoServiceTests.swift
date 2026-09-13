import XCTest
@testable import Qingniao

final class ReleaseInfoServiceTests: XCTestCase {
    func testReleaseLinksAreCanonicalProjectHomepageAssets() {
        let info = BundleAboutInfoProvider(bundle: .main).info

        XCTAssertEqual(info.homepageURL.absoluteString, "https://github.com/freeabyss/qingniao")
        XCTAssertEqual(info.privacyPolicyURL.absoluteString, "https://github.com/freeabyss/qingniao/blob/main/PRIVACY.md")
        XCTAssertEqual(info.releasesURL.absoluteString, "https://github.com/freeabyss/qingniao/releases")
        XCTAssertEqual(info.thirdPartyLicensesURL.absoluteString, "https://github.com/freeabyss/qingniao/blob/main/THIRD_PARTY_NOTICES.md")
        XCTAssertEqual(info.feedbackEmail, "feedback@qingniao.app")
    }

    func testProjectHomepageContainsUS020ProductPageMaterialAndScopeGuards() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let privacy = try String(contentsOf: root.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let notices = try String(contentsOf: root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)

        for required in [
            "Product name",
            "Slogan",
            "Core features",
            "Screenshots / demo GIF",
            "Download the latest release",
            "Version history",
            "Privacy policy",
            "feedback@qingniao.app",
            "FAQ",
            "Screen Recording",
            "Accessibility",
            "https://github.com/freeabyss/qingniao/releases"
        ] {
            XCTAssertTrue(readme.contains(required), "README.md should contain \\(required)")
        }

        for excluded in ["account", "payment", "subscriptions", "Mac App Store"] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(excluded), "README.md should explicitly guard MVP scope for \\(excluded)")
        }

        XCTAssertTrue(privacy.contains("does not upload clipboard history"))
        XCTAssertTrue(privacy.contains("Feedback is user-initiated email only"))
        XCTAssertTrue(changelog.contains("0.1.0-mvp"))
        XCTAssertTrue(notices.contains("GitHub Releases"))
    }

    func testFeedbackEmailIncludesVersionSystemSummaryAndUserDescription() throws {
        let service = FeedbackEmailService(recipient: "support@example.com")
        let url = try service.makeFeedbackEmail(context: FeedbackContext(
            appVersion: "0.1.0",
            buildNumber: "7",
            macOSVersion: "Version 15.0",
            errorSummary: "Screenshot failed",
            userDescription: "It happened after pressing the shortcut."
        ))

        let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        XCTAssertTrue(absolute.hasPrefix("mailto:support@example.com?"))
        XCTAssertTrue(absolute.contains("青鸟 Qingniao 反馈"))
        XCTAssertTrue(absolute.contains("App version: 0.1.0 (7)"))
        XCTAssertTrue(absolute.contains("macOS version: Version 15.0"))
        XCTAssertTrue(absolute.contains("Error summary: Screenshot failed"))
        XCTAssertTrue(absolute.contains("It happened after pressing the shortcut."))
        XCTAssertTrue(absolute.contains("does not attach clipboard history, screenshots, files, or automatic crash logs"))
    }

    func testUpdateCheckServiceOpensReleasesURLOnly() {
        let opener = RecordingURLOpener()
        let releasesURL = URL(string: "https://example.com/releases")!
        let service = WebUpdateCheckService(releasesURL: releasesURL, opener: opener)

        service.openDownloadPage()

        XCTAssertEqual(opener.openedURLs, [releasesURL])
    }
}

private final class RecordingURLOpener: ReleaseURLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}
