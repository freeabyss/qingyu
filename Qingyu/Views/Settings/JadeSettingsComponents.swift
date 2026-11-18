import SwiftUI

// MARK: - Settings icons

/// 侧栏使用单色、轻量的图标，让选中状态而非装饰性色块承担导航层级。
struct SettingsSidebarIcon: View {
    let systemImage: String
    /// 选中时转主色，与所在行的胶囊底一起构成导航层级。
    var isActive: Bool = false

    /// 侧栏图标边长：18pt 正方形，仅用于设置侧栏图标；不并入 JadeSpace，那是间距档位，不是图标尺寸。
    private static let iconSize: CGFloat = 18

    var body: some View {
        Image(systemName: systemImage)
            .font(JadeFont.settingsSidebarIcon)
            .foregroundStyle(isActive ? JadeColor.primary : JadeColor.textSecondary)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .accessibilityHidden(true)
    }
}

/// 页首图标只作为标题的辅助线索，避免形成独立的彩色视觉块。
struct SettingsHeaderIcon: View {
    let systemImage: String

    /// 页首图标边长：28pt 正方形，仅用于设置页首图标；不并入 JadeSpace，那是间距档位，不是图标尺寸。
    private static let iconSize: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(JadeFont.settingsHeaderIcon)
            .foregroundStyle(JadeColor.primary)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .accessibilityHidden(true)
    }
}

// MARK: - Card

/// 设置内容组：安静的单层表面、细边界与统一的行间距。
///
/// 行间分隔用 `JadeSettingsDivider`（自标签文字左缘 inset）；小节标题由
/// `SettingsSection` 放在卡片外。玻璃语言下卡片是半透明浮层，
/// 让窗口材质继续从内容组之间透出。
struct JadeSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jadePadding(.x4)
        .background(JadeGlass.cardFill)
        .jadeRadius(.lg)
        .jadeRadiusBorder(.lg)
    }
}

/// 内容组内的细分隔线。它从已内缩的内容区开始，与文本左缘对齐。
struct JadeSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(JadeGlass.separator)
    }
}

// MARK: - Segmented picker

/// 胶囊形分段选择器（玻璃语言版 `.segmented`）。
///
/// 系统 `pickerStyle(.segmented)` 自带一块不透明材质，会把玻璃盖死；
/// 这里用键帽底做轨道、选中段实心（深色外观白 / 浅色外观深），
/// 对应交接文档第四节第 4 点。选项内容与选中态走无障碍语义（`.isSelected`）。
struct JadeSegmentedPicker<Option: Hashable>: View {
    let options: [(option: Option, label: String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: JadeSpace.x1.value) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.option == selection
                Button {
                    selection = option.option
                } label: {
                    Text(option.label)
                        .font(JadeFont.subhead)
                        .foregroundStyle(isSelected ? JadeColor.onPrimary : JadeColor.textPrimary)
                        .jadePadding(.horizontal, .x3)
                        .jadePadding(.vertical, .x1)
                        // Capsule 是形状语义（完全圆的两端），JadeRadius 是圆角档位，不互相换算。
                        .background(isSelected ? JadeGlass.selectionMark : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(JadeSpace.x1.value)
        .background(JadeGlass.keycapFill, in: Capsule())
        .overlay(Capsule().strokeBorder(JadeGlass.keycapBorder, lineWidth: 1))
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
        .jadePadding(.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 460, height: 320)
    .background(JadeGlass.tint)
}
