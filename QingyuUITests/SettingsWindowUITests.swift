import XCTest

/// TC-UI-019~020：设置窗口导航（Task 004 五页结构；1.0.0 FeatureGate 隐藏截图页后为四页）
///
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSettings`/`openAbout`
/// 硬依赖：`settings.sidebar`；侧栏恰好 4 项：
/// `settings.general` / `settings.quick-launch` / `settings.clipboard` / `settings.about`
/// （插件页 identifier 取 PluginID rawValue，快速启动插件为 `quick-launch`；
/// 1.0.0 FeatureGate：ScreenshotPlugin 不注册，`settings.screenshot` 不出现）
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
            + "QingyuUITest/SettingsWindowUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    private func baseArgs(tmpDir: String) -> [String] {
        ["--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]
    }

    /// 侧栏恰好出现 4 个可选页面（两固定页 + 两插件页），以 accessibility id 断言；
    /// 并断言截图设置页不出现（1.0.0 FeatureGate）。
    private func assertSidebarContainsExactlyFourPages() {
        // SwiftUI NavigationSplitView 侧栏在当前 macOS 运行时不是 Group 类型，
        // 用任意类型 + identifier 匹配，避免对元素类型的硬依赖（同 PinWindowUITests）。
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings.sidebar").firstMatch
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 10),
            "设置窗口侧栏应呈现"
        )

        let identifiers = ["settings.general", "settings.quick-launch", "settings.clipboard", "settings.about"]
        for identifier in identifiers {
            let item = sidebar.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                item.waitForExistence(timeout: 5),
                "侧栏应含 \(identifier) 项"
            )
        }

        // 1.0.0 FeatureGate：截图设置页与插件行应消失（key 保留，仅隐藏入口）。
        let screenshotItem = sidebar.descendants(matching: .any)["settings.screenshot"]
        XCTAssertFalse(
            screenshotItem.exists,
            "1.0.0 截图功能隐藏：侧栏不应出现 settings.screenshot 项"
        )

        let unexpected = sidebar.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH 'settings.' AND NOT (identifier IN %@)",
                argumentArray: [identifiers]
            ))
        XCTAssertEqual(unexpected.count, 0, "侧栏不应出现旧导航残留项")
    }

    // MARK: - TC-UI-019　设置窗口侧栏导航切换（1.0.0 起四页）

    func testTCUI019SidebarHasExactlyFourPagesAndSwitches() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-019")
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", "openSettings"]
        app.launch()
        app.activate()

        assertSidebarContainsExactlyFourPages()

        // 点侧栏"剪贴板"项 -> 剪贴板设置（含"保留时间"）
        let clipboardItem = sidebarItem("settings.clipboard")
        clipboardItem?.click()
        let retentionText = app.staticTexts["保留时间"]
        XCTAssertTrue(
            retentionText.waitForExistence(timeout: 3),
            "点\"剪贴板\"后主区域应切换到剪贴板设置（含\"保留时间\"）"
        )

        // 点侧栏"关于"项 -> 关于页（含"清羽"/"Qingyu"；AX StaticText 只带 value 不带 label，
        // label/value 双匹配）
        let aboutItem = sidebarItem("settings.about")
        aboutItem?.click()
        let qingyuText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "清羽", "清羽")
        ).firstMatch
        let pinyinText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Qingyu", "Qingyu")
        ).firstMatch
        let aboutSwitched = qingyuText.waitForExistence(timeout: 3) || pinyinText.exists
        XCTAssertTrue(
            aboutSwitched,
            "点\"关于\"后主区域应切换到关于页（含\"清羽\"或\"Qingyu\"）"
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
