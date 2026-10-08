import SwiftUI

/// 概览页统计卡片。契约来源：PRD §9.5 通用组件规范。
///
/// 图标 + 标题 + 数值三段式。`JadeRadius.lg` 圆角、`JadeColor.surface2` 底，
/// hover 时切换到 `surface3`。
///
/// 全部尺寸 / 颜色 / 圆角 / 字号走 Jade token，禁止硬编码。
public struct StatCard: View {

    private let icon: Image
    private let title: LocalizedStringKey
    private let value: String
    private let tint: Color

    @State private var isHovering = false

    /// - Parameters:
    ///   - icon: 卡片图标。
    ///   - title: 标题(本地化 key)。
    ///   - value: 数值(格式化后的字符串)。
    ///   - tint: 图标着色，默认主色。
    public init(icon: Image,
                title: LocalizedStringKey,
                value: String,
                tint: Color = JadeColor.primary) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            HStack {
                icon
                    .font(JadeFont.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(value)
                .font(JadeFont.title1)
                .foregroundStyle(JadeColor.textPrimary)
            Text(title)
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JadeSpace.x4.value)
        .background(isHovering ? JadeColor.surface3 : JadeColor.surface2)
        .jadeRadius(.lg)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        // VoiceOver：合并为 "标题: 数值"。
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

private struct StatCardGallery: View {
    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            StatCard(icon: Image(systemName: "doc.on.clipboard"),
                     title: "剪贴板条目", value: "1,284")
            StatCard(icon: Image(systemName: "camera.viewfinder"),
                     title: "截图", value: "37", tint: JadeColor.info)
            StatCard(icon: Image(systemName: "magnifyingglass"),
                     title: "搜索次数", value: "512", tint: JadeColor.success)
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 460)
        .background(JadeColor.surface1)
    }
}

#Preview("StatCard · Light") {
    StatCardGallery()
        .preferredColorScheme(.light)
}

#Preview("StatCard · Dark") {
    StatCardGallery()
        .preferredColorScheme(.dark)
}
