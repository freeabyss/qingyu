import SwiftUI

/// 列表行右侧 hover 出现的图标操作。契约来源：PRD §9.5 通用组件规范。
public struct JadeRowAction: Identifiable {
    public let id = UUID()
    /// SF Symbol 名称
    public let systemImage: String
    /// 无障碍标签
    public let label: LocalizedStringKey
    /// 点击回调
    public let action: () -> Void
    /// 是否为危险操作(红色前景)
    public let isDestructive: Bool

    public init(systemImage: String,
                label: LocalizedStringKey,
                isDestructive: Bool = false,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// 行高规格。
public enum JadeRowSize {
    /// 紧凑：44pt
    case compact
    /// 舒适：64pt
    case comfortable

    var height: CGFloat {
        switch self {
        case .compact: return 44
        case .comfortable: return 64
        }
    }
}

/// 统一列表行。契约来源：PRD §9.5 通用组件规范。
///
/// - 选中态：`JadeColor.primaryFill` 底 + `JadeRadius.lg` 圆角。
/// - 操作：`alwaysShowsActions` 为 true 时始终显示右侧 actions；否则 hover 浮现。
/// - 行高由 `rowSize` 决定（44 / 64）。
///
/// 全部尺寸 / 颜色 / 圆角走 Jade token，禁止硬编码。
public struct JadeListRow<Content: View>: View {

    private let selected: Bool
    private let rowSize: JadeRowSize
    private let actions: [JadeRowAction]
    private let alwaysShowsActions: Bool
    private let content: Content

    @State private var isHovering = false

    public init(selected: Bool = false,
                rowSize: JadeRowSize = .comfortable,
                actions: [JadeRowAction] = [],
                alwaysShowsActions: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.rowSize = rowSize
        self.actions = actions
        self.alwaysShowsActions = alwaysShowsActions
        self.content = content()
    }

    private var backgroundColor: Color {
        if selected { return JadeColor.primaryFill }
        if isHovering { return JadeColor.surface2 }
        return .clear
    }

    private var showsActions: Bool {
        alwaysShowsActions || isHovering
    }

    public var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsActions, !actions.isEmpty {
                HStack(spacing: JadeSpace.x1.value) {
                    ForEach(actions) { action in
                        Button {
                            action.action()
                        } label: {
                            Image(systemName: action.systemImage)
                                .font(JadeFont.body)
                                .foregroundStyle(action.isDestructive ? JadeColor.danger : JadeColor.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(JadeColor.surface3)
                                .jadeRadius(.sm)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(action.label))
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, JadeSpace.x3.value)
        .frame(height: rowSize.height)
        .background(backgroundColor)
        .jadeRadius(.lg)
        .contentShape(JadeRadius.lg.shape)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}

// MARK: - Preview

private struct JadeListRowGallery: View {
    private var demoActions: [JadeRowAction] {
        [
            JadeRowAction(systemImage: "doc.on.doc", label: "copy") {},
            JadeRowAction(systemImage: "trash", label: "delete", isDestructive: true) {}
        ]
    }

    private func rowContent(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(JadeFont.body).foregroundStyle(JadeColor.textPrimary)
            Text(subtitle).font(JadeFont.caption).foregroundStyle(JadeColor.textSecondary)
        }
    }

    var body: some View {
        VStack(spacing: JadeSpace.x1.value) {
            JadeListRow(selected: true, rowSize: .comfortable, actions: demoActions) {
                rowContent("选中 · 舒适 64", "primaryFill 底 + lg 圆角")
            }
            JadeListRow(rowSize: .comfortable, actions: demoActions) {
                rowContent("普通 · 舒适 64", "hover 出现右侧操作")
            }
            JadeListRow(rowSize: .compact, actions: demoActions) {
                Text("紧凑 · 44").font(JadeFont.body).foregroundStyle(JadeColor.textPrimary)
            }
        }
        .padding(JadeSpace.x3.value)
        .frame(width: 340)
        .background(JadeColor.surface1)
    }
}

#Preview("JadeListRow · Light") {
    JadeListRowGallery()
        .preferredColorScheme(.light)
}

#Preview("JadeListRow · Dark") {
    JadeListRowGallery()
        .preferredColorScheme(.dark)
}
