import AppKit
import XCTest
@testable import Qingyu

/// 回归：`KeyEventHandler` 只处理「已提供回调」的按键，未提供的按键必须放行。
///
/// 背景（CLIP-013）：剪贴板历史窗口此前没有任何 ⎋ 处理，导致「按 esc 无法关闭
/// 剪贴板历史」。修复改用窗口级 `KeyEventHandler` 接管 ↑↓ / ⏎ / ⎋；同时把回调
/// 全部改为可选，避免未接管的按键（例如同窗口的 j/k/⌘C 隐藏快捷键）被吞掉。
@MainActor
final class KeyEventHandlerTests: XCTestCase {

    private func keyDown(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: - 只消费已接管的按键

    func testEscapeIsHandledWhenCallbackProvided() {
        let view = KeyEventNSView()
        var escapes = 0
        view.onEscape = { escapes += 1 }

        XCTAssertTrue(view.handle(keyDown(53)), "⎋ 有回调时应被消费")
        XCTAssertEqual(escapes, 1)
    }

    func testEscapeIsNotConsumedWithoutCallback() {
        let view = KeyEventNSView()

        XCTAssertFalse(view.handle(keyDown(53)), "无 ⎋ 回调时不得吞掉 Escape")
    }

    func testUnprovidedNavigationKeysAreNotConsumed() {
        let view = KeyEventNSView()
        var up = 0
        view.onUpArrow = { up += 1 }

        XCTAssertTrue(view.handle(keyDown(126)), "↑ 有回调时应被消费")
        XCTAssertFalse(view.handle(keyDown(125)), "↓ 无回调时不得被吞掉")
        XCTAssertFalse(view.handle(keyDown(36)), "⏎ 无回调时不得被吞掉")
        XCTAssertFalse(view.handle(keyDown(48)), "Tab 无回调时不得被吞掉")
        XCTAssertEqual(up, 1)
    }

    func testModifierKeysAreLeftAlone() {
        let view = KeyEventNSView()
        var escapes = 0
        view.onEscape = { escapes += 1 }

        XCTAssertFalse(view.handle(keyDown(53, modifiers: [.command])), "带 ⌘ 的 ⎋ 不属于导航键，应放行")
        XCTAssertEqual(escapes, 0)
    }
}
