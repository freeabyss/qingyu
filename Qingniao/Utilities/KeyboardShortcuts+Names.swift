import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggle the Assistant Command Bar (floating panel) visibility.
    /// Default shortcut: Option+Space (⌥ Space).
    ///
    /// Onboarding validates this binding against enabled macOS symbolic hotkeys.
    /// If it conflicts or cannot be recorded, the user must choose another
    /// successful shortcut before entering the full Assistant experience.
    ///
    /// - Note: ⌥ Space may be claimed by Spotlight / third-party launchers on
    ///   some Macs. We do NOT try to auto-resolve that in code; the settings
    ///   page surfaces a conflict warning instead (see `HotkeyConflictDetector`).
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))

    /// Capture a region of the screen (user selects area via overlay).
    /// Default shortcut: ⇧⌃⌘4 (per PRD §9.6 快捷键总表 / FR-UI-HOTKEYS).
    static let captureRegion = Self("captureRegion", default: .init(.four, modifiers: [.command, .control, .shift]))

    /// Capture the window under the mouse cursor.
    /// Default shortcut: ⇧⌃⌘5 (per PRD §9.6).
    static let captureWindow = Self("captureWindow", default: .init(.five, modifiers: [.command, .control, .shift]))

    /// Capture the entire screen.
    /// Default shortcut: ⌃⌥⌘3 (v1.2 新增, per PRD §9.6).
    static let captureFullscreen = Self("captureFullscreen", default: .init(.three, modifiers: [.control, .option, .command]))

    /// Open the clipboard-history window.
    /// Default shortcut: ⌥⌘C (v1.2 新增, per PRD §9.6).
    static let openClipboardHistory = Self("openClipboardHistory", default: .init(.c, modifiers: [.option, .command]))

    /// Open the settings / management-center window.
    /// Default shortcut: ⌥⌘, (v1.2 新增, per PRD §9.6).
    static let openSettings = Self("openSettings", default: .init(.comma, modifiers: [.option, .command]))

    /// Task 008: toggle mouse-events passthrough for all runtime pins.
    /// Not part of `managedGlobalShortcuts` (bulk reset covers the six core slots).
    static let pinToggleMouseEvents = Self("pinToggleMouseEvents")

    /// All global shortcuts managed by `GlobalShortcutManager`. Used for bulk
    /// registration, conflict scanning, and "reset to defaults".
    static let managedGlobalShortcuts: [KeyboardShortcuts.Name] = [
        .togglePanel,
        .captureRegion,
        .captureWindow,
        .captureFullscreen,
        .openClipboardHistory,
        .openSettings
    ]
}
