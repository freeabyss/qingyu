import AppKit
import Combine
import os.log

/// Dependency injection root for 清羽 Qingyu (design §2.5).
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
    private(set) lazy var settingsService = SettingsService(persistence: .shared)

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
            let snapThreshold = (try? await settings.value(for: .pinSnapThreshold, as: Double.self))
                ?? Double(PinSnapping.defaultThreshold)
            let showsShortcutHints = (try? await settings.value(for: .pinShowsShortcutHints, as: Bool.self)) ?? true
            self.pinWindowController.applySettings(
                filePathToImage: filePathToImage,
                restoreCapacity: capacity,
                snapThreshold: PinSnapping.sanitizedThreshold(snapThreshold),
                showsShortcutHints: showsShortcutHints
            )
        }
        return controller
    }()

    private var builtInPluginsRegistered = false

    /// Registers compiled-in plugins. Idempotent; individual start failures are
    /// recorded and isolated by the registry. Plugins are started separately:
    /// quick launch contributes passively, clipboard starts with the full
    /// experience (after onboarding) via `pluginRegistry.start(.clipboard)`.
    ///
    /// 1.0.0 FeatureGate：截图插件不注册（设置页五页侧栏变四页）；
    /// `screenshotPlugin` 为 lazy 属性，未注册即不会被构造。
    func registerBuiltInPlugins() {
        guard !builtInPluginsRegistered else { return }
        builtInPluginsRegistered = true
        do {
            try pluginRegistry.register(quickLaunchPlugin)
            try pluginRegistry.register(clipboardPlugin)
            if FeatureGate.screenshotEnabled {
                try pluginRegistry.register(screenshotPlugin)
            } else {
                logger.info("FeatureGate: screenshot disabled, ScreenshotPlugin not registered")
            }
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
    /// Task 014/07：四角热区监听（默认关闭，由运行时设置决定是否启动）。
    private(set) lazy var hotCornerMonitor: HotCornerMonitor = {
        let monitor = HotCornerMonitor()
        monitor.onTrigger = { [weak self] _, action in
            guard let self else { return }
            switch action {
            case .regionCapture:
                self.screenshotWindowController.startCapture()
            case .ignore:
                break
            }
        }
        return monitor
    }()

    /// Task 015：截图预设仓库（区域 / 尺寸）。会话开始时装入控制器，会话期只读。
    private(set) lazy var capturePresetStore = CapturePresetStore(
        persistence: SettingsCapturePresetPersistence(settings: settingsService)
    )
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
        center.addObserver(self, selector: #selector(handleCommandCaptureScreenshot), name: .commandCaptureScreenshot, object: nil)
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

    @objc private func handleCommandCaptureScreenshot() {
        screenshotWindowController.startCapture()
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
        // 1.0.0 FeatureGate：截图隐藏期间贴图无入口，pinWindowController 不应被
        // 构造/访问（lazy）。开关恢复后 destroyAll() 照常执行。
        if FeatureGate.screenshotEnabled {
            pinWindowController.destroyAll()
        }
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
        await syncMagnifierSettings(settingsService)
        await syncElementDetectionSettings(settingsService)
        // Task 015：预设集合随运行时设置一起装载（会话开始时直接取快照）。
        await capturePresetStore.reload()
        // Task 014/05：预览阶段手势绑定。
        let bindings = (try? await settingsService.value(for: .screenshotGestureBindings, as: ScreenshotGestureBindings.self))
            ?? ScreenshotGestureBindings.default
        screenshotWindowController.gestureBindings = bindings
        // Task 014/07：四角热区（默认关闭时监听器保持停止，不产生任何轮询开销）。
        let hotCorners = (try? await settingsService.value(for: .screenshotHotCorners, as: HotCornerConfiguration.self))
            ?? .default
        hotCornerMonitor.configuration = hotCorners.sanitized()
    }

    /// Task 012：把控件级探测与选区吸附设置同步到截图会话工厂。
    private func syncElementDetectionSettings(_ settingsService: SettingsService) async {
        let detection = (try? await settingsService.value(for: .elementDetection, as: Bool.self)) ?? false
        let threshold = (try? await settingsService.value(for: .snapThreshold, as: Double.self)) ?? 0
        let ignored = (try? await settingsService.value(for: .elementIgnoredApps, as: [String].self)) ?? []

        screenshotWindowController.elementDetectionOptions = ElementProbeOptions(
            isElementProbingEnabled: detection,
            ignoredBundleIDs: Set(ignored),
            timeout: ElementProbeOptions.default.timeout
        )
        // 负值/NaN 一律按关闭处理，避免不可预期的吸附行为。
        screenshotWindowController.snapThreshold = threshold.isFinite && threshold > 0
            ? CGFloat(threshold)
            : 0
    }

    /// Task 011：把放大镜设置同步到截图会话工厂。
    ///
    /// 显示项以 JSON 字符串数组持久化 —— 空数组表示「全部关闭」，
    /// 与「键不存在」区分开，避免用户关掉全部显示项后又被默认值覆盖。
    private func syncMagnifierSettings(_ settingsService: SettingsService) async {
        let defaults = MagnifierConfiguration.default
        let enabled = (try? await settingsService.value(for: .magnifierShown, as: Bool.self))
            ?? defaults.isEnabled
        let zoom = (try? await settingsService.value(for: .magnifierZoom, as: Int.self))
            ?? defaults.zoom
        let rawOptions = (try? await settingsService.value(for: .magnifierOptions, as: [String].self))
            ?? defaults.options.map(\.rawValue).sorted()
        let options = Set(rawOptions.compactMap(MagnifierDisplayOption.init(rawValue:)))

        screenshotWindowController.magnifierConfiguration = MagnifierConfiguration(
            isEnabled: enabled,
            zoom: zoom,
            options: options
        ).sanitized()
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
        // Quick Launch search: apps / commands / calculator / files / settings only.
        // Clipboard history is a dedicated window (⌥⌘C) and is not mixed into ⌥Space.
        let sources = pluginRegistry.searchSources.filter { $0.id != .clipboard }
        let usageStore = UsageStatRepository()
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
            actionExecutor: actionExecutor
        )
        return SearchPanelViewModel(
            searchService: service,
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
