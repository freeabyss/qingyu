import AppKit
import os.log

/// Owns the menu-bar `NSStatusItem` and its menu (design §2.5).
///
/// The menu items forward to the window/command controllers resolved from
/// `AppContainer`; this controller holds no business logic.
@MainActor
final class StatusItemController: NSObject {
    private let logger = Logger.app
    private unowned let container: AppContainer

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    /// Invoked when a screenshot is requested from the menu.
    var onStartScreenshot: (() -> Void)?

    /// Invoked when the user re-opens the onboarding guide from the menu
    /// (v1.2.1, PRD §4.3 / AC-11). Re-opening does not reset completion state.
    var onShowOnboarding: (() -> Void)?

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    /// Installs the status-bar item and builds its menu. Idempotent.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusMenu = makeMenu()

        if let button = item.button {
            // 优先使用打包的 MenuBarIcon（jade bird 占位模板图标），
            // 若资源缺失则回退到系统 `bird` SF Symbol（同为模板渲染，跟随菜单栏明暗）。
            let icon = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "bird", accessibilityDescription: "青鸟 Qingniao")
            icon?.isTemplate = true
            button.image = icon
            button.image?.accessibilityDescription = "青鸟 Qingniao"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem = item
        logger.info("Status item installed")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.localized("menubar.appTitle"))
        menu.autoenablesItems = true

        let openSearch = NSMenuItem(title: L10n.localized("menubar.openSearch"), action: #selector(openSearchFromMenu), keyEquivalent: "")
        openSearch.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        openSearch.target = self
        openSearch.setAccessibilityIdentifier("menubar.openSearch")
        menu.addItem(openSearch)

        let clipboard = NSMenuItem(title: L10n.localized("menubar.clipboard"), action: #selector(openClipboardFromMenu), keyEquivalent: "")
        clipboard.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
        clipboard.target = self
        clipboard.setAccessibilityIdentifier("menubar.clipboard")
        menu.addItem(clipboard)

        let screenshot = NSMenuItem(title: L10n.localized("menubar.screenshot"), action: #selector(startScreenshotFromMenu), keyEquivalent: "")
        screenshot.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        screenshot.target = self
        screenshot.setAccessibilityIdentifier("menubar.screenshot")
        menu.addItem(screenshot)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.localized("menubar.settings"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.target = self
        settings.setAccessibilityIdentifier("menubar.settings")
        menu.addItem(settings)

        let about = NSMenuItem(title: L10n.localized("menubar.about"), action: #selector(openAboutFromMenu), keyEquivalent: "")
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        about.target = self
        about.setAccessibilityIdentifier("menubar.about")
        menu.addItem(about)

        let onboarding = NSMenuItem(title: L10n.localized("menubar.onboarding"), action: #selector(openOnboardingFromMenu), keyEquivalent: "")
        onboarding.image = NSImage(systemSymbolName: "bird", accessibilityDescription: nil)
        onboarding.target = self
        onboarding.setAccessibilityIdentifier("menubar.onboarding")
        menu.addItem(onboarding)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.localized("menubar.quit"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quit.target = self
        quit.setAccessibilityIdentifier("menubar.quit")
        menu.addItem(quit)

        return menu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        logger.info("Status bar menu opened")
        guard let statusItem else { return }
        statusItem.menu = statusMenu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSearchFromMenu() {
        logger.info("Open Search selected from status menu")
        container.commandBarController.show()
    }

    @objc private func openClipboardFromMenu() {
        logger.info("Clipboard selected from status menu")
        container.clipboardHistoryWindowController.show()
    }

    @objc private func startScreenshotFromMenu() {
        logger.info("Screenshot selected from status menu")
        onStartScreenshot?()
    }

    @objc private func openSettingsFromMenu() {
        logger.info("Settings selected from status menu")
        container.settingsWindowController.show(route: .general)
    }

    @objc private func openAboutFromMenu() {
        logger.info("About selected from status menu")
        container.settingsWindowController.show(route: .about)
    }

    @objc private func openOnboardingFromMenu() {
        logger.info("Onboarding guide selected from status menu")
        onShowOnboarding?()
    }

    @objc private func quitFromMenu() {
        logger.info("Quit selected from status menu")
        NSApp.terminate(nil)
    }
}
