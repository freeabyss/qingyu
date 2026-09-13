import XCTest
import KeyboardShortcuts
@testable import Qingniao

/// 1.0.0 FeatureGate：GlobalShortcutManager 跳过截图快捷键注册。
@MainActor
final class GlobalShortcutManagerTests: XCTestCase {

    /// FeatureGate 关闭时 setupShortcuts() 不注册 F1（startScreenshot），
    /// 其余核心快捷键照常注册（正对照，证明跳过是定向的而非全局失效）。
    func test_setupShortcuts_skipsScreenshotF1WhileGateOff() {
        XCTAssertFalse(FeatureGate.screenshotEnabled)

        // 宿主 App 启动时可能已注册过 F1：先清理，确保断言只反映本方法的行为。
        KeyboardShortcuts.removeHandler(for: .startScreenshot)
        KeyboardShortcuts.disable(.startScreenshot)
        defer {
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.disable(.startScreenshot)
        }

        let manager = GlobalShortcutManager(container: AppContainer())
        manager.setupShortcuts()

        XCTAssertFalse(
            KeyboardShortcuts.isEnabled(for: .startScreenshot),
            "FeatureGate 关闭时 GlobalShortcutManager 不应注册 F1 截图快捷键"
        )
        XCTAssertTrue(
            KeyboardShortcuts.isEnabled(for: .togglePanel),
            "FeatureGate 关闭时其余核心快捷键（⌥Space）应照常注册"
        )
    }
}
