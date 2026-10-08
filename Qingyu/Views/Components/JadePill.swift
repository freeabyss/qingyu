import SwiftUI

/// 文本胶囊 / 徽标。契约来源：PRD §9.5 通用组件规范。
///
/// 用于类型 badge、计数徽标、快捷键徽标。六种语义配色，前景为对应色、
/// 底色为同色 15% 透明填充；`JadeFont.caption`。
///
/// 圆角策略：短内容(≤2 字符，如计数)用全 pill(capsule)，其余用 `JadeRadius.sm`。
/// `.toolbar` 变体更大更高，用于截图 / 工具条。
///
/// 全部颜色 / 圆角 / 字号走 Jade token，禁止硬编码。
public struct JadePill: View {

    public enum Style {
        case neutral
        case primary
        case info
        case success
        case warning
        case danger

        var foreground: Color {
            switch self {
            case .neutral: return JadeColor.textSecondary
            case .primary: return JadeColor.primary
            case .info: return JadeColor.info
            case .success: return JadeColor.success
            case .warning: return JadeColor.warning
            case .danger: return JadeColor.danger
            }
        }

        var fill: Color { foreground.opacity(0.15) }
    }

    public enum Size {
        /// 常规徽标
        case regular
        /// 工具条大 pill
        case toolbar
    }

    private let text: String
    private let style: Style
    private let size: Size

    public init(_ text: String, style: Style = .neutral, size: Size = .regular) {
        self.text = text
        self.style = style
        self.size = size
    }

    private var font: Font {
        size == .toolbar ? JadeFont.subhead : JadeFont.caption
    }

    private var hPadding: CGFloat {
        size == .toolbar ? JadeSpace.x3.value : JadeSpace.x2.value
    }

    private var vPadding: CGFloat {
        size == .toolbar ? JadeSpace.x2.value : 2
    }

    /// 内容足够短时用全 pill，否则用 sm 圆角。
    private var usesCapsule: Bool {
        size == .toolbar || text.count <= 2
    }

    public var body: some View {
        Text(text)
            .font(font)
            .fontWeight(.medium)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(
                Group {
                    if usesCapsule {
                        Capsule(style: .continuous).fill(style.fill)
                    } else {
                        JadeRadius.sm.shape.fill(style.fill)
                    }
                }
            )
            .fixedSize()
}
}

/// `JadeBadge` 为 `JadePill` 的语义别名(徽标场景)。
public typealias JadeBadge = JadePill

// MARK: - Preview

private struct JadePillGallery: View {
    private let styles: [(String, JadePill.Style)] = [
        ("neutral", .neutral), ("primary", .primary), ("info", .info),
        ("success", .success), ("warning", .warning), ("danger", .danger)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x4.value) {
            Text("regular").font(JadeFont.subhead).foregroundStyle(JadeColor.textSecondary)
            FlowRow {
                ForEach(styles, id: \.0) { name, style in
                    JadePill(name, style: style)
                }
            }

            Text("计数 / 快捷键").font(JadeFont.subhead).foregroundStyle(JadeColor.textSecondary)
            HStack(spacing: JadeSpace.x2.value) {
                JadePill("3", style: .primary)
                JadePill("99+", style: .danger)
                JadePill("⌥Space", style: .neutral)
            }

            Text("toolbar").font(JadeFont.subhead).foregroundStyle(JadeColor.textSecondary)
            HStack(spacing: JadeSpace.x2.value) {
                JadePill("复制", style: .primary, size: .toolbar)
                JadePill("保存", style: .success, size: .toolbar)
            }
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 340)
        .background(JadeColor.surface1)
    }
}

/// 简易换行布局(仅 Preview 用)。
private struct FlowRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: JadeSpace.x2.value) { content }
    }
}

#Preview("JadePill · Light") {
    JadePillGallery()
        .preferredColorScheme(.light)
}

#Preview("JadePill · Dark") {
    JadePillGallery()
        .preferredColorScheme(.dark)
}
