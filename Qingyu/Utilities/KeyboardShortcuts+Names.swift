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

    /// Task 008 / 017-02：切换贴图鼠标事件穿透。
    ///
    /// 光标下存在贴图时只作用于该贴图；否则整体切换（等价于批量切换）。
    /// 不属于 `managedGlobalShortcuts`（批量重置只覆盖四个核心槽位）。
    static let pinToggleMouseEvents = Self("pinToggleMouseEvents")

    /// Task 016：启动白板（默认 ⌥⌘W）。
    ///
    /// 与截图（F1）同属「会话入口」类，但独立成键：白板是另一类会话，
    /// 两者互斥，不能共用入口。
    static let startWhiteboard = Self("startWhiteboard", default: .init(.w, modifiers: [.option, .command]))

    /// Task 017-03：光标下贴图的缩放与不透明度。
    ///
    /// 卡片原文设想「一个热键 + 按住修饰键反向」，但全局快捷键按**精确组合**匹配，
    /// 单一组合无法在按下修饰键时改变语义；因此改为每个方向一个可重绑热键。
    /// 上下限与恢复 100% 沿用 `PinTransform` 的既有钳制与「中键复位」。
    static let pinScaleUp = Self("pinScaleUp", default: .init(.equal, modifiers: [.control, .option]))
    static let pinScaleDown = Self("pinScaleDown", default: .init(.minus, modifiers: [.control, .option]))
    static let pinOpacityUp = Self("pinOpacityUp", default: .init(.rightBracket, modifiers: [.control, .option]))
    static let pinOpacityDown = Self("pinOpacityDown", default: .init(.leftBracket, modifiers: [.control, .option]))

    /// 贴图相关的全部可重绑快捷键。
    static var pinGlobalShortcuts: [KeyboardShortcuts.Name] {
        [.pinToggleMouseEvents, .pinScaleUp, .pinScaleDown, .pinOpacityUp, .pinOpacityDown]
    }

    /// 冲突扫描覆盖的槽位：四个核心槽位 + 贴图快捷键。
    ///
    /// 与 `managedGlobalShortcuts` 分开，是因为后者的语义是「参与批量重置的核心槽位」；
    /// 贴图快捷键只参与冲突扫描，不应被核心重置改写。
    static var conflictScannedShortcuts: [KeyboardShortcuts.Name] {
        managedGlobalShortcuts + pinGlobalShortcuts + [.startWhiteboard]
    }

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
