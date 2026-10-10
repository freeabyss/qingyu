import AppKit
import SwiftUI

/// Qingyu clipboard history window (PRD P-02).
///
/// Borderless chrome: full-width search + chips on top; **list on the left,
/// detail on the right**. List rows show pin/copy/delete icons always.
/// Keyboard: ⌘F focus search, ↑↓ / jk move, ⏎ / ⌘C copy & close, ⌫ delete.
struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    /// Invoked when an item is copied via ⏎ / click — closes the window.
    var onCopyAndClose: () -> Void = {}

    /// Fixed detail-pane width (independent of content size).
    private static let detailPaneWidth: CGFloat = 360

    @FocusState private var searchFocused: Bool

    /// Primary type filters shown as compact chips (全部 / 文本 / 图片 / 文件).
    private let primaryFilters: [ClipboardListViewModel.SidebarSelection] = [
        .all, .text, .image, .file
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, JadeSpace.x4.value)
                .padding(.top, JadeSpace.x3.value)
                .padding(.bottom, JadeSpace.x2.value)

            Divider().overlay(JadeColor.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(JadeColor.border)

            statusBar
                .frame(height: 36)
                .padding(.horizontal, JadeSpace.x4.value)
        }
        .frame(minWidth: 720, minHeight: 420)
        .jadeWindowSurface(radius: .xxl)
        .jadeShadow(.xl, radius: .xxl)
        .tint(JadeColor.primary)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .focusClipboardSearchField)) { _ in
            searchFocused = true
        }
        .background(keyboardShortcuts)
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
                .strokeBorder(
                    searchFocused ? JadeColor.primary.opacity(0.65) : JadeColor.border,
                    lineWidth: searchFocused ? 1.5 : 1
                )
        )
        .contentShape(JadeRadius.lg.shape)
        .onTapGesture { searchFocused = true }
        .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: searchFocused)
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
                .padding(.vertical, JadeSpace.x1.value)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? JadeColor.primary : Color.clear)
                        .frame(height: 2)
                }
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
                .frame(width: 360)
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
                .padding(.horizontal, JadeSpace.x3.value)
                .padding(.vertical, JadeSpace.x2.value)
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
                .font(.system(size: 40))
                .foregroundStyle(JadeColor.textSecondary)
                .accessibilityHidden(true)
            Text(viewModel.isSearching
                 ? L10n.localized("clipboard.empty.search.title")
                 : L10n.localized("clipboard.empty.title"))
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textSecondary)
            if !viewModel.isSearching {
                Text(L10n.localized("clipboard.empty.subtitle"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: JadeSpace.x3.value) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 40))
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

    private var keyboardShortcuts: some View {
        ZStack {
            shortcutButton(.init("f"), modifiers: .command) { searchFocused = true }
            shortcutButton(.upArrow, modifiers: []) { viewModel.moveSelectionUp() }
            shortcutButton(.downArrow, modifiers: []) { viewModel.moveSelectionDown() }
            shortcutButton(.init("k"), modifiers: []) { viewModel.moveSelectionUp() }
            shortcutButton(.init("j"), modifiers: []) { viewModel.moveSelectionDown() }
            shortcutButton(.return, modifiers: []) {
                viewModel.copySelectedToPasteboard()
                onCopyAndClose()
            }
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
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

#Preview {
    ClipboardHistoryView(viewModel: ClipboardListViewModel())
}
