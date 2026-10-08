import AppKit
import SwiftUI
import os.log

/// Borderless panel that can become key (search field needs keyboard focus).
final class FloatingClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Borderless clipboard history window — chrome-free like the command bar.
/// Title bar / traffic lights are gone; the window is moved by dragging the
/// content background and stays resizable from the edges.
@MainActor
final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let logger = Logger.app
    private unowned let container: AppContainer
    private var viewModel: ClipboardListViewModel?

    init(container: AppContainer) {
        self.container = container
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        // Mutual exclusion with the command bar — never stack both floating UIs.
        container.commandBarController.hide(animate: false)

        if window == nil {
            let viewModel = container.makeClipboardListViewModel()
            self.viewModel = viewModel
            let window = FloatingClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            let view = ClipboardHistoryView(
                viewModel: viewModel,
                onCopyAndClose: { [weak window] in window?.close() }
            )
            .tint(JadeColor.primary)
            window.contentMinSize = NSSize(width: 720, height: 420)
            window.center()
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.delegate = self
            self.window = window
            logger.info("Clipboard history window created")
        }

        window?.makeKeyAndOrderFront(nil)
        activateApp()
        // Clear search every open and reload history.
        if let viewModel {
            Task { await viewModel.prepareForShow() }
        }
        // Put the caret in the search field (SwiftUI + AppKit, same pattern as
        // the command bar). Timed retries cover first-layout races.
        focusSearchField(force: true)
        for delay in [0.05, 0.2, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.focusSearchField()
            }
        }
    }

    func hide() {
        guard let window else { return }
        // orderOut alone can leave a floating panel "stacked" visually when the
        // command bar takes key — force a full hide.
        window.orderOut(nil)
        window.resignKey()
        logger.debug("Clipboard history window hidden")
    }

    /// Focus the clipboard search field. `force` retries makeFirstResponder even
    /// when SwiftUI already flipped `@FocusState`, so the caret always appears.
    private func focusSearchField(force: Bool = false) {
        guard let window, window.isVisible else { return }

        if let field = firstFocusableTextField(in: window.contentView) {
            let current = window.firstResponder
            let already = current === field || (field.currentEditor() != nil && current === field.currentEditor())
            if force || !already {
                window.makeFirstResponder(field)
                if let editor = field.currentEditor() {
                    let end = (field.stringValue as NSString).length
                    editor.selectedRange = NSRange(location: end, length: 0)
                }
            }
        } else if force, let textView = firstFocusableTextView(in: window.contentView) {
            window.makeFirstResponder(textView)
        }

        NotificationCenter.default.post(name: .focusClipboardSearchField, object: nil)
    }

    private func firstFocusableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.isEnabled, !field.isHidden, field.acceptsFirstResponder {
            return field
        }
        for subview in view.subviews {
            if let field = firstFocusableTextField(in: subview) {
                return field
            }
        }
        return nil
    }

    private func firstFocusableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView,
           textView.isEditable, !textView.isHidden, textView.acceptsFirstResponder {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstFocusableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
