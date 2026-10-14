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
            // 优先使用打包的 MenuBarIcon（jade 羽毛模板图标），
            // 若资源缺失则回退到系统 `feather` SF Symbol。
            let icon = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "leaf", accessibilityDescription: "清羽 Qingyu")
            icon?.isTemplate = true
            button.image = icon
            button.image?.accessibilityDescription = "清羽 Qingyu"
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

        // 1.0.0 FeatureGate：截图入口整体隐藏，菜单不出现「截图」项；
        // 代码保留，开关恢复后自动回到菜单。
        if FeatureGate.screenshotEnabled {
            let screenshot = NSMenuItem(title: L10n.localized("menubar.screenshot"), action: #selector(startScreenshotFromMenu), keyEquivalent: "")
            screenshot.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
            screenshot.target = self
            screenshot.setAccessibilityIdentifier("menubar.screenshot")
            menu.addItem(screenshot)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.localized("menubar.settings"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.target = self
        settings.setAccessibilityIdentifier("menubar.settings")
        menu.addItem(settings)

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

    @objc private func quitFromMenu() {
        logger.info("Quit selected from status menu")
        NSApp.terminate(nil)
    }
}
