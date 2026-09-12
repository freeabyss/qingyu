import AppKit
import Combine
import os.log

/// Dependency injection root for 青鸟 Qingniao (design §2.5).
///
/// Constructs and owns the Service / Repository / Data-layer singletons and the
/// App Shell window controllers, replacing the hand-rolled assembly that used to
/// live inside `AppDelegate`. It is the single place that knows how to wire the
/// whole object graph, which also makes the controllers testable via injected
/// mocks.
@MainActor
final class AppContainer: NSObject {
    private let logger = Logger.app

    // MARK: - Data / Index layer

    let clipboardSearchIndex = InMemorySearchIndex()
    private(set) lazy var resourceStore: FileResourceStoreProtocol =
        FileResourceStore(fileSystem: PersistenceController.shared.fileSystem)

    private(set) lazy var clipboardRepository: ClipboardRepositoryProtocol = {
        let base = ClipboardRepository(persistence: .shared, resourceStore: resourceStore)
        let loader = ClipboardSearchIndexLoader(persistence: .shared, index: clipboardSearchIndex)
        return IndexingClipboardRepository(base: base, index: clipboardSearchIndex, loader: loader)
    }()

    // MARK: - Services

    let clipboardMonitor = ClipboardMonitor()
    let cleanupService = DataCleanupService()
    let updateService = UpdateService()
    private(set) var permissionService: PermissionServiceProtocol = PermissionService()
    let screenshotService: ScreenshotServiceProtocol = ScreenshotService()

    /// Task 001: first-party plugin kernel. Built-in features are migrated onto
    /// this registry in Tasks 002/003; until then existing wiring stays intact.
    let pluginRegistry = PluginRegistry()

    /// Task 002: quick launch plugin owns the app/file/calculator/command/
    /// settings search sources and the whitelisted command actions. AppContainer
    /// only injects dependencies; the plugin builds its own contributions.
    private(set) lazy var quickLaunchPlugin = QuickLaunchPlugin(
        appSource: appSearchSource,
        fileSource: fileSearchSource,
        calculatorSource: calculatorSearchSource,
        commandSource: systemCommandSource,
        settingsService: SettingsService(persistence: .shared),
        commandExecutor: SystemCommandExecutor(
            clipboardHistoryService: ClipboardHistoryService(repository: clipboardRepository)
        ),
        confirmationProvider: SearchPanelCommandConfirmationProvider()
    )

    /// Task 003: clipboard plugin owns monitoring, the search contribution and
    /// the history-window entry. AppContainer only injects dependencies.
    private(set) lazy var clipboardPlugin = ClipboardPlugin(
        monitor: clipboardMonitor,
        index: clipboardSearchIndex,
        repository: clipboardRepository,
        resourceStore: resourceStore,
        settingsService: SettingsService(persistence: .shared),
        openHistoryWindow: { [weak self] in
            self?.clipboardHistoryWindowController.show()
        }
    )

    /// Task 004: screenshot plugin shell — registers the screenshot settings
    /// page for the five-page sidebar; capture wiring moves in at Task 009.
    private(set) lazy var screenshotPlugin = ScreenshotPlugin()

    /// Task 008: runtime pin (贴图) state and windows. Settings values are read
    /// asynchronously and applied to the store/factory after load.
    private(set) lazy var pinWindowController: PinWindowController = {
        let controller = PinWindowController(
            store: PinStore(),
            payloadFactory: PinPayloadFactory(),
            onOpenSettings: { [weak self] in
                // ⇧⌘P / 贴图右键菜单：复用统一设置窗口路由打开「截图与贴图」页。
                self?.settingsWindowController.show(route: .screenshot)
            }
        )
        Task { [weak self] in
            guard let self else { return }
            let settings = SettingsService(persistence: .shared)
            let filePathToImage = (try? await settings.value(for: .pinFilePathToImage, as: Bool.self)) ?? true
            let capacity = (try? await settings.value(for: .pinRestoreCapacity, as: Int.self)) ?? PinStore.defaultRestoreCapacity
            self.pinWindowController.applySettings(filePathToImage: filePathToImage, restoreCapacity: capacity)
        }
        return controller
    }()

    private var builtInPluginsRegistered = false

    /// Registers compiled-in plugins. Idempotent; individual start failures are
    /// recorded and isolated by the registry. Plugins are started separately:
    /// quick launch contributes passively, clipboard starts with the full
    /// experience (after onboarding) via `pluginRegistry.start(.clipboard)`.
    func registerBuiltInPlugins() {
        guard !builtInPluginsRegistered else { return }
        builtInPluginsRegistered = true
        do {
            try pluginRegistry.register(quickLaunchPlugin)
            try pluginRegistry.register(clipboardPlugin)
            try pluginRegistry.register(screenshotPlugin)
        } catch {
            logger.error("Failed to register built-in plugins: \(error, privacy: .public)")
        }
    }

    /// Lazy：`UsageStatRepository` 默认捕获 `PersistenceController.shared`，
    /// 必须在 AppDelegate `configureUITestDataDir`（--uitest-data-dir 隔离）之后才构造，
    /// 否则会落在外部从未 load 的默认栈上（UI 测试执行应用启动结果即崩溃）。
    private(set) lazy var appSearchSource = AppSearchSource()
    private let systemCommandSource = SystemCommandSource()
    private let calculatorSearchSource = CalculatorSource()
    private let fileSearchSource = FileSearchSource()

    // MARK: - Window / status controllers (lazy, resolved on demand)

    private(set) lazy var statusItemController = StatusItemController(container: self)
    private(set) lazy var commandBarController = CommandBarController(container: self)
    private(set) lazy var clipboardHistoryWindowController = ClipboardHistoryWindowController(container: self)
    private(set) lazy var settingsWindowController = SettingsWindowController(container: self)
    private(set) lazy var screenshotWindowController = ScreenshotWindowController(container: self)

    /// v1.2 (T-008): unified global-shortcut registrar. Owns the six rebindable
    /// hotkeys and the basic conflict detector surfaced to the settings page.
    private(set) lazy var globalShortcutManager = GlobalShortcutManager(container: self)

    nonisolated override init() {
        super.init()
    }

    #if DEBUG
    /// Keeps screenshot permission checks on the same injectable boundary used
    /// by onboarding and UI tests instead of constructing a second live service.
    func setPermissionServiceForUITest(_ service: PermissionServiceProtocol) {
        permissionService = service
    }
    #endif

    // MARK: - Command routing (notifications)

    /// Registers observers for command-bar / system-command notifications and
    /// update requests, routing each to the appropriate controller or service.
    func registerCommandObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleCheckForUpdates), name: .checkForUpdates, object: nil)
        center.addObserver(self, selector: #selector(handleOpenManagementCenter(_:)), name: .openManagementCenter, object: nil)
        center.addObserver(self, selector: #selector(handleSettingsDidChange), name: .settingsDidChange, object: nil)
        center.addObserver(self, selector: #selector(handleCommandToggleClipboardRecording), name: .commandToggleClipboardRecording, object: nil)
        center.addObserver(self, selector: #selector(handleCommandCheckPermissions), name: .commandCheckPermissions, object: nil)
        center.addObserver(self, selector: #selector(handleCommandCaptureRegion), name: .commandCaptureRegion, object: nil)
        center.addObserver(self, selector: #selector(handleCommandCaptureWindow), name: .commandCaptureWindow, object: nil)
        center.addObserver(self, selector: #selector(handleCommandCaptureFullScreen), name: .commandCaptureFullScreen, object: nil)
        center.addObserver(self, selector: #selector(handleCommandOpenClipboardHistory), name: .commandOpenClipboardHistory, object: nil)
    }

    @objc private func handleOpenManagementCenter(_ notification: Notification) {
        if let route = notification.object as? SettingsRoute {
            settingsWindowController.show(route: route)
        } else {
            settingsWindowController.show(route: .general)
        }
    }

    @objc private func handleSettingsDidChange() {
        Task { await syncRuntimeSettings() }
    }

    @objc private func handleCommandToggleClipboardRecording() {
        Task {
            let service = SettingsService(persistence: .shared)
            let current = (try? await service.value(for: .clipboardEnabled, as: Bool.self)) ?? true
            try? await service.set(!current, for: .clipboardEnabled)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    @objc private func handleCommandCheckPermissions() {
        settingsWindowController.show(route: .general)
    }

    @objc private func handleCommandCaptureRegion() {
        screenshotWindowController.captureRegion()
    }

    @objc private func handleCommandCaptureWindow() {
        screenshotWindowController.captureWindow()
    }

    @objc private func handleCommandCaptureFullScreen() {
        screenshotWindowController.captureFullScreen()
    }

    @objc private func handleCommandOpenClipboardHistory() {
        clipboardHistoryWindowController.show()
    }

    @objc private func handleCheckForUpdates() {
        logger.info("Manual update check triggered from UI")
        updateService.checkNow()
    }

    // MARK: - Data stack bootstrap

    /// Prepares the persistence stack and Application Support directory. Runs the
    /// brand-rename data-directory migration first (T-003), then opens the GRDB +
    /// Core Data stores and rebuilds the in-memory clipboard index.
    ///
    /// `onMigrationFallback` is invoked (on the main queue) when the directory
    /// migration failed and fell back to a backup, so the caller can alert.
    func bootstrapDataStack(onMigrationFallback: @escaping (URL) -> Void) {
        let outcome = DataDirectoryMigrator().migrateIfNeeded()
        switch outcome {
        case .alreadyMigrated, .freshInstall, .migrated:
            logger.info("Data directory migration outcome: \(String(describing: outcome), privacy: .public)")
        case .fallbackBackup(let backupURL, let underlying):
            logger.error("Data directory migration fell back to backup at \(backupURL.path, privacy: .public): \(underlying, privacy: .public)")
            DispatchQueue.main.async { onMigrationFallback(backupURL) }
        }

        do {
            try DatabaseManager.shared.setup()
            logger.info("Database initialized successfully")
        } catch {
            logger.error("Database initialization failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try PersistenceController.shared.load()
            startInitialClipboardIndexRebuild()
            logger.info("Core Data clipboard stack initialized successfully")
        } catch {
            logger.error("Core Data initialization failed: \(error.localizedDescription, privacy: .public)")
        }

        createApplicationSupportDirectory()
    }

    private func startInitialClipboardIndexRebuild() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let loader = ClipboardSearchIndexLoader(persistence: .shared, index: self.clipboardSearchIndex)
                try await loader.rebuildFromPersistentStore()
                self.logger.info("Clipboard in-memory index rebuilt from Core Data")
            } catch {
                self.logger.error("Failed to rebuild clipboard index: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func createApplicationSupportDirectory() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let appDir = appSupport.appendingPathComponent(AssistantFileSystem.directoryName)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            logger.debug("Created Application Support directory at \(appDir.path, privacy: .public)")
        }
    }

    // MARK: - Runtime services lifecycle

    /// Starts the clipboard plugin (capture + periodic cleanup). Called after
    /// onboarding completes or is skipped.
    func startFullExperienceServices() {
        registerBuiltInPlugins()
        Task {
            await pluginRegistry.start(.clipboard)
            await syncRuntimeSettings()
        }
        cleanupService.start()
    }

    func stopRuntimeServices() {
        cleanupService.stop()
        pinWindowController.destroyAll()
        Task { await pluginRegistry.stopAll() }
    }

    /// Aligns the clipboard recording state and launch-at-login registration with
    /// the stored settings. Called at launch and on settings changes.
    func syncRuntimeSettings() async {
        let settingsService = SettingsService(persistence: .shared)
        let enabled = (try? await settingsService.value(for: .clipboardEnabled, as: Bool.self)) ?? true
        if enabled {
            clipboardPlugin.clipboardService.resumeRecording()
        } else {
            clipboardPlugin.clipboardService.pauseRecording()
        }
        logger.info("Runtime settings synced: clipboardEnabled=\(enabled)")
    }

    /// Reads the stored launch-at-login preference (default true) and aligns the
    /// system registration.
    func syncLaunchAtLoginPreference() {
        let settingsService = SettingsService(persistence: .shared)
        let launchAtLoginService = LaunchAtLoginService()
        Task {
            let shouldEnable = (try? await settingsService.value(for: .launchAtLoginEnabled, as: Bool.self)) ?? true
            do {
                try launchAtLoginService.setEnabled(shouldEnable)
                logger.info("Launch at login synced: enabled=\(shouldEnable)")
            } catch {
                logger.error("Failed to sync launch-at-login preference: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads the persisted onboarding completion state from Core Data.
    ///
    /// v1.2 (AC-6): 首选新键 `onboarding.completedAt`（Date?，非空即已完成/跳过），
    /// 若为空则回落到 legacy 布尔 `onboarding.completed`（向后兼容旧安装）。
    /// 只要任一表明已完成，重启即不重弹 onboarding。
    func loadOnboardingCompletionState() -> Bool {
        let context = PersistenceController.shared.viewContext
        var completed = false
        context.performAndWait {
            // 1) 新键 onboarding.completedAt：非空字符串即已完成。
            let completedAtRequest = CDAppSetting.fetchRequest()
            completedAtRequest.fetchLimit = 1
            completedAtRequest.predicate = NSPredicate(format: "key == %@", SettingKey.onboardingCompletedAt.rawValue)
            let completedAt = (try? context.fetch(completedAtRequest).first?.value) ?? ""
            if !completedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completed = true
                return
            }

            // 2) legacy 布尔回落。
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", SettingKey.onboardingCompleted.rawValue)
            let rawValue = (try? context.fetch(request).first?.value) ?? "false"
            completed = ["true", "1", "yes", "on"].contains(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return completed
    }

    #if DEBUG
    // MARK: - UITest hooks (DEBUG only, review C-1)

    /// Clears onboarding completion markers (`onboarding.completedAt` + legacy
    /// `onboarding.completed`) so the app enters first-run state.
    ///
    /// Must be called AFTER `bootstrapDataStack` (store ready) and BEFORE
    /// `loadOnboardingCompletionState()` (review C-8).
    func resetOnboardingState() {
        let context = PersistenceController.shared.viewContext
        context.performAndWait {
            for key in [SettingKey.onboardingCompletedAt.rawValue, SettingKey.onboardingCompleted.rawValue] {
                let request = CDAppSetting.fetchRequest()
                request.predicate = NSPredicate(format: "key == %@", key)
                if let records = try? context.fetch(request) {
                    records.forEach { context.delete($0) }
                }
            }
            try? context.save()
        }
    }

    /// Writes onboarding completion markers so the app skips onboarding on launch.
    /// Called between `bootstrapDataStack` and `loadOnboardingCompletionState`.
    func markOnboardingCompletedForUITest() {
        let context = PersistenceController.shared.viewContext
        let timestamp = ISO8601DateFormatter().string(from: Date())
        context.performAndWait {
            for (key, value) in [
                (SettingKey.onboardingCompletedAt.rawValue, timestamp),
                (SettingKey.onboardingCompleted.rawValue, "true")
            ] {
                let request = CDAppSetting.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "key == %@", key)
                if let existing = try? context.fetch(request).first {
                    existing.value = value
                    existing.updatedAt = Date()
                } else {
                    let setting = CDAppSetting(context: context)
                    setting.key = key
                    setting.value = value
                    setting.updatedAt = Date()
                }
            }
            try? context.save()
        }
    }
    #endif

    // MARK: - Factories

    /// Builds the search panel view model with all live sources wired in.
    ///
    /// `onClose` is invoked when the view model wants the hosting panel dismissed
    /// (e.g. after confirming a result).
    func makeSearchPanelViewModel(onClose: @escaping () -> Void) -> SearchPanelViewModel {
        registerBuiltInPlugins()
        // Task 003: all six search sources now come from the plugin registry
        // (quick launch + clipboard plugins).
        let sources = pluginRegistry.searchSources
        let usageStore = UsageStatRepository()
        let blacklistChecker = SearchBlacklistRepository(persistence: .shared)
        let commandExecutor = SystemCommandExecutor(
            clipboardHistoryService: ClipboardHistoryService(repository: clipboardRepository)
        )
        let actionExecutor = SearchPanelActionExecutor(
            appExecutor: AppSearchActionExecutor(appSource: appSearchSource),
            commandExecutor: CommandSearchActionExecutor(
                commandExecutor: commandExecutor,
                confirmationProvider: SearchPanelCommandConfirmationProvider()
            ),
            clipboardRepository: clipboardRepository,
            resourceStore: resourceStore,
            pluginRegistry: pluginRegistry
        )
        let service = SearchService(
            sources: sources,
            usageStore: usageStore,
            blacklistChecker: blacklistChecker,
            actionExecutor: actionExecutor
        )
        let homeProvider = CommandBarHomeProvider(
            usageRepository: usageStore,
            appSource: appSearchSource,
            clipboardRepository: clipboardRepository
        )
        return SearchPanelViewModel(
            searchService: service,
            homeProvider: homeProvider,
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show(route: .general)
            },
            onClose: onClose
        )
    }

    /// Builds a clipboard-history list view model backed by the shared repository/index.
    func makeClipboardListViewModel() -> ClipboardListViewModel {
        let queryService = ClipboardIndexQueryService(index: clipboardSearchIndex, repository: clipboardRepository)
        let actionExecutor = SearchPanelActionExecutor(
            appExecutor: NoopSearchActionExecutor(),
            commandExecutor: NoopSearchActionExecutor(),
            clipboardRepository: clipboardRepository,
            resourceStore: resourceStore
        )
        return ClipboardListViewModel(
            queryService: queryService,
            repository: clipboardRepository,
            historyService: ClipboardHistoryService(repository: clipboardRepository),
            actionExecutor: actionExecutor,
            resourceStore: resourceStore
        )
    }
}
