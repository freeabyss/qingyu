import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

protocol HotkeyValidationServiceProtocol {
    func currentShortcut() -> KeyboardShortcuts.Shortcut?
    func validateCurrentShortcut() -> HotkeyValidationResult
    func persistCurrentShortcutString() -> String
}

enum HotkeyValidationResult: String, Codable, Hashable {
    case valid
    case conflict
    case invalid
}

/// Validates the current Assistant search shortcut against enabled macOS symbolic hotkeys.
///
/// KeyboardShortcuts handles recording and registration. This service makes the conflict
/// decision testable for Onboarding and prevents completing setup with a missing or
/// system-reserved key combination.
final class HotkeyValidationService: HotkeyValidationServiceProtocol {
    private let shortcutProvider: () -> KeyboardShortcuts.Shortcut?
    private let systemShortcutProvider: () -> [KeyboardShortcuts.Shortcut]

    init(
        shortcutProvider: @escaping () -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.Shortcut(name: .togglePanel) },
        systemShortcutProvider: @escaping () -> [KeyboardShortcuts.Shortcut] = HotkeyValidationService.enabledSystemShortcuts
    ) {
        self.shortcutProvider = shortcutProvider
        self.systemShortcutProvider = systemShortcutProvider
    }

    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        shortcutProvider()
    }

    func validateCurrentShortcut() -> HotkeyValidationResult {
        guard let shortcut = currentShortcut() else { return .invalid }
        guard shortcut.carbonKeyCode >= 0, shortcut.carbonModifiers != 0 else { return .invalid }
        return systemShortcutProvider().contains(shortcut) ? .conflict : .valid
    }

    func persistCurrentShortcutString() -> String {
        guard let shortcut = currentShortcut() else { return "" }
        if shortcut.carbonKeyCode == KeyboardShortcuts.Shortcut(.space, modifiers: [.option]).carbonKeyCode,
           shortcut.carbonModifiers == KeyboardShortcuts.Shortcut(.space, modifiers: [.option]).carbonModifiers {
            return "option+space"
        }
        return "carbon:\(shortcut.carbonKeyCode):\(shortcut.carbonModifiers)"
    }

    static func enabledSystemShortcuts() -> [KeyboardShortcuts.Shortcut] {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
              let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        return shortcuts.compactMap { item in
            guard (item[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let keyCode = item[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = item[kHISymbolicHotKeyModifiers] as? Int else {
                return nil
            }
            return KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers)
        }
    }
}
