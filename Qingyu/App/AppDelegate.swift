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

    /// Records the app version whose downloaded `.dmg` was already cleaned up,
    /// so the cleanup runs at most once per installed version.
    private static let installerCleanupVersionKey = "installerCleanup.lastVersion"

    #if DEBUG
    /// Parsed UITest launch arguments. Non-nil only when at least one
    /// `--uitest-*` argument is present (review C-1).
    private var uitestSupport: UITestSupport?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Qingyu launching")

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
        // onboarding 仅在首启自动展示。
        container.statusItemController.onStartScreenshot = { [weak self] in
            self?.container.screenshotWindowController.startCapture()
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
        cleanupDownloadedInstallersIfNeeded()

        #if DEBUG
        if let uitest = uitestSupport, let action = uitest.validatedTriggerAction {
            // Defer trigger to next run-loop so launch setup completes first.
            DispatchQueue.main.async { [weak self] in
                self?.handleUITestTrigger(action)
            }
        }
        #endif

        #if DEBUG
        // 设计评审用：把真实窗口自绘成 PNG 后退出。
        //
        // 屏幕录制权限拿不到时 screencapture 只能得到 "could not create image from display"，
        // 而 TextField / Toggle / List 这些 AppKit 控件在 SwiftUI 的 ImageRenderer 里只能画成
        // 黄色占位块——两条路都看不到真实外观。让窗口自己把自己画出来，绕开屏幕录制，
        // 拿到的是真实布局与真实控件。仅 DEBUG 生效，且必须显式传参。
        // 放大字号变体：让 --uitest-large-text 真正生效。
        // 设计 token 用的是固定字号，不随系统字号变化；把这个因子调到 1.35，
        // 才能真的检验「放大字号下布局是否还站得住」。
        if uitestSupport?.largeText == true {
            JadeFont.scale = 1.35
        }

        // 深色评审：DEBUG 下强制 NSApp 外观，用来截深色模式下的真实窗口。
        // 系统级改外观会影响用户整台机器，不能这么做；per-app defaults 对 LSUIElement 应用无效。
        // --uitest-search-slow <seconds>：把搜索人为放慢，用来截「搜索中」状态。
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--uitest-search-slow"),
           index + 1 < ProcessInfo.processInfo.arguments.count,
           let seconds = TimeInterval(ProcessInfo.processInfo.arguments[index + 1]) {
            SearchPanelViewModel.debugSearchDelay = seconds
        }

        if ProcessInfo.processInfo.arguments.contains("--uitest-dark-appearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        // --uitest-open-pin：用一张生成的图片打开贴图窗口，用来评审贴图界面。
        // 真实入口依赖截图会话（需要屏幕录制授权），这条路径绕开它。
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-pin") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, let data = Self.makePinSampleImageData() else { return }
                _ = self.container.pinWindowController.present(payload: .image(data))
            }
        }

        if let path = Self.capturePNGPath() {
            let delay = Self.captureDelay()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.captureFrontmostWindow(to: path)
            }
        }
        #endif

        logger.info("Qingyu launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Qingyu terminating")
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

    /// --uitest-capture-png <path>：取其后一个参数作为输出路径。
    private static func capturePNGPath() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-capture-png"),
              index + 1 < args.count,
              !args[index + 1].hasPrefix("--") else { return nil }
        return args[index + 1]
    }

    /// 把每个滚动文档单独画成 PNG（<base>-scrollN.png）。
    private static func captureScrollDocuments(in root: NSView, basePath: String) {
        var documents: [NSView] = []
        func walk(_ view: NSView) {
            if let clip = view as? NSClipView, let document = clip.documentView,
               document.bounds.width >= 200, document.bounds.height >= 200 {
                documents.append(document)
            }
            view.subviews.forEach(walk)
        }
        walk(root)

        let base = URL(fileURLWithPath: basePath).deletingPathExtension()
        for (index, document) in documents.enumerated() {
            guard let rep = document.bitmapImageRepForCachingDisplay(in: document.bounds) else { continue }
            document.effectiveAppearance.performAsCurrentDrawingAppearance {
                document.cacheDisplay(in: document.bounds, to: rep)
            }
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: base.appendingPathExtension("scroll\(index).png"))
        }
    }

    /// 递归转储视图层级（类名 + frame），用于诊断「截图里某块区域是空白」。
    private static func describe(_ view: NSView, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let frame = NSStringFromRect(view.frame)
        var line = "\(indent)\(type(of: view)) \(frame) hidden=\(view.isHidden) alpha=\(view.alphaValue)\n"
        for subview in view.subviews {
            line += describe(subview, depth: depth + 1)
        }
        return line
    }

    /// --uitest-toast <text>：在剪贴板窗口里显示的 toast 文案。
    private static func toastMessageArgument() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-toast"),
              index + 1 < args.count,
              !args[index + 1].hasPrefix("--") else { return nil }
        return args[index + 1]
    }

    /// --uitest-search-query <text>：命令栏查询串。
    private static func searchQueryArgument() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-search-query"),
              index + 1 < args.count,
              !args[index + 1].hasPrefix("--") else { return nil }
        return args[index + 1]
    }

    /// --uitest-window-size 1000x700：截图前的窗口内容尺寸。
    private static func windowSizeArgument() -> NSSize? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-window-size"),
              index + 1 < args.count else { return nil }
        let parts = args[index + 1].lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]) else { return nil }
        return NSSize(width: width, height: height)
    }

    /// --uitest-capture-delay <seconds>：截图前等待秒数，默认 1.5。
    private static func captureDelay() -> TimeInterval {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-capture-delay"),
              index + 1 < args.count,
              let value = TimeInterval(args[index + 1]) else { return 1.5 }
        return value
    }

    /// 生成一张用于贴图评审的示例图片（渐变 + 文字）。
    private static func makePinSampleImageData() -> Data? {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.30, green: 0.39, blue: 0.53, alpha: 1),
            NSColor(srgbRed: 0.69, green: 0.77, blue: 0.87, alpha: 1)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -45)
        let text = "贴图预览 · Pin Preview" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attributes
        )
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// 把当前最大的可见窗口自绘为 PNG 并退出应用。
    ///
    /// 用 cacheDisplay(in:to:) 而不是截屏 API：它走视图自己的绘制路径，
    /// AppKit 控件（输入框、开关、侧栏列表）都会真实绘制出来。
    @MainActor
    private func captureFrontmostWindow(to path: String, attempt: Int = 0) {
        let candidates = NSApp.windows.filter { window in
            guard window.isVisible, let view = window.contentView else { return false }
            // 命令栏收起时只有 760×56，门槛放低才能截到它。
            return view.bounds.width >= 200 && view.bounds.height >= 40
        }
        guard let window = candidates.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }), let view = window.contentView else {
            // 窗口还没就绪就放弃，会得到「什么都没截到」的空结果；
            // 浮层（命令栏）尤其容易赶在窗口出现前被检查。重试几秒再放弃。
            guard attempt < 12 else {
                logger.error("UITest capture: no visible window to capture")
                NSApp.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.captureFrontmostWindow(to: path, attempt: attempt + 1)
            }
            return
        }

        // --uitest-window-size WxH：截图前把窗口改成指定内容尺寸，
        // 用来验证大窗口下的布局（响应式一直只在最小尺寸上看过）。
        if let size = Self.windowSizeArgument() {
            window.setContentSize(size)
        }

        // 非活动窗口会把系统控件画成灰态（开关的强调色会退成灰），
        // 那样的图会让人误判成「开关关闭 / 按钮被禁用」。
        // 激活是异步的：先激活，等一个 run loop 周期后再画。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.drawWindow(window, view: view, to: path)
        }
    }

    @MainActor
    private func drawWindow(_ window: NSWindow, view: NSView, to path: String) {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            logger.error("UITest capture: bitmap rep unavailable")
            NSApp.terminate(nil)
            return
        }
        // 必须在窗口自身外观下绘制：否则动态 NSColor（Jade 品牌色/语义色）会按
        // 浅色解析，深色截图里的开关、分段控件会显示成浅色模式的强调色。
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            logger.error("UITest capture: PNG encoding failed")
            NSApp.terminate(nil)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: path))
            // 同时写一份 PDF：cacheDisplay 走的是屏幕绘制路径，某些图层可能被跳过；
            // dataWithPDF 走打印路径，两者对照就能区分「界面真的空白」和「截图方式漏画」。
            let pdfURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("pdf")
            try? view.dataWithPDF(inside: bounds).write(to: pdfURL)
            // 视图层级转储：空白区域到底是「没画」还是「根本没有这个视图」，
            // 只能靠 frames 判断。
            let dumpURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("txt")
            try? Self.describe(view, depth: 0).write(to: dumpURL, atomically: true, encoding: .utf8)

            // cacheDisplay 会跳过 PlatformContainer 里的滚动内容（窗口 PNG 里那块会显示为空白），
            // 但内容本身是存在的。逐个把滚动文档单独画出来，才能评审真实的设置页排版。
            Self.captureScrollDocuments(in: view, basePath: path)
            logger.info("UITest capture wrote \(path, privacy: .public)")
        } catch {
            logger.error("UITest capture write failed \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    /// Dispatches `--uitest-trigger <action>` to the corresponding controller,
    /// bypassing the status-item menu (design §5.5, cases.md §0.4).
    @MainActor
    private func handleUITestTrigger(_ action: UITestTriggerAction) {
        switch action {
        case .openSearch:
            container.commandBarController.show()
            // --uitest-search-query <text>：注入查询，截「有结果」的命令栏。
            if let query = Self.searchQueryArgument() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.container.commandBarController.debugSetQuery(query)
                }
            }
        case .openClipboard:
            container.clipboardHistoryWindowController.show()
            // --uitest-toast <text>：在真实窗口里显示一条 toast，用来截取交互反馈。
            if let message = Self.toastMessageArgument() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.container.clipboardHistoryWindowController
                        .debugShowToast(message, variant: .success)
                }
            }
        case .openSettings:
            container.settingsWindowController.show(route: .general)
        case .openAbout:
            container.settingsWindowController.show(route: .about)
        case .openQuickLaunch:
            container.settingsWindowController.show(route: .quickLaunch)
        case .openOnboarding:
            showOnboardingWindow()
        case .startScreenshot:
            // 与 statusItemController.onStartScreenshot 闭包调用同一方法
            // （cases.md §0.4）；配合 --uitest-skip-screenshot-capture 仅测入口可达。
            container.screenshotWindowController.startCapture()
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

    // MARK: - Installer cleanup

    /// Moves our own downloaded installer (`.dmg`) to the Trash once the app is
    /// installed under `/Applications`. This implements the "安装完毕后自动删除
    /// 安装包" promise without ever hard-deleting user files: the archive is
    /// recycled, so it stays recoverable from the Trash.
    ///
    /// Guard rails: it only runs when the running bundle lives in
    /// `/Applications`, only touches files named `Qingyu-*.dmg`, and runs at
    /// most once per installed version.
    @MainActor
    private func cleanupDownloadedInstallersIfNeeded() {
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        guard appPath.hasPrefix("/Applications/") else { return }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        guard UserDefaults.standard.string(forKey: Self.installerCleanupVersionKey) != version else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let searchDirectories = ["Downloads", "Desktop"].map { home.appendingPathComponent($0, isDirectory: true) }
        let removed = InstallerCleanup.removeDownloadedInstallers(in: searchDirectories) { url in
            NSWorkspace.shared.recycle([url], completionHandler: nil)
        }
        if !removed.isEmpty {
            logger.info("Installer cleanup recycled \(removed.count) archive(s): \(removed.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")
        }
        UserDefaults.standard.set(version, forKey: Self.installerCleanupVersionKey)
    }
}

/// Pure helpers for the post-install cleanup of the downloaded `.dmg`.
/// `AppDelegate` wires them to `NSWorkspace.recycle`; tests inject a recorder.
enum InstallerCleanup {
    /// Matches the installer file names produced by `scripts/package-release.sh`
    /// (`Qingyu-<version>.dmg`, `Qingyu-<version>-universal.dmg`, …).
    static func isOwnInstallerName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.hasPrefix("qingyu-") && lowercased.hasSuffix(".dmg")
    }

    /// Recycles every matching installer found in `searchDirectories` and
    /// returns the files handed to `recycle`. Missing directories are ignored.
    @discardableResult
    static func removeDownloadedInstallers(
        in searchDirectories: [URL],
        fileManager: FileManager = .default,
        recycle: (URL) -> Void
    ) -> [URL] {
        var removed: [URL] = []
        for directory in searchDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries where isOwnInstallerName(url.lastPathComponent) {
                recycle(url)
                removed.append(url)
            }
        }
        return removed
    }
}

/// 语言切换后的自动重启入口。
///
/// `AppleLanguages` 只在进程启动时被 `Bundle` 读一次，改语言无法热生效，因此
/// 直接把当前 App 重新拉起来、再退出自己，用户不需要手动退出重开。
///
/// 关键在于 `createsNewApplicationInstance = true`：没有它，系统只会把已有的
/// 旧进程激活到前台，语言覆盖永远不生效。重启失败时仍然退出——宁可让用户
/// 手动再打开一次，也不能留下两个并存进程。
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                Logger.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
