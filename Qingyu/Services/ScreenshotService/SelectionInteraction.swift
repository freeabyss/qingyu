import CoreGraphics
import Foundation

// MARK: - Aspect ratio lock (Task 014 / 06)

/// 拖拽时按 `⇧` 锁定长宽比：把当前点投影到"以起点为锚、按给定比例"的矩形顶点上。
enum SelectionAspectLock {

    /// 按 `ratio`（宽 / 高）投影当前拖拽点。
    ///
    /// 取 `|dx|` 与 `ratio * |dy|` 中较大者作为宽度基准，保证锁定后选区不会"贴着手不动"。
    /// 比例非法（≤ 0 / 非有限）时原样返回当前点。
    static func project(start: CGPoint, current: CGPoint, ratio: CGFloat) -> CGPoint {
        guard ratio > 0, ratio.isFinite else { return current }
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard dx != 0 || dy != 0 else { return current }

        let width = max(abs(dx), abs(dy) * ratio)
        let height = width / ratio

        return CGPoint(
            x: start.x + (dx < 0 ? -width : width),
            y: start.y + (dy < 0 ? -height : height)
        )
    }

    /// 由矩形推导长宽比；任一边为 0 时返回 nil（无法锁定）。
    static func ratio(of rect: CGRect) -> CGFloat? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect.width / rect.height
    }
}

// MARK: - Annotation pen width stepping (Task 014 / 02)

/// 笔宽三档步进：滚轮与 `[` `]` 走相邻档。
///
/// 说明：数字键 `1`-`9` 已被「工具条分组选择」占用（Task 013），因此不提供数字预设笔宽。
enum AnnotationLineWidthStepper {

    /// 相邻档位：`direction > 0` 加粗，`< 0` 变细；到边界后保持不动（不循环）。
    static func step(_ current: AnnotationLineWidth, direction: Int) -> AnnotationLineWidth {
        let all = AnnotationLineWidth.allCases
        guard let index = all.firstIndex(of: current) else { return current }
        let next = index + (direction > 0 ? 1 : -1)
        guard all.indices.contains(next) else { return current }
        return all[next]
    }
}

// MARK: - Color value formatting (Task 014 / 04)

/// 取色值的色彩空间。
enum ColorValueSpace: String, CaseIterable, Codable, Identifiable, Sendable {
    case rgb, hsv, hsl

    var id: String { rawValue }

    var displayName: String { L10n.localized("settings.colorValue.space.\(rawValue)") }
}

/// 取色输出格式选项（Task 014 / 04）。
///
/// 默认值与既有行为一致：小写 `#rrggbb`，因此不改设置时行为不变。
struct ColorValueOptions: Equatable, Codable, Sendable {
    var space: ColorValueSpace = .rgb
    /// 默认与既有 UI 一致：**大写**十六进制（`#RRGGBB`）。
    /// 归入本任务时不改变已有呈现，因此没有采用「默认小写」的方案。
    var uppercaseHex: Bool = true
    var omitHash: Bool = false
    var spacedComponents: Bool = false

    static let `default` = ColorValueOptions()
}

/// 取色文本格式化。纯函数，可在无屏幕环境下单测。
enum ColorValueFormatter {

    /// 单像素颜色 + 选项 → 复制到剪贴板的文本。
    static func string(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        options: ColorValueOptions
    ) -> String {
        switch options.space {
        case .rgb:
            // RGB 空间下十六进制是主格式；分量形式由 `spacedComponents` 控制分隔符。
            return hex(red: red, green: green, blue: blue, options: options)
        case .hsv:
            let hsv = hsvComponents(red: red, green: green, blue: blue)
            return components(hsv, options: options)
        case .hsl:
            let hsl = hslComponents(red: red, green: green, blue: blue)
            return components(hsl, options: options)
        }
    }

    /// `#rrggbb`；受 `uppercaseHex` / `omitHash` 影响。
    static func hex(red: UInt8, green: UInt8, blue: UInt8, options: ColorValueOptions) -> String {
        let format = options.uppercaseHex ? "%02X%02X%02X" : "%02x%02x%02x"
        let digits = String(format: format, red, green, blue)
        return (options.omitHash ? "" : "#") + digits
    }

    // MARK: - Private

    private static func components(_ values: [Int], options: ColorValueOptions) -> String {
        let separator = options.spacedComponents ? ", " : ","
        return values.map(String.init).joined(separator: separator)
    }

    private static func hsvComponents(red: UInt8, green: UInt8, blue: UInt8) -> [Int] {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return [
            Int(hue.rounded()),
            Int((saturation * 100).rounded()),
            Int((maxValue * 100).rounded())
        ]
    }

    private static func hslComponents(red: UInt8, green: UInt8, blue: UInt8) -> [Int] {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2

        var hue: Double = 0
        if delta > 0 {
            if maxValue == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let denominator = 1 - abs(2 * lightness - 1)
        let saturation = denominator == 0 ? 0 : delta / denominator
        return [
            Int(hue.rounded()),
            Int((saturation * 100).rounded()),
            Int((lightness * 100).rounded())
        ]
    }
}
