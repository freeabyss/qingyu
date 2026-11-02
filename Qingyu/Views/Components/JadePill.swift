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

        /// 胶囊文字色。
        ///
        /// 早先直接用系统语义色（systemGreen 等）作前景。问题：同一颜色以 15%
        /// 透明度铺成底后再用同色写字，文字与底几乎同亮——浅色模式实测
        /// success 1.92:1、warning 1.90:1、info 3.22:1、danger 2.83:1，全部读不清。
        /// 现改为「深一档、保留色相」的文字色：底仍取该文字色 15%，
        /// 因此色相一致，而文字在底上均 >= 4.5:1（实测 4.78–6.11:1）。
        var foreground: Color {
            switch self {
            case .neutral: return JadeColor.textSecondary
            case .primary: return JadeColor.pillInkPrimary
            case .info: return JadeColor.pillInkInfo
            case .success: return JadeColor.pillInkSuccess
            case .warning: return JadeColor.pillInkWarning
            case .danger: return JadeColor.pillInkDanger
            }
        }

        /// 胶囊填充透明度：文字色 15% 不透明铺底；因底色随 foreground 变化，
        /// 不能做成 JadeColor 固定色 token，故放在 Style 内。
        static let fillOpacity: Double = 0.15
        var fill: Color { foreground.opacity(Self.fillOpacity) }
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

    /// 常规胶囊纵向内边距：刻意取 2pt，低于 JadeSpace 最小档 x1=4，因常规胶囊高度紧凑；工具条变体仍用 x2。命名此例外，而非让它以裸数字出现。
    private static let regularVerticalPadding: CGFloat = 2

    private var vPadding: CGFloat {
        size == .toolbar ? JadeSpace.x2.value : Self.regularVerticalPadding
    }

    /// 内容足够短时用全 pill，否则用 sm 圆角。
    private var usesCapsule: Bool {
        size == .toolbar || text.count <= 2
    }

    public var body: some View {
        Text(text)
            .font(font.weight(.medium))
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
        .jadePadding(.x6)
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
