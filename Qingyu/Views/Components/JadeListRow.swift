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
    /// 是否常驻显示。false 表示按需显示（悬停/聚焦时才可见）。
    ///
    /// PRD：「复制为主要行内动作；预览和删除按需显示」——删除这类不可逆操作
    /// 常驻在每一行上既是视觉噪音，也容易被误点。
    public let showsAlways: Bool

    public init(systemImage: String,
                label: LocalizedStringKey,
                isDestructive: Bool = false,
                showsAlways: Bool = true,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isDestructive = isDestructive
        self.showsAlways = showsAlways
        self.action = action
    }
}

/// 行操作图标的样式规则。
///
/// 抽成与视图状态解耦的纯函数，是为了让 hover 分支能被单测覆盖——
/// 离屏渲染模拟不了 hover，只靠肉眼看快照等于没验证。
public enum JadeRowActionStyle {

    /// 磁贴底色：静止态透明，hover 时才浮现，作为「这里可以点」的反馈。
    ///
    /// 常驻底色会把列表画成工具栏：一行 4–6 个方块的总面积盖过标题。
    public static func tileBackground(isHovering: Bool) -> Color {
        isHovering ? JadeGlass.controlHover : .clear
    }

    /// 图标颜色：危险操作静止态也用普通文字色，hover 整行时才转红。
    ///
    /// 常驻红色会在每行留下一条红杠，把注意力从内容拉走。
    public static func iconColor(isDestructive: Bool, isHovering: Bool) -> Color {
        if isDestructive, isHovering { return JadeColor.danger }
        return JadeColor.textSecondary
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
    /// 全键盘访问（Full Keyboard Access）下，焦点可以直接落到行内的图标按钮上。
    /// 此时若仍按「按需」隐藏，用户聚焦的是一个看不见的按钮——所以也纳入露出条件。
    @FocusState private var focusedActionID: UUID?

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
        if selected { return JadeGlass.rowSelected }
        if isHovering { return JadeGlass.rowHover }
        return .clear
    }

    private var showsActions: Bool {
        alwaysShowsActions || isHovering || isFocused
    }

    /// 「按需显示」的动作（删除等）只在悬停或聚焦时露出。
    /// 不能复用 showsActions——它含 alwaysShowsActions，会让按需条件恒真。
    private var revealsOnDemand: Bool {
        #if DEBUG
        if Self.debugForceRevealsOnDemand { return true }
        #endif
        return isHovering || isFocused || focusedActionID != nil
    }

    #if DEBUG
    /// 设计评审用：强制「按需动作」露出。离屏截图拿不到真实鼠标悬停，
    /// 没有这条通道就无法证明「删除按钮在悬停时确实会出现」。
    /// 泛型类型不能有 static 存储属性，用计算属性转存到文件级变量。
    static var debugForceRevealsOnDemand: Bool {
        get { jadeListRowDebugForceReveals }
        set { jadeListRowDebugForceReveals = newValue }
    }
    #endif

    public var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            // 常驻动作的行：整组动作**始终参与布局**，只是按需的按钮用透明度隐藏。
            // 否则悬停时多出几个图标会把标题行横向挤开（行内重排比隐藏更难接受）。
            if !actions.isEmpty, alwaysShowsActions || revealsOnDemand {
                HStack(spacing: JadeSpace.x1.value) {
                    ForEach(actions) { action in
                        let isVisible = action.showsAlways || revealsOnDemand
                        Button {
                            action.action()
                        } label: {
                            Image(systemName: action.systemImage)
                                .font(JadeFont.body)
                                .foregroundStyle(JadeRowActionStyle.iconColor(
                                    isDestructive: action.isDestructive,
                                    isHovering: isHovering
                                ))
                                .frame(width: Self.actionHitSize, height: Self.actionHitSize)
                                .background(JadeRowActionStyle.tileBackground(isHovering: isHovering))
                                .jadeRadius(.sm)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedActionID, equals: action.id)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                        // PRD 控件表：图标按钮要同时有本地化辅助功能标签与悬停说明。
                        .help(Text(action.label))
                        .accessibilityLabel(Text(action.label))
                        // 视觉上按需露出，但**不**从无障碍树里移除：
                        // 读屏用户不产生鼠标悬停，移除后「删除」就永远不可达。
                        // 保留在树里，VoiceOver 仍能逐项聚焦到这些操作。
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
            // 选中与键盘焦点共用同一圈描边，但粗细区分：
            // 焦点比选中更粗，让纯键盘用户能看出「当前落在哪一行」——
            // 此前 isFocused 只用来显示操作按钮，行本身没有任何焦点视觉反馈。
            if selected {
                JadeRadius.lg.shape.strokeBorder(JadeColor.rowSelectionBorder, lineWidth: isFocused ? 2 : 1)
            } else if isFocused {
                JadeRadius.lg.shape.strokeBorder(JadeColor.focusBorder, lineWidth: 2)
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
        .background(JadeGlass.tint)
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

#if DEBUG
/// `JadeListRow` 是泛型类型，无法持有 static 存储属性；强制露出开关存在这里。
var jadeListRowDebugForceReveals = false
#endif
