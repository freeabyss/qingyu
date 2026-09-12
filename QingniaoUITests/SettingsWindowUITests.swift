import XCTest

/// TC-UI-019~020：设置窗口导航（Task 004 五页结构）
///
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSettings`/`openAbout`
/// 硬依赖：`settings.sidebar`；侧栏恰好 5 项：
/// `settings.general` / `settings.quick-launch` / `settings.clipboard` / `settings.screenshot` / `settings.about`
/// （插件页 identifier 取 PluginID rawValue，快速启动插件为 `quick-launch`）
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
        // SwiftUI NavigationSplitView 侧栏在当前 macOS 运行时不是 Group 类型，
        // 用任意类型 + identifier 匹配，避免对元素类型的硬依赖（同 PinWindowUITests）。
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings.sidebar").firstMatch
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 10),
            "设置窗口侧栏应呈现"
        )

        let identifiers = ["settings.general", "settings.quick-launch", "settings.clipboard", "settings.screenshot", "settings.about"]
        for identifier in identifiers {
            let item = sidebar.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                item.waitForExistence(timeout: 5),
                "侧栏应含 \(identifier) 项"
            )
        }

        let unexpected = sidebar.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH 'settings.' AND NOT (identifier IN %@)",
                argumentArray: [identifiers]
            ))
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

        // 点侧栏"关于"项 -> 关于页（含"青鸟"/"Qingniao"；AX StaticText 只带 value 不带 label，
        // label/value 双匹配）
        let aboutItem = sidebarItem("settings.about")
        aboutItem?.click()
        let qingniaoText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "青鸟", "青鸟")
        ).firstMatch
        let pinyinText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Qingniao", "Qingniao")
        ).firstMatch
        let aboutSwitched = qingniaoText.waitForExistence(timeout: 3) || pinyinText.exists
        XCTAssertTrue(
            aboutSwitched,
            "点\"关于\"后主区域应切换到关于页（含\"青鸟\"或\"Qingniao\"）"
        )
    }

    private func sidebarItem(_ identifier: String) -> XCUIElement? {
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings.sidebar").firstMatch
        guard sidebar.exists else { return nil }
        let item = sidebar.descendants(matching: .any)[identifier]
        return item.exists ? item : nil
    }

    // MARK: - TC-UI-020　关于页版本号可见

    /// 版本号从 Bundle 读取（当前 0.2.x 基线）；文本形如 "版本 0.2.x (构建号)"。
    /// macOS 26 上 SwiftUI Text 的 AX StaticText 只带 value 不带 label，
    /// 故同时匹配 label 与 value，避免对 AX 属性的硬依赖。
    func testTCUI020AboutPageShowsVersion() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-020")
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", "openAbout"]
        app.launch()
        app.activate()

        let versionText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "0.2.", "0.2.")
        ).firstMatch
        XCTAssertTrue(
            versionText.waitForExistence(timeout: 10),
            "关于页应显示版本号（label 含 0.2.x 子串）"
        )
    }
}
