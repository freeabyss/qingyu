import AppKit
import Combine
import Foundation
import os.log

/// Search-source filter selectable via ⌘1-6 in the command bar (T-011, PRD §9.6).
enum CommandBarSource: Int, CaseIterable, Identifiable {
    case all = 1
    case app = 2
    case command = 3
    case clipboard = 4
    case file = 5
    case settings = 6

    var id: Int { rawValue }

    /// Filters shown in the command-bar UI. Clipboard is excluded because
    /// Quick Launch search no longer mixes in clipboard history.
    static var visibleCases: [CommandBarSource] {
        allCases.filter { $0 != .clipboard }
    }

    /// The `SearchSourceID` this filter keeps, or `nil` for "所有".
    var sourceID: SearchSourceID? {
        switch self {
        case .all: return nil
        case .app: return .app
        case .command: return .command
        case .clipboard: return .clipboard
        case .file: return .file
        case .settings: return .settings
        }
    }

    /// Whether a result belongs to this filter. Calculator/convert results are
    /// treated as part of "所有" only (they have no dedicated ⌘ slot).
    func matches(_ result: SearchResult) -> Bool {
        guard let sourceID else { return true }
        return result.sourceID == sourceID
    }

    var localizedTitleKey: String {
        switch self {
        case .all: return "commandBar.source.all"
        case .app: return "commandBar.source.app"
        case .command: return "commandBar.source.command"
        case .clipboard: return "commandBar.source.clipboard"
        case .file: return "commandBar.source.file"
        case .settings: return "commandBar.source.settings"
        }
    }
}

@MainActor
final class SearchPanelViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [SearchResult] = []
    /// `results` 回答的那个查询（去空白后）：用于判断结果是否已对应当前输入。
    @Published private(set) var resultsQuery: String = ""
    /// Cursor into `navigableResults`. `-1` means **no selection** (home open
    /// state). Search mode starts at `0` so Enter runs the top hit.
    @Published private(set) var selectedIndex: Int = -1
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""

    /// Active ⌘1-6 source filter (default "所有").
    @Published var activeSource: CommandBarSource = .all

    /// Pending danger command awaiting `⏎` confirmation; drives `JadeConfirmationDialog`.
    @Published var pendingDangerResult: SearchResult?

    private let searchService: SearchServiceProtocol
    private let dangerCommandIDs: Set<String>
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let logger = Logger.search
    private var cancellables = Set<AnyCancellable>()

    /// 查询是否非空（仅空白视为空）。控制器订阅 `$query` 时也用它，
    /// 使「是否显示内容区」只有一处判断。
    nonisolated static func isQueryPresent(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 去除首尾空白后的查询；搜索与结果归属都以它为准。
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasQuery: Bool {
        Self.isQueryPresent(query)
    }

    /// 是否展示"未找到匹配项"。除了"结果为空"，还要求结果确实对应当前查询：
    /// 查询刚变化时结果尚未返回（防抖 180ms + 搜索），结果集仍属于旧查询，
    /// 只看"结果为空"就会先闪一次空结果态。
    var shouldShowNoResults: Bool {
        hasQuery && visibleResults.isEmpty && !isLoading && resultsQuery == trimmedQuery
    }

    /// Results filtered by the active ⌘1-6 source (search mode).
    var visibleResults: [SearchResult] {
        results.filter { activeSource.matches($0) }
    }

    /// Flat list used for ↑↓ navigation and Enter. Empty without a query, since
    /// the empty-query panel has no content area at all.
    var navigableResults: [SearchResult] {
        hasQuery ? visibleResults : []
    }

    var selectedResult: SearchResult? {
        let list = navigableResults
        guard selectedIndex >= 0, list.indices.contains(selectedIndex) else { return nil }
        return list[selectedIndex]
    }

    init(
        searchService: SearchServiceProtocol,
        dangerCommandIDs: Set<String> = SearchPanelViewModel.defaultDangerCommandIDs,
        onOpenSettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.searchService = searchService
        self.dangerCommandIDs = dangerCommandIDs
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        setupDebounce()
    }

    /// Danger commands that require a `⏎` second confirmation (PRD §9.5 / T-011).
    nonisolated static let defaultDangerCommandIDs: Set<String> = [
        "clearClipboardHistory",
        "restartFinder",
        "restartDock",
        "lockScreen",
        "sleepComputer",
        "restartComputer",
        "shutdownComputer"
    ]

    /// Whether a result is a danger command (shows ⚠️ badge + confirmation dialog).
    /// Command results carry either the legacy `.runCommand` or the plugin-routed
    /// `.runPluginAction(.quickLaunchCommand(...))`; both resolve to a CommandID.
    func isDangerous(_ result: SearchResult) -> Bool {
        guard let commandID = result.primaryAction.commandID else { return false }
        return dangerCommandIDs.contains(commandID.rawValue)
    }

    /// Whether the result is the calculator/convert top answer, pinned to row 0.
    func isCalculatorTopResult(_ result: SearchResult) -> Bool {
        result.sourceID == .calculator && visibleResults.first?.id == result.id
    }

    func open() {
        query = ""
        activeSource = .all
        pendingDangerResult = nil
        clearResults()
    }

    func close() {
        onClose()
    }

    func openSettings() {
        onOpenSettings()
    }

    /// Clears the input (⌘K); the panel collapses back to the input-only state.
    func clearInput() {
        query = ""
    }

    func selectSource(_ source: CommandBarSource) {
        activeSource = source
        selectedIndex = visibleResults.isEmpty ? -1 : 0
    }

    func moveUp() {
        let count = navigableResults.count
        guard count > 0 else { return }
        if selectedIndex < 0 {
            selectedIndex = count - 1
        } else {
            selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : count - 1
        }
    }

    func moveDown() {
        let count = navigableResults.count
        guard count > 0 else { return }
        if selectedIndex < 0 {
            selectedIndex = 0
        } else {
            selectedIndex = selectedIndex < count - 1 ? selectedIndex + 1 : 0
        }
    }

    func select(_ result: SearchResult) {
        guard let index = navigableResults.firstIndex(where: { $0.id == result.id }) else { return }
        selectedIndex = index
    }

    func confirmSelection() {
        guard let result = selectedResult else { return }
        trigger(result)
    }

    /// Runs a result's primary action, routing danger commands through confirmation.
    func trigger(_ result: SearchResult) {
        if isDangerous(result) {
            pendingDangerResult = result
            return
        }
        Task { await execute(result) }
    }

    /// Confirms the pending danger command (invoked by the confirmation dialog).
    func confirmPendingDanger() {
        guard let result = pendingDangerResult else { return }
        pendingDangerResult = nil
        Task { await execute(result) }
    }

    func cancelPendingDanger() {
        pendingDangerResult = nil
    }

    /// Copies the current selection's value (text / path / result value) to the
    /// pasteboard without executing its primary action (⌘C, PRD §9.6).
    func copyCurrentValue() {
        guard let result = selectedResult, let text = copyableText(for: result) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast(message: L10n.localized("commandBar.copied"))
    }

    private func copyableText(for result: SearchResult) -> String? {
        switch result.primaryAction {
        case .copyText(let text):
            return text
        case .openFile(let url), .revealInFinder(let url):
            return url.path
        case .openURL(let url):
            return url.absoluteString
        case .openURLWithClipboard(let url, let text):
            return "\(text)\n\(url.absoluteString)"
        case .openApplication:
            if case .appIcon(let url) = result.icon { return url.path }
            return result.subtitle
        case .copyClipboardRecord:
            return result.title
        case .runCommand, .runPluginAction, .openSettings:
            return result.title
        }
    }

    func execute(_ result: SearchResult) async {
        await searchService.recordSelection(result)
        do {
            let response = try await searchService.execute(result.primaryAction)
            if response.shouldCloseSearchPanel {
                onClose()
            }
        } catch {
            logger.error("Search action failed: \(error.localizedDescription, privacy: .public)")
            showToast(message: error.localizedDescription)
        }
    }

    func searchNow() async {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let response = await searchService.search(query: trimmed)
        results = Array(response.results.prefix(SearchService.defaultResultLimit))
        resultsQuery = trimmed
        selectedIndex = visibleResults.isEmpty ? -1 : 0
        elapsed = response.elapsed * 1000
        logger.info("CommandBar query returned \(self.results.count) results in \(String(format: "%.1f", self.elapsed))ms")
    }

    private func setupDebounce() {
        $query
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.searchNow() }
            }
            .store(in: &cancellables)

        // Reset selection when the source filter changes so the highlight stays in bounds.
        $activeSource
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.selectedIndex = self.visibleResults.isEmpty ? -1 : 0
            }
            .store(in: &cancellables)
    }

    private func clearResults() {
        results = []
        resultsQuery = ""
        // Home open: no pre-selection; user picks with ↑↓.
        selectedIndex = -1
        elapsed = 0
        isLoading = false
    }

    private func showToast(message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.showToast = false
        }
    }
}

/// Composite executor used by US-011 search panel to route all MVP primary actions.
final class SearchPanelActionExecutor: SearchActionExecutorProtocol {
    private let appExecutor: SearchActionExecutorProtocol
    private let commandExecutor: SearchActionExecutorProtocol
    private let clipboardRepository: ClipboardRepositoryProtocol
    private let resourceStore: FileResourceStoreProtocol
    /// Task 002: routes `.runPluginAction` through the plugin registry. `nil`
    /// (e.g. clipboard-list wiring) makes plugin actions unreachable.
    private let pluginRegistry: PluginRegistry?
    private let logger = Logger.search

    init(
        appExecutor: SearchActionExecutorProtocol,
        commandExecutor: SearchActionExecutorProtocol,
        clipboardRepository: ClipboardRepositoryProtocol,
        resourceStore: FileResourceStoreProtocol,
        pluginRegistry: PluginRegistry? = nil
    ) {
        self.appExecutor = appExecutor
        self.commandExecutor = commandExecutor
        self.clipboardRepository = clipboardRepository
        self.resourceStore = resourceStore
        self.pluginRegistry = pluginRegistry
    }

    func execute(_ action: SearchAction) async throws {
        switch action {
        case .openApplication:
            try await appExecutor.execute(action)
        case .runCommand:
            try await commandExecutor.execute(action)
        case .runPluginAction(let actionID):
            guard let pluginRegistry else {
                throw NSError(
                    domain: "com.freeabyss.qingyu.searchPanel",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Plugin registry is not wired into this executor"]
                )
            }
            try await pluginRegistry.execute(actionID)
        case .copyClipboardRecord(let id):
            try await copyClipboardRecord(id)
        case .copyText(let text):
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        case .openSettings(let route):
            await openSettings(route)
        case .openFile(let url):
            await MainActor.run {
                if !NSWorkspace.shared.open(url) {
                    logger.error("NSWorkspace.open failed for file: \(url.path, privacy: .public)")
                }
            }
        case .revealInFinder(let url):
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .openURL(let url):
            await MainActor.run {
                if !NSWorkspace.shared.open(url) {
                    logger.error("NSWorkspace.open failed for URL: \(url.absoluteString, privacy: .public)")
                }
            }
        case .openURLWithClipboard(let url, let text):
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                if !NSWorkspace.shared.open(url) {
                    logger.error("NSWorkspace.open failed for URL: \(url.absoluteString, privacy: .public)")
                }
            }
        }
    }

    private func copyClipboardRecord(_ id: UUID) async throws {
        guard let snapshot = try await clipboardRepository.fetch(id: id) else {
            throw NSError(domain: "com.freeabyss.qingyu.searchPanel", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.localized("searchPanel.error.recordNotFound")])
        }

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch snapshot.contentType {
            case .text:
                if let text = snapshot.plainText {
                    pasteboard.setString(text, forType: .string)
                }
            case .richText:
                if let text = snapshot.plainText {
                    pasteboard.setString(text, forType: .string)
                }
            case .image:
                // The image data is read off-main below; this case is filled by the async path.
                break
            case .file:
                if let url = snapshot.filePath {
                    pasteboard.writeObjects([url as NSPasteboardWriting])
                }
            }
        }

        if snapshot.contentType == .richText || snapshot.contentType == .image {
            try await writeResources(snapshot)
        }
    }

    private func writeResources(_ snapshot: ClipboardRecordSnapshot) async throws {
        let resources = snapshot.resources
        switch snapshot.contentType {
        case .richText:
            for resource in resources {
                switch resource.type {
                case .richTextRTF:
                    let data = try await resourceStore.read(relativePath: resource.relativePath)
                    await MainActor.run { _ = NSPasteboard.general.setData(data, forType: .rtf) }
                case .richTextHTML:
                    let data = try await resourceStore.read(relativePath: resource.relativePath)
                    await MainActor.run { _ = NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType("public.html")) }
                default:
                    break
                }
            }
        case .image:
            if let original = resources.first(where: { $0.type == .imageOriginal }) {
                let data = try await resourceStore.read(relativePath: original.relativePath)
                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.png"))
                    if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                    }
                }
            }
        case .text, .file:
            break
        }
    }

    @MainActor
    private func openSettings(_ route: SettingsRoute) {
        NotificationCenter.default.post(name: .openManagementCenter, object: route)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class SearchPanelCommandConfirmationProvider: CommandConfirmationProviding {
    func confirm(command: AssistantCommandDefinition) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = command.chineseName
        alert.informativeText = L10n.localized("searchPanel.confirm.destructive")
        alert.addButton(withTitle: L10n.localized("settings.alert.ok"))
        alert.addButton(withTitle: L10n.localized("settings.alert.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
