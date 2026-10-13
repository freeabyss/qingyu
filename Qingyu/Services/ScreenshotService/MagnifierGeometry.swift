import CoreGraphics
import Foundation

// MARK: - Magnifier configuration (Task 011)

/// 放大镜内可独立开关的显示项。
///
/// 对应 Snipaste「In the magnifier, show:」的一组勾选项；清羽只取其中四项，
/// 且默认值下行为与「有放大镜」的直觉一致。
enum MagnifierDisplayOption: String, CaseIterable, Codable, Hashable, Sendable {
    /// 每个源像素之间的网格线。
    case grid
    /// 光标所在像素的屏幕坐标（物理像素）。
    case coordinate
    /// 当前放大倍数标签。
    case zoomLabel
    /// 在放大镜内对「当前选区之外」的部分加暗。
    case mask
}

/// 放大镜配置。
///
/// 默认值：开启、放大 8×、网格 / 坐标 / 遮罩开。
/// 所有取值都经 `clampZoom` 与 `sanitized` 收敛，非法输入不得导致崩溃或空白放大镜。
struct MagnifierConfiguration: Equatable, Sendable {
    /// 可选放大倍数（点/源像素）。与 Snipaste 的像素缩放档位语义一致。
    static let availableZooms: [Int] = [2, 4, 8, 16]
    static let defaultZoom = 8

    /// 放大镜框边长（逻辑点）。
    static let viewSize: CGFloat = 112
    /// 放大镜与光标之间的间距（逻辑点）。
    static let anchorGap: CGFloat = 18

    var isEnabled: Bool
    var zoom: Int
    var options: Set<MagnifierDisplayOption>

    static let `default` = MagnifierConfiguration(
        isEnabled: true,
        zoom: defaultZoom,
        options: [.grid, .coordinate, .mask]
    )

    /// 收敛到合法倍数：不在档位内时回落到默认倍数。
    static func clampZoom(_ zoom: Int) -> Int {
        availableZooms.contains(zoom) ? zoom : defaultZoom
    }

    /// 收敛整份配置（用于从设置读回的值）。
    func sanitized() -> MagnifierConfiguration {
        MagnifierConfiguration(
            isEnabled: isEnabled,
            zoom: Self.clampZoom(zoom),
            options: options
        )
    }

    /// 每边采样的源像素数：视图边长 ÷ 放大倍数，向下取整且至少 1。
    var pixelCount: Int {
        MagnifierGeometry.pixelCount(viewSize: Self.viewSize, zoom: zoom)
    }
}

// MARK: - Magnifier geometry

/// 放大镜几何换算。
///
/// 全部为纯函数，不依赖 `NSScreen` / 真实窗口，可在无屏幕环境下单测。
/// 坐标约定：
/// - 「逻辑点」= AppKit 全局坐标（左下原点，单位 point）；
/// - 「像素」= 某台显示器内的物理像素（左上原点，`y` 向下），可直接用于位图索引；
/// - 「Quartz 屏幕坐标」= `CGWindowListCreateImage` 所需（左上原点、`y` 向下、以主显示器左上角为原点）。
enum MagnifierGeometry {

    // MARK: 逻辑点 ⇄ 像素

    /// AppKit 全局逻辑点 → 该显示器内的物理像素坐标（左上原点）。
    static func samplePoint(
        logicalPoint: CGPoint,
        screenFrame: CGRect,
        scale: CGFloat
    ) -> CGPoint {
        let scale = safeScale(scale)
        return CGPoint(
            x: (logicalPoint.x - screenFrame.minX) * scale,
            y: (screenFrame.maxY - logicalPoint.y) * scale
        )
    }

    /// 物理像素坐标 → AppKit 全局逻辑点（`samplePoint` 的逆运算）。
    static func logicalPoint(
        pixelPoint: CGPoint,
        screenFrame: CGRect,
        scale: CGFloat
    ) -> CGPoint {
        let scale = safeScale(scale)
        return CGPoint(
            x: screenFrame.minX + pixelPoint.x / scale,
            y: screenFrame.maxY - pixelPoint.y / scale
        )
    }

    /// 显示器像素尺寸 ÷ 逻辑尺寸；非法（0 或负）时回落到 1，避免除零。
    static func displayScale(frame: CGRect, pixelSize: CGSize) -> CGFloat {
        guard frame.width > 0, frame.height > 0, pixelSize.width > 0 else { return 1 }
        return pixelSize.width / frame.width
    }

    // MARK: 采样窗口

    /// 每边采样的源像素数：向下取整且至少 1。
    static func pixelCount(viewSize: CGFloat, zoom: Int) -> Int {
        let zoom = max(1, zoom)
        return max(1, Int((viewSize / CGFloat(zoom)).rounded(.down)))
    }

    /// 以目标像素为中心、边长为 `pixelCount` 的采样窗口；
    /// 原点钳制进显示器像素范围，避免越界请求。
    static func sourceRect(
        centeredAt pixel: CGPoint,
        pixelCount: Int,
        displayPixelSize: CGSize
    ) -> CGRect {
        let side = CGFloat(max(1, pixelCount))
        let maxX = max(0, displayPixelSize.width - side)
        let maxY = max(0, displayPixelSize.height - side)
        let originX = min(max((pixel.x - side / 2).rounded(.down), 0), maxX)
        let originY = min(max((pixel.y - side / 2).rounded(.down), 0), maxY)
        return CGRect(x: originX, y: originY, width: side, height: side)
    }

    // MARK: 放大镜框位置

    /// 放大镜框：默认放在锚点右上方，越界时翻转到锚点左下方，最后整体钳制进可见区。
    ///
    /// 可见区小于放大镜时以可见区原点为准（保证框完整可见）。
    static func magnifierFrame(
        anchor: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat
    ) -> CGRect {
        var originX = anchor.x + gap
        if originX + size.width > visibleFrame.maxX {
            originX = anchor.x - gap - size.width
        }
        var originY = anchor.y + gap
        if originY + size.height > visibleFrame.maxY {
            originY = anchor.y - gap - size.height
        }

        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - size.width)
        let minY = visibleFrame.minY
        let maxY = max(minY, visibleFrame.maxY - size.height)

        return CGRect(
            x: min(max(originX, minX), maxX),
            y: min(max(originY, minY), maxY),
            width: size.width,
            height: size.height
        )
    }

    // MARK: Quartz 屏幕坐标

    /// AppKit 全局矩形 → Quartz 屏幕坐标矩形（供 `CGWindowListCreateImage` 使用）。
    ///
    /// `mainDisplayHeight` 必须是 AppKit 原点所在显示器的逻辑高度。
    static func quartzRect(fromAppKitRect rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: Private

    private static func safeScale(_ scale: CGFloat) -> CGFloat {
        scale > 0 && scale.isFinite ? scale : 1
    }
}
