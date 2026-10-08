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
    ///
    /// 1.0.0 FeatureGate：截图快捷键（F1）不注册，故同步从该列表剔除，
    /// 保持「未注册的 Name 不参与冲突扫描 / 批量重置」的现有语义。
    /// Name 定义与默认键位保留，开关恢复后自动回到四槽位。
    static var managedGlobalShortcuts: [KeyboardShortcuts.Name] {
        FeatureGate.screenshotEnabled
            ? [.togglePanel, .startScreenshot, .openClipboardHistory, .openSettings]
            : [.togglePanel, .openClipboardHistory, .openSettings]
    }
}
