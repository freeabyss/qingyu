import SwiftUI

/// 轻质感阴影：控件仅有接触阴影，浮窗使用柔和扩散阴影。
/// 普通分组不使用投影；浮窗保留细轮廓以区分桌面背景。
public enum JadeShadow: CaseIterable {
    case sm
    case md
    case lg
    case xl

    /// 阴影颜色（黑色 + 对应透明度）
    fileprivate var color: Color {
        switch self {
        case .sm: return Color.black.opacity(0.06)
        case .md: return Color.black.opacity(0.07)
        case .lg: return Color.black.opacity(0.10)
        case .xl: return Color.black.opacity(0.14)
        }
    }

    /// 模糊半径（PRD blur 值 / 2，SwiftUI radius 语义近似 CSS blur 的一半）
    fileprivate var radius: CGFloat {
        switch self {
        case .sm: return 1
        case .md: return 4
        case .lg: return 12
        case .xl: return 20
        }
    }

    /// Y 方向偏移
    fileprivate var y: CGFloat {
        switch self {
        case .sm: return 1
        case .md: return 2
        case .lg: return 4
        case .xl: return 8
        }
    }

    /// lg / xl 需要附加 1px Border 描边
    fileprivate var hasBorder: Bool {
        switch self {
        case .sm, .md: return false
        case .lg, .xl: return true
        }
    }
}

// MARK: - View 扩展

extension View {
    /// 应用阴影 token。lg / xl 会附加 1px Border 描边（沿指定圆角）。
    ///
    /// ```swift
    /// panel.jadeShadow(.xl, radius: .xxl)
    /// ```
    public func jadeShadow(_ shadow: JadeShadow,
                           radius: JadeRadius = .lg) -> some View {
        modifier(JadeShadowModifier(shadow: shadow, cornerRadius: radius))
    }
}

private struct JadeShadowModifier: ViewModifier {
    let shadow: JadeShadow
    let cornerRadius: JadeRadius

    func body(content: Content) -> some View {
        content
            // Treat the panel as one surface; do not cast shadows from each child.
            .compositingGroup()
            .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
            .modifier(BorderIfNeeded(shadow: shadow, cornerRadius: cornerRadius))
    }
}

private struct BorderIfNeeded: ViewModifier {
    let shadow: JadeShadow
    let cornerRadius: JadeRadius

    func body(content: Content) -> some View {
        if shadow.hasBorder {
            content.overlay(
                cornerRadius.shape.strokeBorder(JadeColor.border, lineWidth: 1)
            )
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview("JadeShadow") {
    VStack(spacing: 28) {
        ForEach(JadeShadow.allCases, id: \.self) { s in
            JadeColor.surface1
                .frame(width: 180, height: 60)
                .jadeRadius(.lg)
                .jadeShadow(s, radius: .lg)
                .overlay(
                    Text(String(describing: s))
                        .font(JadeFont.subhead)
                        .foregroundStyle(JadeColor.textSecondary)
                )
        }
    }
    .padding(48)
    .frame(width: 300, height: 460)
    .background(JadeColor.surface2)
}
