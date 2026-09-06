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
    @Published private(set) var selectedIndex: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""

    /// Active ⌘1-6 source filter (default "所有").
    @Published var activeSource: CommandBarSource = .all

    /// Empty-query home content (T-011 / D-120).
    @Published private(set) var recentResults: [SearchResult] = []
    @Published private(set) var favoriteResults: [SearchResult] = []

    /// Pending danger command awaiting `⏎` confirmation; drives `JadeConfirmationDialog`.
    @Published var pendingDangerResult: SearchResult?

    private let searchService: SearchServiceProtocol
    private let homeProvider: CommandBarHomeProviding?
    private let dangerCommandIDs: Set<String>
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let logger = Logger.search
    private var cancellables = Set<AnyCancellable>()

    static let homeSectionLimit = 5

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stable, executable shortcuts shown on the empty-query home screen. These
    /// keep the two most common tool flows discoverable without requiring users
    /// to remember a keyword or global shortcut.
    var homeQuickActions: [SearchResult] {
        let commandIDs: [CommandID] = [
            .openClipboardHistory,
            .captureRegion,
            .captureWindow,
            .captureFullScreen
        ]
        return commandIDs.compactMap { commandID in
            guard let command = AssistantCommandCatalog.byID[commandID] else { return nil }
            return SearchResult(
                id: SearchResultID(rawValue: "command:\(command.id.rawValue)"),
                sourceID: .command,
                title: command.chineseName,
                subtitle: command.englishName,
                icon: .systemSymbol(command.iconSystemName),
                typeLabel: L10n.localized("searchPanel.type.command"),
                baseScore: SourcePriority.command,
                matchScore: 0,
                usageScore: 0,
                primaryAction: .runPluginAction(.quickLaunchCommand(command.id)),
                secondaryActions: []
            )
        }
    }

    /// Home content is shown when there is no query. Quick actions are always
    /// present; recent/favorite records enrich the screen when available.
    var hasHomeContent: Bool {
        !homeQuickActions.isEmpty || !recentResults.isEmpty || !favoriteResults.isEmpty
    }

    /// The floating panel needs room for either search results or its empty-query
    /// home sections. Keeping this state in the view model prevents the AppKit
    /// controller from collapsing visible recents/favorites to the input height.
    var shouldExpandPanel: Bool {
        hasQuery || hasHomeContent
    }

    /// Results filtered by the active ⌘1-6 source (search mode).
    var visibleResults: [SearchResult] {
        results.filter { activeSource.matches($0) }
    }

    var selectedResult: SearchResult? {
        let list = visibleResults
        guard list.indices.contains(selectedIndex) else { return nil }
        return list[selectedIndex]
    }

    init(
        searchService: SearchServiceProtocol,
        homeProvider: CommandBarHomeProviding? = nil,
        dangerCommandIDs: Set<String> = SearchPanelViewModel.defaultDangerCommandIDs,
        onOpenSettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.searchService = searchService
        self.homeProvider = homeProvider
        self.dangerCommandIDs = dangerCommandIDs
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        setupDebounce()
    }

    /// Danger commands that require a `⏎` second confirmation (PRD §9.5 / T-011).
    nonisolated static let defaultDangerCommandIDs: Set<String> = [
        "clearClipboardHistory",
        "restartFinder",
        "restartDock"
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
        Task { await loadHomeContent() }
    }

    func close() {
        onClose()
    }

    func openSettings() {
        onOpenSettings()
    }

    /// Clears the input (⌘K). Reloads home content.
    func clearInput() {
        query = ""
    }

    func selectSource(_ source: CommandBarSource) {
        activeSource = source
        selectedIndex = 0
    }

    func moveUp() {
        let count = visibleResults.count
        guard count > 0 else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : count - 1
    }

    func moveDown() {
        let count = visibleResults.count
        guard count > 0 else { return }
        selectedIndex = selectedIndex < count - 1 ? selectedIndex + 1 : 0
    }

    func select(_ result: SearchResult) {
        guard let index = visibleResults.firstIndex(where: { $0.id == result.id }) else { return }
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
        case .openApplication:
            if case .appIcon(let url) = result.icon { return url.path }
            return result.subtitle
        case .copyClipboardRecord:
            return result.title
        case .runCommand, .runPluginAction, .openSettings, .startScreenshot:
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

    func loadHomeContent() async {
        guard let homeProvider else {
            recentResults = []
            favoriteResults = []
            return
        }
        let limit = Self.homeSectionLimit
        async let recents = homeProvider.recentResults(limit: limit)
        async let favorites = homeProvider.favoriteResults(limit: limit)
        recentResults = await recents
        favoriteResults = await favorites
    }

    func searchNow() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            await loadHomeContent()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let response = await searchService.search(query: trimmed)
        results = Array(response.results.prefix(SearchService.defaultResultLimit))
        selectedIndex = 0
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
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    private func clearResults() {
        results = []
        selectedIndex = 0
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
                    domain: "com.assistant.searchPanel",
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
        case .startScreenshot(let mode):
            await startScreenshot(mode)
        case .openFile(let url):
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        case .revealInFinder(let url):
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func copyClipboardRecord(_ id: UUID) async throws {
        guard let snapshot = try await clipboardRepository.fetch(id: id) else {
            throw NSError(domain: "com.assistant.searchPanel", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.localized("searchPanel.error.recordNotFound")])
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

    @MainActor
    private func startScreenshot(_ mode: AssistantScreenshotMode) {
        switch mode {
        case .region:
            NotificationCenter.default.post(name: .commandCaptureRegion, object: nil)
        case .fullScreen:
            NotificationCenter.default.post(name: .commandCaptureFullScreen, object: nil)
        case .window:
            NotificationCenter.default.post(name: .commandCaptureWindow, object: nil)
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
