import AppKit
import CoreGraphics
import Foundation

// MARK: - Exported image framing (Task 014 / 03)

/// 导出结果图的圆角 / 边框 / 阴影。
///
/// 数值单位是**点**（逻辑像素）；实际绘制时按传入的显示缩放折算成位图像素，
/// 这样 Retina 截图上半径 8 点的圆角看上去就是 8 点。
///
/// **默认全关**（`isIdentity == true`）：不改设置时导出结果与引入本能力前**逐字节一致**，
/// 因此这是纯增量能力，不会改变既有呈现。
struct ScreenshotFrameStyle: Equatable, Sendable {
    /// 圆角半径（点）。0 = 直角。
    var cornerRadius: CGFloat = 0
    /// 边框宽度（点）。0 = 无边框。
    var borderWidth: CGFloat = 0
    /// 边框颜色（`#RRGGBB`）。
    var borderColorHex: String = "#000000"
    /// 阴影扩散（点）。0 = 无阴影。
    var shadowWidth: CGFloat = 0
    /// 阴影颜色（`#RRGGBB`）。
    var shadowColorHex: String = "#000000"
    /// 阴影总开关（沿用设置页既有的 `screenshot.includeShadow`）。
    var showsShadow: Bool = true

    static let `default` = ScreenshotFrameStyle()

    /// 是否等于「不装饰」：全关时直接返回原图，保证既有行为不变。
    var isIdentity: Bool {
        cornerRadius <= 0 && borderWidth <= 0 && effectiveShadowWidth <= 0
    }

    /// 实际生效的阴影扩散（总开关关闭时为 0）。
    var effectiveShadowWidth: CGFloat {
        showsShadow ? max(0, shadowWidth) : 0
    }

    /// 收敛到合法范围：负值与非有限值一律按 0，超大值按上限截断，避免生成异常尺寸的画布。
    func sanitized() -> ScreenshotFrameStyle {
        ScreenshotFrameStyle(
            cornerRadius: Self.clamp(cornerRadius, upper: 120),
            borderWidth: Self.clamp(borderWidth, upper: 60),
            borderColorHex: borderColorHex,
            shadowWidth: Self.clamp(shadowWidth, upper: 120),
            shadowColorHex: shadowColorHex,
            showsShadow: showsShadow
        )
    }

    // MARK: - Geometry (pure)

    /// 画布尺寸 = 源图 + 两侧边框 + 两侧阴影留白。入参、出参都是**位图像素**。
    func canvasSize(forImagePixelSize size: CGSize, scale: CGFloat = 1) -> CGSize {
        let inset = pixelInset(scale: scale)
        return CGSize(width: size.width + inset * 2, height: size.height + inset * 2)
    }

    /// 源图在画布中的位置（位图像素坐标，原点左下）。
    func imageRect(forImagePixelSize size: CGSize, scale: CGFloat = 1) -> CGRect {
        let inset = pixelInset(scale: scale)
        return CGRect(x: inset, y: inset, width: size.width, height: size.height)
    }

    // MARK: - Apply

    /// 按本样式重绘结果图并重新编码为 PNG。
    ///
    /// `scale` 是源图的显示缩放（Retina 通常为 2）；`isIdentity` 或解码失败时原样返回。
    /// 绘制走显式的 `NSBitmapImageRep`，尺寸严格等于几何计算值，不受当前屏幕缩放影响。
    func applying(to imageData: Data, scale: CGFloat = 1) -> Data {
        guard !isIdentity, let sourceRep = NSBitmapImageRep(data: imageData) else { return imageData }
        let pixelSize = CGSize(width: sourceRep.pixelsWide, height: sourceRep.pixelsHigh)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return imageData }

        let canvas = canvasSize(forImagePixelSize: pixelSize, scale: scale)
        let pixelWidth = Int(canvas.width.rounded())
        let pixelHeight = Int(canvas.height.rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let outputRep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelWidth,
                  pixelsHigh: pixelHeight,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: outputRep) else {
            return imageData
        }

        let scaledRadius = max(0, cornerRadius) * scale
        let scaledBorder = max(0, borderWidth) * scale
        let scaledShadow = effectiveShadowWidth * scale
        let imageRect = imageRect(forImagePixelSize: pixelSize, scale: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let source = NSImage(size: pixelSize)
        source.addRepresentation(sourceRep)
        let clipPath = NSBezierPath(
            roundedRect: imageRect,
            xRadius: scaledRadius,
            yRadius: scaledRadius
        )

        // 1) 阴影：以图片轮廓为形状做模糊投影。
        if scaledShadow > 0, let shadowColor = NSColor(hexString: shadowColorHex) {
            let shadow = NSShadow()
            shadow.shadowColor = shadowColor.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = scaledShadow
            shadow.shadowOffset = NSSize(width: 0, height: -scaledShadow / 3)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            shadowColor.withAlphaComponent(0.35).setFill()
            clipPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 2) 圆角裁剪后绘制原图。
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        source.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        NSGraphicsContext.restoreGraphicsState()

        // 3) 边框：沿同一圆角轮廓居中描边。
        if scaledBorder > 0, let borderColor = NSColor(hexString: borderColorHex) {
            let borderPath = NSBezierPath(
                roundedRect: imageRect.insetBy(dx: -scaledBorder / 2, dy: -scaledBorder / 2),
                xRadius: scaledRadius + scaledBorder / 2,
                yRadius: scaledRadius + scaledBorder / 2
            )
            borderPath.lineWidth = scaledBorder
            borderColor.setStroke()
            borderPath.stroke()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = outputRep.representation(using: .png, properties: [:]) else {
            return imageData
        }
        return png
    }

    // MARK: - Private

    /// 边框 + 阴影在画布四边各占的像素数。
    private func pixelInset(scale: CGFloat) -> CGFloat {
        (max(0, borderWidth) + effectiveShadowWidth) * scale
    }

    private static func clamp(_ value: CGFloat, upper: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, upper)
    }
}

// MARK: - Defaults-backed current style

extension ScreenshotFrameStyle {
    /// 输出装饰相关的 UserDefaults 键；与截图设置页的 `@AppStorage` 保持一致。
    enum DefaultsKey {
        static let includeShadow = "screenshot.includeShadow"
        static let cornerRadius = "screenshot.frame.cornerRadius"
        static let borderWidth = "screenshot.frame.borderWidth"
        static let borderColor = "screenshot.frame.borderColor"
        static let shadowWidth = "screenshot.frame.shadowWidth"
        static let shadowColor = "screenshot.frame.shadowColor"
    }

    /// 读取当前样式。缺省值与设置页默认一致：
    /// 圆角 / 边框 / 阴影扩散均为 0（不装饰），阴影总开关默认开（沿用既有 `includeShadow`）。
    static func current(from defaults: UserDefaults = .standard) -> ScreenshotFrameStyle {
        func number(_ key: String) -> CGFloat {
            (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? 0
        }
        func string(_ key: String, fallback: String) -> String {
            defaults.string(forKey: key) ?? fallback
        }
        let showsShadow = (defaults.object(forKey: DefaultsKey.includeShadow) as? NSNumber)?.boolValue ?? true

        return ScreenshotFrameStyle(
            cornerRadius: number(DefaultsKey.cornerRadius),
            borderWidth: number(DefaultsKey.borderWidth),
            borderColorHex: string(DefaultsKey.borderColor, fallback: "#000000"),
            shadowWidth: number(DefaultsKey.shadowWidth),
            shadowColorHex: string(DefaultsKey.shadowColor, fallback: "#000000"),
            showsShadow: showsShadow
        ).sanitized()
    }

    /// 当前主屏的显示缩放；取不到时按 1 处理。
    static func displayScale(for screen: NSScreen? = NSScreen.main) -> CGFloat {
        guard let scale = screen?.backingScaleFactor, scale > 0 else { return 1 }
        return scale
    }

    /// 生成装饰后的截图结果：保留原 `id` 与来源信息（含选区位置），只替换像素与尺寸。
    ///
    /// 尺寸取自装饰后位图的**像素**值，与 `ScreenshotResult.width/height` 的口径一致。
    func decorated(_ result: ScreenshotResult, scale: CGFloat = 1) -> ScreenshotResult {
        guard !isIdentity else { return result }
        let data = applying(to: result.imageData, scale: scale)
        guard data != result.imageData, let rep = NSBitmapImageRep(data: data) else { return result }
        return ScreenshotResult(
            id: result.id,
            imageData: data,
            width: rep.pixelsWide,
            height: rep.pixelsHigh,
            captureDate: result.captureDate,
            sourceType: result.sourceType,
            regionSelection: result.regionSelection
        )
    }
}

// MARK: - Hex color parsing

extension NSColor {
    /// `#RRGGBB` / `RRGGBB` → 颜色；格式非法返回 nil（调用方按「不绘制」处理）。
    convenience init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
