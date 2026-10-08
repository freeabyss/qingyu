import XCTest
import KeyboardShortcuts
@testable import Qingyu

@MainActor
final class HotkeyConflictDetectorTests: XCTestCase {

    // MARK: - Default binding values (SHORTCUT-001..004)

    func testDefaultShortcutValuesMatchPRD() {
        // PRD「截图与贴图」/ Task 009：F1 开始截图（唯一截图快捷键槽位）。
        assertShortcut(.togglePanel, key: .space, modifiers: [.option])
        assertShortcut(.startScreenshot, key: .f1, modifiers: [])
        assertShortcut(.openClipboardHistory, key: .c, modifiers: [.option, .command])
        assertShortcut(.openSettings, key: .comma, modifiers: [.option, .command])
    }

    /// 1.0.0 FeatureGate 关闭：F1（startScreenshot）不注册，因此不参与
    /// 冲突扫描 / 批量重置（managedGlobalShortcuts 同步条件化）。
    /// Name 定义与 F1 默认键位保留，开关恢复后自动回到四槽位。
    func testManagedGlobalShortcutsExcludeScreenshotWhileGateOff() {
        XCTAssertFalse(FeatureGate.screenshotEnabled)
        XCTAssertEqual(KeyboardShortcuts.Name.managedGlobalShortcuts.count, 3)
        XCTAssertFalse(KeyboardShortcuts.Name.managedGlobalShortcuts.contains(.startScreenshot))
        XCTAssertEqual(
            Set(KeyboardShortcuts.Name.managedGlobalShortcuts),
            [.togglePanel, .openClipboardHistory, .openSettings]
        )
    }

    /// F1 槽位的 HotkeyAction 映射保留（开关恢复后 .screenshot 重新可用）。
    func testHotkeyActionNameRoundTrip() {
        for action in HotkeyAction.allCases {
            XCTAssertEqual(HotkeyAction(name: action.name), action)
        }
        XCTAssertEqual(HotkeyAction.screenshot.name, .startScreenshot)
    }

    // MARK: - Conflict detection

    func testNoConflictWhenAllDistinctAndNoSystemClash() {
        let detector = HotkeyConflictDetector(
            managedNames: KeyboardShortcuts.Name.managedGlobalShortcuts,
            currentShortcutProvider: { KeyboardShortcuts.Shortcut(name: $0) },
            systemShortcutProvider: { [] }
        )
        detector.scan()
        XCTAssertTrue(detector.conflictingNames.isEmpty)
        XCTAssertTrue(detector.conflictMessages.isEmpty)
    }

    func testSystemConflictIsFlagged() {
        // Force ⌥ Space to collide with an "enabled system shortcut".
        let systemShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
        let detector = HotkeyConflictDetector(
            managedNames: [.togglePanel],
            currentShortcutProvider: { _ in KeyboardShortcuts.Shortcut(.space, modifiers: [.option]) },
            systemShortcutProvider: { [systemShortcut] }
        )
        detector.scan()
        XCTAssertTrue(detector.conflictingNames.contains(.togglePanel))
        XCTAssertNotNil(detector.conflictMessages[.togglePanel])
    }

    func testInternalDuplicateIsFlagged() {
        // Two managed names bound to the same combination -> internal conflict.
        let dup = KeyboardShortcuts.Shortcut(.c, modifiers: [.option, .command])
        let detector = HotkeyConflictDetector(
            managedNames: [.openClipboardHistory, .openSettings],
            currentShortcutProvider: { _ in dup },
            systemShortcutProvider: { [] }
        )
        detector.scan()
        XCTAssertTrue(detector.conflictingNames.contains(.openClipboardHistory))
        XCTAssertTrue(detector.conflictingNames.contains(.openSettings))
    }

    func testEvaluateReturnsRegisteredForFreeShortcut() {
        let detector = HotkeyConflictDetector(
            managedNames: [.togglePanel],
            currentShortcutProvider: { _ in nil },
            systemShortcutProvider: { [] }
        )
        let outcome = detector.evaluate(KeyboardShortcuts.Shortcut(.f, modifiers: [.command, .control]), for: .startScreenshot)
        XCTAssertEqual(outcome, .registered)
    }

    func testEvaluateReturnsConflictForSystemShortcut() {
        let system = KeyboardShortcuts.Shortcut(.three, modifiers: [.control, .option, .command])
        let detector = HotkeyConflictDetector(
            managedNames: [.startScreenshot],
            currentShortcutProvider: { _ in nil },
            systemShortcutProvider: { [system] }
        )
        let outcome = detector.evaluate(system, for: .startScreenshot)
        guard case .conflict = outcome else {
            return XCTFail("Expected .conflict, got \(outcome)")
        }
    }

    // MARK: - Helpers

    private func assertShortcut(
        _ name: KeyboardShortcuts.Name,
        key: KeyboardShortcuts.Key,
        modifiers: NSEvent.ModifierFlags,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
        XCTAssertEqual(name.defaultShortcut, expected, "\(name.rawValue) default mismatch", file: file, line: line)
    }
}
