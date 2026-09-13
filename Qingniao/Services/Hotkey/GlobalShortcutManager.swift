import AppKit
import Foundation
import KeyboardShortcuts
import os.log

/// v1.2 (T-008) unified global-shortcut registrar (App Shell layer, api.md §17).
///
/// Owns the wiring between the six user-rebindable global shortcuts and their
/// actions. It replaces the ad-hoc `KeyboardShortcuts.onKeyUp` calls that used
/// to live inline in `AppDelegate`.
///
/// Default bindings (PRD「截图与贴图」/ Task 009):
///   - togglePanel          = ⌥ Space
///   - startScreenshot      = F1      (single screenshot entry, modes auto-detected)
///   - openClipboardHistory = ⌥⌘C
///   - openSettings         = ⌥⌘,
///
/// User customizations are persisted automatically by `KeyboardShortcuts` via
/// `UserDefaults`; this manager only re-attaches the handlers on each launch.
@MainActor
final class GlobalShortcutManager {
    private let logger = Logger.app
    private unowned let container: AppContainer

    /// Basic conflict detection surfaced to the settings page.
    let conflictDetector: HotkeyConflictDetector

    init(container: AppContainer, conflictDetector: HotkeyConflictDetector? = nil) {
        self.container = container
        self.conflictDetector = conflictDetector ?? HotkeyConflictDetector()
    }

    // MARK: - Bulk lifecycle

    /// Registers all global shortcuts and refreshes conflict state. Defaults
    /// are applied automatically by `KeyboardShortcuts.Name(default:)`; persisted
    /// user overrides win.
    func setupShortcuts() {
        registerSearchToggle()
        registerScreenshot()
        registerOpenClipboardHistory()
        registerOpenSettings()
        refreshConflicts()
        logger.info("Global shortcuts registered: togglePanel, startScreenshot, openClipboardHistory, openSettings")
    }

    func unregisterAll() {
        KeyboardShortcuts.disable(KeyboardShortcuts.Name.managedGlobalShortcuts)
        for name in KeyboardShortcuts.Name.managedGlobalShortcuts {
            KeyboardShortcuts.onKeyUp(for: name) {}
        }
    }

    /// Re-scan managed shortcuts for conflicts (system + internal duplicates).
    func refreshConflicts() {
        conflictDetector.scan()
    }

    /// Reset every managed shortcut back to its default binding, then refresh.
    func resetAllShortcutsToDefaults() {
        KeyboardShortcuts.reset(KeyboardShortcuts.Name.managedGlobalShortcuts)
        refreshConflicts()
        logger.info("All global shortcuts reset to defaults")
    }

    // MARK: - Individual registration (api.md GlobalShortcutManagerProtocol)

    func registerSearchToggle() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            Task { @MainActor in self?.container.commandBarController.toggle() }
        }
    }

    func registerScreenshot() {
        KeyboardShortcuts.onKeyUp(for: .startScreenshot) { [weak self] in
            Task { @MainActor in self?.container.screenshotWindowController.startCapture() }
        }
    }

    func registerOpenClipboardHistory() {
        KeyboardShortcuts.onKeyUp(for: .openClipboardHistory) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.container.clipboardHistoryWindowController.show()
            }
        }
    }

    func registerOpenSettings() {
        KeyboardShortcuts.onKeyUp(for: .openSettings) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.container.settingsWindowController.show(route: .general)
            }
        }
    }
}
