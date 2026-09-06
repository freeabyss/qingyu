import AppKit
import Foundation
import os.log

// MARK: - Assistant MVP Command IDs

extension CommandID {
    static let openSystemSettings = CommandID(rawValue: "openSystemSettings")
    static let openAppSettings = CommandID(rawValue: "openAppSettings")
    static let openDownloads = CommandID(rawValue: "openDownloads")
    static let openApplications = CommandID(rawValue: "openApplications")
    static let openDesktop = CommandID(rawValue: "openDesktop")
    static let captureRegion = CommandID(rawValue: "captureRegion")
    static let captureFullScreen = CommandID(rawValue: "captureFullScreen")
    static let captureWindow = CommandID(rawValue: "captureWindow")
    static let openClipboardHistory = CommandID(rawValue: "openClipboardHistory")
    static let clearClipboardHistory = CommandID(rawValue: "clearClipboardHistory")
    static let toggleClipboardRecording = CommandID(rawValue: "toggleClipboardRecording")
    static let checkPermissions = CommandID(rawValue: "checkPermissions")
    static let restartFinder = CommandID(rawValue: "restartFinder")
    static let restartDock = CommandID(rawValue: "restartDock")
    static let toggleAppearance = CommandID(rawValue: "toggleAppearance")
}

// MARK: - Command source domain

protocol CommandSourceProtocol: SearchSource {
    var commands: [AssistantCommandDefinition] { get }
}

protocol CommandExecutorProtocol {
    func execute(_ commandID: CommandID, confirmed: Bool) async throws
    func requiresConfirmation(_ commandID: CommandID) -> Bool
}

protocol CommandConfirmationProviding {
    func confirm(command: AssistantCommandDefinition) async -> Bool
}

struct AssistantCommandDefinition: Identifiable, Hashable {
    let id: CommandID
    let chineseName: String
    let englishName: String
    let chineseAliases: [String]
    let englishAliases: [String]
    let pinyin: String
    let initials: String
    let iconSystemName: String
    let requiresConfirmation: Bool

    var title: String { chineseName }
    var subtitle: String { englishName }
    var aliases: [String] { chineseAliases + englishAliases + [englishName] }

    func candidate() -> SearchTextCandidate {
        SearchTextCandidate(
            text: chineseName,
            aliases: aliases,
            pinyin: pinyin,
            initials: initials
        )
    }
}

enum AssistantCommandExecutionError: LocalizedError, Equatable {
    case unknownCommand(CommandID)
    case confirmationRequired(CommandID)
    case executionFailed(CommandID, String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let id):
            return "Unknown command: \(id.rawValue)"
        case .confirmationRequired(let id):
            return "Command requires confirmation: \(id.rawValue)"
        case .executionFailed(let id, let reason):
            return "Command \(id.rawValue) failed: \(reason)"
        }
    }
}

// MARK: - Command catalog

enum AssistantCommandCatalog {
    static let commands: [AssistantCommandDefinition] = [
        command(
            .openSystemSettings,
            zh: "打开系统设置",
            en: "Open System Settings",
            zhAliases: ["系统设置", "设置", "打开系统偏好设置", "系统偏好设置"],
            enAliases: ["system settings", "settings", "preferences", "open preferences"],
            icon: "gearshape"
        ),
        command(
            .openAppSettings,
            zh: "打开本应用设置",
            en: "Open App Settings",
            zhAliases: ["应用设置", "本应用设置", "助手设置", "偏好设置"],
            enAliases: ["app settings", "assistant settings", "preferences"],
            icon: "slider.horizontal.3"
        ),
        command(
            .openDownloads,
            zh: "打开下载目录",
            en: "Open Downloads",
            zhAliases: ["下载", "下载文件夹", "下载目录"],
            enAliases: ["downloads", "download folder", "open downloads"],
            icon: "arrow.down.circle"
        ),
        command(
            .openApplications,
            zh: "打开应用程序目录",
            en: "Open Applications",
            zhAliases: ["应用程序", "应用目录", "程序目录", "打开应用程序"],
            enAliases: ["applications", "apps folder", "open applications"],
            icon: "app"
        ),
        command(
            .openDesktop,
            zh: "打开桌面目录",
            en: "Open Desktop",
            zhAliases: ["桌面", "桌面文件夹", "桌面目录"],
            enAliases: ["desktop", "desktop folder", "open desktop"],
            icon: "desktopcomputer"
        ),
        command(
            .captureRegion,
            zh: "区域截图",
            en: "Capture Region",
            zhAliases: ["截图", "截屏", "区域截屏", "选择区域截图"],
            enAliases: ["screenshot", "capture region", "region screenshot", "area screenshot"],
            icon: "crop"
        ),
        command(
            .captureFullScreen,
            zh: "全屏截图",
            en: "Capture Full Screen",
            zhAliases: ["全屏截屏", "截取全屏", "屏幕截图"],
            enAliases: ["full screen screenshot", "capture full screen", "screen capture"],
            icon: "rectangle.inset.filled"
        ),
        command(
            .captureWindow,
            zh: "窗口截图",
            en: "Capture Window",
            zhAliases: ["窗口截屏", "截取窗口", "选窗口截图"],
            enAliases: ["window screenshot", "capture window"],
            icon: "macwindow"
        ),
        command(
            .openClipboardHistory,
            zh: "打开剪贴板历史",
            en: "Open Clipboard History",
            zhAliases: ["剪贴板历史", "剪切板历史", "打开剪贴板", "打开剪切板", "剪贴板", "剪切板"],
            enAliases: ["clipboard history", "open clipboard", "clipboard"],
            icon: "clipboard"
        ),
        command(
            .clearClipboardHistory,
            zh: "清空剪贴板历史",
            en: "Clear Clipboard History",
            zhAliases: ["清空历史", "清除剪贴板", "删除剪贴板历史"],
            enAliases: ["clear clipboard", "clear history", "clear clipboard history"],
            icon: "trash",
            requiresConfirmation: true
        ),
        command(
            .toggleClipboardRecording,
            zh: "暂停或恢复剪贴板记录",
            en: "Pause or Resume Clipboard Recording",
            zhAliases: ["暂停剪贴板", "恢复剪贴板", "切换剪贴板记录", "剪贴板记录"],
            enAliases: ["pause clipboard", "resume clipboard", "toggle clipboard", "clipboard recording"],
            icon: "pause.circle"
        ),
        command(
            .checkPermissions,
            zh: "检查权限状态",
            en: "Check Permissions",
            zhAliases: ["权限", "检查权限", "权限状态", "查看权限"],
            enAliases: ["permissions", "check permissions", "permission status"],
            icon: "checkmark.shield"
        ),
        command(
            .restartFinder,
            zh: "重启 Finder",
            en: "Restart Finder",
            zhAliases: ["重启访达", "重启 Finder", "重新启动 Finder", "重新启动访达"],
            enAliases: ["restart finder", "relaunch finder"],
            icon: "face.smiling",
            requiresConfirmation: true
        ),
        command(
            .restartDock,
            zh: "重启 Dock",
            en: "Restart Dock",
            zhAliases: ["重启程序坞", "重新启动 Dock", "重新启动程序坞"],
            enAliases: ["restart dock", "relaunch dock"],
            icon: "dock.rectangle",
            requiresConfirmation: true
        ),
        command(
            .toggleAppearance,
            zh: "切换深色或浅色模式",
            en: "Toggle Appearance",
            zhAliases: ["切换深色模式", "切换浅色模式", "深色模式", "浅色模式", "外观"],
            enAliases: ["toggle appearance", "dark mode", "light mode", "toggle dark mode"],
            icon: "circle.lefthalf.filled"
        )
    ]

    static let allowedIDs = Set(commands.map(\.id))
    static let byID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })

    private static func command(
        _ id: CommandID,
        zh: String,
        en: String,
        zhAliases: [String],
        enAliases: [String],
        icon: String,
        requiresConfirmation: Bool = false
    ) -> AssistantCommandDefinition {
        AssistantCommandDefinition(
            id: id,
            chineseName: zh,
            englishName: en,
            chineseAliases: zhAliases,
            englishAliases: enAliases,
            pinyin: PinyinHelper.toPinyin(zh),
            initials: PinyinHelper.toInitials(zh),
            iconSystemName: icon,
            requiresConfirmation: requiresConfirmation
        )
    }
}

// MARK: - Assistant MVP command source

/// Search source for the Assistant MVP built-in command whitelist.
///
/// The catalog is intentionally closed: it exposes exactly the 15 commands in
/// `docs/architecture/api.md` section 10.1. It does not parse arbitrary user text
/// as shell, and it does not include shutdown, system restart, logout, sudo,
/// file deletion, process killing, or custom command execution.
final class SystemCommandSource: CommandSourceProtocol {
    let id: SearchSourceID = .command
    let displayName = "Commands"
    let isEnabledInSearch = true

    let commands: [AssistantCommandDefinition]
    private let logger = Logger.search

    init(commands: [AssistantCommandDefinition] = AssistantCommandCatalog.commands) {
        self.commands = commands
    }

    func canSearch(query: String) -> Bool {
        SearchTriggerRules.standardMinimumLength(sourceID: .command, query: query)
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch(query: trimmed) else { return [] }

        let matches = matchedCommands(query: trimmed)
        logger.info("CommandSource search '\(trimmed, privacy: .public)': \(matches.count) results")
        return matches.map { match in
            SearchResult(
                id: SearchResultID(rawValue: "command:\(match.command.id.rawValue)"),
                sourceID: .command,
                title: match.command.chineseName,
                subtitle: match.command.englishName,
                icon: .systemSymbol(match.command.iconSystemName),
                typeLabel: "Command",
                baseScore: SourcePriority.command,
                matchScore: match.kind.score,
                usageScore: 0,
                primaryAction: .runPluginAction(.quickLaunchCommand(match.command.id)),
                secondaryActions: []
            )
        }
    }

    private struct CommandMatch {
        let command: AssistantCommandDefinition
        let kind: SearchTextMatcher.MatchKind
    }

    private func matchedCommands(query: String) -> [CommandMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return commands.compactMap { command -> CommandMatch? in
            guard let kind = SearchTextMatcher.match(query: trimmed, candidate: command.candidate()) else {
                return nil
            }
            return CommandMatch(command: command, kind: kind)
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.command.chineseName.localizedCaseInsensitiveCompare(rhs.command.chineseName) == .orderedAscending
        }
    }
}

// MARK: - Safe command execution

final class SystemCommandExecutor: CommandExecutorProtocol {
    private let commandLookup: [CommandID: AssistantCommandDefinition]
    private let clipboardHistoryService: ClipboardHistoryServiceProtocol?
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults

    init(
        commands: [AssistantCommandDefinition] = AssistantCommandCatalog.commands,
        clipboardHistoryService: ClipboardHistoryServiceProtocol? = nil,
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.commandLookup = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        self.clipboardHistoryService = clipboardHistoryService
        self.workspace = workspace
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
    }

    func requiresConfirmation(_ commandID: CommandID) -> Bool {
        commandLookup[commandID]?.requiresConfirmation ?? false
    }

    func execute(_ commandID: CommandID, confirmed: Bool = false) async throws {
        guard let command = commandLookup[commandID] else {
            throw AssistantCommandExecutionError.unknownCommand(commandID)
        }
        guard !command.requiresConfirmation || confirmed else {
            throw AssistantCommandExecutionError.confirmationRequired(commandID)
        }

        switch commandID {
        case .openSystemSettings:
            guard let settingsURL = URL(string: "x-apple.systempreferences:") else {
                throw AssistantCommandExecutionError.executionFailed(commandID, "Invalid system settings URL")
            }
            try openURL(settingsURL, commandID: commandID)
        case .openAppSettings:
            await postOnMainActor(name: .openManagementCenter, object: SettingsRoute.settings)
        case .openDownloads:
            workspace.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
        case .openApplications:
            workspace.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        case .openDesktop:
            workspace.open(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
        case .captureRegion:
            await postOnMainActor(name: .commandCaptureRegion)
        case .captureFullScreen:
            await postOnMainActor(name: .commandCaptureFullScreen)
        case .captureWindow:
            await postOnMainActor(name: .commandCaptureWindow)
        case .openClipboardHistory:
            await postOnMainActor(name: .commandOpenClipboardHistory)
        case .clearClipboardHistory:
            guard let clipboardHistoryService else { return }
            try await clipboardHistoryService.clearAll(confirmed: true)
        case .toggleClipboardRecording:
            await postOnMainActor(name: .commandToggleClipboardRecording)
        case .checkPermissions:
            await postOnMainActor(name: .openManagementCenter, object: SettingsRoute.permissions)
        case .restartFinder:
            restartRunningApplication(bundleIdentifier: "com.apple.finder")
            if let finderURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                workspace.open(finderURL)
            }
        case .restartDock:
            restartRunningApplication(bundleIdentifier: "com.apple.dock")
        case .toggleAppearance:
            toggleAppearance()
        default:
            throw AssistantCommandExecutionError.unknownCommand(commandID)
        }
    }

    private func openURL(_ url: URL, commandID: CommandID) throws {
        if !workspace.open(url) {
            throw AssistantCommandExecutionError.executionFailed(commandID, "NSWorkspace refused to open URL")
        }
    }

    /// NotificationCenter delivers synchronously on the posting thread. These
    /// notifications are consumed by AppKit window controllers, so posting from
    /// a search task's cooperative executor would make them touch NSWindow off
    /// the main thread and trip AppKit's queue precondition.
    private func postOnMainActor(name: Notification.Name, object: Any? = nil) async {
        await MainActor.run {
            notificationCenter.post(name: name, object: object)
        }
    }

    private func restartRunningApplication(bundleIdentifier: String) {
        workspace.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .forEach { app in
                if !app.terminate() {
                    app.forceTerminate()
                }
            }
    }

    private func toggleAppearance() {
        Task { @MainActor in
            NSApp.effectiveAppearance.name == .darkAqua
                ? NSApp.appearance = NSAppearance(named: .aqua)
                : (NSApp.appearance = NSAppearance(named: .darkAqua))
        }
    }
}

final class CommandSearchActionExecutor: SearchActionExecutorProtocol {
    private let commandExecutor: CommandExecutorProtocol
    private let confirmationProvider: CommandConfirmationProviding?

    init(commandExecutor: CommandExecutorProtocol, confirmationProvider: CommandConfirmationProviding? = nil) {
        self.commandExecutor = commandExecutor
        self.confirmationProvider = confirmationProvider
    }

    func execute(_ action: SearchAction) async throws {
        guard case .runCommand(let commandID) = action else { return }
        let confirmed: Bool
        if commandExecutor.requiresConfirmation(commandID) {
            guard let command = AssistantCommandCatalog.byID[commandID] else {
                throw AssistantCommandExecutionError.unknownCommand(commandID)
            }
            confirmed = await confirmationProvider?.confirm(command: command) ?? false
            guard confirmed else { return }
        } else {
            confirmed = false
        }
        try await commandExecutor.execute(commandID, confirmed: confirmed)
    }
}

extension Notification.Name {
    static let commandCaptureRegion = Notification.Name("com.assistant.command.captureRegion")
    static let commandCaptureFullScreen = Notification.Name("com.assistant.command.captureFullScreen")
    static let commandCaptureWindow = Notification.Name("com.assistant.command.captureWindow")
    static let commandOpenClipboardHistory = Notification.Name("com.assistant.command.openClipboardHistory")
    static let commandToggleClipboardRecording = Notification.Name("com.assistant.command.toggleClipboardRecording")
    static let commandCheckPermissions = Notification.Name("com.assistant.command.checkPermissions")
}
