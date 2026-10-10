import XCTest
@testable import Qingyu

final class ReleaseInfoServiceTests: XCTestCase {
    func testReleaseLinksAreCanonicalProjectHomepageAssets() {
        let info = BundleAboutInfoProvider(bundle: .main).info

        XCTAssertEqual(info.homepageURL.absoluteString, "https://github.com/freeabyss/qingyu")
        XCTAssertEqual(info.privacyPolicyURL.absoluteString, "https://github.com/freeabyss/qingyu/blob/main/PRIVACY.md")
        XCTAssertEqual(info.releasesURL.absoluteString, "https://github.com/freeabyss/qingyu/releases")
        XCTAssertEqual(info.thirdPartyLicensesURL.absoluteString, "https://github.com/freeabyss/qingyu/blob/main/THIRD_PARTY_NOTICES.md")
        XCTAssertEqual(info.feedbackEmail, "qingyu_freeabyss@163.com")
    }

    func testProjectHomepageContainsUS020ProductPageMaterialAndScopeGuards() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let privacy = try String(contentsOf: root.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let notices = try String(contentsOf: root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)

        // 锚点对齐当前 README 结构（US-020 产品页材料 + MVP 范围守卫）。
        // FAQ/常见问题已于产品说明中移除，不再作为必备章节。
        for required in [
            "# Qingyu (清羽)",
            "local-first macOS productivity tool",
            "## Features",
            "## Download",
            "Get the latest release",
            "https://github.com/freeabyss/qingyu/releases",
            "## Privacy",
            "PRIVACY.md",
            "### Permissions",
            "Accessibility",
            "## Version History",
            "qingyu_freeabyss@163.com",
            "## Feedback",
        ] {
            XCTAssertTrue(readme.contains(required), "README.md should contain \(required)")
        }

        XCTAssertFalse(readme.contains("## FAQ"), "README.md should not include an FAQ section")

        for excluded in ["account", "payment", "subscriptions", "Mac App Store"] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(excluded), "README.md should explicitly guard MVP scope for \(excluded)")
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
        XCTAssertTrue(absolute.contains("清羽 Qingyu 反馈"))
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

final class InstallerCleanupTests: XCTestCase {
    func testRecognizesOnlyQingyuDMGNames() {
        XCTAssertTrue(InstallerCleanup.isOwnInstallerName("Qingyu-0.3.40.dmg"))
        XCTAssertTrue(InstallerCleanup.isOwnInstallerName("Qingyu-0.3.40-universal.dmg"))
        XCTAssertTrue(InstallerCleanup.isOwnInstallerName("qingyu-1.0.dmg"))
        XCTAssertFalse(InstallerCleanup.isOwnInstallerName("Qingyu.zip"))
        XCTAssertFalse(InstallerCleanup.isOwnInstallerName("Other-1.0.dmg"))
        XCTAssertFalse(InstallerCleanup.isOwnInstallerName(".dmg"))
    }

    func testRemoveDownloadedInstallersRecyclesMatchingFilesAndSkipsMissingDirectories() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("QingyuInstallerCleanupTests-\(UUID().uuidString)")
        let downloads = root.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let installer = downloads.appendingPathComponent("Qingyu-0.3.40.dmg")
        let untouched = downloads.appendingPathComponent("Notes.dmg")
        try Data().write(to: installer)
        try Data().write(to: untouched)

        var recycled: [URL] = []
        let removed = InstallerCleanup.removeDownloadedInstallers(
            in: [root.appendingPathComponent("Desktop"), downloads],
            fileManager: fileManager,
            recycle: { recycled.append($0) }
        )

        XCTAssertEqual(removed.map(\.lastPathComponent), ["Qingyu-0.3.40.dmg"])
        XCTAssertEqual(recycled.map(\.lastPathComponent), ["Qingyu-0.3.40.dmg"])
        XCTAssertTrue(fileManager.fileExists(atPath: untouched.path))
    }
}
