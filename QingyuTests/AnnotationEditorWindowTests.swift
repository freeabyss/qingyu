import AppKit
import XCTest
@testable import Qingyu

/// 标注编辑器窗口尺寸契约。
///
/// 用户报告（2026-10-18）：「拖拽完毕后，点击截图工具时，截图缩小了，应该保持不变」。
///
/// 成因：`NSWindow.contentViewController` 的赋值会把窗口尺寸改成**内容的固有尺寸**。
/// 编辑器内容里画布是 `NSViewRepresentable`（没有固有尺寸），只有上下两条工具条有，
/// 于是窗口被缩成约 312×132 的窄条；画布再把截图 `min(bounds/imageSize)` 缩放进去，
/// 用户看到的就是「点标注后截图突然变小了」。区域截图下窗口本该与选区严丝合缝。
@MainActor
final class AnnotationEditorWindowTests: XCTestCase {

    private func makeImage(width: Int = 918, height: Int = 683) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        return NSImage(
            cgImage: rep.cgImage!,
            size: NSSize(width: width, height: height)
        )
    }

    private func makeEditor(presentationFrame: NSRect?) -> AnnotationEditorWindow {
        AnnotationEditorWindow(
            image: makeImage(),
            captureDate: Date(timeIntervalSince1970: 0),
            presentationFrame: presentationFrame,
            initialTool: .rectangle,
            onCopy: { _ in },
            onSave: { _, _ in URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("unused.png") },
            onComplete: { _ in }
        )
    }

    /// 区域截图进入标注：窗口必须与选区严丝合缝，截图按 1:1 呈现。
    func testRegionEditorWindowMatchesTheSelection() throws {
        let selection = NSRect(x: 420, y: 260, width: 918, height: 683)
        let editor = makeEditor(presentationFrame: selection)

        editor.present()
        defer { editor.close() }

        let frame = try XCTUnwrap(editor.window?.frame)
        XCTAssertEqual(frame.width, selection.width, accuracy: 0.5, "标注窗口被缩窄 → 截图会被缩放成更小的一张")
        XCTAssertEqual(frame.height, selection.height, accuracy: 0.5, "标注窗口被压矮 → 截图会被缩放成更小的一张")
        XCTAssertEqual(frame.origin.x, selection.origin.x, accuracy: 0.5, "区域标注窗必须盖在选区上")
        XCTAssertEqual(frame.origin.y, selection.origin.y, accuracy: 0.5, "区域标注窗必须盖在选区上")
    }

    /// 非区域入口（预览 → 标注）：窗口按 `computeWindowRect()` 的尺寸开，不得被内容挤成一条窄条。
    func testPreviewEditorWindowKeepsItsComputedSize() throws {
        let editor = makeEditor(presentationFrame: nil)

        editor.present()
        defer { editor.close() }

        let frame = try XCTUnwrap(editor.window?.frame)
        XCTAssertGreaterThanOrEqual(frame.width, 680, "窗口宽度下限被内容尺寸覆盖了")
        XCTAssertGreaterThanOrEqual(frame.height, 480, "窗口高度下限被内容尺寸覆盖了")
    }
}
