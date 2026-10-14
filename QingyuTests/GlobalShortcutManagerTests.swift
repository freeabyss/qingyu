import XCTest
import KeyboardShortcuts
@testable import Qingyu

/// 1.0.0 FeatureGate：GlobalShortcutManager 跳过截图快捷键注册。
@MainActor
final class GlobalShortcutManagerTests: XCTestCase {

    /// FeatureGate 关闭时 setupShortcuts() 不注册 F1（startScreenshot），
    /// 其余核心快捷键照常注册（正对照，证明跳过是定向的而非全局失效）。
    /// 截图入口已开放：`setupShortcuts()` 必须注册 F1。
    func test_setupShortcuts_registersScreenshotF1() {
        XCTAssertTrue(FeatureGate.screenshotEnabled, "截图入口已开放，本用例描述当前产品行为")

        // 宿主 App 启动时可能已注册过 F1：先清理，确保断言只反映本方法的行为。
        KeyboardShortcuts.removeHandler(for: .startScreenshot)
        KeyboardShortcuts.disable(.startScreenshot)
        defer {
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.disable(.startScreenshot)
        }

        let manager = GlobalShortcutManager(container: AppContainer())
        manager.setupShortcuts()

        XCTAssertTrue(
            KeyboardShortcuts.isEnabled(for: .startScreenshot),
            "截图入口开放时应注册 F1 截图快捷键"
        )
        XCTAssertTrue(
            KeyboardShortcuts.isEnabled(for: .togglePanel),
            "其余核心快捷键（⌥Space）应照常注册"
        )
    }
}
