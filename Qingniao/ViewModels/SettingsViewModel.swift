import AppKit
import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import os.log

/// Notification posted when Assistant MVP settings change so long-running services
/// can reload their runtime state without waiting for app restart.
extension Notification.Name {
    static let settingsDidChange = Notification.Name("com.assistant.settingsDidChange")
    static let openManagementCenter = Notification.Name("com.assistant.openManagementCenter")
}

/// Sidebar groupings for the management center (P-03). `.top` has no header;
/// `.core` / `.system` render a Section header.
enum ManagementSidebarSection: String, CaseIterable, Identifiable, Hashable {
    case top
    case core
    case system

    var id: String { rawValue }

    /// Localized header title, or `nil` for the top (headerless) group.
    var header: String? {
        switch self {
        case .top: return nil
        case .core: return L10n.localized("management.section.core")
        case .system: return L10n.localized("management.section.system")
        }
    }
}

/// The eleven detail pages of the settings / management center (P-03).
enum ManagementCenterPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case clipboard
    case shortcuts
    case screenshot
    case searchSources
    case appearance
    case permissions
    case data
    case updates
    case about
    case feedback

    var id: String { rawValue }

    /// Which sidebar group this page belongs to.
    var section: ManagementSidebarSection {
        switch self {
        case .overview:
            return .top
        case .clipboard, .shortcuts, .screenshot, .searchSources:
            return .core
        case .appearance, .permissions, .data, .updates, .about, .feedback:
            return .system
        }
    }

    /// Pages belonging to a given sidebar section, in display order.
    static func pages(in section: ManagementSidebarSection) -> [ManagementCenterPage] {
        allCases.filter { $0.section == section }
    }

    var title: String {
        switch self {
        case .overview: return L10n.localized("management.page.overview")
        case .clipboard: return L10n.localized("management.page.clipboard")
        case .shortcuts: return L10n.localized("management.page.shortcuts")
        case .screenshot: return L10n.localized("management.page.screenshot")
        case .searchSources: return L10n.localized("management.page.searchSources")
        case .appearance: return L10n.localized("management.page.appearance")
        case .permissions: return L10n.localized("management.page.permissions")
        case .data: return L10n.localized("management.page.data")
        case .updates: return L10n.localized("management.page.updates")
        case .about: return L10n.localized("management.page.about")
        case .feedback: return L10n.localized("management.page.feedback")
        }
    }

    var iconName: String {
        switch self {
        case .overview: return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        case .shortcuts: return "keyboard"
        case .screenshot: return "camera.viewfinder"
        case .searchSources: return "magnifyingglass"
        case .appearance: return "paintpalette"
        case .permissions: return "lock.shield"
        case .data: return "externaldrive"
        case .updates: return "arrow.clockwise"
        case .about: return "info.circle"
        case .feedback: return "envelope"
        }
    }
}

@MainActor
struct SearchSourceToggle: Identifiable, Hashable {
    let id: SearchSourceID
    let settingKey: SettingKey
    let title: String
    let subtitle: String
    let iconName: String
    var isEnabled: Bool
}

/// ViewModel for US-015 Management Center.
///
/// Uses the Assistant MVP Core Data `SettingsService`, `PermissionService`, and
/// `SearchBlacklistRepository`; legacy GRDB settings are intentionally not used
/// for new management-center settings.
@MainActor
final class SettingsViewModel: ObservableObject {
    private let settingsService: SettingsServiceProtocol
    private let blacklistRepository: SearchBlacklistRepositoryProtocol
    private let permissionService: PermissionServiceProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private let dataManagementService: DataManagementService
    private let conflictDetector: HotkeyConflictDetector
    private let clipboardRepository: ClipboardRepositoryProtocol
    private let logger = Logger.app

    @Published var selectedPage: ManagementCenterPage = .overview
    @Published var sidebarFilter: String = ""
    @Published var sourceToggles: [SearchSourceToggle] = SettingsViewModel.defaultSearchSourceToggles
    @Published var clipboardEnabled = true
    @Published var clipboardRetention: ClipboardRetention = .thirtyDays
    @Published var screenshotSaveDirectory: URL = URL(fileURLWithPath: ("~/Desktop" as NSString).expandingTildeInPath)
    @Published var launchAtLoginEnabled = true
    @Published var languageMode: LanguageMode = .followSystem
    @Published var appearanceMode: AppearanceMode = .system
    @Published var blacklistItems: [SearchBlacklistItemSnapshot] = []
    @Published var permissionStatuses: [PermissionKind: PermissionStatus] = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, .unknown) })

    // v1.2 (T-013) overview usage metrics. Zero when no data / repositories unavailable.
    @Published var usageDaysCount: Int = 0
    @Published var averageDailyLaunches: Int = 0
    @Published var clipboardItemCount: Int = 0
    @Published var screenshotItemCount: Int = 0

    // v1.2 (T-013) data page storage usage (bytes). `nil` until computed.
    @Published var storageUsageBytes: Int64?

    // v1.2 (T-013) auto-check-updates preference (MVP: only opens Releases page).
    @Published var autoCheckUpdates = true

    @Published var newBlacklistSourceID = SearchSourceID.app.rawValue
    @Published var newBlacklistResultID = ""
    @Published var newBlacklistTitle = ""
    @Published var newBlacklistType = "application"

    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var showDirectoryImporter = false
    @Published var showLanguageRestartAlert = false

    /// v1.2 (T-003): drives the "清空所有数据" confirmation + post-reset restart prompt
    /// on the settings Data page (T-013 UI binds to these).
    @Published var showResetAllDataConfirmation = false
    @Published var showResetAllDataRestartAlert = false
    @Published var isResettingAllData = false

    /// v1.2 (T-008): per-shortcut conflict warnings surfaced to the settings
    /// shortcut rows (T-013 UI binds to these). Empty when no conflicts. Keyed by
    /// the `KeyboardShortcuts.Name`; the value is a localized, user-facing message.
    @Published var conflictWarnings: [KeyboardShortcuts.Name: String] = [:]

    var enabledSourceNames: String {
        let names = sourceToggles.filter(\.isEnabled).map(\.title)
        return names.isEmpty ? L10n.localized("management.overview.noSources") : names.joined(separator: ", ")
    }

    var searchHotkeyDescription: String {
        KeyboardShortcuts.Shortcut(name: .togglePanel)?.description ?? "⌥ Space"
    }

    var permissionSummary: String {
        let authorized = PermissionKind.allCases.filter { permissionStatuses[$0]?.isAuthorized == true }.count
        return L10n.localized("management.overview.permissionsCount", authorized, PermissionKind.allCases.count)
    }

    static let retentionOptions: [ClipboardRetention] = [.sevenDays, .thirtyDays, .ninetyDays, .forever]
    static let languageOptions: [LanguageMode] = [.followSystem, .simplifiedChinese, .english]

    static let sourceOptions: [(id: SearchSourceID, label: String)] = [
        (.app, "AppSource"),
        (.command, "CommandSource"),
        (.calculator, "CalculatorSource"),
        (.settings, "SettingsSource"),
        (.clipboard, "ClipboardSource")
    ]

    private static let defaultSearchSourceToggles: [SearchSourceToggle] = [
        SearchSourceToggle(id: .app, settingKey: .appSourceEnabled, title: L10n.localized("management.source.app"), subtitle: L10n.localized("management.source.app.subtitle"), iconName: "app", isEnabled: true),
        SearchSourceToggle(id: .command, settingKey: .commandSourceEnabled, title: L10n.localized("management.source.command"), subtitle: L10n.localized("management.source.command.subtitle"), iconName: "terminal", isEnabled: true),
        SearchSourceToggle(id: .calculator, settingKey: .calculatorSourceEnabled, title: L10n.localized("management.source.calculator"), subtitle: L10n.localized("management.source.calculator.subtitle"), iconName: "function", isEnabled: true),
        SearchSourceToggle(id: .settings, settingKey: .settingsSourceEnabled, title: L10n.localized("management.source.settings"), subtitle: L10n.localized("management.source.settings.subtitle"), iconName: "gearshape", isEnabled: true),
        SearchSourceToggle(id: .file, settingKey: .fileSourceEnabled, title: L10n.localized("management.source.file"), subtitle: L10n.localized("management.source.file.subtitle"), iconName: "doc", isEnabled: true),
        SearchSourceToggle(id: .clipboard, settingKey: .clipboardShowInSearch, title: L10n.localized("management.source.clipboard"), subtitle: L10n.localized("management.source.clipboard.subtitle"), iconName: "clipboard", isEnabled: true)
    ]

    init(
        settingsService: SettingsServiceProtocol = SettingsService(persistence: .shared),
        blacklistRepository: SearchBlacklistRepositoryProtocol = SearchBlacklistRepository(persistence: .shared),
        permissionService: PermissionServiceProtocol = PermissionService(),
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
        notificationCenter: NotificationCenter = .default,
        userDefaults: UserDefaults = .standard,
        dataManagementService: DataManagementService = DataManagementService(),
        conflictDetector: HotkeyConflictDetector? = nil,
        clipboardRepository: ClipboardRepositoryProtocol = ClipboardRepository()
    ) {
        self.settingsService = settingsService
        self.blacklistRepository = blacklistRepository
        self.permissionService = permissionService
        self.launchAtLoginService = launchAtLoginService
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        self.dataManagementService = dataManagementService
        self.conflictDetector = conflictDetector ?? HotkeyConflictDetector()
        self.clipboardRepository = clipboardRepository
    }

    func load() async {
        await loadSettings()
        await reloadBlacklist()
        await refreshPermissions()
        refreshShortcutConflicts()
        await refreshOverviewStats()
        await refreshStorageUsage()
    }

    func select(route: SettingsRoute) {
        switch route {
        case .settings:
            selectedPage = .overview
        case .searchSources:
            selectedPage = .searchSources
        case .hotkey:
            selectedPage = .shortcuts
        case .screenshot:
            selectedPage = .screenshot
        case .permissions:
            selectedPage = .permissions
        case .clipboardHistory:
            selectedPage = .clipboard
        case .about:
            selectedPage = .about
        }
    }

    func select(page: ManagementCenterPage) {
        selectedPage = page
    }

    func saveSettings() async {
        do {
            for toggle in sourceToggles {
                try await settingsService.set(toggle.isEnabled, for: toggle.settingKey)
            }
            try await settingsService.set(clipboardEnabled, for: .clipboardEnabled)
            try await settingsService.set(clipboardRetention, for: .clipboardRetention)
            try await settingsService.set(screenshotSaveDirectory, for: .screenshotSaveDirectory)
            try await settingsService.set(launchAtLoginEnabled, for: .launchAtLoginEnabled)
            try await settingsService.set(languageMode, for: .languageMode)
            try await settingsService.set(appearanceMode, for: .appearanceMode)
            try launchAtLoginService.setEnabled(launchAtLoginEnabled)
            applyLanguagePreference()
            notificationCenter.post(name: .settingsDidChange, object: nil)
            statusMessage = L10n.localized("management.settings.saved")
        } catch {
            logger.error("Failed to save management center settings: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func resetSettingsToDefaults() async {
        do {
            for key in [
                SettingKey.appSourceEnabled,
                .commandSourceEnabled,
                .calculatorSourceEnabled,
                .settingsSourceEnabled,
                .fileSourceEnabled,
                .clipboardShowInSearch,
                .clipboardEnabled,
                .clipboardRetention,
                .screenshotSaveDirectory,
                .launchAtLoginEnabled,
                .languageMode,
                .appearanceMode
            ] {
                try await settingsService.reset(key: key)
            }
            await loadSettings()
            notificationCenter.post(name: .settingsDidChange, object: nil)
            statusMessage = L10n.localized("management.settings.reset")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateScreenshotDirectory(_ directory: URL) {
        screenshotSaveDirectory = directory
        Task { try? await settingsService.set(directory, for: .screenshotSaveDirectory) }
    }

    // MARK: - Appearance (T-013)

    /// Persist the appearance override immediately so the root view's
    /// `.preferredColorScheme` can react without a full "save".
    func updateAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        Task {
            do {
                try await settingsService.set(mode, for: .appearanceMode)
                notificationCenter.post(name: .settingsDidChange, object: nil)
            } catch {
                logger.error("Failed to persist appearance mode: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// SwiftUI `ColorScheme?` for `.preferredColorScheme`; `nil` == follow system.
    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Overview stats + storage (T-013)

    /// Refresh the four overview StatCards. Falls back to 0 on any failure so the
    /// overview always renders (per task spec: "没有就返回 0").
    func refreshOverviewStats() async {
        // Clipboard item count from history.
        if let history = try? await clipboardRepository.fetchHistory(filter: ClipboardHistoryFilter()) {
            clipboardItemCount = history.count
            screenshotItemCount = history.filter { $0.contentType == .image }.count
        }

        // Usage days: elapsed days since first launch (persisted in the app
        // UserDefaults suite). Average daily launches derived from a launch counter.
        let firstLaunch = firstLaunchDate()
        let days = max(1, Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0 + 1)
        usageDaysCount = days
        let launches = userDefaults.integer(forKey: Self.launchCountKey)
        averageDailyLaunches = launches > 0 ? max(1, launches / days) : 0
    }

    /// Compute total on-disk usage (Core Data store + resource files) for the Data page.
    func refreshStorageUsage() async {
        if let usage = try? await clipboardRepository.storageUsage() {
            storageUsageBytes = usage.totalBytes
        }
    }

    /// Human-readable storage size for the Data page (e.g. "12.4 MB").
    var storageUsageText: String {
        ByteCountFormatter.string(fromByteCount: storageUsageBytes ?? 0, countStyle: .file)
    }

    private static let launchCountKey = "usage.launchCount"
    private static let firstLaunchKey = "usage.firstLaunchAt"

    private func firstLaunchDate() -> Date {
        if let stored = userDefaults.object(forKey: Self.firstLaunchKey) as? Date {
            return stored
        }
        let now = Date()
        userDefaults.set(now, forKey: Self.firstLaunchKey)
        return now
    }

    // MARK: - Shortcut conflict detection (T-008)

    /// Re-scan all managed global shortcuts and publish per-name conflict
    /// warnings. Call after `load()`, after a recorder change, or after reset.
    func refreshShortcutConflicts() {
        conflictDetector.scan()
        conflictWarnings = conflictDetector.conflictMessages
    }

    /// Whether the given shortcut currently conflicts with a system or internal
    /// binding. T-013 uses this to color the row red / show a warning.
    func isShortcutConflict(_ name: KeyboardShortcuts.Name) -> Bool {
        conflictDetector.conflictingNames.contains(name)
    }

    /// Localized conflict message for a shortcut, or `nil` when there is none.
    func conflictMessage(for name: KeyboardShortcuts.Name) -> String? {
        conflictWarnings[name]
    }

    /// "重置为默认": reset every managed global shortcut to its default binding,
    /// then refresh conflict state.
    func resetAllShortcutsToDefaults() {
        KeyboardShortcuts.reset(KeyboardShortcuts.Name.managedGlobalShortcuts)
        refreshShortcutConflicts()
        statusMessage = L10n.localized("management.shortcuts.reset")
    }

    // MARK: - Data page actions (T-003 / T-013)

    /// User tapped "清空所有数据" — request the two-step confirmation before wiping.
    func requestResetAllData() {
        showResetAllDataConfirmation = true
    }

    /// Confirmed "清空所有数据": deletes the store, resource files, and UserDefaults
    /// domain, then surfaces the restart prompt. On failure sets `errorMessage`.
    func confirmResetAllData() async {
        showResetAllDataConfirmation = false
        isResettingAllData = true
        defer { isResettingAllData = false }
        do {
            try await dataManagementService.resetAllData()
            showResetAllDataRestartAlert = true
            statusMessage = L10n.localized("management.data.reset.done")
        } catch {
            logger.error("Reset all data failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// "打开数据目录": reveal the Qingniao data directory in Finder.
    func openDataDirectory() {
        dataManagementService.openDataDirectory()
    }

    /// "导出数据": v1.3 placeholder. UI keeps the button disabled with a tooltip;
    /// this exists so the binding compiles and logs if ever triggered.
    func exportData() {
        try? dataManagementService.exportData()
    }

    func refreshPermissions() async {
        permissionStatuses = await permissionService.refreshStatuses()
    }

    func openSystemSettings(for permission: PermissionKind) {
        permissionService.openSystemSettings(for: permission)
    }

    func reloadBlacklist() async {
        do {
            blacklistItems = try await blacklistRepository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addBlacklistItem() async {
        let sourceID = newBlacklistSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultID = newBlacklistResultID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = newBlacklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = newBlacklistType.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceID.isEmpty, !resultID.isEmpty, !title.isEmpty else {
            errorMessage = L10n.localized("management.blacklist.validation")
            return
        }

        do {
            _ = try await blacklistRepository.add(SearchBlacklistDraft(
                resultID: SearchResultID(rawValue: resultID),
                sourceID: SearchSourceID(rawValue: sourceID),
                title: title,
                resultType: type.isEmpty ? sourceID : type
            ))
            newBlacklistResultID = ""
            newBlacklistTitle = ""
            await reloadBlacklist()
            statusMessage = L10n.localized("management.blacklist.added")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBlacklistItem(_ item: SearchBlacklistItemSnapshot) async {
        do {
            try await blacklistRepository.remove(id: item.id)
            await reloadBlacklist()
            statusMessage = L10n.localized("management.blacklist.removed")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retentionTitle(_ retention: ClipboardRetention) -> String {
        switch retention {
        case .sevenDays: return L10n.localized("management.retention.7d")
        case .thirtyDays: return L10n.localized("management.retention.30d")
        case .ninetyDays: return L10n.localized("management.retention.90d")
        case .forever: return L10n.localized("management.retention.forever")
        }
    }

    func languageTitle(_ language: LanguageMode) -> String {
        switch language {
        case .followSystem: return L10n.localized("management.language.system")
        case .simplifiedChinese: return L10n.localized("management.language.zh")
        case .english: return L10n.localized("management.language.en")
        }
    }

    func permissionTitle(_ kind: PermissionKind) -> String {
        switch kind {
        case .screenRecording: return L10n.localized("management.permission.screenRecording")
        case .accessibility: return L10n.localized("management.permission.accessibility")
        }
    }

    func permissionDescription(_ kind: PermissionKind) -> String {
        switch kind {
        case .screenRecording: return L10n.localized("management.permission.screenRecording.description")
        case .accessibility: return L10n.localized("management.permission.accessibility.description")
        }
    }

    func statusTitle(_ status: PermissionStatus) -> String {
        switch status {
        case .authorized: return L10n.localized("management.permission.authorized")
        case .denied: return L10n.localized("management.permission.denied")
        case .notDetermined: return L10n.localized("management.permission.notDetermined")
        case .unknown: return L10n.localized("management.permission.unknown")
        }
    }

    private func loadSettings() async {
        do {
            for index in sourceToggles.indices {
                let enabled = try await settingsService.value(for: sourceToggles[index].settingKey, as: Bool.self)
                sourceToggles[index].isEnabled = enabled
            }
            clipboardEnabled = try await settingsService.value(for: .clipboardEnabled, as: Bool.self)
            clipboardRetention = try await settingsService.value(for: .clipboardRetention, as: ClipboardRetention.self)
            screenshotSaveDirectory = try await settingsService.value(for: .screenshotSaveDirectory, as: URL.self)
            launchAtLoginEnabled = try await settingsService.value(for: .launchAtLoginEnabled, as: Bool.self)
            languageMode = try await settingsService.value(for: .languageMode, as: LanguageMode.self)
            appearanceMode = try await settingsService.value(for: .appearanceMode, as: AppearanceMode.self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLanguagePreference() {
        switch languageMode {
        case .followSystem:
            userDefaults.removeObject(forKey: "AppleLanguages")
        case .simplifiedChinese:
            userDefaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case .english:
            userDefaults.set(["en"], forKey: "AppleLanguages")
        }
        showLanguageRestartAlert = true
    }
}
