import SwiftUI
import AppKit

/// Notifications used by the floating search panel.
///
/// Relocated from the removed `MenuBarView.swift` (T-005). `focusSearchField`
/// requests the search text field to become first responder; `checkForUpdates`
/// triggers a manual update check.
extension Notification.Name {
    static let focusSearchField = Notification.Name("Assistant.focusSearchField")
    /// Clipboard history window: put the caret in its search field on open.
    static let focusClipboardSearchField = Notification.Name("com.freeabyss.qingyu.focusClipboardSearchField")
    static let checkForUpdates = Notification.Name("Assistant.checkForUpdates")
}

// MARK: - AutoFocusTextField

/// A custom NSTextField wrapper that can programmatically become first responder.
/// Used instead of SwiftUI's TextField for reliable keyboard focus in borderless windows.
///
/// Relocated from the removed `MenuBarView.swift` (T-005). Retained as a reusable
/// focus-driving text field; the T-011 `CommandBarView` uses a native SwiftUI
/// `TextField` with `@FocusState` instead.
struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 16)
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        context.coordinator.setTextField(textField)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: AutoFocusTextField
        var focusObserver: NSObjectProtocol?

        init(_ parent: AutoFocusTextField) {
            self.parent = parent
        }

        func setTextField(_ textField: NSTextField) {
            // Listen for focus requests
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusSearchField,
                object: nil,
                queue: .main
            ) { [weak textField] _ in
                guard let textField = textField,
                      let window = textField.window else { return }
                window.makeFirstResponder(textField)
            }
        }

        deinit {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        if let observer = coordinator.focusObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.focusObserver = nil
        }
    }
}
