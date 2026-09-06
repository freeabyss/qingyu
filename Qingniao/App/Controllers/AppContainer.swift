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
    private(set) lazy var clipboardService = ClipboardService(
        repository: clipboardRepository,
        resourceStore: resourceStore
    )
    let cleanupService = DataCleanupService()
    let updateService = UpdateService()
    private(set) var permissionService: PermissionServiceProtocol = PermissionService()
    let screenshotService: ScreenshotServiceProtocol = ScreenshotService()

    private let appSearchSource = AppSearchSource()
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

    /// Task that consumes clipboard events from the monitor stream.
    private var monitorTask: Task<Void, Never>?

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
        } else if let page = notification.object as? ManagementCenterPage {
            let route: SettingsRoute
            switch page {
            case .overview: route = .settings
            case .clipboard: route = .clipboardHistory
            case .shortcuts: route = .hotkey
            case .screenshot: route = .screenshot
            case .searchSources: route = .searchSources
            case .permissions: route = .permissions
            case .about, .updates: route = .about
            case .appearance, .data, .feedback: route = .settings
            }
            settingsWindowController.show(route: route)
        } else {
            settingsWindowController.show(route: .settings)
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
        settingsWindowController.show(route: .permissions)
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

    /// Starts clipboard capture and periodic cleanup. Called after onboarding.
    func startFullExperienceServices() {
        startClipboardMonitoring()
        Task { await syncRuntimeSettings() }
        cleanupService.start()
    }

    func stopRuntimeServices() {
        cleanupService.stop()
        clipboardMonitor.stop()
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func startClipboardMonitoring() {
        clipboardMonitor.start()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.clipboardMonitor.events {
                do {
                    if let snapshot = try await self.clipboardService.handle(event: event) {
                        self.logger.debug("Processed clipboard event -> record id=\(snapshot.id.uuidString, privacy: .public)")
                    }
                } catch {
                    self.logger.error("Failed to process clipboard event: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        logger.info("Clipboard monitoring started")
    }

    /// Aligns the clipboard recording state and launch-at-login registration with
    /// the stored settings. Called at launch and on settings changes.
    func syncRuntimeSettings() async {
        let settingsService = SettingsService(persistence: .shared)
        let enabled = (try? await settingsService.value(for: .clipboardEnabled, as: Bool.self)) ?? true
        if enabled {
            clipboardService.resumeRecording()
        } else {
            clipboardService.pauseRecording()
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
        let clipboardQueryService = ClipboardIndexQueryService(index: clipboardSearchIndex, repository: clipboardRepository)
        let settingsService = SettingsService(persistence: .shared)
        let appSource = SettingsBackedSearchSource(source: appSearchSource, settingsService: settingsService, settingKey: .appSourceEnabled)
        let commandSource = SettingsBackedSearchSource(source: systemCommandSource, settingsService: settingsService, settingKey: .commandSourceEnabled)
        let calculatorSource = SettingsBackedSearchSource(source: calculatorSearchSource, settingsService: settingsService, settingKey: .calculatorSourceEnabled)
        let fileSource = SettingsBackedSearchSource(source: fileSearchSource, settingsService: settingsService, settingKey: .fileSourceEnabled)
        let clipboardSource = AssistantClipboardSource(queryService: clipboardQueryService, settingsService: settingsService)
        let settingsSource = SettingsSource(settingsService: settingsService)
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
            resourceStore: resourceStore
        )
        let service = SearchService(
            sources: [appSource, commandSource, calculatorSource, settingsSource, fileSource, clipboardSource],
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
                self?.settingsWindowController.show(route: .settings)
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
