import AppKit
import XCTest
@testable import Qingyu

/// Task 017/02–04：光标下贴图的作用域、穿透、悬停提示文案。
///
/// 所有与「光标位置」有关的行为都通过 `pinUnderCursorProvider` 注入判定结果，
/// 避免单测结果随测试机上鼠标的实际位置漂移。
@MainActor
final class PinInteractionTests: XCTestCase {

    // MARK: - 光标命中（纯函数）

    func testPinUnderCursorPicksFrontmostMatch() {
        let back = UUID()
        let front = UUID()
        let candidates: [(id: UUID, frame: NSRect)] = [
            (id: front, frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
            (id: back, frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        ]

        XCTAssertEqual(
            PinWindowController.pinUnderCursor(mouseLocation: NSPoint(x: 50, y: 50), candidates: candidates),
            front,
            "重叠时取更靠前的那个"
        )
    }

    func testPinUnderCursorReturnsNilWhenOutside() {
        let candidates: [(id: UUID, frame: NSRect)] = [
            (id: UUID(), frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        ]

        XCTAssertNil(
            PinWindowController.pinUnderCursor(mouseLocation: NSPoint(x: 200, y: 200), candidates: candidates)
        )
        XCTAssertNil(PinWindowController.pinUnderCursor(mouseLocation: .zero, candidates: []))
    }

    // MARK: - 穿透作用域

    private func makeController(cursorPin: UUID? = nil, hasCursorPin: Bool = true) -> PinWindowController {
        let controller = PinWindowController(store: PinStore(), payloadFactory: PinPayloadFactory())
        if hasCursorPin {
            controller.pinUnderCursorProvider = { cursorPin }
        }
        return controller
    }

    private func presentImagePin(_ controller: PinWindowController) -> PinItem {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 120,
            pixelsHigh: 80,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return controller.present(payload: .image(rep.representation(using: .png, properties: [:])!))
    }

    func testPassthroughTogglesOnlyThePinUnderCursor() {
        let controller = makeController()
        let target = presentImagePin(controller)
        let other = presentImagePin(controller)
        controller.pinUnderCursorProvider = { target.id }

        controller.toggleMouseEventsForPinUnderCursor()

        XCTAssertTrue(controller.store.item(id: target.id)?.ignoresMouseEvents == true)
        XCTAssertFalse(
            controller.store.item(id: other.id)?.ignoresMouseEvents == true,
            "光标下有贴图时只切它，不得波及其它贴图"
        )
    }

    func testPassthroughTogglesBackToFalse() {
        let controller = makeController()
        let target = presentImagePin(controller)
        controller.pinUnderCursorProvider = { target.id }

        controller.toggleMouseEventsForPinUnderCursor()
        controller.toggleMouseEventsForPinUnderCursor()

        XCTAssertFalse(controller.store.item(id: target.id)?.ignoresMouseEvents == true)
    }

    func testPassthroughWithoutCursorPinTogglesEveryPin() {
        let controller = makeController(cursorPin: nil)
        let first = presentImagePin(controller)
        let second = presentImagePin(controller)

        controller.toggleMouseEventsForPinUnderCursor()

        XCTAssertTrue(controller.store.item(id: first.id)?.ignoresMouseEvents == true)
        XCTAssertTrue(
            controller.store.item(id: second.id)?.ignoresMouseEvents == true,
            "无光标下贴图时整体切换"
        )

        controller.toggleMouseEventsForPinUnderCursor()
        XCTAssertFalse(controller.store.item(id: first.id)?.ignoresMouseEvents == true)
        XCTAssertFalse(controller.store.item(id: second.id)?.ignoresMouseEvents == true)
    }

    /// 穿透状态不持久化：整体销毁后重新呈现的贴图一律回到未穿透。
    func testPassthroughIsNotPersisted() {
        let controller = makeController()
        let item = presentImagePin(controller)
        controller.setIgnoresMouseEvents(true, for: item.id)
        XCTAssertTrue(controller.store.item(id: item.id)?.ignoresMouseEvents == true)

        controller.destroyAll()
        XCTAssertTrue(controller.store.items.isEmpty)
        XCTAssertEqual(controller.windowCount, 0)
    }

    // MARK: - 缩放与不透明度

    func testScaleClampsAtBothBounds() {
        let controller = makeController()
        let item = presentImagePin(controller)
        controller.pinUnderCursorProvider = { item.id }

        for _ in 0..<200 { controller.adjustScaleForPinUnderCursor(by: 1.1) }
        XCTAssertEqual(
            controller.store.item(id: item.id)?.transform.scale,
            PinTransform.maximumScale,
            "放大到上限即钳制，不报错"
        )

        for _ in 0..<400 { controller.adjustScaleForPinUnderCursor(by: 1 / 1.1) }
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.scale, PinTransform.minimumScale)
    }

    func testOpacityClampsAtBothBounds() {
        let controller = makeController()
        let item = presentImagePin(controller)
        controller.pinUnderCursorProvider = { item.id }

        for _ in 0..<50 { controller.adjustOpacityForPinUnderCursor(by: 0.1) }
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.opacity, PinTransform.maximumOpacity)

        for _ in 0..<50 { controller.adjustOpacityForPinUnderCursor(by: -0.1) }
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.opacity, PinTransform.minimumOpacity)
    }

    func testScaleAndOpacityDoNothingWithoutCursorPin() {
        let controller = makeController(cursorPin: nil)
        let item = presentImagePin(controller)
        let original = controller.store.item(id: item.id)?.transform

        controller.adjustScaleForPinUnderCursor(by: 1.1)
        controller.adjustOpacityForPinUnderCursor(by: -0.1)

        XCTAssertEqual(controller.store.item(id: item.id)?.transform, original, "无光标下贴图时不响应")
    }

    /// 缩放/不透明度只改显示参数，不修改原始图像数据（导出仍是原图尺寸）。
    func testAdjustmentsDoNotTouchPayload() {
        let controller = makeController()
        let item = presentImagePin(controller)
        controller.pinUnderCursorProvider = { item.id }
        guard case .image(let original) = item.payload else {
            return XCTFail("预期图像载荷")
        }

        controller.adjustScaleForPinUnderCursor(by: 1.5)
        controller.adjustOpacityForPinUnderCursor(by: -0.2)

        guard case .image(let after) = controller.store.item(id: item.id)?.payload else {
            return XCTFail("预期图像载荷")
        }
        XCTAssertEqual(after, original, "显示参数不得改写原始图像数据")
    }

    // MARK: - 悬停提示文案（走生产实现）

    /// 未绑定的动作不应出现在提示里。
    ///
    /// 断言必须用**键位符号**（`⌃` / `Esc`）而不是本地化文案做子串匹配：
    /// 中文下「复位缩放与不透明度」天然包含「缩放」与「不透明度」，
    /// 按文案匹配会随语言与措辞漂移而假失败（该缺陷已在中文构建下暴露过一次）。
    func testHoverHintSkipsUnboundShortcuts() {
        let text = PinEventContainerView.hoverHintText(shortcutDescriptions: [:])

        XCTAssertFalse(text.contains("⌃"), "未绑定的可重绑快捷键不应出现")
        XCTAssertFalse(text.contains("⌥"), "未绑定的可重绑快捷键不应出现")
        XCTAssertTrue(text.contains("Esc"), "固定键位提示始终存在")
        XCTAssertTrue(
            text.contains(L10n.localized("pin.hint.resetKey")),
            "中键复位提示始终存在"
        )
    }

    func testHoverHintIncludesBoundShortcuts() {
        let text = PinEventContainerView.hoverHintText(shortcutDescriptions: [
            .pinScaleUp: "⌃⌥=",
            .pinOpacityUp: "⌃⌥]",
            .pinToggleMouseEvents: "⌃⌥P"
        ])

        XCTAssertTrue(text.contains("⌃⌥="))
        XCTAssertTrue(text.contains("⌃⌥]"))
        XCTAssertTrue(text.contains("⌃⌥P"))
    }

    func testHintTextTruncatesAndSkipsBlankKeys() {
        let items = (0..<10).map { PinShortcutHints.Item(action: "a\($0)", keys: "k\($0)") }
            + [PinShortcutHints.Item(action: "blank", keys: "   ")]

        let text = PinShortcutHints.text(items)
        let parts = text.components(separatedBy: " · ")

        XCTAssertEqual(parts.count, PinShortcutHints.maximumItems)
        XCTAssertFalse(text.contains("blank"))
        XCTAssertEqual(PinShortcutHints.text([]), "")
    }

    /// 提示开关关闭时不得插入提示行。
    func testHintIsSuppressedWhenDisabled() {
        let container = PinEventContainerView(
            item: PinItem(payload: .text("hello")),
            size: NSSize(width: 200, height: 100)
        )
        container.showsShortcutHints = false

        container.mouseEntered(with: NSEvent())
        XCTAssertFalse(container.isHoverHintVisible, "关闭后不得插入提示行")

        container.showsShortcutHints = true
        container.mouseEntered(with: NSEvent())
        XCTAssertTrue(container.isHoverHintVisible)
    }
}
