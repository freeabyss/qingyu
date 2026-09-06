import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import KeyboardShortcuts

/// The distinct global-shortcut slots managed by `GlobalShortcutManager`
/// (mirrors `KeyboardShortcuts.Name.managedGlobalShortcuts`, api.md §17).
enum HotkeyAction: Hashable, CaseIterable {
    case search
    case regionCapture
    case windowCapture
    case fullscreenCapture
    case openClipboard
    case openSettings

    /// The `KeyboardShortcuts.Name` this action is bound to.
    var name: KeyboardShortcuts.Name {
        switch self {
        case .search: return .togglePanel
        case .regionCapture: return .captureRegion
        case .windowCapture: return .captureWindow
        case .fullscreenCapture: return .captureFullscreen
        case .openClipboard: return .openClipboardHistory
        case .openSettings: return .openSettings
        }
    }

    init?(name: KeyboardShortcuts.Name) {
        guard let match = HotkeyAction.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// Outcome of evaluating a candidate shortcut for a slot (api.md §17).
enum HotkeyRegistrationOutcome: Hashable {
    case registered
    /// Carries a localized, user-facing conflict description for the settings row.
    case conflict(String)
}

/// v1.2 (T-008) basic conflict detector.
///
/// `KeyboardShortcuts` persists and registers shortcuts through Carbon under the
/// hood, but it does not surface *why* a chosen combination is unavailable. This
/// detector layers a lightweight, testable check on top so the settings page can
/// show an inline red warning and offer "reset to defaults":
///
///  1. Clash with an **enabled macOS symbolic hotkey** (Spotlight, screenshots …).
///  2. **Duplicate** assignment across our own managed shortcuts.
///
/// It intentionally does not attempt to auto-resolve conflicts (per task spec:
/// ⌥ Space overlap with Spotlight is only *reported*, never rewritten).
@MainActor
protocol HotkeyConflictDetectorProtocol {
    /// Evaluate a candidate shortcut for a slot without mutating persisted state.
    func evaluate(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) -> HotkeyRegistrationOutcome
}

@MainActor
final class HotkeyConflictDetector: ObservableObject, HotkeyConflictDetectorProtocol {
    /// Names currently in conflict. Bound by the settings page for red warnings.
    @Published private(set) var conflictingNames: Set<KeyboardShortcuts.Name> = []

    /// Localized conflict message per conflicting name (for inline display).
    @Published private(set) var conflictMessages: [KeyboardShortcuts.Name: String] = [:]

    private let managedNames: [KeyboardShortcuts.Name]
    private let currentShortcutProvider: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    private let systemShortcutProvider: () -> [KeyboardShortcuts.Shortcut]

    init(
        managedNames: [KeyboardShortcuts.Name] = KeyboardShortcuts.Name.managedGlobalShortcuts,
        currentShortcutProvider: @escaping (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.getShortcut(for: $0) },
        systemShortcutProvider: @escaping () -> [KeyboardShortcuts.Shortcut] = HotkeyValidationService.enabledSystemShortcuts
    ) {
        self.managedNames = managedNames
        self.currentShortcutProvider = currentShortcutProvider
        self.systemShortcutProvider = systemShortcutProvider
    }

    /// Re-scan all managed shortcuts and refresh the published conflict state.
    /// Call after registration, after a recorder change, or after reset.
    func scan() {
        var conflicts: Set<KeyboardShortcuts.Name> = []
        var messages: [KeyboardShortcuts.Name: String] = [:]

        // Count internal duplicates by (keyCode, modifiers).
        var occupancy: [ShortcutKey: [KeyboardShortcuts.Name]] = [:]
        for name in managedNames {
            guard let shortcut = currentShortcutProvider(name) else { continue }
            occupancy[ShortcutKey(shortcut), default: []].append(name)
        }

        let system = systemShortcutProvider()

        for name in managedNames {
            let outcome = evaluate(currentShortcutProvider(name), for: name, occupancy: occupancy, systemShortcuts: system)
            if case .conflict(let message) = outcome {
                conflicts.insert(name)
                messages[name] = message
            }
        }

        conflictingNames = conflicts
        conflictMessages = messages
    }

    func evaluate(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) -> HotkeyRegistrationOutcome {
        var occupancy: [ShortcutKey: [KeyboardShortcuts.Name]] = [:]
        for other in managedNames {
            guard let existing = currentShortcutProvider(other) else { continue }
            occupancy[ShortcutKey(existing), default: []].append(other)
        }
        // Ensure the candidate itself is represented for the target name.
        if let shortcut {
            var names = occupancy[ShortcutKey(shortcut)] ?? []
            if !names.contains(name) { names.append(name) }
            occupancy[ShortcutKey(shortcut)] = names
        }
        return evaluate(shortcut, for: name, occupancy: occupancy, systemShortcuts: systemShortcutProvider())
    }

    // MARK: - Core evaluation

    private func evaluate(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for name: KeyboardShortcuts.Name,
        occupancy: [ShortcutKey: [KeyboardShortcuts.Name]],
        systemShortcuts: [KeyboardShortcuts.Shortcut]
    ) -> HotkeyRegistrationOutcome {
        guard let shortcut else { return .registered }

        // 1. Internal duplicate across our own shortcuts.
        if let sharing = occupancy[ShortcutKey(shortcut)], sharing.count > 1 {
            return .conflict(L10n.localized("management.shortcuts.conflict.internal"))
        }

        // 2. Enabled macOS symbolic hotkey clash.
        if systemShortcuts.contains(where: { $0.carbonKeyCode == shortcut.carbonKeyCode && $0.carbonModifiers == shortcut.carbonModifiers }) {
            return .conflict(L10n.localized("management.shortcuts.conflict.system"))
        }

        return .registered
    }

    /// Hashable (keyCode, modifiers) pair, used to detect duplicate assignments.
    private struct ShortcutKey: Hashable {
        let keyCode: Int
        let modifiers: Int
        init(_ shortcut: KeyboardShortcuts.Shortcut) {
            keyCode = shortcut.carbonKeyCode
            modifiers = shortcut.carbonModifiers
        }
    }
}
