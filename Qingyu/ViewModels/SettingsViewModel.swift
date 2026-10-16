import AppKit
import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import os.log

/// Notification posted when Assistant MVP settings change so long-running services
/// can reload their runtime state without waiting for app restart.
extension Notification.Name {
    static let settingsDidChange = Notification.Name("com.freeabyss.qingyu.settingsDidChange")
    static let openManagementCenter = Notification.Name("com.freeabyss.qingyu.openManagementCenter")
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

/// ViewModel for the settings window (Task 004).
///
/// The sidebar is `general` + currently visible plugin pages + `about`; hidden
/// feature gates must never leak a settings entry or detail view.
@MainActor
final class SettingsViewModel: ObservableObject {
    private let settingsService: SettingsServiceProtocol
    private let blacklistRepository: SearchBlacklistRepositoryProtocol
    private let permissionService: PermissionServiceProtocol
    /// 本应用签名状态：决定屏幕录制授权能否跨构建保留（ad-hoc 构建每次重编都失效）。
    let appSignatureStatus: AppSignatureStatus = PermissionService.appSignatureStatus()
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private let dataManagementService: DataManagementService
    private let conflictDetector: HotkeyConflictDetector
    private let clipboardRepository: ClipboardRepositoryProtocol
    private let pluginRegistry: PluginRegistry?
    private let logger = Logger.app

    @Published var selectedPage: SettingsPageID = .general
    @Published var sourceToggles: [SearchSourceToggle] = SettingsViewModel.defaultSearchSourceToggles
    @Published var clipboardEnabled = true
    @Published var clipboardRetention: ClipboardRetention = .thirtyDays
    @Published var launchAtLoginEnabled = true
    @Published var languageMode: LanguageMode = .followSystem
    @Published var appearanceMode: AppearanceMode = .system
    /// 关键词跳转定制（改关键词 / 自定义条目）。
    @Published var keywordLaunchCustomization = KeywordLaunchCustomization.empty
    @Published var blacklistItems: [SearchBlacklistItemSnapshot] = []
    @Published var permissionStatuses: [PermissionKind: PermissionStatus] = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, .unknown) })

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

    /// 重启应用的可注入入口。生产环境走 `AppRelauncher`；单元测试注入空实现，
    /// 否则跑测试时真的会把宿主进程重启掉。
    private let relaunch: @MainActor () -> Void

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

    static let retentionOptions: [ClipboardRetention] = [.sevenDays, .thirtyDays, .ninetyDays, .forever]
    /// 语言列表顺序即用户扫读顺序：先系统，再按中文 → 英文 → 日文 → 法文。
    static let languageOptions: [LanguageMode] = [
        .followSystem,
        .simplifiedChinese,
        .traditionalChinese,
        .english,
        .japanese,
        .french
    ]

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
        SearchSourceToggle(id: .clipboard, settingKey: .clipboardShowInSearch, title: L10n.localized("management.source.clipboard"), subtitle: L10n.localized("management.source.clipboard.subtitle"), iconName: "clipboard", isEnabled: false)
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
        clipboardRepository: ClipboardRepositoryProtocol = ClipboardRepository(),
        pluginRegistry: PluginRegistry? = nil,
        relaunch: @escaping @MainActor () -> Void = { AppRelauncher.relaunch() }
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
        self.pluginRegistry = pluginRegistry
        self.relaunch = relaunch
    }

    /// Sidebar page order: 通用、当前可见的插件页（按 order 排序）、关于。
    var visiblePageIDs: [SettingsPageID] {
        [.general] + visiblePluginSettingsPages.map { .plugin($0.id) } + [.about]
    }

    /// Plugin settings are filtered at the same boundary as the feature itself.
    /// This prevents a disabled feature from being reachable through a stale
    /// registry contribution or a deep link.
    private var visiblePluginSettingsPages: [PluginSettingsPageDescriptor] {
        pluginRegistry?.settingsPages.filter { page in
            page.id != .screenshot || FeatureGate.screenshotEnabled
        } ?? []
    }

    /// Sidebar metadata for a plugin page (title/icon/accessibility id).
    func pluginSettingsPage(for id: PluginID) -> PluginSettingsPageDescriptor? {
        visiblePluginSettingsPages.first { $0.id == id }
    }

    /// The plugin-contributed detail view for `.plugin(id)` pages.
    func makePluginPageView(id: PluginID) -> AnyView? {
        visiblePluginSettingsPages.first { $0.id == id }?.makeView()
    }

    // MARK: - Plugin page settings access (Task 004)

    /// Read-through access for plugin settings pages that need persisted values
    /// without owning a second settings service.
    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        try await settingsService.value(for: key, as: type)
    }

    /// Write-through access for plugin settings pages (persists immediately).
    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        try await settingsService.set(value, for: key)
    }

    func load() async {
        await loadSettings()
        await reloadBlacklist()
        await refreshPermissions()
        refreshShortcutConflicts()
        await refreshStorageUsage()
    }

    func select(route: SettingsRoute) {
        switch route {
        case .general:
            selectedPage = .general
        case .quickLaunch:
            selectedPage = .plugin(.quickLaunch)
        case .clipboard:
            selectedPage = .plugin(.clipboard)
        case .screenshot:
            if FeatureGate.screenshotEnabled {
                selectedPage = .plugin(.screenshot)
            }
        case .about:
            selectedPage = .about
        }
    }

    func saveSettings() async {
        do {
            // 先取落盘的语言，用来判断这次保存是否真的改了语言（见 applyLanguagePreference）。
            let previousLanguage = try? await settingsService.value(for: .languageMode, as: LanguageMode.self)
            for toggle in sourceToggles {
                try await settingsService.set(toggle.isEnabled, for: toggle.settingKey)
            }
            try await settingsService.set(clipboardEnabled, for: .clipboardEnabled)
            try await settingsService.set(clipboardRetention, for: .clipboardRetention)
            try await settingsService.set(launchAtLoginEnabled, for: .launchAtLoginEnabled)
            try await settingsService.set(languageMode, for: .languageMode)
            try await settingsService.set(appearanceMode, for: .appearanceMode)
            try launchAtLoginService.setEnabled(launchAtLoginEnabled)
            applyLanguagePreference(previous: previousLanguage)
            notificationCenter.post(name: .settingsDidChange, object: nil)
            statusMessage = L10n.localized("management.settings.saved")
        } catch {
            logger.error("Failed to save management center settings: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func resetSettingsToDefaults() async {
        do {
            // 恢复默认会把语言也改回「跟随系统」，同样属于语言变更，需要重启。
            let previousLanguage = try? await settingsService.value(for: .languageMode, as: LanguageMode.self)
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
            applyLanguagePreference(previous: previousLanguage)
            notificationCenter.post(name: .settingsDidChange, object: nil)
            statusMessage = L10n.localized("management.settings.reset")
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// 保存关键词跳转定制；搜索来源每次查询都会重新读取，因此立即生效。
    func saveKeywordLaunchCustomization(_ customization: KeywordLaunchCustomization) {
        keywordLaunchCustomization = customization
        Task {
            do {
                try await settingsService.set(customization, for: .keywordLaunchCustomization)
            } catch {
                errorMessage = error.localizedDescription
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

    // MARK: - Storage usage (T-013)

    /// Compute total on-disk usage (Core Data store + resource files) for the General page's data section.
    func refreshStorageUsage() async {
        if let usage = try? await clipboardRepository.storageUsage() {
            storageUsageBytes = usage.totalBytes
        }
    }

    /// Human-readable storage size (e.g. "12.4 MB").
    var storageUsageText: String {
        ByteCountFormatter.string(fromByteCount: storageUsageBytes ?? 0, countStyle: .file)
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

    /// "打开数据目录": reveal the Qingyu data directory in Finder.
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
        language.displayName
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
            launchAtLoginEnabled = try await settingsService.value(for: .launchAtLoginEnabled, as: Bool.self)
            languageMode = try await settingsService.value(for: .languageMode, as: LanguageMode.self)
            appearanceMode = try await settingsService.value(for: .appearanceMode, as: AppearanceMode.self)
            keywordLaunchCustomization = (try? await settingsService.value(
                for: .keywordLaunchCustomization,
                as: KeywordLaunchCustomization.self
            )) ?? .empty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 落盘语言覆盖，并在语言**真的变了**时自动重启应用。
    ///
    /// `AppleLanguages` 只在进程启动时被 `Bundle` 读取一次，切换语言无法热生效，
    /// 因此这里直接重启而不是弹「需要重启」提示。
    ///
    /// - Parameter previous: 本次保存前的落盘语言。`nil`（读取失败）时只写覆盖，
    ///   不重启——把「读不到旧值」当成语言变更会让非语言设置的保存也重启应用。
    private func applyLanguagePreference(previous: LanguageMode?) {
        if let override = languageMode.appleLanguagesOverride {
            userDefaults.set(override, forKey: "AppleLanguages")
        } else {
            userDefaults.removeObject(forKey: "AppleLanguages")
        }

        guard let previous, previous != languageMode else { return }
        logger.info("Interface language changed \(previous.rawValue, privacy: .public) -> \(self.languageMode.rawValue, privacy: .public); relaunching")
        relaunch()
    }
}
