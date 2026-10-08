import XCTest

/// TC-UI-001~010：Onboarding UI 用例（v1.2.1 AC-01/06/07/08/09/10/11/12）。
///
/// 严格对照 `docs/iterations/v1.2.1/test/cases.md` 实现。通用约定见 cases.md §0：
/// - 每用例 `--uitest-data-dir <tmp>` + `--uitest-skip-shortcuts`（§0.1）
/// - setUp 创建临时目录，tearDown 清理（§0.2）
/// - 用 accessibilityIdentifier 查询控件（§0.5）
/// - waitForExistence 处理时序，不固定 sleep（§0.6）
/// - menuBars 驻留断言带降级（§0.7）
final class OnboardingUITests: XCTestCase {

    private var app: XCUIApplication?
    private var dataDirs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        for dir in dataDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        dataDirs.removeAll()
    }

    // MARK: - Helpers（cases.md §0）

    /// 构造按用例名隔离的临时数据目录（§0.1）。
    @discardableResult
    private func makeDataDir(named name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QingyuUITest", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        dataDirs.append(url)
        return url
    }

    /// 通用 launch arguments：数据隔离 + 跳过热键（§0.1）。
    private func commonArgs(dataDir: URL) -> [String] {
        ["--uitest-data-dir", dataDir.path, "--uitest-skip-shortcuts"]
    }

    /// 配置并启动 app（§0.2）。
    private func launchApp(arguments: [String]) {
        let application = XCUIApplication()
        application.launchArguments = arguments
        application.launch()
        application.activate()
        app = application
    }

    /// 等待 onboarding 窗口出现（通过「开始使用」按钮判定，§0.5）。
    private func waitForOnboarding(timeout: TimeInterval = 10) -> Bool {
        app!.buttons["onboarding.startButton"].waitForExistence(timeout: timeout)
    }

    /// 等待 onboarding 窗口消失（轮询 `!exists`，超时 5s，§0.6）。
    private func waitForOnboardingGone(timeout: TimeInterval = 5) -> Bool {
        let button = app!.buttons["onboarding.startButton"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !button.exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !button.exists
    }

    /// 断言 app 驻留菜单栏（§0.7：优先 menuBars，降级 app.state != .notRunning）。
    private func assertAppResides() {
        if app!.menuBars.firstMatch.waitForExistence(timeout: 3) {
            XCTAssertTrue(app!.menuBars.firstMatch.exists, "app 应驻留菜单栏")
        } else {
            XCTAssertNotEqual(app!.state, .notRunning, "app 应仍在运行（menuBars 降级，§0.7）")
        }
    }

    // MARK: - TC-UI-001 首启显示欢迎页（AC-01）

    /// 前置：`--uitest-reset-onboarding` + 通用（cases.md TC-UI-001）。
    func testTC_UI_001_FirstLaunchShowsOnboarding() throws {
        let dir = makeDataDir(named: "TC-UI-001")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        // 标题文案"欢迎使用 清羽 Qingyu"（cases.md 步骤4，用 CONTAINS 兜底；
        // AX StaticText 在当前 macOS 运行时只带 value 不带 label，label/value 双匹配）
        let title = app!.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "清羽", "清羽")
        ).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "标题文案应含「清羽」")
    }

    // MARK: - TC-UI-002 「开始使用」可见可点（AC-06）

    /// 前置：同 TC-UI-001。只断言可见可点，不断言 isEnabled（cases.md TC-UI-002）。
    func testTC_UI_002_StartButtonVisibleAndHittable() throws {
        let dir = makeDataDir(named: "TC-UI-002")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        let startButton = app!.buttons["onboarding.startButton"]
        XCTAssertTrue(startButton.exists, "「开始使用」按钮应存在")
        XCTAssertTrue(startButton.isHittable, "「开始使用」按钮应可点击")
    }

    // MARK: - TC-UI-003 「跳过设置」可见可点（AC-07）

    /// 前置：同 TC-UI-001。跳过按钮不依赖 canStart，始终可用（cases.md TC-UI-003）。
    func testTC_UI_003_SkipButtonVisibleHittableEnabled() throws {
        let dir = makeDataDir(named: "TC-UI-003")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        let skipButton = app!.buttons["onboarding.skipButton"]
        XCTAssertTrue(skipButton.exists, "「跳过设置」按钮应存在")
        XCTAssertTrue(skipButton.isHittable, "「跳过设置」按钮应可点击")
        XCTAssertTrue(skipButton.isEnabled, "「跳过设置」应可用（不依赖 canStart，v1.1.0 回归）")
    }

    // MARK: - TC-UI-004 「跳过设置」+ 二次确认 + 关窗（AC-07）

    /// 前置：同 TC-UI-001。点跳过 -> 二次确认 sheet -> 确认 -> 关窗（cases.md TC-UI-004）。
    func testTC_UI_004_SkipWithConfirmationClosesWindow() throws {
        let dir = makeDataDir(named: "TC-UI-004")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        app!.buttons["onboarding.skipButton"].tap()

        // 二次确认 dialog（jadeConfirmationDialog -> SwiftUI confirmationDialog -> sheet）
        let sheet = app!.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "二次确认 dialog 应出现")
        // 确认按钮文案"跳过"（L10n key onboarding.skip.confirm.action = "跳过"）
        let confirmButton = sheet.buttons["跳过"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3), "确认按钮应可见")
        confirmButton.tap()

        XCTAssertTrue(waitForOnboardingGone(timeout: 5), "确认后 onboarding 窗口应消失")
    }

    // MARK: - TC-UI-005 footer 恒定可见（含放大字号变体，AC-10/AC-06）

    /// 5a 默认字号 + 5b 放大字号（--uitest-large-text，落实评审 C-2）。
    /// 不验证 frame 像素，只验证可点击性（cases.md TC-UI-005）。
    func testTC_UI_005_FooterAlwaysVisibleLargeTextVariant() throws {
        // 5a 默认字号
        let dir5a = makeDataDir(named: "TC-UI-005a")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir5a))
        XCTAssertTrue(waitForOnboarding(timeout: 10), "5a: onboarding 窗口应出现")
        let start5a = app!.buttons["onboarding.startButton"]
        let skip5a = app!.buttons["onboarding.skipButton"]
        XCTAssertTrue(start5a.exists && start5a.isHittable, "5a: 「开始使用」应可见可点")
        XCTAssertTrue(skip5a.exists && skip5a.isHittable, "5a: 「跳过设置」应可见可点")

        // 5b 放大字号
        app!.terminate()
        let dir5b = makeDataDir(named: "TC-UI-005b")
        launchApp(arguments: ["--uitest-reset-onboarding", "--uitest-large-text"] + commonArgs(dataDir: dir5b))
        XCTAssertTrue(waitForOnboarding(timeout: 10), "5b: onboarding 窗口应出现")
        let start5b = app!.buttons["onboarding.startButton"]
        let skip5b = app!.buttons["onboarding.skipButton"]
        XCTAssertTrue(start5b.exists && start5b.isHittable, "5b: 放大字号下「开始使用」应可见可点")
        XCTAssertTrue(skip5b.exists && skip5b.isHittable, "5b: 放大字号下「跳过设置」应可见可点")
    }

    // MARK: - TC-UI-006 屏幕录制段隐藏、「开始使用」/「跳过设置」可用（AC-12，1.0.0 修订）

    /// 1.0.0 FeatureGate：截图整体隐藏，屏幕录制（必选）段不渲染，
    /// 「开始使用」不再被屏幕录制授权阻塞（canStart 恒 true）；
    /// 「跳过设置」保持可用（v1.1.0 死锁修复回归的等价断言）。
    /// 前置：`--uitest-reset-onboarding` + `--uitest-mock-screen-recording-denied`（cases.md TC-UI-006）。
    func testTC_UI_006_ScreenRecordingSectionHiddenStartEnabledWhenDenied() throws {
        let dir = makeDataDir(named: "TC-UI-006")
        launchApp(arguments: [
            "--uitest-reset-onboarding",
            "--uitest-mock-screen-recording-denied",
        ] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        let startButton = app!.buttons["onboarding.startButton"]
        let skipButton = app!.buttons["onboarding.skipButton"]
        XCTAssertTrue(startButton.exists, "「开始使用」按钮应可见")
        XCTAssertTrue(skipButton.exists, "「跳过设置」按钮应可见")
        XCTAssertTrue(startButton.isEnabled, "截图隐藏期间未授权也不应禁用「开始使用」（canStart == true）")
        XCTAssertTrue(skipButton.isEnabled, "「跳过设置」应可用（v1.1.0 死锁修复回归）")
        // 屏幕录制段整体不渲染：授予/暂不开启按钮均不存在（key 保留，仅隐藏入口）。
        XCTAssertFalse(app!.buttons["onboarding.screenRecording.grant"].exists,
                       "1.0.0 截图功能隐藏：屏幕录制授予按钮不应出现")
        XCTAssertFalse(app!.buttons["onboarding.screenRecording.skip"].exists,
                       "1.0.0 截图功能隐藏：屏幕录制「暂不开启」按钮不应出现")
    }

    // MARK: - TC-UI-007 点「开始使用」后关窗 + 驻留 authorized（AC-08）

    /// 前置：`--uitest-reset-onboarding` + `--uitest-mock-screen-recording-authorized`（cases.md TC-UI-007）。
    func testTC_UI_007_StartAuthorizedClosesAndResides() throws {
        let dir = makeDataDir(named: "TC-UI-007")
        launchApp(arguments: [
            "--uitest-reset-onboarding",
            "--uitest-mock-screen-recording-authorized",
        ] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        let startButton = app!.buttons["onboarding.startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "「开始使用」按钮应存在")
        XCTAssertTrue(startButton.isEnabled, "authorized 路径下「开始使用」应可用（canStart == true）")
        startButton.tap()

        XCTAssertTrue(waitForOnboardingGone(timeout: 5), "点击后 onboarding 窗口应消失")
        assertAppResides()
    }

    // MARK: - TC-UI-008 点「跳过设置」+ 确认后关窗 + 驻留 skip（AC-08）

    /// 前置：同 TC-UI-001（skip 不依赖 canStart，无需 mock 权限，cases.md TC-UI-008）。
    func testTC_UI_008_SkipConfirmedClosesAndResides() throws {
        let dir = makeDataDir(named: "TC-UI-008")
        launchApp(arguments: ["--uitest-reset-onboarding"] + commonArgs(dataDir: dir))

        XCTAssertTrue(waitForOnboarding(timeout: 10), "onboarding 窗口应出现")
        app!.buttons["onboarding.skipButton"].tap()

        let sheet = app!.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "二次确认 dialog 应出现")
        let confirmButton = sheet.buttons["跳过"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3), "确认按钮应可见")
        confirmButton.tap()

        XCTAssertTrue(waitForOnboardingGone(timeout: 5), "确认后 onboarding 窗口应消失")
        assertAppResides()
    }

    // MARK: - TC-UI-009 菜单主动打开欢迎页 + 关闭不改完成态（AC-11）

    /// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openOnboarding`（cases.md TC-UI-009）。
    /// trigger 等价性见 §0.4：调用 showOnboardingWindow()。
    func testTC_UI_009_ManuallyOpenOnboardingNoStateChange() throws {
        let dir = makeDataDir(named: "TC-UI-009")
        launchApp(arguments: [
            "--uitest-mark-onboarding-completed",
            "--uitest-trigger", "openOnboarding",
        ] + commonArgs(dataDir: dir))

        // 主动打开后 onboarding 窗口出现
        XCTAssertTrue(waitForOnboarding(timeout: 10), "主动打开后 onboarding 窗口应出现")

        // 关闭 onboarding 窗口（cases.md 步骤4：方式A 关闭按钮 / 方式B ⌘W）
        let closeButton = app!.windows.firstMatch.buttons[XCUIIdentifierCloseWindow]
        if closeButton.waitForExistence(timeout: 3) && closeButton.isHittable {
            closeButton.tap()
        } else {
            app!.typeKey("w", modifierFlags: .command)
        }

        XCTAssertTrue(waitForOnboardingGone(timeout: 5), "关闭后 onboarding 窗口应消失")
        assertAppResides()
    }

    // MARK: - TC-UI-010 重启不自动弹欢迎页（AC-09）

    /// 两步 launch，单方法内完成，复用同一 tmpDir（cases.md TC-UI-010 关键点）。
    func testTC_UI_010_RestartDoesNotShowOnboarding() throws {
        // 复用同一 tmpDir：步骤1写入 onboarding.completedAt 持久化到 tmpDir 的 Core Data store，
        // 步骤2读取同一 store 的 loadOnboardingCompletionState() 应返回已完成。
        let dir = makeDataDir(named: "TC-UI-010")

        // 步骤 1：标记已完成 + data-dir
        launchApp(arguments: ["--uitest-mark-onboarding-completed"] + commonArgs(dataDir: dir))
        _ = app!.menuBars.firstMatch.waitForExistence(timeout: 3)
        // 已完成态不弹 onboarding（等待 3s 确认不弹）
        XCTAssertFalse(
            app!.buttons["onboarding.startButton"].waitForExistence(timeout: 3),
            "步骤1: 已完成态不应弹 onboarding"
        )

        app!.terminate()

        // 步骤 2：复用同一 tmpDir，不传 mark/reset
        launchApp(arguments: commonArgs(dataDir: dir))
        _ = app!.menuBars.firstMatch.waitForExistence(timeout: 5)
        // 重启不自动弹（等待 3s 确认不弹）
        XCTAssertFalse(
            app!.buttons["onboarding.startButton"].waitForExistence(timeout: 3),
            "步骤2: 重启不应自动弹 onboarding"
        )
        assertAppResides()
    }
}
