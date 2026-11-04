import AppKit
import SwiftUI

/// Qingyu clipboard history window (PRD P-02).
///
/// Borderless chrome: full-width search + chips on top; **list on the left,
/// detail on the right**. List rows show pin / favorite / copy / delete icons always.
/// Keyboard: ⌘F focus search, ↑↓ / jk move, ⏎ / ⌘C copy & close, ⌫ delete.
struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    /// Invoked when an item is copied via ⏎ / click — closes the window.
    var onCopyAndClose: () -> Void = {}
    /// Invoked by ⎋ — closes the window without copying (PRD §9.7「关闭窗口且保留应用运行」).
    var onClose: () -> Void = {}
    /// 出现时是否自动读取历史。生产环境恒为 true。
    ///
    /// 设计快照测试传 false：离屏渲染同样会触发 `.task`，于是每次渲染都重新进入加载态，
    /// 「已加载完成且为空」的确定状态就渲染不出来（快照只能停在 Loading）。
    var autoLoadsOnAppear: Bool = true

    /// Fixed detail-pane width (independent of content size).
    private static let detailPaneWidth: CGFloat = 360

    /// 状态栏高度：36pt，仅用于剪贴板历史窗口底部的状态栏；只定高，宽度随窗口而定，不并入 JadeSpace，那是间距档位，不是状态栏高度。
    private static let statusBarHeight: CGFloat = 36


    /// 搜索栏最小高度：40pt，仅用于剪贴板历史顶部的搜索输入框；宽度撑满，只保底高度，不并入 JadeSpace，那是间距档位，不是控件高度。
    private static let searchInputMinHeight: CGFloat = 40

    /// 窗口最小宽度：860pt，等于窗口打开时的默认宽度（见 ClipboardHistoryWindowController 的 contentRect），仅用于剪贴板历史窗口的最小尺寸约束，与最小高度成组出现；不并入 JadeSpace，那是间距档位，不是窗口尺寸。720pt 时文件行 6 个操作占 212pt，标题只剩约 43pt，缩到打开尺寸以下即不可读，故下限定为打开尺寸。
    private static let windowMinWidth: CGFloat = 860

    /// 窗口最小高度：420pt，仅用于剪贴板历史窗口的最小尺寸约束，与最小宽度成组出现；不并入 JadeSpace，那是间距档位，不是窗口尺寸。
    private static let windowMinHeight: CGFloat = 420

    /// 隐藏快捷键按钮尺寸：0pt，仅用于只承载键盘快捷键、不占布局空间的不可见按钮；不是视觉尺寸，不并入 JadeSpace，那是间距档位，不是按钮尺寸。
    private static let hiddenShortcutSize: CGFloat = 0

    @FocusState private var searchFocused: Bool

    /// Primary type filters shown as compact chips (全部 / 文本 / 图片 / 文件).
    private let primaryFilters: [ClipboardListViewModel.SidebarSelection] = [
        .all, .text, .image, .file
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 剪贴板关闭时，搜索与筛选没有任何可作用的对象；
            // 保持可交互会让用户输入后才意识到「这里什么都搜不到」。
            header
                .disabled(!viewModel.clipboardEnabled)
                .jadePadding(.horizontal, .x4)
                .jadePadding(.top, .x3)
                .jadePadding(.bottom, .x2)

            Divider().overlay(JadeColor.border)

            // 暂停说明条：紧贴工具栏下方，属于「当前状态」而非内容，不放进列表。
            if viewModel.clipboardEnabled, viewModel.isRecordingPaused {
                pausedBanner
                    .jadePadding(.horizontal, .x4)
                    .jadePadding(.vertical, .x2)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(JadeColor.border)

            statusBar
                .frame(height: Self.statusBarHeight)
                .jadePadding(.horizontal, .x4)
        }
        .frame(minWidth: Self.windowMinWidth, minHeight: Self.windowMinHeight)
        .jadeWindowSurface(radius: .xxl)
        .jadeShadow(.xl, radius: .xxl)
        .tint(JadeColor.primary)
        .task {
            guard autoLoadsOnAppear else { return }
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusClipboardSearchField)) { _ in
            searchFocused = true
        }
        .background(keyboardShortcuts)
        .background(navigationKeys)
        .jadeConfirmationDialog(
            "clipboard.clearAll.title",
            isPresented: $viewModel.showClearAllConfirmation,
            confirmTitle: "clipboard.clearAll.action",
            cancelTitle: "settings.alert.cancel",
            message: "clipboard.clearAll.message"
        ) {
            Task { await viewModel.clearAllConfirmed() }
        }
        // 底部要让出状态栏高度：toast 默认距窗口底 32pt，而状态栏高 36pt，
        // 不额外内缩就会压在状态栏和分隔线上。
        .jadeToast(
            viewModel.toastMessage,
            isShowing: $viewModel.showToast,
            variant: viewModel.toastVariant,
            bottomInset: Self.statusBarHeight
        )
    }

    // MARK: - Full-width search + chips

    private var header: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            searchInput
            filterTabs
        }
    }

    private var searchInput: some View {
        HStack(spacing: JadeSpace.x2.value) {
            TextField("clipboard.search.placeholder", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(JadeFont.searchField)
                .foregroundStyle(JadeColor.textPrimary)
                .focused($searchFocused)
                .accessibilityIdentifier("clipboard.searchField")

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(JadeFont.dismissIcon)
                        .foregroundStyle(JadeColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("a11y.commandBar.clear"))
            }
        }
        .jadePadding(.horizontal, .x3)
        .frame(maxWidth: .infinity, minHeight: Self.searchInputMinHeight)
        .background(JadeColor.surface2, in: JadeRadius.lg.shape)
        .overlay(
            JadeRadius.lg.shape
                .strokeBorder(
                    searchFocused ? JadeColor.focusBorder : JadeColor.border,
                    lineWidth: searchFocused ? 1.5 : 1
                )
        )
        .contentShape(JadeRadius.lg.shape)
        .onTapGesture { searchFocused = true }
        .jadeAnimation(.easeInOut(duration: 0.12), value: searchFocused)
    }

    private var filterTabs: some View {
        HStack(spacing: JadeSpace.x3.value) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JadeSpace.x4.value) {
                    ForEach(primaryFilters) { filter in
                        filterChip(filter)
                    }
                }
            }

            Spacer(minLength: 0)

            // 暂停/恢复记录：PRD §02-ui-spec 剪贴板工具栏要求。
            // 与「设置里关掉剪贴板」不同——那是禁用功能；这里只是先别记新的，
            // 已有记录照常可查可复制，适合「接下来要复制密码」这类临时场景。
            if viewModel.canToggleRecording {
                Button {
                    viewModel.toggleRecordingPause()
                } label: {
                    Label(
                        L10n.localized(viewModel.isRecordingPaused
                                       ? "clipboard.recording.resume"
                                       : "clipboard.recording.pause"),
                        systemImage: viewModel.isRecordingPaused ? "play.fill" : "pause.fill"
                    )
                    .font(JadeFont.caption.weight(.medium))
                    .foregroundStyle(viewModel.isRecordingPaused ? JadeColor.primary : JadeColor.textSecondary)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("clipboard.recording.toggle")
            }
        }
    }

    /// 暂停中的说明条：明确「新内容不会记录」，并给出恢复入口。
    /// PRD 状态表要求「说明当前功能已暂停并提供恢复按钮」。
    @ViewBuilder
    private var pausedBanner: some View {
        if viewModel.isRecordingPaused, viewModel.clipboardEnabled {
            HStack(spacing: JadeSpace.x2.value) {
                Image(systemName: "pause.circle.fill")
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.warningText)
                    .accessibilityHidden(true)
                Text(L10n.localized("clipboard.recording.pausedHint"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
                Spacer(minLength: 0)
                // 恢复入口只保留工具栏那一个：
                // 横幅再放一个「恢复」会和工具栏的重复，同一屏两个同样按钮反而让人犹豫。
            }
            .jadePadding(.horizontal, .x3)
            .jadePadding(.vertical, .x2)
            .background(JadeColor.surface2, in: JadeRadius.md.shape)
        }
    }

    private func filterChip(_ filter: ClipboardListViewModel.SidebarSelection) -> some View {
        let isSelected = viewModel.selection == filter
        return Button {
            viewModel.selection = filter
        } label: {
            Text(filter.title)
                .font(JadeFont.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? JadeColor.primary : JadeColor.textSecondary)
                .jadePadding(.horizontal, .x2)
                .jadePadding(.vertical, .x1)
                .background(isSelected ? JadeColor.primaryFill : Color.clear, in: JadeRadius.md.shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clipboard.filterChip.\(filter.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Side-by-side: list (left) + detail (right)

    @ViewBuilder
    private var content: some View {
        if !viewModel.clipboardEnabled {
            disabledState
        } else if viewModel.items.isEmpty && viewModel.isLoading {
            loadingState
        } else if viewModel.items.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                list
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(JadeColor.border)

                ClipboardDetailPane(
                    item: viewModel.selectedItem,
                    imageProvider: { await viewModel.originalImageData(for: $0) },
                    richTextProvider: { await viewModel.richTextAttributed(for: $0) },
                    fileImageProvider: { await viewModel.fileImageData(for: $0) },
                    onCopy: { target in
                        viewModel.select(target)
                        Task {
                            await viewModel.copyToPasteboard(target)
                            onCopyAndClose()
                        }
                    }
                )
                .frame(width: Self.detailPaneWidth)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: JadeSpace.x1.value) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index)
                            .id(item.id)
                    }
                }
                .jadePadding(.horizontal, .x3)
                .jadePadding(.vertical, .x2)
            }
            .background(JadeColor.surface1)
            .onChange(of: viewModel.selectedIndex) { _ in
                guard let selected = viewModel.selectedItem else { return }
                withAnimation(JadeAccessibility.animation(.easeInOut(duration: 0.12))) {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
    }

    private func row(_ item: ClipboardRecordSnapshot, index: Int) -> some View {
        JadeClipboardRow(
            item: item,
            selected: index == viewModel.selectedIndex,
            thumbnailProvider: { await viewModel.thumbnailData(for: $0) },
            onPin: { Task { await viewModel.togglePin(item) } },
            onFavorite: { Task { await viewModel.toggleFavorite(item) } },
            onCopy: {
                viewModel.select(item)
                Task {
                    await viewModel.copyToPasteboard(item)
                    onCopyAndClose()
                }
            },
            onDelete: { Task { await viewModel.delete(item) } },
            onRevealInFinder: { viewModel.revealInFinder(item) },
            onCopyPath: { Task { await viewModel.copyAbsolutePath(item) } }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.select(item)
        }
        .onTapGesture(count: 2) {
            viewModel.select(item)
            Task {
                await viewModel.copyToPasteboard(item)
                onCopyAndClose()
            }
        }
        .contextMenu {
            Button(L10n.localized("clipboard.action.copy")) {
                Task { await viewModel.copyToPasteboard(item) }
            }
            if item.contentType == .file, item.filePath != nil {
                Button(L10n.localized("clipboard.action.copyPath")) {
                    Task { await viewModel.copyAbsolutePath(item) }
                }
                Button(L10n.localized("preview.showInFinder")) {
                    viewModel.revealInFinder(item)
                }
            }
            Button(item.isPinned ? L10n.localized("clipboard.unpin") : L10n.localized("clipboard.pin")) {
                Task { await viewModel.togglePin(item) }
            }
            Button(item.isFavorite ? L10n.localized("clipboard.unfavorite") : L10n.localized("clipboard.favorite")) {
                Task { await viewModel.toggleFavorite(item) }
            }
            Divider()
            Button(role: .destructive) {
                Task { await viewModel.delete(item) }
            } label: {
                Text(L10n.localized("preview.delete"))
            }
            Button(role: .destructive) {
                viewModel.showClearAllConfirmation = true
            } label: {
                Text(L10n.localized("clipboard.clearAll.button"))
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: JadeSpace.x1.value) {
            Text(L10n.localized("clipboard.status.summary",
                                viewModel.items.count,
                                viewModel.formattedStorageUsage,
                                retentionText))
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textTertiary)
            Spacer()
            if viewModel.isLoading {
                ProgressView().scaleEffect(0.6)
            }
        }
    }

    private var retentionText: String {
        if let days = viewModel.retentionDays {
            return L10n.localized("clipboard.status.retentionDays", days)
        }
        return L10n.localized("clipboard.status.retentionForever")
    }

    // MARK: - Empty states

    /// 首次读取历史期间的占位。
    ///
    /// 没有这条分支时，`items` 为空且 `isLoading` 为 true 会落进「列表 + 详情」分支：
    /// 左栏整片空白、右栏提示「选择一条记录以预览」，用户读到的结论是「没有内容」，
    /// 而不是「正在读取」——冷启动那一瞬间看起来就像加载失败。
    private var loadingState: some View {
        VStack(spacing: JadeSpace.x3.value) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.localized("clipboard.loading"))
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clipboard.loading")
    }

    private var emptyState: some View {
        VStack(spacing: JadeSpace.x3.value) {
            Image(systemName: viewModel.isSearching ? "questionmark.circle" : "tray")
                .font(JadeFont.placeholderIcon)
                .foregroundStyle(JadeColor.textSecondary)
                .accessibilityHidden(true)
            Text(viewModel.isSearching
                 ? L10n.localized("clipboard.empty.search.title")
                 : L10n.localized("clipboard.empty.title"))
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textSecondary)
            Text(viewModel.isSearching
                 ? L10n.localized("clipboard.empty.search.subtitle")
                 : L10n.localized("clipboard.empty.subtitle"))
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: JadeSpace.x3.value) {
            Image(systemName: "hand.raised.slash")
                .font(JadeFont.placeholderIcon)
                .foregroundStyle(JadeColor.textSecondary)
                .accessibilityHidden(true)
            Text(L10n.localized("clipboard.empty.disabled.title"))
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textSecondary)
            Button(L10n.localized("clipboard.empty.disabled.enable")) {
                Task { await viewModel.enableClipboard() }
            }
            .buttonStyle(.jadePrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard shortcuts (hidden buttons, macOS 13 compatible)

    /// ↑↓ / ⏎ / ⎋。改由 `KeyEventHandler` 接管：与命令栏同一套窗口级本地监听，
    /// 既能在搜索框持有 first responder 时生效，也尊重中文输入法的候选态
    /// （⌘F / j / k / ⌫ / ⌘C 仍走下面的隐藏按钮）。
    private var navigationKeys: some View {
        KeyEventHandler(
            onUpArrow: { viewModel.moveSelectionUp() },
            onDownArrow: { viewModel.moveSelectionDown() },
            onReturn: {
                viewModel.copySelectedToPasteboard()
                onCopyAndClose()
            },
            onEscape: { onClose() }
        )
        .allowsHitTesting(false)
    }

    private var keyboardShortcuts: some View {
        ZStack {
            shortcutButton(.init("f"), modifiers: .command) { searchFocused = true }
            shortcutButton(.init("k"), modifiers: []) { viewModel.moveSelectionUp() }
            shortcutButton(.init("j"), modifiers: []) { viewModel.moveSelectionDown() }
            shortcutButton(.init("c"), modifiers: .command) {
                viewModel.copySelectedToPasteboard()
                onCopyAndClose()
            }
            shortcutButton(.delete, modifiers: []) {
                if !searchFocused { Task { await viewModel.deleteSelected() } }
            }
        }
        .allowsHitTesting(false)
    }

    private func shortcutButton(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: { EmptyView() }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: modifiers)
        .frame(width: Self.hiddenShortcutSize, height: Self.hiddenShortcutSize)
        .jadeHiddenShortcut()
    }
}

#Preview {
    ClipboardHistoryView(viewModel: ClipboardListViewModel())
}
