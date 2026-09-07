import AppKit
import CoreGraphics
import Foundation

// MARK: - Color sampling (Task 007)

/// 取色结果格式：`#RRGGBB` 与 `R, G, B`。
enum ColorString {
    static func hex(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func rgb(red: UInt8, green: UInt8, blue: UInt8) -> String {
        "\(red), \(green), \(blue)"
    }
}

/// 像素取色：从捕获图像按像素坐标采样，返回颜色与两种文本格式。
enum ColorSampler {
    typealias SampledColor = (red: UInt8, green: UInt8, blue: UInt8)

    /// 采样指定像素（图像像素坐标，左上原点）；越界返回 nil。
    /// 直接把目标像素绘制进 1×1 RGBA 位图读取，避免色彩空间转换漂移。
    static func samplePixel(at point: CGPoint, in cgImage: CGImage) -> SampledColor? {
        let width = cgImage.width
        let height = cgImage.height
        guard Int(point.x) >= 0, Int(point.y) >= 0,
              Int(point.x) < width, Int(point.y) < height else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let result = pixel.withUnsafeMutableBytes { buffer -> SampledColor? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .none
            // 图像第 point.y 行（左上原点）对应 CG 绘制矩形 y 偏移 -(height - y - 1)。
            let offset = CGRect(
                x: -CGFloat(Int(point.x)),
                y: -(CGFloat(height - Int(point.y) - 1)),
                width: CGFloat(width),
                height: CGFloat(height)
            )
            context.draw(cgImage, in: offset)
            let bytes = buffer.bindMemory(to: UInt8.self)
            return (red: bytes[0], green: bytes[1], blue: bytes[2])
        }
        return result
    }

    /// 采样并生成两种文本格式；越界返回 nil。
    static func sample(at point: CGPoint, in cgImage: CGImage) -> (hex: String, rgb: String)? {
        guard let color = samplePixel(at: point, in: cgImage) else { return nil }
        return (
            hex: ColorString.hex(red: color.red, green: color.green, blue: color.blue),
            rgb: ColorString.rgb(red: color.red, green: color.green, blue: color.blue)
        )
    }
}
