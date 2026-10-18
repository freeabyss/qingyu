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
            window.frame,
            ScreenshotGeometry.toolbarFrame(
                selection: selection,
                toolbarSize: controller.regionToolbarSize,
                screenFrame: screenFrame
            ),
            "工具条位置不得因进入标注而改变"
        )
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
}
