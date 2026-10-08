import SwiftUI
import AppKit

/// 清羽的轻质感视觉系统：中性表面、低饱和蓝灰强调色与系统语义文字。
/// 保留 Jade API 名称以兼容现有调用；视觉契约见 docs/prd/02-ui-spec.md。
/// 颜色随深浅外观解析，边框响应系统增强对比度。
public enum JadeColor {

    // MARK: - Hex 值表（PRD §9.2.1 / §9.2.2 基准值）

    /// PRD §9.2 双模式取值定义。`light` / `dark` 为 sRGB 十六进制。
    private struct Pair {
        let light: NSColor
        let dark: NSColor
    }

    /// 生成随系统外观自动切换的动态 `NSColor`。
    private static func dynamic(_ name: String, _ pair: Pair) -> NSColor {
        NSColor(name: NSColor.Name("Jade.\(name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? pair.dark : pair.light
        }
    }

    // MARK: - 品牌色（NSColor 桥接）

    /// 低饱和蓝灰强调色；旧 jade500 命名仅作 API 兼容。
    public static let jade500NS = dynamic("500", Pair(
        light: NSColor(srgbHex: 0x4D6487),
        dark: NSColor(srgbHex: 0xB2C4DF)
    ))

    /// 强调色 hover。
    public static let jade600NS = dynamic("600", Pair(
        light: NSColor(srgbHex: 0x3C5273),
        dark: NSColor(srgbHex: 0xCBDAEE)
    ))

    /// 选中状态的低对比表面，配合轮廓与文字区分。
    public static let jade50NS = dynamic("50", Pair(
        light: NSColor(srgbHex: 0xECF0F6),
        dark: NSColor(srgbHex: 0x2A3443)
    ))

    // MARK: - 品牌色（SwiftUI Color）

    /// Jade 500 主色
    public static let jade500 = Color(jade500NS)
    /// Jade 600 深主色 / hover
    public static let jade600 = Color(jade600NS)
    /// Jade 50 主色底
    public static let jade50 = Color(jade50NS)

    // MARK: - 语义色（brand semantic）

    /// 主色 = Jade 500
    public static let primary = jade500
    /// 主色 hover = Jade 600
    public static let primaryHover = jade600
    /// 主色浅底 = Jade 50
    public static let primaryFill = jade50

    /// NSColor 版本（供 AppKit 场景使用）
    public static let primaryNS = jade500NS
    public static let primaryHoverNS = jade600NS
    public static let primaryFillNS = jade50NS

    // MARK: - 中性色 · 文字（绑定系统动态色，PRD §9.2.2）

    /// 主文字 = `NSColor.labelColor`
    public static let textPrimary = Color(nsColor: .labelColor)
    /// 次文字 = `NSColor.secondaryLabelColor`
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    /// 元信息沿用系统次要文字色；以字号和位置降级，避免深色下过暗。
    public static let textTertiary = Color(nsColor: .secondaryLabelColor)

    // MARK: - 中性色 · 表面（PRD §9.2.2）

    /// 主内容面；保持轻微灰度，避免大面积纯白的眩光。
    public static let surface1NS = dynamic("Surface1", Pair(
        light: NSColor(srgbHex: 0xFCFCFD), dark: NSColor(srgbHex: 0x202226)
    ))
    public static let surface1 = Color(surface1NS)
    /// 工作区 / 侧栏底色。
    public static let surface2NS = dynamic("Surface2", Pair(
        light: NSColor(srgbHex: 0xF3F4F6), dark: NSColor(srgbHex: 0x191B1F)
    ))
    public static let surface2 = Color(surface2NS)
    /// 悬停 / 按下反馈。
    public static let surface3NS = dynamic("Surface3", Pair(
        light: NSColor(srgbHex: 0xE9EBEF), dark: NSColor(srgbHex: 0x30343B)
    ))
    public static let surface3 = Color(surface3NS)
    /// 平整的设置分组表面，不叠加卡片阴影。
    public static let settingsCardNS = dynamic("SettingsCard", Pair(
        light: NSColor(srgbHex: 0xFFFFFF), dark: NSColor(srgbHex: 0x24272D)
    ))
    public static let settingsCard = Color(settingsCardNS)
    /// 白字按钮单独使用较深的底色，避免深色模式强调文字色过亮。
    public static let actionFill = Color(dynamic("ActionFill", Pair(
        light: NSColor(srgbHex: 0x4D6487), dark: NSColor(srgbHex: 0x526B90)
    )))
    public static let actionPressed = Color(dynamic("ActionPressed", Pair(
        light: NSColor(srgbHex: 0x3D5272), dark: NSColor(srgbHex: 0x435B7D)
    )))
    /// 轻拟物仅用于控件边缘的一点高光和接触阴影。
    public static let edgeHighlight = Color(dynamic("EdgeHighlight", Pair(
        light: NSColor.white.withAlphaComponent(0.8),
        dark: NSColor.white.withAlphaComponent(0.08)
    )))
    public static let controlShadow = Color.black.opacity(0.07)

    // MARK: - 描边 / 遮罩（PRD §9.2.2）

    /// Border 分隔线 / 描边：Light `rgba(0,0,0,0.08)` / Dark `rgba(255,255,255,0.08)`。
    ///
    /// PRD §9.8「增强对比度」：系统开启该辅助功能时，边框透明度加深到 0.2，
    /// 使描边在高对比模式下清晰可辨。通过 `dynamicProvider` 在绘制时读取
    /// `NSWorkspace` 的对比度设置，无需重建视图即可跟随系统切换。
    public static let borderNS = NSColor(name: NSColor.Name("Jade.Border")) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.2 : 0.08
        return isDark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }
    public static let border = Color(borderNS)

    /// Overlay 全屏遮罩：`rgba(0,0,0,0.4)`（明暗一致）
    public static let overlay = Color.black.opacity(0.4)
    public static let overlayNS = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4)

    // MARK: - 语义色 · 状态（直接走系统色，PRD §9.2.1）

    /// 成功
    public static let success = Color(nsColor: .systemGreen)
    /// 危险 / 错误
    public static let danger = Color(nsColor: .systemRed)
    /// 警告
    public static let warning = Color(nsColor: .systemOrange)
    /// 提醒 / 高亮
    public static let attention = Color(nsColor: .systemYellow)
    /// 信息
    public static let info = Color(nsColor: .systemBlue)

    /// 结果类型底色（PRD §9.2.9），前景 glyph 用同色、底色 15% 透明。
    public static let indigo = Color(nsColor: .systemIndigo)
    public static let purple = Color(nsColor: .systemPurple)
    public static let pink = Color(nsColor: .systemPink)
    public static let green = Color(nsColor: .systemGreen)
    public static let blue = Color(nsColor: .systemBlue)
    public static let orange = Color(nsColor: .systemOrange)
    public static let gray = Color(nsColor: .systemGray)
}

// MARK: - NSColor sRGB Hex 便捷初始化

extension NSColor {
    /// 以 `0xRRGGBB` sRGB 十六进制构造不透明颜色。
    fileprivate convenience init(srgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Preview

#Preview("JadeColor · Light / Dark") {
    func swatch(_ color: Color, _ name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .frame(width: 64, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(JadeColor.border, lineWidth: 1)
                )
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(JadeColor.textSecondary)
        }
    }

    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Brand")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                swatch(JadeColor.jade50, "jade50")
                swatch(JadeColor.jade500, "jade500")
                swatch(JadeColor.jade600, "jade600")
            }

            Text("Neutral / Surface")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                swatch(JadeColor.surface1, "surface1")
                swatch(JadeColor.surface2, "surface2")
                swatch(JadeColor.surface3, "surface3")
                swatch(JadeColor.border, "border")
            }

            Text("Status")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                swatch(JadeColor.success, "success")
                swatch(JadeColor.danger, "danger")
                swatch(JadeColor.warning, "warning")
                swatch(JadeColor.info, "info")
            }

            Text("Text on surface")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("textPrimary").foregroundStyle(JadeColor.textPrimary)
                Text("textSecondary").foregroundStyle(JadeColor.textSecondary)
                Text("textTertiary").foregroundStyle(JadeColor.textTertiary)
            }
            .font(.system(size: 13))
        }
        .padding(24)
    }
    .frame(width: 360, height: 520)
}
