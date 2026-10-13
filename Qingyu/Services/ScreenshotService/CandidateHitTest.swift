import CoreGraphics
import Foundation

// MARK: - Candidate model (Task 012)

/// 候选区域来源：窗口级（`CGWindowList`，无需额外权限）或控件级（辅助功能，需授权）。
enum CandidateKind: Equatable, Hashable, Sendable {
    case window
    case element
}

/// 一个可高亮/可吸附的候选区域。`frame` 一律为 AppKit 全局坐标（左下原点）。
struct CandidateRegion: Equatable, Hashable, Sendable {
    let kind: CandidateKind
    let frame: CGRect
    let ownerBundleID: String?
    let title: String?

    init(kind: CandidateKind, frame: CGRect, ownerBundleID: String? = nil, title: String? = nil) {
        self.kind = kind
        self.frame = frame
        self.ownerBundleID = ownerBundleID
        self.title = title
    }
}

/// 控件级探测选项。
struct ElementProbeOptions: Equatable, Sendable {
    /// 是否启用控件级探测（关闭时只做窗口级）。
    var isElementProbingEnabled: Bool
    /// 命中这些应用时**不做**控件级探测，只保留窗口级（用于规避个别程序探测卡顿/崩溃）。
    var ignoredBundleIDs: Set<String>
    /// 单次探测的超时上限（秒）。
    var timeout: TimeInterval

    static let `default` = ElementProbeOptions(
        isElementProbingEnabled: true,
        ignoredBundleIDs: [],
        timeout: 0.05
    )

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }
}

// MARK: - Hit testing and snapping

/// 候选命中优先级与选区边缘吸附。全部为纯函数，可在无窗口系统/无权限的环境下单测。
enum CandidateHitTest {

    /// 命中规则：**控件优先于窗口**；同类中取面积最小（最具体）的一个。
    ///
    /// 指针不在任何候选内时返回 nil —— 调用方据此回落到「整屏默认目标」。
    static func hit(point: CGPoint, candidates: [CandidateRegion]) -> CandidateRegion? {
        let containing = candidates.filter { $0.frame.contains(point) && !$0.frame.isEmpty }
        guard !containing.isEmpty else { return nil }
        return containing.min { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    /// 边缘吸附：选区的四条边各自吸附到阈值内最近的候选边；未命中阈值则保持原值。
    ///
    /// 阈值按**逻辑点**计（不按物理像素），避免不同缩放屏幕手感不一致。
    /// 阈值 <= 0 或没有候选时原样返回。
    static func snap(rect: CGRect, candidates: [CandidateRegion], threshold: CGFloat) -> CGRect {
        guard threshold > 0, !candidates.isEmpty, !rect.isNull, !rect.isEmpty else { return rect }

        let verticalEdges = candidates.flatMap { [$0.frame.minX, $0.frame.maxX] }
        let horizontalEdges = candidates.flatMap { [$0.frame.minY, $0.frame.maxY] }

        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if let target = nearest(to: minX, in: verticalEdges, threshold: threshold) { minX = target }
        if let target = nearest(to: maxX, in: verticalEdges, threshold: threshold) { maxX = target }
        if let target = nearest(to: minY, in: horizontalEdges, threshold: threshold) { minY = target }
        if let target = nearest(to: maxY, in: horizontalEdges, threshold: threshold) { maxY = target }

        // 吸附后若某一边越过了对边，保持至少 1pt 宽度/高度，避免产生空选区。
        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// 把点吸附到最近的候选边（x 与 y 独立判定）。
    ///
    /// 用于拖拽选区时吸附**被拖动的那个角**：x / y 各自找阈值内最近的竖直/水平候选边。
    static func snap(point: CGPoint, candidates: [CandidateRegion], threshold: CGFloat) -> CGPoint {
        guard threshold > 0, !candidates.isEmpty else { return point }
        let verticalEdges = candidates.flatMap { [$0.frame.minX, $0.frame.maxX] }
        let horizontalEdges = candidates.flatMap { [$0.frame.minY, $0.frame.maxY] }
        return CGPoint(
            x: nearest(to: point.x, in: verticalEdges, threshold: threshold) ?? point.x,
            y: nearest(to: point.y, in: horizontalEdges, threshold: threshold) ?? point.y
        )
    }

    // MARK: - Private

    /// 数值越小优先级越高。
    private static func rank(_ region: CandidateRegion) -> Int {
        switch region.kind {
        case .element: return 0
        case .window: return 1
        }
    }

    private static func nearest(to value: CGFloat, in edges: [CGFloat], threshold: CGFloat) -> CGFloat? {
        var best: (distance: CGFloat, edge: CGFloat)?
        for edge in edges {
            let distance = abs(edge - value)
            guard distance <= threshold else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, edge)
            }
        }
        return best?.edge
    }
}
