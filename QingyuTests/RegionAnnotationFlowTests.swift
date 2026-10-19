import AppKit
import XCTest
@testable import Qingyu

/// 「点标注工具 = 原地编辑，不动其他任何东西」的行为契约（用户预期 2026-10-18）。
///
/// 旧行为是点工具后另开一个标注编辑窗：选区外的压暗消失、工具条被换成编辑器自己那套。
/// 用户明确要求「选中区域、工具栏、选中区域之外，没有变化」，因此这条链路现在是：
/// 懒捕获 → 叠层进入标注态 → 工具条原地重排（只高亮选中工具），窗口实例与位置都不变。
@MainActor
final class RegionAnnotationFlowTests: XCTestCase {

    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let selection = CGRect(x: 400, y: 400, width: 600, height: 400)

    /// 记录型宿主：只记录被谁、以什么顺序调用，绝不碰真实叠层。
    private final class AnnotationHostSpy: RegionAnnotationHost {
        private(set) var prepareCalls = 0
        private(set) var beginCalls: [(tool: AnnotationTool, region: CGRect)] = []
        private(set) var toolUpdates: [AnnotationTool] = []
        private(set) var styleUpdates: [AnnotationStyle] = []
        private(set) var finished = false
        var shapes: [AnnotationShape] = []
        var isAnnotating = false

        func prepareForAnnotationCapture() { prepareCalls += 1 }

        func beginAnnotation(
            image: NSImage,
            regionGlobal: CGRect,
            tool: AnnotationTool,
            style: AnnotationStyle
        ) -> Bool {
            beginCalls.append((tool, regionGlobal))
            isAnnotating = true
            return true
        }

        func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle) {
            toolUpdates.append(tool)
            styleUpdates.append(style)
        }

        var annotationShapes: [AnnotationShape] { shapes }
        var annotationRegionSize: CGSize { CGSize(width: 600, height: 400) }

        func finishAnnotation() {
            finished = true
            isAnnotating = false
        }
    }

    private final class CaptureSpy {
        private(set) var calls = 0
        let screenFrame: CGRect
        let selection: CGRect

        init(screenFrame: CGRect, selection: CGRect) {
            self.screenFrame = screenFrame
            self.selection = selection
        }

        func capture() async throws -> ScreenshotResult {
            calls += 1
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let data = rep.representation(using: .png, properties: [:])!
            return ScreenshotResult(
                imageData: data, width: 1200, height: 800,
                captureDate: Date(), sourceType: .region,
                regionSelection: RegionCaptureSelection(
                    sessionID: UUID(), displayID: 1,
                    screenFrame: screenFrame, globalRect: selection
                )
            )
        }
    }

    /// 点工具：只进入标注态，**不**结束会话、**不**隐藏叠层（不触发 onDismiss）。
    func testPickingAToolEntersInPlaceAnnotationWithoutEndingTheSession() async throws {
        let controller = ScreenshotToolbarController()
        let host = AnnotationHostSpy()
        let spy = CaptureSpy(screenFrame: screenFrame, selection: selection)
        var dismissCalls = 0

        controller.showRegionDraft(
            globalRect: selection,
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            annotationCapture: { try await spy.capture() },
            onDismiss: { dismissCalls += 1 },
            annotationHost: host
        )

        let draftToolbarSize = controller.regionToolbarSize
        await controller.performDraftAnnotation(tool: .rectangle)

        XCTAssertEqual(host.beginCalls.count, 1, "点工具应进入原地标注")
        XCTAssertEqual(host.beginCalls.first?.tool, .rectangle)
        XCTAssertEqual(host.beginCalls.first?.region, selection, "标注必须锚在同一个选区上")
        XCTAssertEqual(dismissCalls, 0, "标注期间会话继续，不得触发收尾（会取消会话）")
        XCTAssertTrue(host.isAnnotating)
        XCTAssertEqual(spy.calls, 1, "只在进入标注时捕获一次")

        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible, "工具条必须留在原处可见")
        XCTAssertTrue(window.becomesKeyOnlyIfNeeded, "工具条仍不得夺 key：叠层要继续持有键盘")
        XCTAssertEqual(
            controller.regionToolbarSize.height,
            draftToolbarSize.height,
            "工具条保持单行；颜色/粗细放在独立样式面板里"
        )
        XCTAssertEqual(
            window.frame,
            ScreenshotGeometry.toolbarFrame(
                selection: selection,
                toolbarSize: controller.regionToolbarSize,
                screenFrame: screenFrame
            ),
            "工具条位置不得因选中工具而改变"
        )

        let content = try XCTUnwrap(window.contentView as? RegionToolbarView)
        let palette = try XCTUnwrap(controller.stylePaletteViewForTesting, "点工具后必须出现样式面板")
        XCTAssertEqual(palette.modeForTesting, .line, "矩形工具应出现颜色 + 粗细面板")
        XCTAssertNotNil(palette.colorButtonForTesting(0), "矩形工具应出现颜色选项")
        XCTAssertNotNil(palette.sizeButtonForTesting(0), "矩形工具应出现粗细选项")
        XCTAssertNil(palette.backgroundButtonForTesting(0), "矩形工具不应出现背景色选项")

        // 面板贴在矩形按钮正下方，而不是铺满工具条。
        let paletteWindow = try XCTUnwrap(controller.stylePaletteWindowForTesting)
        let button = try XCTUnwrap(content.buttonFrame(forTool: .rectangle))
        XCTAssertEqual(paletteWindow.frame.minX, window.frame.minX + button.minX, accuracy: 0.5)
        XCTAssertEqual(paletteWindow.frame.maxY, window.frame.minY + button.minY - 6, accuracy: 0.5)

        palette.colorButtonForTesting(2)?.performClick(nil)
        XCTAssertEqual(host.styleUpdates.last?.color, .blue, "标注中改颜色必须即时传给叠层")
    }

    /// 选中工具后可以继续切换别的工具：高亮跟着走、样式面板换形态并重新贴到新按钮下方。
    func testSwitchingToolsMovesHighlightAndStylePalette() async throws {
        let controller = ScreenshotToolbarController()
        let host = AnnotationHostSpy()
        let spy = CaptureSpy(screenFrame: screenFrame, selection: selection)

        controller.showRegionDraft(
            globalRect: selection,
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            annotationCapture: { try await spy.capture() },
            onDismiss: {},
            annotationHost: host
        )
        await controller.performDraftAnnotation(tool: .rectangle)

        controller.selectAnnotationToolForTesting(.eraser)

        XCTAssertEqual(host.toolUpdates.last, .eraser, "换工具必须通知叠层")
        XCTAssertEqual(controller.stylePaletteViewForTesting?.modeForTesting, .sizeOnlyBrush)
        XCTAssertNil(controller.stylePaletteViewForTesting?.colorButtonForTesting(0), "橡皮擦面板没有颜色")
        XCTAssertNotNil(controller.stylePaletteViewForTesting?.sizeButtonForTesting(0))

        let content = try XCTUnwrap(controller.window?.contentView as? RegionToolbarView)
        let eraserIndex = try XCTUnwrap(AnnotationTool.allCases.firstIndex(of: .eraser))
        let highlightAlpha = content.buttonForTesting(eraserIndex)?.layer?.backgroundColor?.alpha ?? 0
        XCTAssertGreaterThan(highlightAlpha, 0.1, "选中工具必须高亮")
        let rectangleIndex = try XCTUnwrap(AnnotationTool.allCases.firstIndex(of: .rectangle))
        let staleAlpha = content.buttonForTesting(rectangleIndex)?.layer?.backgroundColor?.alpha ?? 0
        XCTAssertEqual(staleAlpha, 0, accuracy: 0.001, "旧工具的高亮必须撤掉")
    }

    /// 标注中换工具：只调用 `updateAnnotationTool`，不重新捕获、不移动工具条窗口。
    func testSwitchingToolsDoesNotRecaptureOrMoveTheToolbar() async throws {
        let controller = ScreenshotToolbarController()
        let host = AnnotationHostSpy()
        let spy = CaptureSpy(screenFrame: screenFrame, selection: selection)

        controller.showRegionDraft(
            globalRect: selection,
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            annotationCapture: { try await spy.capture() },
            onDismiss: {},
            annotationHost: host
        )
        await controller.performDraftAnnotation(tool: .rectangle)
        let window = try XCTUnwrap(controller.window)
        let frameBefore = window.frame
        let originBefore = window.frame.origin

        controller.selectAnnotationToolForTesting(.arrow)

        XCTAssertEqual(host.toolUpdates, [.arrow], "换工具只走标注态更新")
        XCTAssertEqual(spy.calls, 1, "换工具不得再次捕获")
        XCTAssertTrue(controller.window === window, "工具条窗口实例不得重建")
        XCTAssertEqual(window.frame, frameBefore, "工具条位置不得改变")
        XCTAssertEqual(window.frame.origin, originBefore)
    }

    /// 标注完成（复制）：形状烘进位图后收起临时画布，并走既有复制路径。
    func testFinishingAnnotatedCopyFlattensThenCopies() async throws {
        let controller = ScreenshotToolbarController()
        let host = AnnotationHostSpy()
        let spy = CaptureSpy(screenFrame: screenFrame, selection: selection)
        host.shapes = [
            AnnotationShape(
                tool: .rectangle,
                startPoint: CGPoint(x: 10, y: 10),
                endPoint: CGPoint(x: 100, y: 100),
                text: nil,
                style: AnnotationStyle()
            )
        ]

        controller.showRegionDraft(
            globalRect: selection,
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            annotationCapture: { try await spy.capture() },
            onDismiss: {},
            annotationHost: host
        )
        await controller.performDraftAnnotation(tool: .rectangle)

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy.types.isEmpty ? nil : copy
        }
        defer {
            if let saved, !saved.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(saved)
            }
        }

        await controller.performAnnotatedActionForTesting(.copy)

        XCTAssertTrue(host.finished, "动作完成后应收起标注画布")
        XCTAssertNotNil(pasteboard.data(forType: .png), "复制应把带标注的结果写进剪贴板")
    }

    /// SHOT-LIFE-016：真实叠层必须真正进入标注态，并且选区内拖拽能落下图形。
    ///
    /// 用户报告（2026-10-18）：「选中方形后，无法画出方形」。根因是
    /// CaptureOverlayWindowController.beginAnnotation 的签名与协议要求（返回 Bool）
    /// 不一致：Swift 静默采用协议扩展里的默认实现（什么都不做、返回 false），
    /// 会话却仍把 isAnnotating 置为 true。于是工具条一直以为在标注、点工具只换高亮，
    /// 而内容视图的 annotationSession 为 nil，所有落笔都被忽略。
    func testConcreteOverlayStartsAnnotationThroughProtocolAndAcceptsDrawing() throws {
        let display = CaptureDisplay(
            id: 7,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            pixelSize: CGSize(width: 800, height: 600)
        )
        let overlay = CaptureOverlayWindowController(display: display)
        let region = CGRect(x: 100, y: 100, width: 400, height: 300)

        let started = (overlay as CaptureOverlayWindow).beginAnnotation(
            image: NSImage(size: region.size),
            regionGlobal: region,
            tool: .rectangle,
            style: AnnotationStyle()
        )

        XCTAssertTrue(started, "协议派发必须到达真实叠层（不能落到默认实现的 false）")
        XCTAssertTrue(overlay.isAnnotating, "内容视图必须进入标注态，否则落笔会被直接忽略")
        let view = overlay.contentViewForTesting
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "第一次点击就必须能落笔，而不是只激活窗口")

        let down = try mouseEvent(.leftMouseDown, at: NSPoint(x: 150, y: 150))
        let drag = try mouseEvent(.leftMouseDragged, at: NSPoint(x: 350, y: 300))
        let up = try mouseEvent(.leftMouseUp, at: NSPoint(x: 350, y: 300))
        view.mouseDown(with: down)
        view.mouseDragged(with: drag)
        view.mouseUp(with: up)

        XCTAssertEqual(overlay.annotationShapes.count, 1, "选区内拖拽必须落下一个矩形")
        XCTAssertEqual(overlay.annotationShapes.first?.tool, .rectangle)
    }

    /// 文字工具在落点直接出现输入框（不是 NSAlert），回车提交成一条文字标注。
    func testInlineTextAppearsAtCursorAndCommitsOnReturn() throws {
        let display = CaptureDisplay(
            id: 8,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            pixelSize: CGSize(width: 800, height: 600)
        )
        let overlay = CaptureOverlayWindowController(display: display)
        let region = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertTrue((overlay as CaptureOverlayWindow).beginAnnotation(
            image: NSImage(size: region.size),
            regionGlobal: region,
            tool: .text,
            style: AnnotationStyle()
        ))

        let view = overlay.contentViewForTesting
        view.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: 160, y: 160)))

        let field = try XCTUnwrap(
            view.subviews.compactMap { $0 as? NSTextField }.first,
            "文字工具必须在光标落点直接出现输入框，而不是弹系统对话框"
        )
        XCTAssertFalse(field.drawsBackground, "输入框必须是透明的（用户要求）")
        field.stringValue = "Hello"
        _ = view.control(
            field,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertEqual(overlay.annotationShapes.count, 1)
        XCTAssertEqual(overlay.annotationShapes.first?.tool, .text)
        XCTAssertEqual(overlay.annotationShapes.first?.text, "Hello")
        XCTAssertTrue(
            view.subviews.compactMap { $0 as? NSTextField }.isEmpty,
            "提交后输入框应被移除"
        )
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
    }
}
