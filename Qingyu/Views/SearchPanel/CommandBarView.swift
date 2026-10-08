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

    var body: some View {
        VStack(spacing: 0) {
            inputBar
                .frame(height: CommandBarMetrics.inputRowHeight)
                .padding(.horizontal, JadeSpace.x3.value)

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

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.clearInput()
                    isInputFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(JadeColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("a11y.commandBar.clear"))
            }
        }
        .padding(.horizontal, JadeSpace.x2.value)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if viewModel.hasQuery {
                inputHairline
            }
        }
        .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: isInputFocused)
    }

    /// 输入区与结果区之间唯一的分隔与焦点反馈：静止 1pt 描边，聚焦加厚为 2pt 强调色。
    /// 空查询没有结果区，也就不绘制这条线。
    private var inputHairline: some View {
        Rectangle()
            .fill(isInputFocused ? JadeColor.primary.opacity(0.65) : JadeColor.border)
            .frame(height: isInputFocused ? 2 : 1)
    }

    // MARK: - Content

    /// 空查询时不渲染内容区，面板高度自然回落到输入行高度。
    @ViewBuilder
    private var content: some View {
        if viewModel.hasQuery {
            if viewModel.shouldShowNoResults {
                noResultsState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Search results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.visibleResults) { result in
                        CommandBarResultRow(
                            result: result,
                            isSelected: result.id == viewModel.selectedResult?.id,
                            isDangerous: viewModel.isDangerous(result)
                        )
                        .id(result.id)
                        .onTapGesture {
                            viewModel.select(result)
                            viewModel.trigger(result)
                        }
                    }
                }
                .padding(.horizontal, JadeSpace.x2.value)
                .padding(.vertical, JadeSpace.x2.value)
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

    private var noResultsState: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30))
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
        .padding(JadeSpace.x6.value)
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
        .opacity(0)
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            iconTile

            VStack(alignment: .leading, spacing: 1) {
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

            if isDangerous {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(JadeColor.warning)
                    .accessibilityHidden(true)
            }

        }
        .padding(.horizontal, JadeSpace.x3.value)
        .frame(height: 52)
        .background(
            isSelected ? JadeColor.primaryFill : (isHovering ? JadeColor.surface2 : Color.clear),
            in: JadeRadius.lg.shape
        )
        .overlay(
            JadeRadius.lg.shape
                .strokeBorder(isSelected ? JadeColor.primary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: isHovering)
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
                .frame(width: 32, height: 32)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? JadeColor.primary : JadeColor.textSecondary)
        }
        .frame(width: 32, height: 32)
    }
}

#Preview {
    CommandBarView(viewModel: SearchPanelViewModel(searchService: SearchService(sources: [])))
        .frame(height: 420)
        .padding(40)
        .background(LinearGradient(colors: [.teal, .blue], startPoint: .top, endPoint: .bottom))
}
