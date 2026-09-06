import AppKit
import SwiftUI

/// Qingniao clipboard history window (PRD P-02).
///
/// A command-bar-consistent single-column search and result list. Filters and
/// management actions live beside the shared search affordance so users do not
/// have to learn a second navigation model. Keyboard-driven: ⌘F focus search, ⌘A select all,
/// ↑↓ / jk move cursor, ⏎ / ⌘C copy & close, space / ⌘Y preview, ⌫ delete.
struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    /// Invoked when an item is copied via ⏎ / click — closes the window.
    var onCopyAndClose: () -> Void = {}
    /// Opens the settings window from the sidebar footer.
    var onOpenSettings: () -> Void = {}

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .frame(height: 56)
                .padding(.horizontal, JadeSpace.x4.value)

            Divider().overlay(JadeColor.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(JadeColor.border)

            statusBar
                .frame(height: 44)
                .padding(.horizontal, JadeSpace.x4.value)
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(JadeColor.surface1)
        .tint(JadeColor.primary)
        .task { await viewModel.load() }
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
        .sheet(item: $viewModel.previewItem) { item in
            PreviewPanel(
                item: item,
                imageProvider: { await viewModel.originalImageData(for: $0) },
                richTextProvider: { await viewModel.richTextData(for: $0) },
                onCopy: { Task { await viewModel.copyToPasteboard(item) } },
                onDelete: { Task { await viewModel.delete(item) } }
            )
        }
        .jadeToast(viewModel.toastMessage, isShowing: $viewModel.showToast, variant: .info)
    }

    // MARK: - Shared command-bar search affordance

    private var searchBar: some View {
        HStack(spacing: JadeSpace.x3.value) {
            searchInput

            filterMenu

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(JadeColor.surface3, in: JadeRadius.sm.shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("management.page.settings"))
        }
    }

    private var searchInput: some View {
        HStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(searchFocused ? JadeColor.primary : JadeColor.textSecondary)
                .accessibilityHidden(true)

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

    private var filterMenu: some View {
        Menu {
            ForEach(ClipboardListViewModel.SidebarSelection.typeCases) { selection in
                filterButton(selection)
            }
            Divider()
            ForEach(ClipboardListViewModel.SidebarSelection.specialCases) { selection in
                filterButton(selection)
            }
            Divider()
            ForEach(ClipboardListViewModel.SidebarSelection.timeCases) { selection in
                filterButton(selection)
            }
            Divider()
            Button(role: .destructive) {
                viewModel.showClearAllConfirmation = true
            } label: {
                Label(L10n.localized("clipboard.clearAll.button"), systemImage: "trash")
            }
            .disabled(viewModel.isClearing || viewModel.items.isEmpty)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(JadeFont.title3)
                .foregroundStyle(viewModel.selection == .all ? JadeColor.textSecondary : JadeColor.primary)
                .frame(width: 32, height: 32)
                .background(JadeColor.surface3, in: JadeRadius.sm.shape)
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("clipboard.filterMenu")
        .accessibilityLabel(Text("clipboard.filter.all"))
    }

    private func filterButton(_ selection: ClipboardListViewModel.SidebarSelection) -> some View {
        Button {
            viewModel.selection = selection
        } label: {
            Label(selection.title, systemImage: selection.iconName)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.clipboardEnabled {
            disabledState
        } else if viewModel.items.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            list
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
            .background(JadeColor.surface2.opacity(0.45))
        }
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
            selected: viewModel.selectedIDs.contains(item.id) || index == viewModel.selectedIndex,
            thumbnailProvider: { await viewModel.thumbnailData(for: $0) },
            onPin: { Task { await viewModel.togglePin(item) } },
            onCopy: { Task { await viewModel.copyToPasteboard(item) } },
            onPreview: { viewModel.previewItem = item },
            onDelete: { Task { await viewModel.delete(item) } }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.select(item)
            Task {
                await viewModel.copyToPasteboard(item)
                onCopyAndClose()
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await viewModel.toggleFavorite(item) }
            } label: {
                Label(item.isFavorite ? L10n.localized("clipboard.unfavorite") : L10n.localized("clipboard.favorite"),
                      systemImage: "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.delete(item) }
            } label: {
                Label(L10n.localized("preview.delete"), systemImage: "trash")
            }
            .tint(.red)
        }
        .contextMenu {
            Button(L10n.localized("clipboard.action.copy")) {
                Task { await viewModel.copyToPasteboard(item) }
            }
            Button(L10n.localized("preview.open")) { viewModel.previewItem = item }
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
            Image(systemName: viewModel.isSearching ? "magnifyingglass" : "tray")
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
            shortcutButton(.init("a"), modifiers: .command) { viewModel.selectAll() }
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
            shortcutButton(.init("y"), modifiers: .command) {
                viewModel.previewItem = viewModel.selectedItem
            }
            shortcutButton(.space, modifiers: []) {
                if !searchFocused { viewModel.previewItem = viewModel.selectedItem }
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
