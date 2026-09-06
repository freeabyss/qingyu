import AppKit
import SwiftUI

/// P-01 命令栏根视图（T-011）。
///
/// 契约来源：PRD §9.4 P-01、FR-UI-COMMAND-BAR、§9.6 快捷键、§9.7 空态；
/// architecture/design.md §3.2（Search 模块）。
///
/// - 760 宽、动态高（外层 `CommandBarController` 控制窗口高度）。
/// - 顶部 56px 输入框（jade 放大镜 + 20pt 输入 + 清空）。
/// - 空查询：最近使用 + 收藏两个 section（各最多 5 条）。
/// - 有查询：结果列表（最多 12 条，⌘1-6 过滤），计算器/换算结果固定首行高亮。
/// - 底部 44px hint bar。
/// - 危险命令 ⏎ 触发 `JadeConfirmationDialog` 二次确认。
///
/// 所有颜色 / 字号 / 圆角 / 间距走 Jade token；用户可见字符串走 xcstrings。
struct CommandBarView: View {
    @ObservedObject var viewModel: SearchPanelViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
                .frame(height: 56)
                .padding(.horizontal, JadeSpace.x4.value)
                .padding(.vertical, JadeSpace.x2.value)

            Divider().overlay(JadeColor.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(JadeColor.border)

            hintBar
                .frame(height: 44)
        }
        .frame(width: 760)
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
        .jadeMaterial(.commandBar, radius: .xxl)
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
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isInputFocused ? JadeColor.primary : JadeColor.textSecondary)
                .accessibilityHidden(true)

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
        .padding(.horizontal, JadeSpace.x3.value)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(JadeColor.surface2, in: JadeRadius.lg.shape)
        .overlay(
            JadeRadius.lg.shape
                .strokeBorder(isInputFocused ? JadeColor.primary.opacity(0.65) : JadeColor.border,
                              lineWidth: isInputFocused ? 1.5 : 1)
        )
        .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: isInputFocused)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.hasQuery {
            if viewModel.visibleResults.isEmpty && !viewModel.isLoading {
                noResultsState
            } else {
                resultsList
            }
        } else {
            homeState
        }
    }

    // MARK: - Search results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: JadeSpace.x1.value) {
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

    // MARK: - Home (empty query)

    @ViewBuilder
    private var homeState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
                homeSection(titleKey: "commandBar.section.quickActions", results: viewModel.homeQuickActions)
                if !viewModel.recentResults.isEmpty {
                    homeSection(titleKey: "commandBar.section.recent", results: viewModel.recentResults)
                }
                if !viewModel.favoriteResults.isEmpty {
                    homeSection(titleKey: "commandBar.section.favorites", results: viewModel.favoriteResults)
                }
            }
            .padding(.horizontal, JadeSpace.x2.value)
            .padding(.vertical, JadeSpace.x3.value)
        }
    }

    private func homeSection(titleKey: String, results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
            HStack(spacing: JadeSpace.x2.value) {
                Capsule()
                    .fill(JadeColor.primary)
                    .frame(width: 3, height: 14)
                Text(L10n.localized(titleKey))
                    .font(JadeFont.subhead)
                    .fontWeight(.semibold)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            .padding(.horizontal, JadeSpace.x3.value)
            .padding(.top, JadeSpace.x1.value)

            ForEach(results) { result in
                CommandBarResultRow(
                    result: result,
                    isSelected: false,
                    isDangerous: viewModel.isDangerous(result)
                )
                .onTapGesture { viewModel.trigger(result) }
            }
        }
    }

    private var homeEmptyState: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(JadeColor.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.localized("commandBar.placeholder"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(JadeSpace.x6.value)
    }

    // MARK: - No-results state (PRD §9.7)

    private var noResultsState: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "magnifyingglass")
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

    // MARK: - Hint bar

    private var hintBar: some View {
        Text(L10n.localized("commandBar.hint"))
            .font(JadeFont.caption)
            .foregroundStyle(JadeColor.textTertiary)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: - Keyboard shortcuts (⌘1-6 / ⌘K / ⌘C / ⌘,)

    private var shortcutButtons: some View {
        ZStack {
            ForEach(CommandBarSource.allCases) { source in
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

/// P-01 结果行（T-011）。44px 高、32×32 类型图标、主/副标题、右侧 type badge + ⏎。
struct CommandBarResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let isDangerous: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            iconTile

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(JadeFont.title3)
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

            typeBadge
                .accessibilityHidden(true)

            Text(L10n.localized("commandBar.enter"))
                .font(JadeFont.caption)
                .foregroundStyle(isSelected ? JadeColor.primary : JadeColor.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, JadeSpace.x3.value)
        .frame(height: 44)
        .background(
            isSelected ? JadeColor.primaryFill : (isHovering ? JadeColor.surface2 : Color.clear),
            in: JadeRadius.lg.shape
        )
        .overlay(
            JadeRadius.lg.shape
                .strokeBorder(isSelected ? JadeColor.primary.opacity(0.25) : Color.clear, lineWidth: 1)
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

    // 类型 badge：前景类型色 + 15% 底（PRD §9.2.9），走 Jade token。
    private var typeBadge: some View {
        Text(result.typeLabel)
            .font(JadeFont.caption)
            .fontWeight(.medium)
            .foregroundStyle(typeColor)
            .padding(.horizontal, JadeSpace.x2.value)
            .padding(.vertical, 2)
            .background(typeColor.opacity(0.15), in: JadeRadius.sm.shape)
    }

    // 32×32 类型图标底（PRD §9.2.9：类型底色 15% + 前景同色）。
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
                .fill(typeColor.opacity(0.15))
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? JadeColor.primary : typeColor)
        }
        .frame(width: 32, height: 32)
    }

    // PRD §9.2.9 类型配色：app blue / command purple / calculator jade /
    // convert pink / settings indigo / clipboard orange / file green。
    private var typeColor: Color {
        switch result.sourceID {
        case .app: return JadeColor.blue
        case .command: return JadeColor.purple
        case .calculator:
            return result.typeLabel == L10n.localized("searchPanel.type.convert") ? JadeColor.pink : JadeColor.primary
        case .settings: return JadeColor.indigo
        case .clipboard: return JadeColor.orange
        case .file: return JadeColor.green
        default: return JadeColor.gray
        }
    }
}

#Preview {
    CommandBarView(viewModel: SearchPanelViewModel(searchService: SearchService(sources: [])))
        .frame(height: 420)
        .padding(40)
        .background(LinearGradient(colors: [.teal, .blue], startPoint: .top, endPoint: .bottom))
}
