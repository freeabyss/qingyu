import XCTest

/// Task 008 贴图 UI 冒烟（PinWindowUITests）。
///
/// 取舍说明：贴图窗口只能由「真实截图 → 截图工具条贴图按钮」或剪贴板贴图触发产生。
/// 前者依赖屏幕录制 TCC 授权与全屏 overlay 自动化交互（现有基建中 ScreenshotOverlayUITests
/// 对此类用例采用环境性 XCTSkip）；后者没有任何用户入口/触发钩子，无法在 UI 测试内驱动。
/// 因此按 Task 008 验收允许的最贴近稳定形式断言：设置 → 截图页包含「贴图」区块
/// （`settings.pin.*`：文件路径首贴转图片、恢复队列、鼠标穿透快捷键），
/// 沿用 `--uitest-trigger openSettings` 免 TCC 触发模式（同 SettingsWindowUITests）。
final class PinWindowUITests: XCTestCase {

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

    private func makeTmpDir(for caseName: String) -> String {
        let path = NSTemporaryDirectory()
            + "QingniaoUITest/PinWindowUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    /// 截图设置页应展示贴图区块（贴图设置项存在于统一设置窗口）。
    func testScreenshotSettingsShowsPinSection() throws {
        let tmpDir = makeTmpDir(for: "PinSettingsSection")
        app.launchArguments = [
            "--uitest-data-dir", tmpDir,
            "--uitest-skip-shortcuts",
            "--uitest-mark-onboarding-completed",
            "--uitest-trigger", "openSettings"
        ]
        app.launch()
        app.activate()

        // 首次冷启动 + 数据栈引导 + 触发开窗在自动化会话中较慢（失败快照显示窗口最终会呈现），
        // 放宽等待时间避免偶发超时。
        // 注意：SwiftUI NavigationSplitView 侧栏在当前 macOS 运行时不是 Group 类型，
        // 用任意类型 + identifier 匹配，避免对元素类型的硬依赖。
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings.sidebar").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 30), "设置窗口侧栏应呈现")

        let screenshotItem = sidebar.descendants(matching: .any).matching(identifier: "settings.screenshot").firstMatch
        XCTAssertTrue(screenshotItem.waitForExistence(timeout: 10), "侧栏应含截图设置项")
        screenshotItem.click()

        let pinSectionHeader = app.staticTexts["贴图"]
        XCTAssertTrue(pinSectionHeader.waitForExistence(timeout: 10), "截图设置页应包含「贴图」区块")

        let filePathToImageRow = app.staticTexts["文件路径首贴转图片"]
        XCTAssertTrue(filePathToImageRow.waitForExistence(timeout: 10), "贴图区块应含「文件路径首贴转图片」设置")

        let restoreCapacityRow = app.staticTexts["恢复队列"]
        XCTAssertTrue(restoreCapacityRow.waitForExistence(timeout: 10), "贴图区块应含「恢复队列」设置")
    }
}
