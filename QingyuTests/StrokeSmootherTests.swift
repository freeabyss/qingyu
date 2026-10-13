import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 013：自由手绘采样点处理（平滑 / 抽稀）的纯函数契约。
final class StrokeSmootherTests: XCTestCase {

    private func zigzag(count: Int) -> [CGPoint] {
        (0..<count).map { CGPoint(x: CGFloat($0), y: CGFloat($0 % 2 == 0 ? 0 : 10)) }
    }

    func testSmoothPreservesCountAndEndpoints() {
        let points = zigzag(count: 8)
        let smoothed = StrokeSmoother.smooth(points: points)
        XCTAssertEqual(smoothed.count, points.count, "平滑不改变点数")
        XCTAssertEqual(smoothed.first, points.first, "首点必须严格保留")
        XCTAssertEqual(smoothed.last, points.last, "末点必须严格保留")
    }

    /// 平滑输出必须落在输入包围盒内 —— 否则笔画会外扩，视觉上“胖出来”。
    func testSmoothStaysInsideInputBoundingBox() {
        let points = zigzag(count: 12)
        let smoothed = StrokeSmoother.smooth(points: points)
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        for point in smoothed {
            XCTAssertGreaterThanOrEqual(point.x, minX)
            XCTAssertLessThanOrEqual(point.x, maxX)
            XCTAssertGreaterThanOrEqual(point.y, minY)
            XCTAssertLessThanOrEqual(point.y, maxY)
        }
    }

    /// 平滑后抖动幅度必须变小：这是「手绘不毛刺」的可测代理。
    func testSmoothReducesJitter() {
        let points = zigzag(count: 12)
        func totalVariation(_ list: [CGPoint]) -> CGFloat {
            zip(list, list.dropFirst()).reduce(0) { $0 + abs($1.1.y - $1.0.y) }
        }
        XCTAssertLessThan(totalVariation(StrokeSmoother.smooth(points: points)), totalVariation(points))
    }

    func testSmoothIsNoOpForShortOrEmptyStroke() {
        XCTAssertTrue(StrokeSmoother.smooth(points: []).isEmpty)
        let single = [CGPoint(x: 1, y: 2)]
        XCTAssertEqual(StrokeSmoother.smooth(points: single), single)
        let pair = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]
        XCTAssertEqual(StrokeSmoother.smooth(points: pair), pair, "两点不成折线，无需平滑")
    }

    func testSimplifyDropsDensePointsButKeepsLast() {
        let dense = (0..<20).map { CGPoint(x: CGFloat($0) * 0.2, y: 0) }
        let simplified = StrokeSmoother.simplify(points: dense, tolerance: 1)
        XCTAssertLessThan(simplified.count, dense.count)
        XCTAssertEqual(simplified.first, dense.first)
        XCTAssertEqual(simplified.last, dense.last, "末点必须保留")
    }

    func testSimplifyIsNoOpWithoutToleranceOrForShortStroke() {
        let dense = (0..<10).map { CGPoint(x: CGFloat($0) * 0.2, y: 0) }
        XCTAssertEqual(StrokeSmoother.simplify(points: dense, tolerance: 0), dense)
        let pair = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
        XCTAssertEqual(StrokeSmoother.simplify(points: pair, tolerance: 5), pair)
    }

    /// 落笔标准处理：抽稀 + 平滑，结果仍可用于绘制（≥2 点）且不增加点数。
    func testFinishKeepsStrokeDrawableAndDoesNotGrow() {
        let points = zigzag(count: 30)
        let finished = StrokeSmoother.finish(points: points)
        XCTAssertGreaterThanOrEqual(finished.count, 2)
        XCTAssertLessThanOrEqual(finished.count, points.count)
        XCTAssertEqual(finished.first, points.first)
        XCTAssertEqual(finished.last, points.last)
    }
}
