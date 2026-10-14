import AppKit
import CoreGraphics

// MARK: - Whiteboard background (Task 016)

/// 白板底图来源。
///
/// 纯色底图**完全不读取屏幕内容**，因此不需要屏幕录制权限 —— 这是本任务的硬性要求，
/// 由 `solidImage` 的实现方式（纯内存绘制，不触碰任何抓屏 API）保证。
enum WhiteboardBackground {
    /// 纯色底图：按像素尺寸绘制，1:1 输出，不受当前屏幕缩放影响。
    static func solidImage(pixelSize: CGSize, color: NSColor) -> NSImage? {
        let width = Int(max(1, pixelSize.width.rounded()))
        let height = Int(max(1, pixelSize.height.rounded()))
        guard let rep = NSBitmapImageRep(
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
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: CGSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    /// 冻结底图：由调用方注入抓屏结果（`CGImage`）。
    ///
    /// 单独成函数而不是直接抓屏，是为了让「底图构造」可测：
    /// 抓屏本身需要屏幕录制权限，不应出现在单元测试路径里。
    static func frozenImage(from cgImage: CGImage) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
