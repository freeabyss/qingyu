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
            header
                .jadePadding(.horizontal, .x4)
                .jadePadding(.top, .x3)
                .jadePadding(.bottom, .x2)

            Divider().overlay(JadeColor.border)

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
        .task { await viewModel.load() }
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
        .jadeToast(viewModel.toastMessage, isShowing: $viewModel.showToast, variant: viewModel.toastVariant)
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
                .font(JadeFont.commandBarInput)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JadeSpace.x4.value) {
                ForEach(primaryFilters) { filter in
                    filterChip(filter)
                }
            }
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
        } else if viewModel.items.isEmpty && !viewModel.isLoading {
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
                    fileImageProvider: { await viewModel.fileImageData(for: $0) }
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
