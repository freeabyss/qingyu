import AppKit
import SwiftUI

/// 命令栏几何契约：视图与 `CommandBarController` 必须共用同一组数值，
/// 否则窗口高度会与输入行高度漂移（空查询时面板高度就等于输入行高度）。
enum CommandBarMetrics {
    static let width: CGFloat = 760
    /// 输入行高度；空查询时面板高度就是这个值。
    static let inputRowHeight: CGFloat = 56
    /// 有关键词、显示结果时的面板高度。
    static let resultsHeight: CGFloat = 560
    /// 输入行顶边距屏幕可见区中心的高度。收起与展开共用同一锚点，
    /// 因此输入框在两种状态下都不移动，结果列表只在其下方展开。
    static let inputRowTopOffset: CGFloat = 336
    /// 面板与可见区边缘的最小间距，避免在小屏上越界。
    static let minimumScreenMargin: CGFloat = 8

    /// 面板原点 y（Cocoa 底边）：把输入行顶边固定在 `inputRowTopOffset` 上，
    /// 面板只向下生长。可见区装不下时整体收拢进可见区——此时输入框会略上移，
    /// 以免面板跑出屏幕。
    static func panelOriginY(visibleFrame: NSRect, panelHeight: CGFloat) -> CGFloat {
        let anchoredTop = visibleFrame.midY + inputRowTopOffset
        let cappedTop = min(anchoredTop, visibleFrame.maxY - minimumScreenMargin)
        return max(cappedTop - panelHeight, visibleFrame.minY + minimumScreenMargin)
    }
}

/// 命令栏：空查询时面板就是输入框本身；有关键词时是输入框 + 结果区。
/// 输入区与结果区之间只有一条细线：静止 1pt 描边，聚焦加厚为 2pt 强调色。
/// 窗口尺寸及动作由 `CommandBarController` / `SearchPanelViewModel` 管理。
struct CommandBarView: View {
    @ObservedObject var viewModel: SearchPanelViewModel
    @FocusState private var isInputFocused: Bool

    /// 结果列表行间距：2pt，仅用于结果行之间的分隔；行高 52pt 且行已有 lg 圆角背景，改用 Jade 最小 4pt 会拉开列表密度，不并入 JadeSpace。
    private static let resultsListSpacing: CGFloat = 2

    /// 加载指示器尺寸：20pt，仅用于输入框加载时 ProgressView 的宽高；不是布局间距，不并入 JadeSpace，也不与其它 20pt 尺寸合并。
    private static let loadingSpinnerSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            inputBar
                .frame(height: CommandBarMetrics.inputRowHeight)
                .jadePadding(.horizontal, .x3)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: CommandBarMetrics.width)
        // 填满面板并把内容钉在顶部：收起/展开动画中途面板高于内容时，
        // 根视图若只有内容高度就会被垂直居中，输入框会先滑到中间再弹回（闪一下），
        // 面板表面也会只覆盖一小块。填满后两者都稳定。
        .frame(maxHeight: .infinity, alignment: .top)
        .background(shortcutButtons)
        .background(
            KeyEventHandler(
                onUpArrow: { viewModel.moveUp() },
                onDownArrow: { viewModel.moveDown() },
                onReturn: { viewModel.confirmSelection() },
                onEscape: { viewModel.close() },
                onTab: { completeUniquePrefix() }
            )
            .allowsHitTesting(false)
        )
        .jadeWindowSurface(radius: .xxl)
        .jadeShadow(.xl, radius: .xxl)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isInputFocused = true
        }
        .jadeConfirmationDialog(
            LocalizedStringKey(viewModel.pendingDangerResult?.title ?? "commandBar.danger.confirmTitle"),
            isPresented: Binding(
                get: { viewModel.pendingDangerResult != nil },
                set: { if !$0 { viewModel.cancelPendingDanger() } }
            ),
            confirmTitle: "commandBar.danger.confirmTitle",
            cancelTitle: "commandBar.danger.cancel",
            message: "commandBar.danger.message",
            onConfirm: { viewModel.confirmPendingDanger() }
        )
        .toast(message: viewModel.toastMessage, isShowing: viewModel.showToast)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: JadeSpace.x2.value) {
            TextField(text: $viewModel.query) {
                Text(L10n.localized("commandBar.placeholder"))
            }
            .textFieldStyle(.plain)
            .font(JadeFont.commandBarInput)
            .foregroundStyle(JadeColor.textPrimary)
            .focused($isInputFocused)
            .onSubmit { viewModel.confirmSelection() }
            .accessibilityLabel(Text("commandBar.placeholder"))
            .accessibilityIdentifier("commandBar.searchField")

            // 输入框右侧的小转圈只在「已有结果、正在刷新」时出现。
            // 首次搜索还没有结果时，内容区已经显示了「搜索中…」，再放一个就是两个转圈同时转。
            if viewModel.isLoading, !viewModel.visibleResults.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Self.loadingSpinnerSize, height: Self.loadingSpinnerSize)
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.clearInput()
                    isInputFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(JadeFont.dismissIcon)
                        .foregroundStyle(JadeColor.textTertiary)
                }
                .buttonStyle(.plain)
                // PRD 控件表：图标按钮要同时有本地化辅助功能标签与悬停说明。
                .help(L10n.localized("a11y.commandBar.clear"))
                .accessibilityLabel(Text("a11y.commandBar.clear"))
            }
        }
        .jadePadding(.horizontal, .x2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if viewModel.hasQuery {
                inputHairline
            }
        }
        .jadeAnimation(.easeInOut(duration: 0.12), value: isInputFocused)
    }

    /// 输入区与结果区之间唯一的分隔与焦点反馈：静止 1pt 描边，聚焦加厚为 2pt 强调色。
    /// 空查询没有结果区，也就不绘制这条线。
    private var inputHairline: some View {
        Rectangle()
            .fill(isInputFocused ? JadeColor.focusBorder : JadeColor.border)
            .frame(height: isInputFocused ? 2 : 1)
    }

    // MARK: - Content

    /// 空查询时不渲染内容区，面板高度自然回落到输入行高度。
    @ViewBuilder
    private var content: some View {
        if viewModel.hasQuery {
            if viewModel.shouldShowNoResults {
                noResultsState
            } else if viewModel.isLoading && viewModel.visibleResults.isEmpty {
                // 慢查询（文件搜索会扫目录）期间，结果区原本是一片空白 + 右上角一个小转圈，
                // 用户看不出「还在搜」还是「搜坏了」。把状态放到用户正在看的地方。
                searchingState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Search results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Self.resultsListSpacing) {
                    ForEach(viewModel.visibleResults) { result in
                        CommandBarResultRow(
                            result: result,
                            isSelected: result.id == viewModel.selectedResult?.id,
                            isDangerous: viewModel.isDangerous(result),
                            onHide: viewModel.canHide(result)
                                ? { Task { await viewModel.hide(result) } }
                                : nil
                        )
                        .id(result.id)
                        .onTapGesture {
                            viewModel.select(result)
                            viewModel.trigger(result)
                        }
                    }

                    // 索引在后台建时，文件结果这一轮是缺席的（见 FileSearchSource）。
                    // 不说明的话，用户会以为「搜不到我的文件」；这里如实提示进度，
                    // 索引就绪后 SearchPanelViewModel 会自动重查，文件结果自己补上。
                    if viewModel.isIndexWarmingUp {
                        HStack(spacing: JadeSpace.x2.value) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.localized("commandBar.indexing"))
                                .font(JadeFont.caption)
                                .foregroundStyle(JadeColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jadePadding(.horizontal, .x3)
                        .jadePadding(.vertical, .x2)
                        .accessibilityIdentifier("commandBar.indexingHint")
                    }
                }
                .jadePadding(.horizontal, .x2)
                .jadePadding(.vertical, .x2)
                .accessibilityIdentifier("commandBar.resultList")
            }
            .onChange(of: viewModel.selectedIndex) { _ in
                if let selected = viewModel.selectedResult {
                    withAnimation(JadeAccessibility.animation(.easeInOut(duration: 0.12))) {
                        proxy.scrollTo(selected.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - No-results state (PRD §9.7)

    /// 搜索进行中、还没有任何结果的占位。
    private var searchingState: some View {
        VStack(spacing: JadeSpace.x2.value) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.localized("commandBar.searching"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commandBar.searching")
    }

    private var noResultsState: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "questionmark.circle")
                .font(JadeFont.commandBarNoResultsIcon)
                .foregroundStyle(JadeColor.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.localized("commandBar.noResults.title"))
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
            Text(L10n.localized("commandBar.noResults.subtitle"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jadePadding(.x6)
    }

    // MARK: - Keyboard shortcuts (⌘1-6 / ⌘K / ⌘C / ⌘,)

    private var shortcutButtons: some View {
        ZStack {
            ForEach(CommandBarSource.visibleCases) { source in
                Button("") { viewModel.selectSource(source) }
                    .keyboardShortcut(KeyEquivalent(Character("\(source.rawValue)")), modifiers: .command)
            }
            Button("") { viewModel.clearInput(); isInputFocused = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("") { viewModel.copyCurrentValue() }
                .keyboardShortcut("c", modifiers: .command)
            Button("") { viewModel.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        .jadeHiddenShortcut()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Tab 补全：当输入是当前结果标题的唯一前缀时补全为完整标题。
    private func completeUniquePrefix() {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prefixMatches = viewModel.visibleResults.filter {
            $0.title.lowercased().hasPrefix(trimmed.lowercased())
        }
        if prefixMatches.count == 1, let unique = prefixMatches.first {
            viewModel.query = unique.title
        }
    }
}

// MARK: - Result row

/// P-01 结果行（T-011）。图标 + 主/副标题；右侧仅危险提示，无装饰角标/品牌标。
struct CommandBarResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let isDangerous: Bool
    /// 可隐藏时提供「隐藏此结果」回调；nil 则不显示该按钮（例如预览/测试环境）。
    var onHide: (() -> Void)? = nil
    @State private var isHovering = false

    #if DEBUG
    /// 设计评审截图用：强制显示「隐藏此结果」按钮。
    /// 悬停需要真实鼠标指针，离屏渲染截不到；置 true 后可静态检查它的位置与样式。
    static var debugForceHover = false
    #endif

    /// 结果行图标磁贴边长：32pt 正方形，应用图标与系统符号磁贴共用同一尺寸；不并入 JadeSpace（那是间距档位，不是磁贴尺寸）。
    private static let iconTileSize: CGFloat = 32

    /// 结果行高度：52pt，仅用于 CommandBarResultRow 整行；与图标磁贴 32pt 角色不同，不合并。
    private static let rowHeight: CGFloat = 52

    /// 主/副标题配对间隙：1pt，仅用于标题与副标题的紧凑配对；是行内文本间隙，不是通用间距档位，不并入 JadeSpace。
    private static let titleSubtitleSpacing: CGFloat = 1

    /// 实际生效的悬停态：DEBUG 截图时可被强制打开，其余情况等同 isHovering。
    private var effectiveHovering: Bool {
        #if DEBUG
        if Self.debugForceHover { return true }
        #endif
        return isHovering
    }

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            iconTile

            VStack(alignment: .leading, spacing: Self.titleSubtitleSpacing) {
                Text(result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? L10n.localized("searchPanel.type.unknown")
                     : result.title)
                    .font(JadeFont.headline)
                    .foregroundStyle(JadeColor.textPrimary)
                    .lineLimit(1)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(JadeFont.subhead)
                        .foregroundStyle(JadeColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: JadeSpace.x3.value)

            // 悬停时在类型标签左侧露出「隐藏此结果」按钮——
            // 普通用户不必去设置里手填稳定 ID，直接从结果上屏蔽（PRD FR-SEARCH-8i）。
            if effectiveHovering, let onHide {
                Button(action: onHide) {
                    Image(systemName: "eye.slash")
                        // 图标比类型标签略大：它是可点操作，不是标注，
                        // 用 caption 会小得像装饰、点不到的感觉。
                        .font(JadeFont.subhead)
                        // 需压在选中行的 primaryFill 浅蓝底上仍清晰；
                        // textSecondary 在该底色上只有 4.07:1，用 typeLabel 令牌（4.64:1）。
                        .foregroundStyle(JadeColor.typeLabel)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.localized("commandBar.hideResult"))
                .accessibilityLabel(Text(L10n.localized("commandBar.hideResult")))
                // 与右侧类型标签留出呼吸：两者靠太近会读成「eye.slash 应用」一组。
                .padding(.trailing, JadeSpace.x2.value)
            }

            // 结果类型：应用 / 文件 / 命令 / 网页搜索……混排时只靠图标很难分辨，
            // 副标题里应用和文件都是路径，读起来几乎一样。类型标签给的是「这是什么」，
            // 比路径末尾几个字符更有用。
            Text(result.typeLabel)
                .font(JadeFont.caption)
                // 专用令牌：需压在选中行的 primaryFill 浅蓝底上仍 >= 4.5:1，
                // 用 textTertiary 会掉到 4.07:1。
                .foregroundStyle(JadeColor.typeLabel)
                .lineLimit(1)
                .layoutPriority(-1)

            if isDangerous {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(JadeFont.smallIconSemibold)
                    .foregroundStyle(JadeColor.warningText)
                    .accessibilityHidden(true)
            }

            // PRD §02-ui-spec：「只有选中行展示回车提示」。
            // 选中行是焦点所在，也是最可能被立刻执行的一行——给出 ⏎ 让
            // 「按回车会发生什么」无需猜测。未选中行不展示，避免整列表噪音。
            if isSelected {
                Text(L10n.localized("commandBar.enter"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.typeLabel)
                    .jadePadding(.horizontal, .x1)
                    // 纵向 1pt 是徽标内边距、不是间距档位（x1=4 会让它显得臃肿）。
                    .padding(.vertical, 1)
                    .background(JadeColor.surface1.opacity(0.9), in: JadeRadius.sm.shape)
                    .overlay(
                        JadeRadius.sm.shape.strokeBorder(JadeColor.border, lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }

        }
        .jadePadding(.horizontal, .x3)
        .frame(height: Self.rowHeight)
        .background(
            isSelected ? JadeColor.primaryFill : (effectiveHovering ? JadeColor.surface2 : Color.clear),
            in: JadeRadius.lg.shape
        )
        .overlay(
            JadeRadius.lg.shape
                .strokeBorder(isSelected ? JadeColor.resultSelectionBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .jadeAnimation(.easeInOut(duration: 0.12), value: isHovering)
        // VoiceOver：把整行合并成单个可读元素——标题 + 副标题 + 类型，
        // 选中/危险状态通过 value/hint 补充（PRD §9.8）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(isSelected
            ? L10n.localized("a11y.state.selected")
            : ""))
        .accessibilityHint(Text(isDangerous
            ? L10n.localized("a11y.commandBar.dangerHint")
            : L10n.localized("a11y.commandBar.activateHint")))
        .accessibilityAddTraits(.isButton)
    }

    /// 拼出 "标题, 副标题, 类型" 的可读串（副标题可空)。
    private var accessibilityLabelText: String {
        var parts: [String] = [result.title]
        if let subtitle = result.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append(result.typeLabel)
        return parts.joined(separator: ", ")
    }

    // 应用结果保留真实图标；系统命令使用中性图标底，避免结果行被类型色占据。
    @ViewBuilder
    private var iconTile: some View {
        switch result.icon {
        case .appIcon(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconTileSize, height: Self.iconTileSize)
        case .systemSymbol(let name):
            symbolTile(name)
        case .thumbnail, .none:
            symbolTile("sparkles")
        }
    }

    private func symbolTile(_ name: String) -> some View {
        ZStack {
            JadeRadius.md.shape
                .fill(isSelected ? JadeColor.primaryFill : JadeColor.surface2)
            Image(systemName: name)
                .font(JadeFont.resultTileIcon)
                .foregroundStyle(isSelected ? JadeColor.primary : JadeColor.textSecondary)
        }
        .frame(width: Self.iconTileSize, height: Self.iconTileSize)
    }
}

#Preview {
    CommandBarView(viewModel: SearchPanelViewModel(searchService: SearchService(sources: [])))
        .frame(height: 420)
        .padding(40)
        .background(LinearGradient(colors: [.teal, .blue], startPoint: .top, endPoint: .bottom))
}
