import AppKit
import CoreGraphics
import Foundation

// MARK: - Stroke smoothing (Task 013)

/// 自由手绘的采样点处理。全部为纯函数，可在无视图环境下单测。
///
/// 鼠标事件的采样点又密又抖，直接连成折线会有明显的折角与毛刺。
/// 落笔时做一次平滑 + 抽稀，既改善观感也降低后续命中测试的开销。
enum StrokeSmoother {

    /// 加权平滑：每个内点取其与左右邻点的加权平均（`1:2:1`），首末点保持不变。
    ///
    /// - 点数保持不变（便于逐点对齐调试）；
    /// - 首末点严格保留，避免笔画两端"缩进去"；
    /// - 输出每个坐标都落在输入的包围盒内（不会外扩）。
    static func smooth(points: [CGPoint], passes: Int = 1) -> [CGPoint] {
        guard points.count > 2, passes > 0 else { return points }
        var current = points
        for _ in 0..<passes {
            var next: [CGPoint] = [current[0]]
            next.reserveCapacity(current.count)
            for index in 1..<(current.count - 1) {
                let previous = current[index - 1]
                let middle = current[index]
                let following = current[index + 1]
                next.append(CGPoint(
                    x: (previous.x + 2 * middle.x + following.x) / 4,
                    y: (previous.y + 2 * middle.y + following.y) / 4
                ))
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
    }

    /// 抽稀：丢弃与上一个保留点距离小于 `tolerance` 的采样点；末点始终保留。
    ///
    /// 只在点数足够且容差为正时生效，避免把两点笔画抽成一点。
    static func simplify(points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, tolerance > 0 else { return points }
        var result: [CGPoint] = [points[0]]
        for point in points.dropFirst() {
            guard let last = result.last else { continue }
            let dx = point.x - last.x
            let dy = point.y - last.y
            if (dx * dx + dy * dy).squareRoot() < tolerance { continue }
            result.append(point)
        }
        if let last = points.last, result.last != last {
            result.append(last)
        }
        return result
    }

    /// 落笔时的标准处理：先抽稀降噪，再平滑一次。
    static func finish(points: [CGPoint], simplifyTolerance: CGFloat = 1.5) -> [CGPoint] {
        guard points.count > 2 else { return points }
        return smooth(points: simplify(points: points, tolerance: simplifyTolerance))
    }
}

// MARK: - Annotation hit testing (Task 013)

/// 标注命中测试：橡皮擦删除与悬停选中共用。
///
/// 全部为纯函数，按工具类型分别定义几何规则。数组**末尾最上层**，
/// 因此从后往前找，命中即返回。
enum AnnotationHitTest {

    /// 命中该点的最上层标注；无命中返回 nil。
    static func hit(
        point: CGPoint,
        shapes: [AnnotationShape],
        tolerance: CGFloat
    ) -> AnnotationShape.ID? {
        for shape in shapes.reversed() where contains(point: point, in: shape, tolerance: tolerance) {
            return shape.id
        }
        return nil
    }

    /// 单个标注是否被点命中。
    static func contains(point: CGPoint, in shape: AnnotationShape, tolerance: CGFloat) -> Bool {
        // 命中容差随笔宽放宽：细线也要"点得中"；笔刷工具按圆点半径放宽。
        let slack = tolerance + (
            shape.tool.isBrush
                ? shape.style.brushDiameter(for: shape.tool) / 2
                : shape.style.lineWidth.points / 2
        )

        switch shape.tool {
        case .rectangle, .ellipse:
            return shape.rect.insetBy(dx: -slack, dy: -slack).contains(point)

        case .text, .tooltip:
            return tooltipBody(for: shape).insetBy(dx: -slack, dy: -slack).contains(point)

        case .line, .arrow:
            guard let end = shape.endPoint else { return false }
            return distance(from: point, toSegment: shape.startPoint, end) <= slack

        case .polyline, .pencil, .highlighter, .marker, .mosaic, .gaussianBlur:
            guard !shape.points.isEmpty else {
                // 旧数据/矩形兜底：没有轨迹的模糊形状按矩形命中。
                guard shape.tool == .mosaic || shape.tool == .gaussianBlur else { return false }
                return shape.rect.insetBy(dx: -slack, dy: -slack).contains(point)
            }
            if shape.points.count == 1 {
                // 只有圆点笔刷的「单点」才是可见圆点；铅笔单点仍是空笔画。
                guard shape.tool.isBrush else { return false }
                let dx = point.x - shape.points[0].x
                let dy = point.y - shape.points[0].y
                return (dx * dx + dy * dy).squareRoot() <= slack
            }
            for index in 0..<(shape.points.count - 1) {
                if distance(from: point, toSegment: shape.points[index], shape.points[index + 1]) <= slack {
                    return true
                }
            }
            return false

        case .number:
            let radius = max(slack, shape.numberBadgeRadius)
            let center = shape.startPoint
            let dx = point.x - center.x
            let dy = point.y - center.y
            return (dx * dx + dy * dy).squareRoot() <= radius

        case .eraser:
            // 橡皮擦本身不产生图形，不参与命中。
            return false
        }
    }

    // MARK: - Geometry helpers (pure)

    /// 点到线段的最短距离。
    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    /// 提示框气泡主体矩形（不含指向三角）；与渲染保持同一套推导规则。
    static func tooltipBody(for shape: AnnotationShape, maxTextWidth: CGFloat = 320) -> CGRect {
        let text = shape.text ?? ""
        let font = NSFont.systemFont(ofSize: shape.style.textSize.points, weight: .medium)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let padding: CGFloat = 10
        let tail: CGFloat = 7
        return CGRect(
            x: shape.startPoint.x + tail,
            y: shape.startPoint.y + tail,
            width: ceil(bounding.width) + padding * 2,
            height: ceil(bounding.height) + padding * 2
        )
    }
}
