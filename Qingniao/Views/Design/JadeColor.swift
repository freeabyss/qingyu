import SwiftUI
import AppKit

/// Qingniao 品牌 / 语义色 Design Token。
///
/// 契约来源：PRD §9.2.1 / §9.2.2、architecture/design.md §3.7。
///
/// 设计原则：
/// - 品牌色（Jade 500/600/50）为自定义色，通过 `NSColor(name:dynamicProvider:)` 实现明暗自动适配。
/// - 中性文字/表面色优先绑定系统动态色（`labelColor` / `windowBackgroundColor` …），
///   自动跟随系统「增强对比度」「降低透明度」等辅助功能设置。
/// - 语义色直接走系统色（`systemGreen/Red/…`），不自定义。
///
/// View 层禁止硬编码颜色，一律走本 token（约束由 code review 把关）。
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

    /// Jade 500 主色：Light `#0A9488` / Dark `#2DD4BF`
    public static let jade500NS = dynamic("500", Pair(
        light: NSColor(srgbHex: 0x0A9488),
        dark: NSColor(srgbHex: 0x2DD4BF)
    ))

    /// Jade 600 深主色 / hover：Light `#087A70` / Dark `#14B8A6`
    public static let jade600NS = dynamic("600", Pair(
        light: NSColor(srgbHex: 0x087A70),
        dark: NSColor(srgbHex: 0x14B8A6)
    ))

    /// Jade 50 主色底（选中态 / 浅底）：Light `#E6F7F5` / Dark `#0D3D39`
    public static let jade50NS = dynamic("50", Pair(
        light: NSColor(srgbHex: 0xE6F7F5),
        dark: NSColor(srgbHex: 0x0D3D39)
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
    /// 三级文字 = `NSColor.tertiaryLabelColor`
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: - 中性色 · 表面（PRD §9.2.2）

    /// Surface 1 = `NSColor.windowBackgroundColor`（Light `#FFFFFF` / Dark `#1E1E1E`）
    public static let surface1 = Color(nsColor: .windowBackgroundColor)
    /// Surface 2 = `NSColor.controlBackgroundColor`（Light `#F5F5F7` / Dark `#2A2A2A`）
    public static let surface2 = Color(nsColor: .controlBackgroundColor)

    /// Surface 3 hover / pressed：比 surface2 深/浅一档
    /// Light `#ECECEE` / Dark `#3A3A3C`。
    public static let surface3NS = dynamic("Surface3", Pair(
        light: NSColor(srgbHex: 0xECECEE),
        dark: NSColor(srgbHex: 0x3A3A3C)
    ))
    public static let surface3 = Color(surface3NS)

    /// 设置卡片填充（System Settings 白底灰卡风格）：Light `#F2F2F7` / Dark `#2A2A2A`。
    public static let settingsCardNS = dynamic("SettingsCard", Pair(
        light: NSColor(srgbHex: 0xF2F2F7),
        dark: NSColor(srgbHex: 0x2A2A2A)
    ))
    public static let settingsCard = Color(settingsCardNS)

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
