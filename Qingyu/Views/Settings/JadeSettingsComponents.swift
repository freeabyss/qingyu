import SwiftUI

// MARK: - Settings icons

/// 侧栏使用单色、轻量的图标，让选中状态而非装饰性色块承担导航层级。
struct SettingsSidebarIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(JadeColor.textSecondary)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

/// 页首图标只作为标题的辅助线索，避免形成独立的彩色视觉块。
struct SettingsHeaderIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(JadeColor.primary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

// MARK: - Card

/// 设置内容组：安静的单层表面、细边界与统一的行间距。
///
/// 行间分隔用 `JadeSettingsDivider`（自标签文字左缘 inset）；小节标题由
/// `SettingsSection` 放在卡片外。
struct JadeSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JadeSpace.x4.value)
        .background(JadeColor.settingsCard)
        .jadeRadius(.lg)
        .jadeRadiusBorder(.lg)
    }
}

/// 内容组内的细分隔线。它从已内缩的内容区开始，与文本左缘对齐。
struct JadeSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(JadeColor.border)
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
                SettingsSidebarIcon(systemImage: "gearshape")
                SettingsSidebarIcon(systemImage: "rocket")
                SettingsSidebarIcon(systemImage: "doc.on.clipboard")
                SettingsHeaderIcon(systemImage: "info.circle")
                SettingsHeaderIcon(systemImage: "camera.viewfinder")
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
