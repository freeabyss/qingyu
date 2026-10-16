import SwiftUI
import AppKit

/// A transparent NSView that intercepts key events for keyboard navigation.
///
/// Used as an overlay on the main content view to handle arrow keys and Enter
/// for search result navigation, compatible with macOS 13+.
struct KeyEventHandler: NSViewRepresentable {
    /// 只处理已传入的按键：未提供的回调不会吞掉该按键，避免遮挡同窗口内的
    /// 其他 SwiftUI `keyboardShortcut`（例如剪贴板窗口的 j/k/⌘C）。
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTab: (() -> Void)?

    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView()
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.onTab = onTab
        return view
    }

    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        nsView.onTab = onTab
    }
}

/// Custom NSView that accepts first responder and intercepts key events.
class KeyEventNSView: NSView {
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTab: (() -> Void)?
    private var keyEventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeKeyEventMonitor()
        guard window != nil else { return }

        // The command bar's text field normally owns first responder, so this
        // transparent NSView never receives keyDown directly. A window-scoped
        // local monitor observes navigation keys before AppKit dispatches them
        // to the focused text field.
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    deinit {
        removeKeyEventMonitor()
    }

    override func keyDown(with event: NSEvent) {
        if handle(event) { return }
        super.keyDown(with: event)
    }

    /// Whether the focused text client is mid IME composition (marked text).
    ///
    /// Chinese/Japanese IMEs stage pinyin as marked text; Enter commits the
    /// staged letters, ↑↓ pick candidates, Space/Tab advance, Esc cancels.
    /// Intercepting those keys here would swallow the commit and leave the
    /// search field empty ("Enter does nothing").
    private func fieldHasMarkedText(in window: NSWindow?) -> Bool {
        guard let window,
              let client = window.firstResponder as? NSTextInputClient
        else { return false }
        return client.hasMarkedText()
    }

    /// Whether this view handles `event`. Internal (not private) so tests can
    /// lock the "consume only keys that have a handler" contract.
    func handle(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }

        // Forward every plain key to the text field while an IME is composing.
        if fieldHasMarkedText(in: event.window) {
            return false
        }

        switch event.keyCode {
        case 126: // Up arrow
            guard let onUpArrow else { return false }
            onUpArrow()
            return true
        case 125: // Down arrow
            guard let onDownArrow else { return false }
            onDownArrow()
            return true
        case 36: // Return/Enter
            guard let onReturn else { return false }
            onReturn()
            return true
        case 53: // Escape
            guard let onEscape else { return false }
            onEscape()
            return true
        case 48: // Tab
            guard let onTab else { return false }
            onTab()
            return true
        default:
            return false
        }
    }

    private func removeKeyEventMonitor() {
        guard let keyEventMonitor else { return }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }
}
