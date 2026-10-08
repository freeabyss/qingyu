import XCTest

/// TC-UI-011~015：菜单分发用例（用 `--uitest-trigger` 绕过 status item 点击）
///
/// 依据：`docs/iterations/v1.2.1/test/cases.md` TC-UI-011~015
/// 通用约定：见 cases.md §0（临时数据目录隔离、`--uitest-skip-shortcuts`、`app.activate()`、`waitForExistence`）
/// trigger 等价性：见 cases.md §0.4 与设计文档 §5.5（trigger 直接调用对应 controller.show()，
///   菜单分发逻辑本身退回代码审查 + 手动）
///
/// 前置：`--uitest-mark-onboarding-completed`（已完成态，门禁放行）+ `--uitest-data-dir` + `--uitest-skip-shortcuts`
final class MenuDispatchUITests: XCTestCase {

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

    /// 创建按用例名隔离的临时数据目录（cases.md §0.1），返回绝对路径并记录到 `tmpDirURL` 供 tearDown 清理。
    @discardableResult
    private func makeTmpDir(for caseName: String) -> String {
        let path = NSTemporaryDirectory()
            + "QingyuUITest/MenuDispatchUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    /// 通用 launch arguments（cases.md §0.1）：数据隔离 + 跳过热键注册。
    private func baseArgs(tmpDir: String) -> [String] {
        ["--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]
    }

    /// 已完成 onboarding 态 + 指定 trigger（cases.md §0.3 时序：mark 在 bootstrap 之后、loadState 之前）。
    private func completedArgs(tmpDir: String, trigger: String) -> [String] {
        baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", trigger]
    }

    // MARK: - TC-UI-011　菜单分发 -> Command Bar 呈现

    /// 覆盖：AC-02；US-002/003；FR-UI-3；FR-SEARCH-1；全局 PRD §9.4 P-01
    /// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSearch`
    /// 硬依赖（cases.md §0.5）：`commandBar.searchField`
    /// trigger 等价性（§0.4）：`openSearch` 直接调 `commandBarController.show()`，门禁已移除，与菜单路径等价。
    func testTCUI011OpenSearchPresentsCommandBar() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-011")
        app.launchArguments = completedArgs(tmpDir: tmpDir, trigger: "openSearch")
        app.launch()
        app.activate()

        let searchField = app.textFields["commandBar.searchField"]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-011: trigger openSearch 后 Command Bar 搜索框应呈现"
        )
        XCTAssertTrue(
            searchField.isHittable,
            "TC-UI-011: Command Bar 搜索框应可聚焦输入"
        )
    }

    // MARK: - TC-UI-012　菜单分发 -> 剪贴板窗口呈现

    /// 覆盖：AC-03；US-002/008；FR-UI-3；全局 PRD §9.4 P-02
    /// 前置：mark-completed + `--uitest-trigger openClipboard`
    /// 硬依赖（§0.5）：`clipboard.searchField`
    /// trigger 等价性（§0.4）：`openClipboard` 直接调 `clipboardHistoryWindowController.show()`。
    ///
    /// 文案偏差说明：cases.md §TC-UI-012 引用空态文案"剪贴板历史为空"，实际 L10n key
    /// `clipboard.empty.title` 的 zh-Hans 值为"暂无剪贴板记录"。本用例用实际 L10n 文案，
    /// 并以搜索框 identifier 作为窗口呈现的主信号（空态文案为辅）。
    func testTCUI012OpenClipboardPresentsWindow() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-012")
        app.launchArguments = completedArgs(tmpDir: tmpDir, trigger: "openClipboard")
        app.launch()
        app.activate()

        let searchField = app.textFields["clipboard.searchField"]
        let fieldExists = searchField.waitForExistence(timeout: 10)

        // 隔离数据目录下剪贴板为空，应走空态。实际 L10n: "暂无剪贴板记录"（clipboard.empty.title）。
        let emptyState = app.staticTexts["暂无剪贴板记录"]
        let emptyExists = fieldExists
            ? emptyState.waitForExistence(timeout: 3)
            : emptyState.waitForExistence(timeout: 10)

        XCTAssertTrue(
            fieldExists || emptyExists,
            "TC-UI-012: trigger openClipboard 后应呈现剪贴板窗口（搜索框或空态文案可见）"
        )
        if fieldExists {
            XCTAssertTrue(
                searchField.isHittable,
                "TC-UI-012: 剪贴板搜索框应可聚焦"
            )
        }
    }

    // MARK: - TC-UI-013　截图入口不可达（1.0.0 FeatureGate 修订）

    /// 1.0.0 修订：截图功能整体隐藏（FeatureGate），`startScreenshot` 触发链
    /// （菜单/快捷键/命令）在 ScreenshotWindowController.startCapture() 守卫处
    /// 直接返回：不弹权限提示、不进入截图会话，应用继续驻留。
    /// 前置：mark-completed + `--uitest-mock-screen-recording-denied`
    ///       + `--uitest-trigger startScreenshot` + `--uitest-skip-screenshot-capture`
    /// trigger 等价性（§0.4）：`startScreenshot` 调 `screenshotWindowController.startCapture()`，
    /// 与菜单/全局快捷键入口同路径，适合断言「入口不可达」。
    func testTCUI013ScreenshotEntryUnreachableWhileGateOff() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-013")
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed",
               "--uitest-mock-screen-recording-denied",
               "--uitest-trigger", "startScreenshot",
               "--uitest-skip-screenshot-capture"]
        app.launch()
        app.activate()

        // 触发后短暂等待：不应出现权限提示（NSAlert 在当前 macOS 运行时的
        // AX 类型是 Dialog，Alert/Sheet 也一并查询兜底）。
        let alert = app.alerts.firstMatch
        let dialog = app.dialogs.firstMatch
        let sheet = app.sheets.firstMatch
        let appeared = alert.waitForExistence(timeout: 3)
            || dialog.exists
            || sheet.exists

        XCTAssertFalse(
            appeared,
            "TC-UI-013: 1.0.0 截图入口隐藏，触发 startScreenshot 不应弹出权限提示"
        )
        XCTAssertNotEqual(app.state, .notRunning, "TC-UI-013: 触发后应用应继续驻留运行")
    }

    // MARK: - TC-UI-014　菜单分发 -> 设置窗口呈现

    /// 覆盖：AC-05；US-002/011；FR-UI-3/5；全局 PRD §9.4 P-03
    /// 前置：mark-completed + `--uitest-trigger openSettings`
    /// 硬依赖（§0.5）：`settings.sidebar`
    /// trigger 等价性（§0.4）：`openSettings` 调 `settingsWindowController.show(route: .settings)`。
    func testTCUI014OpenSettingsPresentsWindow() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-014")
        app.launchArguments = completedArgs(tmpDir: tmpDir, trigger: "openSettings")
        app.launch()
        app.activate()

        // SwiftUI NavigationSplitView 侧栏在当前 macOS 运行时是 Outline 类型（非 Group），
        // 用任意类型 + identifier 匹配，避免对元素类型的硬依赖（同 PinWindowUITests）。
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings.sidebar").firstMatch
        let sidebarExists = sidebar.waitForExistence(timeout: 10)

        // 兜底：若 sidebar identifier 查询不到，按侧栏项文本查询（"通用"/"剪贴板"，实际 L10n；
        // AX StaticText 在当前运行时只带 value 不带 label，用 value 匹配）
        let overviewText = app.staticTexts.containing(
            NSPredicate(format: "label == %@ OR value == %@", "通用", "通用")
        ).firstMatch
        let clipboardText = app.staticTexts.containing(
            NSPredicate(format: "label == %@ OR value == %@", "剪贴板", "剪贴板")
        ).firstMatch
        let textExists = sidebarExists
            ? (overviewText.exists || clipboardText.exists)
            : (overviewText.waitForExistence(timeout: 3) || clipboardText.exists)

        XCTAssertTrue(
            sidebarExists || textExists,
            "TC-UI-014: trigger openSettings 后应呈现设置窗口与侧栏"
        )
    }

    // MARK: - TC-UI-015　菜单分发 -> 关于页呈现

    /// 覆盖：AC-05；US-002/011；FR-UI-8；FR-UI-ABOUT-VERSION
    /// 前置：mark-completed + `--uitest-trigger openAbout`
    /// trigger 等价性（§0.4）：`openAbout` 调 `settingsWindowController.show(route: .about)`。
    /// 关于页内容（全局 PRD §9.4 P-03）：图标 + 应用名 + 版本号 + 版权 + 反馈入口。
    /// 应用名"清羽 Qingyu"在 OverviewPage 与 AboutPage 中均以字面量/Bundle appName 出现。
    func testTCUI015OpenAboutPresentsPage() throws {
        let tmpDir = makeTmpDir(for: "TC-UI-015")
        app.launchArguments = completedArgs(tmpDir: tmpDir, trigger: "openAbout")
        app.launch()
        app.activate()

        // 关于页内容含 "清羽" 或 "Qingyu"（实际：AboutPage 用 about.appName，OverviewPage 用字面量"清羽 Qingyu"；
        // AX StaticText 在当前运行时只带 value 不带 label，label/value 双匹配）
        let qingyuText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "清羽", "清羽")
        ).firstMatch
        let pinyinText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Qingyu", "Qingyu")
        ).firstMatch
        let qingyuExists = qingyuText.waitForExistence(timeout: 10)
        let pinyinExists = qingyuExists
            ? pinyinText.exists
            : pinyinText.waitForExistence(timeout: 3)

        XCTAssertTrue(
            qingyuExists || pinyinExists,
            "TC-UI-015: trigger openAbout 后应呈现关于页（含 \"清羽\" 或 \"Qingyu\" 文案）"
        )
    }
}
