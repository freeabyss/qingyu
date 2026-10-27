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
/// - 选中态：浅底 + 品牌色描边（仅浅底对比度约 1.1-1.3，不足以辨识选中）。
/// - 操作：始终显示，或 hover / 键盘焦点时浮现（避免仅 hover 可见对键盘用户不可达）。
/// - 行高由 `rowSize` 决定（44 / 64）。
///
/// 全部尺寸 / 颜色 / 圆角走 Jade token，禁止硬编码。
public struct JadeListRow<Content: View>: View {

    private let selected: Bool
    private let rowSize: JadeRowSize
    private let actions: [JadeRowAction]
    private let alwaysShowsActions: Bool
    private let content: Content

    static var actionHitSize: CGFloat { 32 } // 泛型类型不支持 static 存储属性，改用计算属性，API 不变
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

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
        alwaysShowsActions || isHovering || isFocused
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
                                .frame(width: Self.actionHitSize, height: Self.actionHitSize)
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
        .jadePadding(.horizontal, .x3)
        .frame(height: rowSize.height)
        .background(backgroundColor)
        .jadeRadius(.lg)
        .overlay {
            if selected {
                JadeRadius.lg.shape.strokeBorder(JadeColor.rowSelectionBorder, lineWidth: 1)
            }
        }
        .contentShape(JadeRadius.lg.shape)
        .focusable()
        .focused($isFocused) // onFocusChange 在本 SDK 的 View 上不存在，改用 FocusState（macOS 12+）
        .onHover { hovering in isHovering = hovering }
        .jadeAnimation(.easeInOut(duration: 0.12), value: isHovering)
        .jadeAnimation(.easeInOut(duration: 0.12), value: selected)
        .jadeAnimation(.easeInOut(duration: 0.12), value: isFocused)
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
        .jadePadding(.x3)
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
