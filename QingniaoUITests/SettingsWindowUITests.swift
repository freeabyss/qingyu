import XCTest

/// TC-UI-019~020：设置窗口导航（Task 004 五页结构）
///
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSettings`/`openAbout`
/// 硬依赖：`settings.sidebar`；侧栏恰好 5 项：
/// `settings.general` / `settings.quickLaunch` / `settings.clipboard` / `settings.screenshot` / `settings.about`
final class SettingsWindowUITests: XCTestCase {

    private var app: XCUIApplication!
    private var tmpDirURL: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let app = app, app.state != .notRunning {
            app.terminate()
        }
        if let url = tmpDirURL {
            try? FileManager.default.removeItem(at: url)
            tmpDirURL = nil
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeTmpDir(for caseName: String) -> String {
        let path = NSTemporaryDirectory()
            + "QingniaoUITest/SettingsWindowUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    private func baseArgs(tmpDir: String) -> [String] {
        ["--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]
    }

    /// 侧栏恰好出现 5 个可选页面（两固定页 + 三插件页），以 accessibility id 断言。
    private func assertSidebarContainsExactlyFivePages() {
        let sidebar = app.groups["settings.sidebar"]
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 10),
            "设置窗口侧栏应呈现"
        )

        let identifiers = ["settings.general", "settings.quickLaunch", "settings.clipboard", "settings.screenshot", "settings.about"]
        for identifier in identifiers {
            let item = sidebar.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                item.waitForExistence(timeout: 5),
                "侧栏应含 \(identifier) 项"
            )
        }

        let unexpected = sidebar.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'settings.' AND identifier NOT IN %@", identifiers))
        XCTAssertEqual(unexpected.count, 0, "侧栏不应出现旧导航残留项")
    }

    // MARK: - TC-UI-019　设置窗口侧栏导航切换（五页）

    func testTCUI019SidebarHasExactlyFivePagesAndSwitches() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-019")
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", "openSettings"]
        app.launch()
        app.activate()

        assertSidebarContainsExactlyFivePages()

        // 点侧栏"剪贴板"项 -> 剪贴板设置（含"保留时间"）
        let clipboardItem = sidebarItem("settings.clipboard")
        clipboardItem?.click()
        let retentionText = app.staticTexts["保留时间"]
        XCTAssertTrue(
            retentionText.waitForExistence(timeout: 3),
            "点\"剪贴板\"后主区域应切换到剪贴板设置（含\"保留时间\"）"
        )

        // 点侧栏"截图"项 -> 截图设置（含"保存目录"区块）
        let screenshotItem = sidebarItem("settings.screenshot")
        screenshotItem?.click()
        let saveDirectoryText = app.staticTexts["保存目录"]
        XCTAssertTrue(
            saveDirectoryText.waitForExistence(timeout: 3),
            "点\"截图\"后主区域应切换到截图设置（含\"保存目录\"）"
        )

        // 点侧栏"关于"项 -> 关于页（含"青鸟"/"Qingniao"）
        let aboutItem = sidebarItem("settings.about")
        aboutItem?.click()
        let qingniaoText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "青鸟")
        ).firstMatch
        let pinyinText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Qingniao")
        ).firstMatch
        let aboutSwitched = qingniaoText.waitForExistence(timeout: 3) || pinyinText.exists
        XCTAssertTrue(
            aboutSwitched,
            "点\"关于\"后主区域应切换到关于页（含\"青鸟\"或\"Qingniao\"）"
        )
    }

    private func sidebarItem(_ identifier: String) -> XCUIElement? {
        let sidebar = app.groups["settings.sidebar"]
        guard sidebar.exists else { return nil }
        let item = sidebar.descendants(matching: .any)[identifier]
        return item.exists ? item : nil
    }

    // MARK: - TC-UI-020　关于页版本号可见

    /// 版本号从 Bundle 读取（当前 0.2.x 基线）；label 形如 "版本 0.2.4 (204)"。
    func testTCUI020AboutPageShowsVersion() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-020")
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", "openAbout"]
        app.launch()
        app.activate()

        let versionText = app.staticTexts.containing(
            NSPredicate(format: "label MATCHES %@", ".*0\\.2\\..*")
        ).firstMatch
        XCTAssertTrue(
            versionText.waitForExistence(timeout: 10),
            "关于页应显示版本号（label 含 0.2.x 子串）"
        )
    }
}
