import AppKit
import CoreGraphics
import XCTest
@testable import Qingniao

@MainActor
final class PinWindowControllerTests: XCTestCase {

    private func makePNGData() -> Data {
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    private func makeController() -> PinWindowController {
        PinWindowController(
            store: PinStore(),
            payloadFactory: PinPayloadFactory(filePathToImage: false)
        )
    }

    /// 取窗口的贴图事件容器（键鼠交互回调入口）。
    private func eventContainer(of controller: PinWindowController, item: PinItem) -> PinEventContainerView? {
        guard let window = controller.window(for: item.id),
              let container = window.contentView as? PinEventContainerView else {
            return nil
        }
        return container
    }

    // MARK: - Presentation

    func testPresentCreatesWindowAndStoresItem() {
        let controller = makeController()
        let item = controller.present(payload: .text("hello"))

        XCTAssertEqual(controller.windowCount, 1)
        XCTAssertEqual(controller.store.item(id: item.id)?.payload, .text("hello"))
        controller.destroyAll()
    }

    func testPresentFromPasteboardParsesPayload() throws {
        let controller = makeController()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinWindowControllerTests-\(UUID().uuidString)"))
        pasteboard.releaseGlobally()
        pasteboard.setString("pinned text", forType: .string)
        defer { pasteboard.releaseGlobally() }

        let item = try controller.presentFromPasteboard(pasteboard)
        XCTAssertEqual(item.payload, .text("pinned text"))
        controller.destroyAll()
    }

    func testScreenshotResultBecomesImagePin() {
        let controller = makeController()
        let result = ScreenshotResult(
            imageData: makePNGData(),
            width: 40,
            height: 30,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: nil
        )

        let item = controller.present(result)

        XCTAssertEqual(item.payload.kind, .image)
        XCTAssertEqual(controller.store.item(id: item.id)?.payload.kind, .image)
        controller.destroyAll()
    }

    // MARK: - Lifecycle

    func testCloseRemovesWindowButKeepsRestoreQueue() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))

        controller.close(item.id)

        XCTAssertEqual(controller.windowCount, 0)
        XCTAssertEqual(controller.store.closedCount, 1)

        let restored = controller.restoreLatestClosed()
        XCTAssertEqual(restored?.id, item.id)
        XCTAssertEqual(controller.windowCount, 1)
        controller.destroyAll()
    }

    func testDestroyRemovesWindowAndState() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))

        controller.destroy(item.id)

        XCTAssertEqual(controller.windowCount, 0)
        XCTAssertNil(controller.store.item(id: item.id))
        XCTAssertNil(controller.restoreLatestClosed())
    }

    func testDestroyAllClosesEverything() {
        let controller = makeController()
        controller.present(payload: .text("1"))
        controller.present(payload: .text("2"))

        controller.destroyAll()

        XCTAssertEqual(controller.windowCount, 0)
        XCTAssertEqual(controller.store.activeCount, 0)
        XCTAssertEqual(controller.store.closedCount, 0)
    }

    func testHideAllOrdersOutButShowAllRestores() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))

        controller.hideAll()
        XCTAssertTrue(controller.store.item(id: item.id)?.isHidden ?? false)

        controller.showAll()
        XCTAssertFalse(controller.store.item(id: item.id)?.isHidden ?? true)
        controller.destroyAll()
    }

    func testMouseEventsPassthroughToggleAppliesToWindows() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))

        controller.toggleIgnoresMouseEventsForAll()
        XCTAssertTrue(controller.store.item(id: item.id)?.ignoresMouseEvents ?? false)

        controller.toggleIgnoresMouseEventsForAll()
        XCTAssertFalse(controller.store.item(id: item.id)?.ignoresMouseEvents ?? true)
        controller.destroyAll()
    }

    // MARK: - Transform via container callbacks（键位表：docs/prd/02-ui-spec.md「贴图」）

    func testWheelScaleClampedToBoundaries() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))

        // 通过容器视图的滚轮回调放大/缩小，验证最终钳制。
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }
        container.onScale?(8)   // 1 × 8 = 800%（上限）
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.scale, PinTransform.maximumScale)
        container.onScale?(2)   // 超出上限仍钳制
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.scale, PinTransform.maximumScale)
        container.onScale?(0.01) // 缩到下限 10%
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.scale, PinTransform.minimumScale)
        controller.destroyAll()
    }

    func testRotateAndFlipCallbacks() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onRotate?(1)
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.quarterTurns, 1, "`1`：顺时针 90°")
        container.onRotate?(-1)
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.quarterTurns, 0, "`2`：逆时针 90°")
        container.onRotate?(-1)
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.quarterTurns, 3, "逆时针跨 0 点回卷")

        container.onFlipHorizontally?()
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.flippedHorizontally, true, "`3`：水平翻转")
        container.onFlipVertically?()
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.flippedVertically, true, "`4`：垂直翻转")
        controller.destroyAll()
    }

    func testCommandOpacityAdjustmentClamped() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onAdjustOpacity?(-0.3)
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.opacity ?? 0, 0.7, accuracy: 0.0001)

        container.onAdjustOpacity?(5)   // 超出上限仍钳制 100%
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.opacity, PinTransform.maximumOpacity)

        container.onAdjustOpacity?(-5)  // 超出下限仍钳制 10%
        XCTAssertEqual(controller.store.item(id: item.id)?.transform.opacity, PinTransform.minimumOpacity)
        controller.destroyAll()
    }

    func testMiddleClickResetsScaleAndOpacityOnly() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onScale?(4)
        container.onRotate?(1)
        container.onFlipHorizontally?()
        container.onAdjustOpacity?(-0.5)

        container.onResetScaleAndOpacity?()  // 中键
        let transform = controller.store.item(id: item.id)?.transform
        XCTAssertEqual(transform?.scale, 1, "恢复 100% 缩放")
        XCTAssertEqual(transform?.opacity, 1, "恢复 100% 不透明度")
        XCTAssertEqual(transform?.quarterTurns, 1, "不复位旋转")
        XCTAssertEqual(transform?.flippedHorizontally, true, "不复位翻转")
        controller.destroyAll()
    }

    func testCloseCallbackEntersRestoreQueue() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onClose?()  // Esc / ⌘W / 左键双击

        XCTAssertEqual(controller.windowCount, 0)
        XCTAssertEqual(controller.store.closedCount, 1, "关闭进入恢复队列")
        XCTAssertEqual(controller.restoreLatestClosed()?.id, item.id)
        controller.destroyAll()
    }

    func testDestroyCallbackPermanentlyRemoves() {
        let controller = makeController()
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onDestroy?()  // ⇧Esc

        XCTAssertEqual(controller.windowCount, 0)
        XCTAssertNil(controller.store.item(id: item.id), "销毁后不可恢复")
        XCTAssertNil(controller.restoreLatestClosed())
    }

    func testOpenSettingsCallbackWired() {
        var settingsOpened = false
        let controller = PinWindowController(
            store: PinStore(),
            payloadFactory: PinPayloadFactory(filePathToImage: false),
            onOpenSettings: { settingsOpened = true }
        )
        let item = controller.present(payload: .text("pin"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        container.onOpenSettings?()  // ⇧⌘P
        XCTAssertTrue(settingsOpened, "⇧⌘P 打开截图与贴图设置")
        controller.destroyAll()
    }

    // MARK: - ⇧⌘C 复制纯文本

    func testCopyPlainTextForTextAndHTMLPins() {
        let controller = makeController()
        let original = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let original { NSPasteboard.general.setString(original, forType: .string) }
        }

        let textPin = controller.present(payload: .text("plain pinned"))
        controller.copyPlainText(for: textPin.id)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "plain pinned")

        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12)]
        let htmlPin = controller.present(payload: .attributedText(NSAttributedString(string: "rich pinned", attributes: attributes)))
        controller.copyPlainText(for: htmlPin.id)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "rich pinned", "HTML 贴图复制纯文本")
        controller.destroyAll()
    }

    func testCopyPlainTextIsNoOpForImageAndColorPins() {
        let controller = makeController()
        let original = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let original { NSPasteboard.general.setString(original, forType: .string) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sentinel", forType: .string)

        let colorPin = controller.present(payload: .color(red: 1, green: 2, blue: 3))
        controller.copyPlainText(for: colorPin.id)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "sentinel", "颜色贴图 no-op")

        let imagePin = controller.present(payload: .image(makePNGData()))
        controller.copyPlainText(for: imagePin.id)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "sentinel", "图像贴图 no-op")
        controller.destroyAll()
    }

    // MARK: - ⌘V 替换载荷

    func testReplaceFromPasteboardKeepsIdentity() {
        let controller = makeController()
        let item = controller.present(payload: .text("before"))
        guard let container = eventContainer(of: controller, item: item) else {
            return XCTFail("Expected pin window with event container")
        }

        // ⌘V 路径读取系统通用剪贴板：先暂存原内容，用颜色字符串驱动替换。
        let original = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let original { NSPasteboard.general.setString(original, forType: .string) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("#00FF00", forType: .string)

        container.onReplaceFromPasteboard?()

        XCTAssertEqual(controller.store.item(id: item.id)?.payload.kind, .color, "⌘V 替换载荷")
        XCTAssertEqual(controller.store.item(id: item.id)?.id, item.id)
        controller.destroyAll()
    }

    // MARK: - 截图贴图原位（PRD 规则 14）

    func testScreenshotPinUsesSelectionRectInPlace() {
        let controller = makeController()
        let globalRect = NSRect(x: 120, y: 90, width: 300, height: 200)
        let selection = RegionCaptureSelection(
            sessionID: UUID(),
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            globalRect: globalRect
        )
        let result = ScreenshotResult(
            imageData: makePNGData(),
            width: 300,
            height: 200,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: selection
        )

        let item = controller.present(result)

        guard let window = controller.window(for: item.id) else {
            return XCTFail("Expected pin window for screenshot pin")
        }
        XCTAssertEqual(window.frame.origin, globalRect.origin, "截图贴图沿用选区原位")
        XCTAssertEqual(window.frame.size, globalRect.size, "截图贴图沿用选区原尺寸（不受 40% 上限约束）")
        controller.destroyAll()
    }

    func testScreenshotPinWithoutSelectionFallsBackToDefaultImageSize() {
        let controller = makeController()
        let result = ScreenshotResult(
            imageData: makePNGData(),
            width: 40,
            height: 30,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: nil
        )

        let item = controller.present(result)

        guard let window = controller.window(for: item.id) else {
            return XCTFail("Expected pin window for screenshot pin")
        }
        XCTAssertEqual(window.frame.size, PinWindowLayout.minimumSize, "无选区回退默认规则：40×30 小图不放大且不低于最小 80×60")
        controller.destroyAll()
    }

    // MARK: - 键位映射（keyAction 纯函数）

    func testKeyActionMappingMatchesUISpec() {
        let map = PinEventContainerView.keyAction

        XCTAssertEqual(map("1", []), .rotateClockwise, "`1` 顺时针 90°")
        XCTAssertEqual(map("2", []), .rotateCounterClockwise, "`2` 逆时针 90°")
        XCTAssertEqual(map("3", []), .flipHorizontally, "`3` 水平翻转")
        XCTAssertEqual(map("4", []), .flipVertically, "`4` 垂直翻转")

        XCTAssertEqual(map("=", []), .zoomIn, "`=` 放大")
        XCTAssertEqual(map("+", []), .zoomIn, "`+` 放大")
        XCTAssertEqual(map("-", []), .zoomOut, "`-` 缩小")

        XCTAssertEqual(map("=", [.command]), .opacityUp, "`⌘=` 提高不透明度")
        XCTAssertEqual(map("+", [.command]), .opacityUp, "`⌘+` 提高不透明度")
        XCTAssertEqual(map("-", [.command]), .opacityDown, "`⌘-` 降低不透明度")

        XCTAssertEqual(map("\u{1B}", []), .close, "`Esc` 关闭")
        XCTAssertEqual(map("\u{1B}", [.shift]), .destroy, "`⇧Esc` 销毁")
        XCTAssertEqual(map("w", [.command]), .close, "`⌘W` 关闭")

        XCTAssertEqual(map("v", [.command]), .replaceFromPasteboard, "`⌘V` 替换载荷")
        XCTAssertEqual(map("c", [.command, .shift]), .copyPlainText, "`⇧⌘C` 复制纯文本")
        XCTAssertEqual(map("C", [.command, .shift]), .copyPlainText, "⇧⌘C 的 charactersIgnoringModifiers 为大写 C")
        XCTAssertEqual(map("p", [.command, .shift]), .openSettings, "`⇧⌘P` 打开截图与贴图设置")

        XCTAssertNil(map("c", [.command]), "⌘C 不属于贴图键位")
        XCTAssertNil(map("x", [.command]))
        XCTAssertNil(map("5", []), "数字键 5–8 预设缩放已删除")
    }

    // MARK: - PinWindowLayout（PRD 规则 12–15）

    func testTextLikePayloadsUse420x280() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(
            PinWindowLayout.defaultSize(forPayload: .text("hi"), visibleFrame: visible),
            PinWindowLayout.textPinSize
        )
        XCTAssertEqual(
            PinWindowLayout.defaultSize(forPayload: .attributedText(NSAttributedString(string: "hi")), visibleFrame: visible),
            PinWindowLayout.textPinSize
        )
        XCTAssertEqual(
            PinWindowLayout.defaultSize(forPayload: .color(red: 1, green: 2, blue: 3), visibleFrame: visible),
            PinWindowLayout.textPinSize
        )
    }

    func testImagePayloadSizeCapsAtFortyPercentOfVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = PinWindowLayout.imageSize(forPointSize: NSSize(width: 3000, height: 2000), visibleFrame: visible)
        XCTAssertEqual(size.width, 400, accuracy: 0.01, "宽度钳制到可见区 40%")
        XCTAssertEqual(size.height, 266.666, accuracy: 0.01, "高度按宽高比等比缩小")
    }

    func testImagePayloadSizeDoesNotEnlargeSmallImages() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = PinWindowLayout.imageSize(forPointSize: NSSize(width: 300, height: 200), visibleFrame: visible)
        XCTAssertEqual(size, NSSize(width: 300, height: 200), "小图保持原始点尺寸")
    }

    func testImagePayloadSizeFloorsAtMinimumSize() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = PinWindowLayout.imageSize(forPointSize: NSSize(width: 40, height: 30), visibleFrame: visible)
        XCTAssertEqual(size, PinWindowLayout.minimumSize, "最小 80×60")
    }

    func testCascadeOriginOffsetsAndWrapsToCenter() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = NSSize(width: 200, height: 200)
        let center = NSPoint(x: 400, y: 400)

        XCTAssertEqual(PinWindowLayout.cascadeOrigin(index: 0, size: size, visibleFrame: visible), center, "首张位于可见区中央")
        XCTAssertEqual(PinWindowLayout.cascadeOrigin(index: 1, size: size, visibleFrame: visible), NSPoint(x: 424, y: 376), "每张向右下偏移 24pt")
        XCTAssertEqual(PinWindowLayout.cascadeOrigin(index: 2, size: size, visibleFrame: visible), NSPoint(x: 448, y: 352))

        // 右移/下移各余 400pt → 最多 16 步；index 17 回卷到中央重新开始。
        XCTAssertEqual(PinWindowLayout.cascadeOrigin(index: 16, size: size, visibleFrame: visible), NSPoint(x: 784, y: 16))
        XCTAssertEqual(PinWindowLayout.cascadeOrigin(index: 17, size: size, visibleFrame: visible), center, "到达边缘后回到中央重新开始")
    }

    func testCascadeOriginStaysCenteredWhenWindowDoesNotFit() {
        let visible = NSRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(
            PinWindowLayout.cascadeOrigin(index: 5, size: PinWindowLayout.textPinSize, visibleFrame: visible),
            NSPoint(x: -60, y: -40),
            "窗口放不进可见区时始终居中（不级联越界）"
        )
    }

    func testScreenshotFrameUsesSelectionRectAsIs() {
        let rect = NSRect(x: 120, y: 90, width: 300, height: 200)
        XCTAssertEqual(PinWindowLayout.screenshotFrame(forSelectionRect: rect), rect, "直接沿用选区矩形")
        XCTAssertNil(PinWindowLayout.screenshotFrame(forSelectionRect: nil), "无选区回退默认规则")
    }
}
