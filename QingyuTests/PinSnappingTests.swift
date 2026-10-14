import AppKit
import XCTest
@testable import Qingyu

/// Task 017/01：贴图拖动吸附（纯函数）。
final class PinSnappingTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)

    private func makeResult(_ origin: NSPoint) -> NSRect {
        NSRect(x: origin.x, y: origin.y, width: 200, height: 120)
    }

    // MARK: - 阈值

    func testSanitizedThresholdAndDisabledStates() {
        XCTAssertEqual(PinSnapping.sanitizedThreshold(-5), 0)
        XCTAssertEqual(PinSnapping.sanitizedThreshold(.nan), 0)
        XCTAssertEqual(PinSnapping.sanitizedThreshold(.infinity), 0)
        XCTAssertEqual(PinSnapping.sanitizedThreshold(0), 0)
        XCTAssertEqual(PinSnapping.sanitizedThreshold(8), 8)
        XCTAssertEqual(
            PinSnapping.sanitizedThreshold(999),
            PinSnapping.maximumThreshold,
            "超上限截断，避免隔着半个屏幕也被吸走"
        )
    }

    func testZeroThresholdDisablesSnapping() {
        let moving = makeResult(NSPoint(x: 103, y: 203))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: [PinSnapCandidate(rect: screen, source: .screenEdge)],
            threshold: 0
        )

        XCTAssertFalse(result.didSnap)
        XCTAssertEqual(result.origin, moving.origin)
    }

    func testEmptyCandidatesDoNotSnap() {
        let moving = makeResult(NSPoint(x: 3, y: 3))
        let result = PinSnapping.resolve(movingRect: moving, candidates: [], threshold: 8)

        XCTAssertFalse(result.didSnap, "没有参照物时不得凭空吸附")
        XCTAssertEqual(result.origin, moving.origin)
    }

    // MARK: - 吸附判定

    func testSnapsLeadingEdgeToScreenEdgeWithinThreshold() {
        let moving = makeResult(NSPoint(x: 5, y: 300))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: [PinSnapCandidate(rect: screen, source: .screenEdge)],
            threshold: 8
        )

        XCTAssertTrue(result.snappedHorizontally)
        XCTAssertFalse(result.snappedVertically, "竖直方向未进入阈值时不得连带吸附")
        XCTAssertEqual(result.origin.x, 0)
        XCTAssertEqual(result.origin.y, 300)
    }

    func testDoesNotSnapBeyondThreshold() {
        let moving = makeResult(NSPoint(x: 9, y: 300))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: [PinSnapCandidate(rect: screen, source: .screenEdge)],
            threshold: 8
        )

        XCTAssertFalse(result.didSnap)
        XCTAssertEqual(result.origin.x, 9)
    }

    func testSnapsTrailingEdgeToScreenEdge() {
        // 窗口宽 200，右缘 1000 需要原点 800 ± 阈值。
        let moving = makeResult(NSPoint(x: 796, y: 300))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: [PinSnapCandidate(rect: screen, source: .screenEdge)],
            threshold: 8
        )

        XCTAssertEqual(result.origin.x, 800)
    }

    func testSnapsToOtherWindowEdgeAndButtsAgainstIt() {
        let other = NSRect(x: 400, y: 100, width: 300, height: 200)
        let candidates = PinSnapping.candidates(
            for: makeResult(NSPoint(x: 703, y: 100)),
            screenVisibleFrame: screen,
            otherWindowRects: [other]
        )

        // 左缘 703 距 other.maxX (700) 仅 3 点 → 贴合到 700；同时下缘与 other.minY 对齐。
        let result = PinSnapping.resolve(
            movingRect: makeResult(NSPoint(x: 703, y: 103)),
            candidates: candidates,
            threshold: 8
        )

        XCTAssertEqual(result.origin.x, 700, "首尾相邻也应吸附（贴合到另一个窗口的右缘）")
        XCTAssertEqual(result.origin.y, 100, "下缘与参照窗口下缘对齐")
    }

    func testCenterAlignmentIsSupported() {
        // 参照物中心 500；贴图宽 200 → 居中时原点 400。
        let other = NSRect(x: 400, y: 0, width: 200, height: 800)
        let result = PinSnapping.resolve(
            movingRect: makeResult(NSPoint(x: 404, y: 200)),
            candidates: PinSnapping.candidates(
                for: makeResult(NSPoint(x: 404, y: 200)),
                screenVisibleFrame: NSRect(x: -5000, y: -5000, width: 1, height: 1),
                otherWindowRects: [other]
            ),
            threshold: 8
        )

        XCTAssertEqual(result.origin.x, 400, "中对中也应吸附")
    }

    func testScreenEdgeWinsOnEqualDistance() {
        // 屏幕左缘 0 与某窗口左缘 12 对贴图左缘 6 等距（各 6 点）；屏幕边缘应胜出。
        let other = NSRect(x: 12, y: 0, width: 100, height: 100)
        let moving = makeResult(NSPoint(x: 6, y: 300))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: PinSnapping.candidates(
                for: moving,
                screenVisibleFrame: screen,
                otherWindowRects: [other]
            ),
            threshold: 8
        )

        XCTAssertEqual(result.origin.x, 0, "同距离时屏幕边缘优先于窗口边缘")
    }

    func testSnappingNeverChangesSize() {
        let moving = makeResult(NSPoint(x: 797, y: 5))
        let result = PinSnapping.resolve(
            movingRect: moving,
            candidates: [PinSnapCandidate(rect: screen, source: .screenEdge)],
            threshold: 8
        )

        let snapped = NSRect(origin: result.origin, size: moving.size)
        XCTAssertEqual(snapped.size, moving.size)
        XCTAssertEqual(snapped.maxX, screen.maxX)
        XCTAssertEqual(snapped.minY, screen.minY)
    }

    // MARK: - 参照物组装与坐标换算

    func testCandidatesIncludeScreenAndFilterDegenerateWindows() {
        let moving = makeResult(NSPoint(x: 0, y: 0))
        let candidates = PinSnapping.candidates(
            for: moving,
            screenVisibleFrame: screen,
            otherWindowRects: [
                NSRect(x: 10, y: 10, width: 0, height: 50),
                NSRect(x: 20, y: 20, width: 50, height: 0),
                moving,
                NSRect(x: 30, y: 30, width: 50, height: 50)
            ]
        )

        XCTAssertEqual(candidates.count, 2, "屏幕 + 唯一合法窗口；退化矩形与自身被过滤")
        XCTAssertEqual(candidates.first?.source, .screenEdge)
        XCTAssertEqual(candidates.last?.source, .windowEdge)
    }

    func testCGToAppKitConversionFlipsVerticalAxis() {
        // 主屏高 900：CG 顶部原点 y=100、高 50 → AppKit 底边 y = 900 - 150 = 750。
        let rect = PinSnapping.appKitRect(
            fromCGWindowBounds: CGRect(x: 20, y: 100, width: 300, height: 50),
            primaryScreenHeight: 900
        )

        XCTAssertEqual(rect, NSRect(x: 20, y: 750, width: 300, height: 50))
    }
}
