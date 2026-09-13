import SwiftUI

// MARK: - Page tint

/// 设置页图标块的语义配色（视觉参照 macOS 系统设置的彩色图标风格）。
///
/// 仅用于设置窗口的图标块（侧栏条目 / 页首标题），是页面语义到既有
/// `JadeColor` 语义色的映射，不新增颜色值。
enum JadeSettingsPageTint {
    /// 中性（通用 / 系统类页面）
    case neutral
    /// 信息 / 快速启动
    case blue
    /// 剪贴板
    case green
    /// 截图（FeatureGate 恢复后沿用）
    case purple
    /// 品牌 Jade 兜底（未识别的插件页）
    case primary

    var color: Color {
        switch self {
        case .neutral: return JadeColor.gray
        case .blue: return JadeColor.blue
        case .green: return JadeColor.green
        case .purple: return JadeColor.purple
        case .primary: return JadeColor.primary
        }
    }

    /// 插件页 → 图标块配色（按 `PluginID.rawValue`；未识别插件回退品牌色）。
    static func forPluginID(_ rawValue: String) -> JadeSettingsPageTint {
        switch rawValue {
        case "quick-launch": return .blue
        case "clipboard": return .green
        case "screenshot": return .purple
        default: return .primary
        }
    }
}

// MARK: - Icon tile

/// 彩色圆角方形图标块：白色 SF Symbol glyph + 语义色填充。
///
/// 用于设置侧栏条目与页首标题图标（默认 28×28、圆角 `JadeRadius.sm`，
/// 更大尺寸自动升到 `.md`），视觉对齐 macOS 系统设置风格。
struct JadeIconTile: View {
    let systemImage: String
    var tint: JadeSettingsPageTint = .primary
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(tint.color)
            .jadeRadius(size >= 32 ? .md : .sm)
            .accessibilityHidden(true)
    }
}

// MARK: - Card

/// 设置内容卡片：每小节一张（`surface2` 填充 + `JadeRadius.lg` 圆角 + x4 内边距）。
///
/// 行间分隔用 `JadeSettingsDivider`（自标签文字左缘 inset）；小节标题由
/// `SettingsSection` 放在卡片外。
struct JadeSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JadeSpace.x4.value)
        .background(JadeColor.surface2)
        .jadeRadius(.lg)
    }
}

/// 卡片内行间分隔线：与卡片行内容左缘（x4 内边距）对齐 inset。
struct JadeSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(JadeColor.border)
            .padding(.leading, JadeSpace.x4.value)
    }
}

// MARK: - Labeled row

/// 设置行：主标签 + 可选 12pt 次要色说明 + 右侧控件。
///
/// 右侧控件（开关 / Picker / HotkeyRecorder 等）由调用方原样传入；
/// 纯开关行仍走 `JadeSwitchRow`。
struct JadeSettingsRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: JadeSpace.x3.value) {
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(title)
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Preview

#Preview("JadeSettingsComponents · Light") {
    settingsComponentsGallery
        .preferredColorScheme(.light)
}

#Preview("JadeSettingsComponents · Dark") {
    settingsComponentsGallery
        .preferredColorScheme(.dark)
}

private var settingsComponentsGallery: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: JadeSpace.x6.value) {
            HStack(spacing: JadeSpace.x3.value) {
                JadeIconTile(systemImage: "gearshape", tint: .neutral)
                JadeIconTile(systemImage: "rocket", tint: .blue)
                JadeIconTile(systemImage: "doc.on.clipboard", tint: .green)
                JadeIconTile(systemImage: "info.circle", tint: .blue)
                JadeIconTile(systemImage: "camera.viewfinder", tint: .purple)
                JadeIconTile(systemImage: "bird", tint: .primary)
            }

            VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                Text("小节标题在卡片外")
                    .font(JadeFont.headline)
                    .foregroundStyle(JadeColor.textSecondary)
                JadeSettingsCard {
                    JadeSettingsRow("带说明的行", subtitle: "12pt 次要色说明文字。") {
                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    JadeSettingsDivider()
                    JadeSettingsRow("普通行") {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(JadeColor.textTertiary)
                    }
                }
            }
        }
        .padding(JadeSpace.x6.value)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 460, height: 320)
    .background(JadeColor.surface1)
}
