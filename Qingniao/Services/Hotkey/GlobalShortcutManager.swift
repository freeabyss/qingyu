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
/// Default bindings (PRD §9.6):
///   - togglePanel          = ⌥ Space
///   - captureRegion        = ⇧⌃⌘4
///   - captureWindow        = ⇧⌃⌘5
///   - captureFullscreen    = ⌃⌥⌘3   (v1.2 新增 → ScreenshotService.captureScreen)
///   - openClipboardHistory = ⌥⌘C    (v1.2 新增)
///   - openSettings         = ⌥⌘,    (v1.2 新增)
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

    /// Registers all six global shortcuts and refreshes conflict state. Defaults
    /// are applied automatically by `KeyboardShortcuts.Name(default:)`; persisted
    /// user overrides win.
    func setupShortcuts() {
        registerSearchToggle()
        registerRegionCapture()
        registerWindowCapture()
        registerFullscreenCapture()
        registerOpenClipboardHistory()
        registerOpenSettings()
        refreshConflicts()
        logger.info("Global shortcuts registered: togglePanel, captureRegion, captureWindow, captureFullscreen, openClipboardHistory, openSettings")
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

    func registerRegionCapture() {
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [weak self] in
            Task { @MainActor in self?.container.screenshotWindowController.captureRegion() }
        }
    }

    func registerWindowCapture() {
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { @MainActor in self?.container.screenshotWindowController.captureWindow() }
        }
    }

    func registerFullscreenCapture() {
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { @MainActor in self?.container.screenshotWindowController.captureFullScreen() }
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
