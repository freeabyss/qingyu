import XCTest

/// Task 008 贴图 UI 冒烟（PinWindowUITests；1.0.0 FeatureGate 修订）。
///
/// 取舍说明：贴图窗口只能由「真实截图 → 截图工具条贴图按钮」或剪贴板贴图触发产生。
/// 前者依赖屏幕录制 TCC 授权与全屏 overlay 自动化交互（现有基建中 ScreenshotOverlayUITests
/// 对此类用例采用环境性 XCTSkip）；后者没有任何用户入口/触发钩子，无法在 UI 测试内驱动。
/// 1.0.0 FeatureGate：截图功能整体隐藏，ScreenshotPlugin 不注册——设置侧栏不再有
/// 截图页（`settings.screenshot`），贴图设置区块随页面一并隐藏（key 保留，开关恢复后回归）。
/// 因此本用例改为断言「截图设置入口不可达」，沿用 `--uitest-trigger openSettings` 触发模式。
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

    /// 1.0.0 FeatureGate：设置窗口不应出现截图设置项（贴图区块随页隐藏）。
    func testScreenshotSettingsEntryUnreachableWhileGateOff() throws {
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

        // 截图设置项不应出现（开关恢复后此断言回到「截图页含贴图区块」用例）。
        let screenshotItem = sidebar.descendants(matching: .any).matching(identifier: "settings.screenshot").firstMatch
        XCTAssertFalse(screenshotItem.waitForExistence(timeout: 3), "1.0.0 截图功能隐藏：侧栏不应出现截图设置项")

        // 贴图区块随截图页隐藏：主区域不应出现「贴图」区块标题。
        let pinSectionHeader = app.staticTexts["贴图"]
        XCTAssertFalse(pinSectionHeader.exists, "1.0.0 截图功能隐藏：贴图区块不应可见")
    }
}
