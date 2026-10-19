import AppKit
import XCTest
@testable import Qingyu

/// 原地标注的**叠层外观与几何**回归（用户预期 2026-10-18）。
///
/// 这些断言覆盖的都不是「能不能画线」，而是用户逐条指出的约束：
/// 1. 点工具之后，叠层上除光标以外**没有任何变化**（压暗范围、选区边框、尺寸徽标）；
/// 2. 形状坐标就是选区局部点，导出时必须按「选区点 → 图像像素」整体缩放；
/// 3. 光标随工具变化，但只在选区内生效。
@MainActor
final class InPlaceAnnotationTests: XCTestCase {

    private let displayFrame = CGRect(x: 0, y: 0, width: 800, height: 500)
    private let region = CGRect(x: 200, y: 150, width: 240, height: 120)

    private var display: CaptureDisplay {
        CaptureDisplay(
            id: 1,
            frame: displayFrame,
            pixelSize: CGSize(width: displayFrame.width, height: displayFrame.height)
        )
    }

    // MARK: - Fixtures

    /// 纯色位图（`size` 为逻辑尺寸，`pixels` 为其像素尺寸）。
    private func makeImage(size: CGSize, pixels: CGSize, color: NSColor = .gray) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
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
        color.setFill()
        NSRect(origin: .zero, size: pixels).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func makeSession(tool: AnnotationTool = .rectangle) -> InPlaceAnnotationSession {
        let session = InPlaceAnnotationSession(
            image: makeImage(size: region.size, pixels: CGSize(width: 480, height: 240)),
            regionGlobalRect: region,
            displayFrame: displayFrame
        )
        session.state.tool = tool
        return session
    }

    private func makeOverlay(isActive: Bool = true) -> CaptureOverlayContentView {
        let view = CaptureOverlayContentView(
            frame: NSRect(origin: .zero, size: displayFrame.size),
            display: display
        )
        view.isActiveDisplay = isActive
        view.regionFrame = region
        view.layoutSubtreeIfNeeded()
        return view
    }

    @discardableResult
    private func render(_ view: NSView, dump name: String) -> NSBitmapImageRep {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/annotation-\(name).png"))
        }
        return rep
    }

    /// 位图坐标（左上原点）处的 alpha；选区内是「透出」（0），选区外是压暗层（>0）。
    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? -1
    }

    // MARK: - 坐标

    /// 形状坐标必须是**选区局部点**：全局点减去选区原点，且钳制进选区。
    func testLocalPointIsSelectionRelativeAndClamped() {
        let session = makeSession()
        let inside = CGPoint(x: region.minX + 30, y: region.minY + 40)
        XCTAssertEqual(session.localPoint(inside), CGPoint(x: 30, y: 40))

        // 拖到选区外：贴边继续，不能画出选区。
        let farTopRight = CGPoint(x: region.maxX + 500, y: region.maxY + 500)
        XCTAssertEqual(session.localPoint(farTopRight), CGPoint(x: region.width, y: region.height))
        XCTAssertTrue(session.contains(global: inside))
        XCTAssertFalse(session.contains(global: farTopRight))
    }

    /// 选区在叠层坐标里的位置：只做原点平移，尺寸不变。
    func testLocalRectOffsetsByDisplayOrigin() {
        let session = makeSession()
        XCTAssertEqual(session.localRect, region)
    }

    // MARK: - 绘制：点工具不得改变叠层其余部分

    /// 进入标注前后：选区内的 alpha（透出）与选区外的压暗层必须**完全一致**。
    ///
    /// 用户原话：「选中工具栏时，选中区域、工具栏、选中区域之外，没有变化。」
    func testEnteringAnnotationDoesNotChangeOverlayAppearance() {
        let view = makeOverlay()
        let before = render(view, dump: "before")

        let image = makeImage(size: region.size, pixels: CGSize(width: 480, height: 240))
        view.beginAnnotation(image: image, regionGlobal: region, tool: .rectangle, style: AnnotationStyle())

        // 没有任何形状时，标注层不画任何东西：画面必须与进入前逐点相同。
        let after = render(view, dump: "after-empty")
        for point in [(50, 50), (700, 450), (400, 250)] {
            XCTAssertEqual(
                alpha(after, x: point.0, y: point.1),
                alpha(before, x: point.0, y: point.1),
                accuracy: 0.02,
                "进入标注后画面不得变化（点 \(point)）"
            )
        }
    }

    /// 画了一个矩形之后：形状必须落在**选区之内**，选区外仍然只有压暗层。
    func testShapeIsDrawnInsideSelectionOnly() {
        let view = makeOverlay()
        let image = makeImage(size: region.size, pixels: CGSize(width: 480, height: 240))
        view.beginAnnotation(image: image, regionGlobal: region, tool: .rectangle, style: AnnotationStyle())

        let session = InPlaceAnnotationSession(
            image: makeImage(size: region.size, pixels: CGSize(width: 480, height: 240)),
            regionGlobalRect: region,
            displayFrame: displayFrame
        )
        session.state.tool = .rectangle
        _ = session.mouseDown(at: CGPoint(x: region.minX + 20, y: region.minY + 20))
        _ = session.mouseDragged(to: CGPoint(x: region.maxX - 20, y: region.maxY - 20))
        _ = session.mouseUp(at: CGPoint(x: region.maxX - 20, y: region.maxY - 20))
        XCTAssertEqual(session.state.shapes.count, 1, "一次拖拽应产生一条矩形")
        // 形状坐标是选区局部点：必须落在 [0, width] × [0, height] 之内。
        let rect = session.state.shapes[0].rect
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, region.width)
        XCTAssertLessThanOrEqual(rect.maxY, region.height)
    }

    // MARK: - 工具与光标

    /// 换工具只改 `state.tool`，已画的形状与叠层区域一律不动（标注会话是同一份状态）。
    func testSwitchingToolKeepsShapes() {
        let session = makeSession(tool: .rectangle)
        _ = session.mouseDown(at: CGPoint(x: region.minX + 10, y: region.minY + 10))
        _ = session.mouseDragged(to: CGPoint(x: region.minX + 80, y: region.minY + 80))
        _ = session.mouseUp(at: CGPoint(x: region.minX + 80, y: region.minY + 80))
        XCTAssertEqual(session.state.shapes.count, 1)

        session.state.tool = .arrow
        XCTAssertEqual(session.state.shapes.count, 1, "切工具不得清空已有标注")
    }

    /// 每个工具的光标互不相同（用户预期「光标随着选中的工具不同而变化」）。
    func testEachToolHasItsOwnCursor() {
        let style = AnnotationStyle()
        let cursors = AnnotationTool.allCases.map { AnnotationToolCursor.cursor(for: $0, style: style) }
        for (index, cursor) in cursors.enumerated() {
            for other in cursors[(index + 1)...] {
                XCTAssertFalse(cursor === other, "不同工具必须各有自己的光标")
            }
        }
    }

    /// 光标只在选区内生效：`mouseMoved` 的边界判定必须严格以选区为准。
    ///
    /// 用户原话：「光标只有在截图区域才会发生变化」—— 选区外必须是箭头。
    func testCursorRegionBoundaryIsTheSelection() {
        let session = makeSession(tool: .arrow)
        XCTAssertTrue(session.contains(global: CGPoint(x: region.minX + 1, y: region.minY + 1)))
        XCTAssertFalse(session.contains(global: CGPoint(x: region.minX - 1, y: region.minY + 1)))
        XCTAssertFalse(session.contains(global: CGPoint(x: region.maxX + 1, y: region.midY)))
        XCTAssertFalse(session.contains(global: CGPoint(x: region.midX, y: region.maxY + 1)))
        XCTAssertLessThan(region.width, displayFrame.width, "游标区必须小于整屏")
    }

    // MARK: - 圆点笔刷（2026-10-19）

    /// 线工具与笔刷工具共用三档，但笔刷映射到明显的圆点直径。
    func testBrushDiameterMapsThreeSizes() {
        XCTAssertEqual(AnnotationStyle(lineWidth: .thin).brushDiameter(for: .highlighter), 14)
        XCTAssertEqual(AnnotationStyle(lineWidth: .medium).brushDiameter(for: .marker), 24)
        XCTAssertEqual(AnnotationStyle(lineWidth: .thick).brushDiameter(for: .gaussianBlur), 40)
        XCTAssertTrue(AnnotationTool.marker.isBrush, "马克笔是圆点笔刷")
        XCTAssertTrue(AnnotationTool.gaussianBlur.isFreehand, "模糊改为笔刷轨迹")
        XCTAssertFalse(AnnotationTool.rectangle.isBrush)
    }

    /// 笔刷单击也要留下一个圆点（而不是要求拖拽距离）。
    func testBrushSingleClickLeavesADot() {
        let session = makeSession(tool: .highlighter)
        session.state.style = AnnotationStyle(lineWidth: .thick)
        let point = CGPoint(x: region.midX, y: region.midY)
        _ = session.mouseDown(at: point)
        _ = session.mouseUp(at: point)

        XCTAssertEqual(session.state.shapes.count, 1)
        XCTAssertEqual(session.state.shapes.first?.points.count, 1, "圆点笔刷单击即一个采样点")
    }

    /// 模糊工具不再拖矩形：轨迹被记录成一条带点的形状，由渲染器按笔刷直径铺开。
    func testBlurBrushRecordsStrokeInsteadOfRect() {
        let session = makeSession(tool: .gaussianBlur)
        session.state.style = AnnotationStyle(lineWidth: .medium)
        let start = CGPoint(x: region.minX + 30, y: region.minY + 30)
        let end = CGPoint(x: region.minX + 120, y: region.minY + 90)
        _ = session.mouseDown(at: start)
        _ = session.mouseDragged(to: end)
        _ = session.mouseUp(at: end)

        let shape = session.state.shapes.first
        XCTAssertEqual(shape?.tool, .gaussianBlur)
        XCTAssertGreaterThanOrEqual(shape?.points.count ?? 0, 2)
    }

    /// 橡皮擦是圆点笔刷：沿轨迹删除命中的整条标注。
    func testEraserBrushDeletesShapesAlongTheStroke() {
        let session = makeSession(tool: .rectangle)
        let start = CGPoint(x: region.minX + 20, y: region.minY + 20)
        let end = CGPoint(x: region.minX + 120, y: region.minY + 90)
        _ = session.mouseDown(at: start)
        _ = session.mouseDragged(to: end)
        _ = session.mouseUp(at: end)
        XCTAssertEqual(session.state.shapes.count, 1, "先画一个矩形")

        session.state.tool = .eraser
        session.state.style = AnnotationStyle(lineWidth: .thick)
        _ = session.mouseDown(at: start)
        XCTAssertTrue(session.state.shapes.isEmpty, "橡皮擦按下即擦除命中标注")
    }

    /// 原地输入提交时必须保留落笔时的工具与样式（输入期间工具条仍可切换）。
    func testAppendTextUsesExplicitToolAndStyle() {
        let session = makeSession(tool: .text)
        let style = AnnotationStyle(color: .blue, lineWidth: .thin, textSize: .large)
        session.appendText(at: CGPoint(x: 10, y: 10), text: "hello", tool: .tooltip, style: style)

        XCTAssertEqual(session.state.shapes.first?.tool, .tooltip)
        XCTAssertEqual(session.state.shapes.first?.text, "hello")
        XCTAssertEqual(session.state.shapes.first?.style, style)
    }

    /// 文字默认背景透明、默认文字红色；设置背景后，文字下方出现背景色。
    func testTextBackgroundDefaultsToClearAndCanBeFilled() throws {
        XCTAssertEqual(AnnotationStyle().backgroundColor, .clear, "背景色默认透明")
        XCTAssertEqual(AnnotationStyle().color, .red, "文字颜色默认红色")

        let size = CGSize(width: 100, height: 100)
        let source = makeImage(size: size, pixels: size, color: .gray)
        let sourceData = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(source.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        let result = ScreenshotResult(
            imageData: sourceData,
            width: 100,
            height: 100,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: nil
        )

        func yellowPixelCount(background: AnnotationBackground) throws -> Int {
            let style = AnnotationStyle(color: .red, lineWidth: .medium, textSize: .large, backgroundColor: background)
            let shape = AnnotationShape(
                tool: .text,
                startPoint: CGPoint(x: 10, y: 50),
                endPoint: nil,
                text: "A",
                style: style
            )
            let flat = InPlaceAnnotationFlattener.flatten(result: result, shapes: [shape], regionSize: size)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: flat.imageData))
            var count = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y) else { continue }
                    if color.redComponent > 0.7, color.greenComponent > 0.7, color.blueComponent < 0.5 {
                        count += 1
                    }
                }
            }
            return count
        }

        XCTAssertEqual(try yellowPixelCount(background: .clear), 0, "透明背景时不应铺任何底色")
        XCTAssertGreaterThan(try yellowPixelCount(background: .yellow), 20, "黄色背景必须铺在文字下方")
    }

    // MARK: - 导出

    /// 导出按「选区点 → 图像像素」整体缩放：2× 屏上画在右下角的图形，
    /// 合成后必须仍在右下角，而不是缩在左上四分之一。
    func testFlattenerScalesShapesToPixelSpace() throws {
        let pointsSize = CGSize(width: 100, height: 100)
        let pixelsSize = CGSize(width: 200, height: 200)

        // 源图：左半红、右半蓝。标注在「右侧一半」画一条线。
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 200,
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
        NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 100, height: 200).fill()
        NSColor.blue.setFill(); NSRect(x: 100, y: 0, width: 100, height: 200).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let result = ScreenshotResult(
            imageData: data,
            width: 200,
            height: 200,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: RegionCaptureSelection(
                sessionID: UUID(),
                displayID: 1,
                screenFrame: displayFrame,
                globalRect: region
            )
        )
        // 在选区右侧一半（点坐标 50..100、y 0..100）画一个粗绿矩形。
        let shape = AnnotationShape(
            tool: .rectangle,
            startPoint: CGPoint(x: 50, y: 0),
            endPoint: CGPoint(x: 100, y: 100),
            text: nil,
            style: AnnotationStyle(color: .green, lineWidth: .thick, textSize: .medium)
        )
        let flattened = InPlaceAnnotationFlattener.flatten(
            result: result,
            shapes: [shape],
            regionSize: pointsSize
        )

        let flatRep = try XCTUnwrap(NSBitmapImageRep(data: flattened.imageData))
        XCTAssertEqual(flatRep.pixelsWide, 200, "导出不得改变像素尺寸")
        XCTAssertEqual(flatRep.pixelsHigh, 200)

        // 缩放正确时：左半仍以红/蓝为主且**没有**绿色；右半边缘出现绿色描边。
        let leftMid = try XCTUnwrap(flatRep.colorAt(x: 20, y: 100))
        XCTAssertLessThan(leftMid.greenComponent, 0.2, "左半不该出现标注描边（说明缩放错误地画到了左上）")
        let rightEdge = try XCTUnwrap(flatRep.colorAt(x: 99, y: 100))
        XCTAssertGreaterThan(rightEdge.greenComponent, 0.3, "右半应有绿色描边")
    }

    /// 没有形状时导出必须原样返回（不得重新编码、不得改变尺寸）。
    func testFlattenerReturnsInputWhenThereAreNoShapes() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let result = ScreenshotResult(
            imageData: data, width: 8, height: 8,
            captureDate: Date(), sourceType: .region, regionSelection: nil
        )
        let same = InPlaceAnnotationFlattener.flatten(
            result: result,
            shapes: [],
            regionSize: CGSize(width: 8, height: 8)
        )
        XCTAssertEqual(same.imageData, data)
    }
}
