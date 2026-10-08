import AppKit
import SwiftUI
import os.log

/// Manages the settings / management-center window (design §16).
///
/// Hosts `ManagementCenterView` (what `SettingsView` renders) with view models
/// owned by this controller, so `show(route:)` can navigate directly via
/// `SettingsViewModel.select(route:)` without round-tripping through the
/// `.openManagementCenter` notification (which would recurse with the
/// AppDelegate observer). The window is created on first show and reused.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let logger = Logger.app
    private unowned let container: AppContainer

    private var settingsViewModel: SettingsViewModel?

    init(container: AppContainer) {
        self.container = container
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(route: SettingsRoute = .general) {
        // Activate first: as an LSUIElement app, `makeKeyAndOrderFront` before
        // the process is frontmost often fails the first time (window is
        // created/ordered but never becomes key — user must click again).
        activateApp()

        container.commandBarController.hide(animate: false)
        container.clipboardHistoryWindowController.hide()
        container.registerBuiltInPlugins()

        if window == nil {
            let settingsViewModel = SettingsViewModel(pluginRegistry: container.pluginRegistry)
            settingsViewModel.select(route: route)
            self.settingsViewModel = settingsViewModel

            let view = ManagementCenterView(viewModel: settingsViewModel)
                .tint(JadeColor.primary) // 全局主色注入（Design Token T-004）
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // 参考系统设置的侧栏一体式外观：不显示「管理中心」标题文字，
            // 红绿灯叠在侧栏上方；标题栏透明 + 可拖动背景保持移动能力。
            window.title = L10n.localized("management.title")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentMinSize = NSSize(width: 920, height: 640)
            window.center()
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            // No toolbar / sidebar-toggle — settings uses a fixed two-column layout.
            window.toolbar = nil
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            self.window = window
            logger.info("Settings window created")
        } else {
            settingsViewModel?.select(route: route)
            window?.toolbar = nil
        }

        bringSettingsWindowForward()

        // Layout/hosting can finish one run loop after first show; re-front once.
        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsWindowForward()
        }
    }

    private func bringSettingsWindowForward() {
        guard let window else { return }
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        logger.debug("Settings window brought forward")
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
