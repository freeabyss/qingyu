import AppKit
import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 013：标注命中测试（橡皮擦删除与悬停选中）的纯函数契约。
final class AnnotationHitTestTests: XCTestCase {

    private let style = AnnotationStyle(color: .red, lineWidth: .thin, textSize: .medium)

    private func rectShape(_ tool: AnnotationTool, _ rect: CGRect) -> AnnotationShape {
        AnnotationShape(
            tool: tool,
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY),
            text: nil,
            style: style
        )
    }

    private func freehand(_ tool: AnnotationTool, _ points: [CGPoint]) -> AnnotationShape {
        var shape = AnnotationShape(
            tool: tool,
            startPoint: points[0],
            endPoint: nil,
            text: nil,
            style: style
        )
        shape.points = points
        return shape
    }

    // MARK: - 点到线段距离

    func testDistanceToSegmentHandlesEndpointsAndInterior() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        XCTAssertEqual(AnnotationHitTest.distance(from: CGPoint(x: 5, y: 3), toSegment: a, b), 3, accuracy: 0.001)
        XCTAssertEqual(AnnotationHitTest.distance(from: CGPoint(x: -4, y: 0), toSegment: a, b), 4, accuracy: 0.001, "投影落在端点外应取端点距离")
        XCTAssertEqual(AnnotationHitTest.distance(from: CGPoint(x: 0, y: 0), toSegment: a, b), 0, accuracy: 0.001)
    }

    func testDistanceToDegenerateSegmentIsPointDistance() {
        let p = CGPoint(x: 3, y: 4)
        XCTAssertEqual(AnnotationHitTest.distance(from: .zero, toSegment: p, p), 5, accuracy: 0.001)
    }

    // MARK: - 各工具命中规则

    func testRectToolsHitInsideAndNearBorderByTolerance() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        for tool in [AnnotationTool.rectangle, .ellipse, .mosaic, .gaussianBlur] {
            let shape = rectShape(tool, rect)
            XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 200, y: 150), in: shape, tolerance: 3), "\(tool) 内部应命中")
            XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 98, y: 150), in: shape, tolerance: 3), "\(tool) 边界外 2pt 应在容差内")
            XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 50, y: 150), in: shape, tolerance: 3), "\(tool) 远处不应命中")
        }
    }

    func testLineAndArrowHitNearSegmentOnly() {
        let shape = AnnotationShape(
            tool: .line,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            text: nil,
            style: style
        )
        XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 50, y: 3), in: shape, tolerance: 2))
        XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 50, y: 30), in: shape, tolerance: 2))
    }

    func testFreehandAndPolylineHitAnySegment() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 0)]
        for tool in [AnnotationTool.polyline, .pencil, .highlighter] {
            let shape = freehand(tool, points)
            XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 15, y: 15), in: shape, tolerance: 2), "\(tool) 第一段应命中")
            XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 45, y: 15), in: shape, tolerance: 2), "\(tool) 第二段应命中")
            XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 30, y: 90), in: shape, tolerance: 2), "\(tool) 远处不应命中")
        }
    }

    /// 铅笔单点仍然是空笔画；圆点笔刷的单点是一个真实可见的圆点，应当可命中。
    func testSinglePointFreehandIsHittableOnlyForBrushTools() {
        let point = CGPoint(x: 5, y: 5)
        let pencil = freehand(.pencil, [point])
        XCTAssertFalse(AnnotationHitTest.contains(point: point, in: pencil, tolerance: 5))

        for tool in [AnnotationTool.highlighter, .marker, .gaussianBlur] {
            let brush = freehand(tool, [point])
            XCTAssertTrue(
                AnnotationHitTest.contains(point: point, in: brush, tolerance: 0),
                "(tool) 的单点圆点应可命中"
            )
        }
    }

    func testNumberHitsWithinBadgeRadius() {
        let shape = AnnotationShape(
            tool: .number,
            startPoint: CGPoint(x: 100, y: 100),
            endPoint: nil,
            text: "3",
            style: style
        )
        let radius = shape.numberBadgeRadius
        XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: 100 + radius - 1, y: 100), in: shape, tolerance: 0))
        XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 100 + radius + 5, y: 100), in: shape, tolerance: 0))
    }

    func testTooltipHitsItsBubbleBody() {
        let shape = AnnotationShape(
            tool: .tooltip,
            startPoint: CGPoint(x: 100, y: 100),
            endPoint: nil,
            text: "这是一段提示文字",
            style: style
        )
        let body = AnnotationHitTest.tooltipBody(for: shape)
        XCTAssertTrue(AnnotationHitTest.contains(point: CGPoint(x: body.midX, y: body.midY), in: shape, tolerance: 1))
        XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 0, y: 0), in: shape, tolerance: 1))
    }

    func testEraserShapeNeverParticipatesInHitTesting() {
        let shape = rectShape(.eraser, CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(AnnotationHitTest.contains(point: CGPoint(x: 50, y: 50), in: shape, tolerance: 5))
    }

    // MARK: - 最上层优先

    /// 数组末尾最上层：重叠时命中后画的那一条。
    func testTopmostShapeWinsWhenOverlapping() {
        let bottom = rectShape(.rectangle, CGRect(x: 0, y: 0, width: 100, height: 100))
        let top = rectShape(.rectangle, CGRect(x: 20, y: 20, width: 40, height: 40))
        let hit = AnnotationHitTest.hit(point: CGPoint(x: 40, y: 40), shapes: [bottom, top], tolerance: 2)
        XCTAssertEqual(hit, top.id)
    }

    func testHitReturnsNilOutsideEveryShape() {
        let shape = rectShape(.rectangle, CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(AnnotationHitTest.hit(point: CGPoint(x: 500, y: 500), shapes: [shape], tolerance: 3))
        XCTAssertNil(AnnotationHitTest.hit(point: .zero, shapes: [], tolerance: 3))
    }

    /// 橡皮擦按「整条删除」工作，因此命中必须随线宽放宽：细线也要点得中。
    func testToleranceGrowsWithLineWidth() {
        func line(_ width: AnnotationLineWidth) -> AnnotationShape {
            AnnotationShape(
                tool: .line,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 100, y: 0),
                text: nil,
                style: AnnotationStyle(color: .red, lineWidth: width, textSize: .medium)
            )
        }
        // 距线段 3pt：细线（半宽 1pt）够不着，粗线（半宽 4pt）应命中。
        let probe = CGPoint(x: 50, y: 3)
        XCTAssertFalse(
            AnnotationHitTest.contains(point: probe, in: line(.thin), tolerance: 0),
            "细线半宽 1pt，3pt 外不应命中"
        )
        XCTAssertTrue(
            AnnotationHitTest.contains(point: probe, in: line(.thick), tolerance: 0),
            "粗线半宽 4pt，3pt 内应命中"
        )
    }

    // MARK: - 画布状态：删除可撤销

    @MainActor
    func testEraseIsUndoableAndRedoable() {
        let state = AnnotationCanvasState(image: NSImage(size: NSSize(width: 200, height: 200)))
        let first = rectShape(.rectangle, CGRect(x: 0, y: 0, width: 10, height: 10))
        let second = rectShape(.rectangle, CGRect(x: 20, y: 20, width: 10, height: 10))
        state.append(first)
        state.append(second)

        XCTAssertTrue(state.erase(shapeID: first.id))
        XCTAssertEqual(state.shapes.map(\.id), [second.id])

        state.undo()
        XCTAssertEqual(state.shapes.map(\.id), [first.id, second.id], "撤销删除应回到原位置")
        state.redo()
        XCTAssertEqual(state.shapes.map(\.id), [second.id])
    }

    @MainActor
    func testEraseUnknownShapeIsNoOp() {
        let state = AnnotationCanvasState(image: NSImage(size: NSSize(width: 200, height: 200)))
        XCTAssertFalse(state.erase(shapeID: UUID()))
    }

    @MainActor
    func testNumberingIncrementsAndResetsOnClear() {
        let state = AnnotationCanvasState(image: NSImage(size: NSSize(width: 200, height: 200)))
        XCTAssertEqual(state.allocateNumber(), 1)
        XCTAssertEqual(state.allocateNumber(), 2)
        XCTAssertEqual(state.allocateNumber(), 3)

        state.append(rectShape(.rectangle, CGRect(x: 0, y: 0, width: 5, height: 5)))
        state.clearAll()
        XCTAssertEqual(state.allocateNumber(), 1, "清空后序号重新从 1 开始")
    }
}
