import AppKit
import SwiftUI
import os.log

/// Manages the clipboard history window (design §16).
///
/// Hosts the existing `ClipboardListView`. The window is created on first show
/// and reused afterwards (hidden, not released) to preserve state.
@MainActor
final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let logger = Logger.app
    private unowned let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        container.commandBarController.hide(animate: false)

        if window == nil {
            let viewModel = container.makeClipboardListViewModel()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            let view = ClipboardHistoryView(
                viewModel: viewModel,
                onCopyAndClose: { [weak window] in window?.close() },
                onOpenSettings: { [weak self] in self?.container.settingsWindowController.show(route: .general) }
            )
                .tint(JadeColor.primary) // 全局主色注入（Design Token T-004）
            window.title = L10n.localized("management.page.clipboard")
            window.contentMinSize = NSSize(width: 680, height: 460)
            window.center()
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            logger.info("Clipboard history window created")
        }

        window?.makeKeyAndOrderFront(nil)
        activateApp()
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
