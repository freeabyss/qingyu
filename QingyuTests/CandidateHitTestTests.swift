import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 012：候选命中优先级与选区吸附的纯函数契约。
///
/// 不依赖窗口系统与辅助功能权限，`scripts/verify.sh` 可稳定运行。
final class CandidateHitTestTests: XCTestCase {

    private func window(_ rect: CGRect) -> CandidateRegion {
        CandidateRegion(kind: .window, frame: rect)
    }

    private func element(_ rect: CGRect) -> CandidateRegion {
        CandidateRegion(kind: .element, frame: rect)
    }

    // MARK: - 命中优先级

    /// 控件优先于窗口：即使窗口面积更小，只要指针落在控件内就返回控件。
    func testElementBeatsWindowAtTheSamePoint() {
        let candidates = [
            window(CGRect(x: 0, y: 0, width: 1000, height: 800)),
            element(CGRect(x: 80, y: 80, width: 40, height: 20))
        ]
        let hit = CandidateHitTest.hit(point: CGPoint(x: 90, y: 90), candidates: candidates)
        XCTAssertEqual(hit?.kind, .element)
        XCTAssertEqual(hit?.frame, CGRect(x: 80, y: 80, width: 40, height: 20))
    }

    /// 同类中取面积最小（最具体）的一个。
    func testSmallestAreaWinsWithinSameKind() {
        let candidates = [
            window(CGRect(x: 0, y: 0, width: 800, height: 600)),
            window(CGRect(x: 10, y: 10, width: 200, height: 150))
        ]
        let hit = CandidateHitTest.hit(point: CGPoint(x: 20, y: 20), candidates: candidates)
        XCTAssertEqual(hit?.frame, CGRect(x: 10, y: 10, width: 200, height: 150))
    }

    func testNoHitOutsideEveryCandidate() {
        let candidates = [window(CGRect(x: 0, y: 0, width: 10, height: 10))]
        XCTAssertNil(CandidateHitTest.hit(point: CGPoint(x: 500, y: 500), candidates: candidates))
    }

    func testEmptyCandidateListReturnsNil() {
        XCTAssertNil(CandidateHitTest.hit(point: .zero, candidates: []))
    }

    /// 空矩形不参与命中（`CGWindowList` 偶发返回 0 尺寸条目）。
    func testZeroSizedCandidateIsIgnored() {
        let candidates = [window(CGRect(x: 0, y: 0, width: 0, height: 0))]
        XCTAssertNil(CandidateHitTest.hit(point: .zero, candidates: candidates))
    }

    // MARK: - 矩形吸附

    /// 只有靠近候选边的两条边移动，对边保持原位（不是整体平移）。
    func testSnapAlignsEdgeWithinThreshold() {
        let candidates = [window(CGRect(x: 100, y: 100, width: 300, height: 200))]
        let rect = CGRect(x: 97, y: 103, width: 100, height: 50)
        let snapped = CandidateHitTest.snap(rect: rect, candidates: candidates, threshold: 5)
        XCTAssertEqual(snapped.minX, 100, accuracy: 0.001)
        XCTAssertEqual(snapped.minY, 100, accuracy: 0.001)
        XCTAssertEqual(snapped.maxX, 197, accuracy: 0.001, "远离候选边的右边不应移动")
        XCTAssertEqual(snapped.maxY, 153, accuracy: 0.001, "远离候选边的上边不应移动")
    }

    func testSnapLeavesRectUntouchedBeyondThreshold() {
        let candidates = [window(CGRect(x: 100, y: 100, width: 300, height: 200))]
        let rect = CGRect(x: 80, y: 80, width: 10, height: 10)
        XCTAssertEqual(CandidateHitTest.snap(rect: rect, candidates: candidates, threshold: 5), rect)
    }

    func testSnapIsDisabledWhenThresholdIsZeroOrNegative() {
        let candidates = [window(CGRect(x: 100, y: 100, width: 300, height: 200))]
        let rect = CGRect(x: 99, y: 99, width: 10, height: 10)
        XCTAssertEqual(CandidateHitTest.snap(rect: rect, candidates: candidates, threshold: 0), rect)
        XCTAssertEqual(CandidateHitTest.snap(rect: rect, candidates: candidates, threshold: -3), rect)
    }

    func testSnapWithoutCandidatesLeavesRectUntouched() {
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(CandidateHitTest.snap(rect: rect, candidates: [], threshold: 10), rect)
    }

    /// 吸附后若对边被越过，保持至少 1pt，避免产生空选区。
    func testSnapKeepsMinimumSizeWhenEdgesCross() {
        let candidates = [window(CGRect(x: 100, y: 100, width: 300, height: 200))]
        let rect = CGRect(x: 99, y: 99, width: 2, height: 2)
        let snapped = CandidateHitTest.snap(rect: rect, candidates: candidates, threshold: 3)
        XCTAssertGreaterThanOrEqual(snapped.width, 1)
        XCTAssertGreaterThanOrEqual(snapped.height, 1)
    }

    // MARK: - 点吸附（拖拽角）

    func testSnapPointAlignsBothAxesIndependently() {
        let candidates = [window(CGRect(x: 100, y: 200, width: 300, height: 200))]
        let snapped = CandidateHitTest.snap(
            point: CGPoint(x: 98, y: 397),
            candidates: candidates,
            threshold: 5
        )
        XCTAssertEqual(snapped.x, 100, accuracy: 0.001)
        XCTAssertEqual(snapped.y, 400, accuracy: 0.001)
    }

    func testSnapPointUntouchedWhenOutOfThresholdOrWithoutCandidates() {
        let point = CGPoint(x: 10, y: 20)
        XCTAssertEqual(CandidateHitTest.snap(point: point, candidates: [], threshold: 5), point)
        let candidates = [window(CGRect(x: 100, y: 100, width: 10, height: 10))]
        XCTAssertEqual(CandidateHitTest.snap(point: point, candidates: candidates, threshold: 5), point)
    }

    // MARK: - 选项

    func testOptionsIgnoreListMatchesBundleID() {
        var options = ElementProbeOptions.default
        options.ignoredBundleIDs = ["com.apple.Safari"]
        XCTAssertTrue(options.isIgnored(bundleID: "com.apple.Safari"))
        XCTAssertFalse(options.isIgnored(bundleID: "com.apple.Finder"))
        XCTAssertFalse(options.isIgnored(bundleID: nil))
    }
}
