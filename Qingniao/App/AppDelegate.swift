import Cocoa
import SwiftUI
import os.log

/// AppKit lifecycle delegate. In v1.2 (T-006) this is reduced to lifecycle
/// callbacks plus first-run onboarding; all data bootstrap, service lifecycle
/// and window/status/command/screenshot management is delegated to
/// `AppContainer` and its controllers.
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger.app

    /// Dependency injection root — owns services and window controllers.
    private let container = AppContainer()

    /// First-run onboarding window. It guides setup but never blocks product entry points.
    private var onboardingWindow: NSWindow?

    /// Whether the user completed the required first-run onboarding flow.
    private var isOnboardingCompleted = false

    /// Guards `startFullExperienceServices()` against double-start when the user
    /// re-opens onboarding from the menu and completes it again (v1.2.1 §3.5).
    private var hasStartedFullExperience = false

    /// Global shortcuts are product entry points, independent from whether the
    /// optional clipboard-monitoring lifecycle has started after onboarding.
    private var hasRegisteredGlobalShortcuts = false

    #if DEBUG
    /// Parsed UITest launch arguments. Non-nil only when at least one
    /// `--uitest-*` argument is present (review C-1).
    private var uitestSupport: UITestSupport?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Qingniao launching")

        #if DEBUG
        let parsed = UITestSupport.parse()
        if parsed.isUITest {
            uitestSupport = parsed
            configureUITestDataDir(parsed)
            if parsed.mockScreenRecordingAuthorized || parsed.mockScreenRecordingDenied {
                container.setPermissionServiceForUITest(
                    UITestMockPermissionService(
                        screenRecordingAuthorized: parsed.mockScreenRecordingAuthorized
                    )
                )
            }
        }
        #endif

        container.bootstrapDataStack { [weak self] backupURL in
            self?.presentMigrationFallbackAlert(backupURL: backupURL)
        }

        #if DEBUG
        // Reset / mark onboarding AFTER bootstrapDataStack (store ready) but
        // BEFORE loadOnboardingCompletionState (review C-8).
        if let uitest = uitestSupport {
            if uitest.resetOnboarding {
                container.resetOnboardingState()
            }
            if uitest.markOnboardingCompleted {
                container.markOnboardingCompletedForUITest()
            }
        }
        #endif

        isOnboardingCompleted = container.loadOnboardingCompletionState()
        container.syncLaunchAtLoginPreference()

        // v1.2.1: 功能入口不再被 onboarding 门禁劫持（PRD §4.1）。
        // onboarding 仅在首启自动展示，或经菜单「欢迎向导」主动打开。
        container.statusItemController.onStartScreenshot = { [weak self] in
            self?.container.screenshotWindowController.captureRegion()
        }
        container.statusItemController.onShowOnboarding = { [weak self] in
            self?.showOnboardingWindow()
        }
        container.statusItemController.install()
        setupGlobalShortcuts()

        if isOnboardingCompleted {
            startFullExperienceServices()
        } else {
            showOnboardingWindow()
        }

        container.updateService.setup()
        container.registerCommandObservers()

        #if DEBUG
        if let uitest = uitestSupport, let action = uitest.validatedTriggerAction {
            // Defer trigger to next run-loop so launch setup completes first.
            DispatchQueue.main.async { [weak self] in
                self?.handleUITestTrigger(action)
            }
        }
        #endif

        logger.info("Qingniao launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Qingniao terminating")
        container.stopRuntimeServices()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Startup wiring

    @MainActor
    private func startFullExperienceServices() {
        // 幂等：菜单再次完成 onboarding 时不重复启动剪贴板监听 / 清理。
        guard !hasStartedFullExperience else { return }
        hasStartedFullExperience = true
        container.startFullExperienceServices()
    }

    /// Register global entry points as soon as the app launches. The onboarding
    /// flow may be dismissed or revisited at any time, so it must not suppress
    /// search, clipboard-history, or screenshot shortcuts.
    @MainActor
    private func setupGlobalShortcuts() {
        guard !hasRegisteredGlobalShortcuts else { return }

        #if DEBUG
        if uitestSupport?.skipShortcuts == true {
            logger.info("UITest: skipping global shortcut setup")
            return
        }
        #endif

        hasRegisteredGlobalShortcuts = true
        container.globalShortcutManager.setupShortcuts()
    }

    // MARK: - Onboarding

    @MainActor
    private func showOnboardingWindow() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        let settingsService = SettingsService(persistence: .shared)

        #if DEBUG
        let viewModel: OnboardingViewModel
        if let uitest = uitestSupport,
           uitest.mockScreenRecordingAuthorized || uitest.mockScreenRecordingDenied
        {
            let mockPermission = UITestMockPermissionService(
                screenRecordingAuthorized: uitest.mockScreenRecordingAuthorized
            )
            viewModel = OnboardingViewModel(
                permissionService: mockPermission,
                settingsService: settingsService,
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.isOnboardingCompleted = true
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    self.startFullExperienceServices()
                }
            )
        } else {
            viewModel = OnboardingViewModel(
                settingsService: settingsService,
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.isOnboardingCompleted = true
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    self.startFullExperienceServices()
                }
            )
        }
        #else
        let viewModel = OnboardingViewModel(settingsService: settingsService, onComplete: { [weak self] in
            guard let self else { return }
            self.isOnboardingCompleted = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.startFullExperienceServices()
        })
        #endif
        let view = OnboardingView(viewModel: viewModel)
            .tint(JadeColor.primary) // 全局主色注入（Design Token T-004）
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 欢迎页包含权限说明和可缩放的系统字体；保留紧凑起始尺寸的同时，
        // 允许用户在较大字号或较窄屏幕下扩大窗口，不让 footer 被内容挤压。
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.title = L10n.localized("onboarding.welcome.title")
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self  // v1.2.1: 关闭时清理 onboardingWindow 引用（防再次被困）
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        activateApp()
    }

    // MARK: - NSWindowDelegate

    /// 欢迎窗关闭（含标题栏红色关闭按钮）时清理引用。不改 `isOnboardingCompleted`
    /// ——从菜单主动打开并关闭不会改变已完成状态（AC-11）；下次经菜单入口重新进入
    /// 走全新创建路径，不会 `makeKeyAndOrderFront` 拉回僵尸窗口。
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            onboardingWindow = nil
        }
    }

    // MARK: - Helpers

    #if DEBUG
    /// Redirects `PersistenceController.shared` and `DatabaseManager` to a
    /// temporary data directory for `--uitest-data-dir` data isolation.
    /// Must be called before `bootstrapDataStack` (design §5.4, review C-4).
    private func configureUITestDataDir(_ uitest: UITestSupport) {
        guard let dataDir = uitest.dataDirURL else { return }
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let fileSystem = AssistantFileSystem(rootDirectory: dataDir)
        let persistence = PersistenceController(
            storeConfiguration: .persistent(storeURL: fileSystem.storeURL),
            fileSystem: fileSystem
        )
        PersistenceController.setDebugShared(persistence)
        DatabaseManager.setDebugDatabaseURL(dataDir.appendingPathComponent("assistant.db"))
        logger.info("UITest: data directory redirected to \(dataDir.path, privacy: .public)")
    }

    /// Dispatches `--uitest-trigger <action>` to the corresponding controller,
    /// bypassing the status-item menu (design §5.5, cases.md §0.4).
    @MainActor
    private func handleUITestTrigger(_ action: UITestTriggerAction) {
        switch action {
        case .openSearch:
            container.commandBarController.show()
        case .openClipboard:
            container.clipboardHistoryWindowController.show()
        case .openSettings:
            container.settingsWindowController.show(route: .general)
        case .openAbout:
            container.settingsWindowController.show(route: .about)
        case .openOnboarding:
            showOnboardingWindow()
        case .startScreenshot:
            // 与 statusItemController.onStartScreenshot 闭包调用同一方法
            // （cases.md §0.4）；配合 --uitest-skip-screenshot-capture 仅测入口可达。
            container.screenshotWindowController.captureRegion()
        }
    }
    #endif

    @MainActor
    private func presentMigrationFallbackAlert(backupURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.localized("data.migration.failed.title")
        alert.informativeText = L10n.localized("data.migration.failed.message", backupURL.path)
        alert.addButton(withTitle: L10n.localized("data.migration.failed.reveal"))
        alert.addButton(withTitle: L10n.localized("data.migration.failed.dismiss"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([backupURL])
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
