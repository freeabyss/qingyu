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

    /// Start the single unified screenshot session (PRD「截图与贴图」规则 1；
    /// Task 009：F1 开始截图）。Region / window / full-display modes are decided
    /// automatically inside the session.
    static let startScreenshot = Self("startScreenshot", default: .init(.f1))

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
        .startScreenshot,
        .openClipboardHistory,
        .openSettings
    ]
}
