import AppKit
import CoreGraphics

// MARK: - Pin window snapping (Task 017 / 01)

/// 吸附参照来源。同距离冲突时**屏幕边缘优先于窗口边缘**（屏幕是更稳定的参照）。
enum PinSnapSource: Int, Equatable {
    case windowEdge = 0
    case screenEdge = 1
}

/// 一个吸附参照物：屏幕可见区或同屏其它可见窗口的矩形。
struct PinSnapCandidate: Equatable {
    let rect: NSRect
    let source: PinSnapSource
}

/// 吸附结果：**只调整原点、不改变尺寸**（拖动吸附不得改变贴图大小）。
struct PinSnapResult: Equatable {
    let origin: NSPoint
    let snappedHorizontally: Bool
    let snappedVertically: Bool

    var didSnap: Bool { snappedHorizontally || snappedVertically }
}

/// 贴图拖动吸附（Task 017/01）。全部为纯函数，不依赖真实屏幕，便于单测。
enum PinSnapping {
    /// 默认吸附阈值（点）。
    static let defaultThreshold: CGFloat = 8
    /// 阈值上限；超过按上限截断，避免"隔着半个屏幕也吸过去"。
    static let maximumThreshold: CGFloat = 40

    /// 阈值清洗：负值 / `NaN` / 非有限值 → 0（关闭吸附）；超上限截断。
    static func sanitizedThreshold(_ value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return min(CGFloat(value), maximumThreshold)
    }

    /// 组装参照集合：屏幕可见区 + 其它窗口矩形（过滤退化矩形与自身）。
    static func candidates(
        for movingRect: NSRect,
        screenVisibleFrame: NSRect,
        otherWindowRects: [NSRect]
    ) -> [PinSnapCandidate] {
        var result = [PinSnapCandidate(rect: screenVisibleFrame, source: .screenEdge)]
        result += otherWindowRects
            .filter { $0.width > 1 && $0.height > 1 && $0 != movingRect }
            .map { PinSnapCandidate(rect: $0, source: .windowEdge) }
        return result
    }

    /// 计算吸附后的原点。
    ///
    /// 每个轴独立处理：把贴图的左/中/右（下/中/上）与每个参照物的同样三条边
    /// **两两比对**，落在阈值内且位移最小者胜出；因此同时覆盖"边对边""中对中"
    /// 与"首尾相邻贴合"三种情形。`threshold <= 0` 表示关闭吸附。
    static func resolve(
        movingRect: NSRect,
        candidates: [PinSnapCandidate],
        threshold: CGFloat
    ) -> PinSnapResult {
        guard threshold.isFinite, threshold > 0, !candidates.isEmpty else {
            return PinSnapResult(origin: movingRect.origin, snappedHorizontally: false, snappedVertically: false)
        }

        let horizontal = bestSnap(
            movingPositions: [movingRect.minX, movingRect.midX, movingRect.maxX],
            candidates: candidates,
            positions: { [$0.minX, $0.midX, $0.maxX] },
            threshold: threshold
        )
        let vertical = bestSnap(
            movingPositions: [movingRect.minY, movingRect.midY, movingRect.maxY],
            candidates: candidates,
            positions: { [$0.minY, $0.midY, $0.maxY] },
            threshold: threshold
        )

        return PinSnapResult(
            // 原点取整：参照物坐标可能带小数，取整后落位稳定，也不会让窗口尺寸被撑大。
            origin: NSPoint(
                x: (movingRect.minX + (horizontal?.delta ?? 0)).rounded(),
                y: (movingRect.minY + (vertical?.delta ?? 0)).rounded()
            ),
            snappedHorizontally: horizontal != nil,
            snappedVertically: vertical != nil
        )
    }

    /// CG 全局坐标（原点在主屏**左上**）→ AppKit 全局坐标（原点在主屏**左下**）。
    ///
    /// `CGWindowListCopyWindowInfo` 返回的就是前者；不转换会得到上下颠倒的吸附结果。
    static func appKitRect(fromCGWindowBounds bounds: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
        NSRect(
            x: bounds.minX,
            y: primaryScreenHeight - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// 同屏其它可见窗口的 AppKit 坐标矩形（排除自身窗口号）。
    ///
    /// 只取普通窗口层（`layer == 0`）且不透明者，跳过桌面图标、状态栏、各类浮层，
    /// 避免吸附到不可见的系统窗口上。
    static func liveWindowRects(excludingWindowNumber excluded: Int?) -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        guard primaryScreenHeight > 0 else { return [] }

        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  ((entry[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  number != excluded,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 1, bounds.height > 1 else {
                return nil
            }
            return appKitRect(fromCGWindowBounds: bounds, primaryScreenHeight: primaryScreenHeight)
        }
    }

    // MARK: - Private

    private struct AxisSnap {
        let delta: CGFloat
        let source: PinSnapSource
    }

    private static func bestSnap(
        movingPositions: [CGFloat],
        candidates: [PinSnapCandidate],
        positions: (NSRect) -> [CGFloat],
        threshold: CGFloat
    ) -> AxisSnap? {
        var best: AxisSnap?
        for candidate in candidates {
            for target in positions(candidate.rect) {
                for position in movingPositions {
                    let delta = target - position
                    guard abs(delta) <= threshold else { continue }
                    guard let current = best else {
                        best = AxisSnap(delta: delta, source: candidate.source)
                        continue
                    }
                    let closer = abs(delta) < abs(current.delta) - 0.0001
                    let tieOnScreenEdge = abs(abs(delta) - abs(current.delta)) <= 0.0001
                        && candidate.source.rawValue > current.source.rawValue
                    if closer || tieOnScreenEdge {
                        best = AxisSnap(delta: delta, source: candidate.source)
                    }
                }
            }
        }
        return best
    }
}
