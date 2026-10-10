import SwiftUI

/// 统一按钮样式（`ButtonStyle`）。契约来源：PRD §9.5 通用组件规范。
///
/// 四种变体：
/// - `.primary`：低饱和深底 + 白字，主操作。
/// - `.secondary`：中性表面 + 正文前景，次操作。
/// - `.destructive`：`systemRed` 实底 + 白字，危险操作。
/// - `.ghost`：无边框、透明底，hover 时浮现 `surface2`。
///
/// 三态：hover / pressed / disabled 通过 `isEnabled` 环境值与内部
/// `onHover` 状态驱动。水平方向 `fixedSize`，随内容宽度自适应。
///
/// 全部尺寸 / 颜色 / 圆角 / 字号走 Jade token，禁止硬编码。
public struct JadeButtonStyle: ButtonStyle {

    public enum Variant {
        case primary
        case secondary
        case destructive
        case ghost
    }

    let variant: Variant

    public init(_ variant: Variant) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        JadeButtonBody(variant: variant, configuration: configuration)
    }
}

private struct JadeButtonBody: View {
    let variant: JadeButtonStyle.Variant
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(JadeFont.callout.weight(.medium))
            .foregroundStyle(foreground)
            .jadePadding(.horizontal, .x3)
            .jadePadding(.vertical, .x2)
            .fixedSize(horizontal: true, vertical: false)
            .background(background)
            .jadeRadius(.md)
            .overlay(borderOverlay)
            .shadow(color: variant == .ghost || pressed ? .clear : JadeColor.controlShadow,
                    radius: 1, x: 0, y: 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(JadeRadius.md.shape)
            .onHover { hovering in
                if isEnabled { isHovering = hovering }
            }
            .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: isHovering)
            .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: configuration.isPressed)
    }

    private var pressed: Bool { configuration.isPressed }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive:
            return .white
        case .secondary, .ghost:
            return JadeColor.textPrimary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .primary:
            (pressed ? JadeColor.actionPressed : JadeColor.actionFill)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.white.opacity(pressed ? 0 : 0.07), .clear],
                                   startPoint: .top, endPoint: .bottom)
                }
        case .destructive:
            JadeColor.danger.opacity(pressed ? 0.85 : 1)
        case .secondary:
            (isHovering || pressed ? JadeColor.surface3 : JadeColor.settingsCard)
        case .ghost:
            (isHovering || pressed ? JadeColor.surface2 : Color.clear)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch variant {
        case .primary, .destructive:
            JadeRadius.md.shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        case .secondary:
            JadeRadius.md.shape.strokeBorder(JadeColor.border, lineWidth: 1)
                .overlay {
                    JadeRadius.md.shape.inset(by: 1)
                        .strokeBorder(JadeColor.edgeHighlight, lineWidth: 0.5)
                }
        default:
            EmptyView()
        }
    }
}

// MARK: - 便捷 API

extension ButtonStyle where Self == JadeButtonStyle {
    /// 主操作按钮
    public static var jadePrimary: JadeButtonStyle { JadeButtonStyle(.primary) }
    /// 次操作按钮
    public static var jadeSecondary: JadeButtonStyle { JadeButtonStyle(.secondary) }
    /// 危险操作按钮
    public static var jadeDestructive: JadeButtonStyle { JadeButtonStyle(.destructive) }
    /// 无边框幽灵按钮
    public static var jadeGhost: JadeButtonStyle { JadeButtonStyle(.ghost) }
}

// MARK: - Preview

private struct JadeButtonGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x4.value) {
            row("primary", style: .jadePrimary)
            row("secondary", style: .jadeSecondary)
            row("destructive", style: .jadeDestructive)
            row("ghost", style: .jadeGhost)
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 340)
        .background(JadeColor.surface1)
    }

    private func row(_ title: String, style: JadeButtonStyle) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            Text(title)
                .font(JadeFont.subhead)
                .foregroundStyle(JadeColor.textSecondary)
            HStack(spacing: JadeSpace.x3.value) {
                Button("Enabled") {}
                    .buttonStyle(style)
                Button("Disabled") {}
                    .buttonStyle(style)
                    .disabled(true)
            }
        }
    }
}

#Preview("JadeButton · Light") {
    JadeButtonGallery()
        .preferredColorScheme(.light)
}

#Preview("JadeButton · Dark") {
    JadeButtonGallery()
        .preferredColorScheme(.dark)
}
