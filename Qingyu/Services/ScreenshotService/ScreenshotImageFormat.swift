import AppKit
import Foundation

// MARK: - Export image format (JPEG support)

/// 截图**落盘**格式。
///
/// 只影响写入磁盘的文件；**剪贴板始终写 PNG** —— JPEG 无 alpha，粘到别处会出现
/// 白底方块或锯齿边缘，而复制场景几乎总是要无损。
enum ScreenshotImageFormat: String, CaseIterable, Codable {
    case png
    case jpeg

    /// 默认 PNG：与引入本能力前的行为完全一致。
    static let `default` = ScreenshotImageFormat.png

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var localizationKey: String {
        switch self {
        case .png: return "management.screenshot.format.png"
        case .jpeg: return "management.screenshot.format.jpeg"
        }
    }

    enum DefaultsKey {
        static let imageFormat = "screenshot.imageFormat"
    }

    /// 读取当前设置；无法识别的取值回落到 PNG，不抛错。
    static func current(from defaults: UserDefaults = .standard) -> ScreenshotImageFormat {
        guard let raw = defaults.string(forKey: DefaultsKey.imageFormat),
              let format = ScreenshotImageFormat(rawValue: raw) else {
            return .default
        }
        return format
    }
}

// MARK: - Encoder

/// 导出编码。
enum ScreenshotImageEncoder {
    /// JPEG 质量；0.9 在体积与观感之间取平衡（截图多为文字与 UI，过低会出现明显振铃）。
    static let jpegQuality: CGFloat = 0.9

    /// JPEG 无 alpha，透明区域统一压平到**不透明白底**。
    ///
    /// 不压平的话，带圆角/阴影的导出图在 JPEG 里会出现黑边（透明被当作黑色）。
    static let jpegBackgroundColor: NSColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// 按目标格式编码。
    ///
    /// - PNG：**原样返回**（截图本身就是 PNG），保证导出结果逐字节不变；
    /// - JPEG：白底压平后重新编码；解码失败时回退为原数据，绝不产出空文件。
    static func encode(_ imageData: Data, format: ScreenshotImageFormat) -> Data {
        switch format {
        case .png:
            return imageData
        case .jpeg:
            guard let jpeg = encodeJPEG(imageData) else { return imageData }
            return jpeg
        }
    }

    /// 编码为 JPEG；取不到位图或编码失败返回 nil。
    static func encodeJPEG(_ imageData: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: imageData) else { return nil }
        let width = source.pixelsWide
        let height = source.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        // 显式位图而不是 `NSImage.lockFocus()`：后者在 Retina 上会产出 2 倍位图，
        // 导致导出尺寸与源图不一致。
        //
        // 缓冲用标准 RGBA（`samplesPerPixel: 4`）：`CGBitmapContextCreate` 不接受
        // 「RGB 无 alpha + 自动行宽」的组合（会报 unsupported parameter combination）。
        // JPEG 本身没有 alpha，编码时会丢弃该通道，所以压平到白底即可。
        guard let flattened = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flattened)
        jpegBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let image = NSImage(size: CGSize(width: width, height: height))
        image.addRepresentation(source)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return flattened.representation(
            using: .jpeg,
            properties: [.compressionFactor: jpegQuality]
        )
    }
}
