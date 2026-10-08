import AppKit
import Combine
import SwiftUI
import os.log

/// A borderless floating panel that can become key window (for text input).
final class FloatingCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the Command Bar floating `NSPanel` (design §2.5 / §16).
///
/// Behaviour: ⌥Space toggles, ⎋ / click-outside / app-switch dismisses (via
/// resign-key + local event monitor). The hosted SwiftUI content is the Jade
/// `CommandBarView` (P-01, T-011): as wide as `CommandBarMetrics.width`, input
/// row height when there is no query, `CommandBarMetrics.resultsHeight` once a
/// query produces results. The input row keeps the position it had in the older
/// fixed-height panel, so collapsing only removes the area *below* the input.
@MainActor
final class CommandBarController: NSObject {
    private let logger = Logger.app
    private unowned let container: AppContainer

    private var panel: NSPanel?
    private var viewModel: SearchPanelViewModel?
    private var searchStateCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var isClosingPanel = false
    /// Block-based panel observers (didBecomeKey focus driver); torn down in `hide()`.
    private var panelObservers: [NSObjectProtocol] = []

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    // MARK: - Public API

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        logger.info("CommandBar show")
        // Always recreate the panel for fresh focus state.
        hide(animate: false)
        panel = nil

        // Mutual exclusion with clipboard history: never stack both floating UIs.
        // Hide first, then again after the panel is key (activation can re-front
        // a floating clipboard window if hide raced with AppKit activation).
        container.clipboardHistoryWindowController.hide()

        createPanel()

        guard let panel else {
            logger.error("Panel is still nil after createPanel()")
            return
        }

        let panelWidth = CommandBarMetrics.width
        let panelHeight = CommandBarMetrics.inputRowHeight
        // Open on the display under the pointer (multi-monitor), not NSScreen.main
        // which is often the primary screen when focus is elsewhere.
        if let screen = activeScreen() {
            let frame = screen.visibleFrame
            let x = frame.midX - panelWidth / 2
            let y = CommandBarMetrics.panelOriginY(visibleFrame: frame, panelHeight: panelHeight)
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        let viewModel = self.viewModel
        DispatchQueue.main.async { viewModel?.open() }

        activateApp()
        panel.makeKeyAndOrderFront(nil)
        // makeKey 之后再激活一次：若首次激活被前台应用延迟/忽略，面板已先成为
        // key window（nonactivating panel 也能收键），此次激活兜底把应用带到前台；
        // 激活完成时面板仍是 key window，不会触发 didResignKey 关闭。
        activateApp()
        // Activation can re-front a floating clipboard panel that we ordered out
        // a moment ago — hide it again now that the command bar is key.
        container.clipboardHistoryWindowController.hide()
        startMonitoringEvents()

        // 事件驱动聚焦：didBecomeKey 观察者在面板真正成为 key window 后立即聚焦
        // （见 registerPanelObservers）。show 路径先 force 一次，再定时重试兜底
        // SwiftUI 首次布局时序（0.45s 一档）。
        focusSearchInput(force: true)
        for delay in [0.05, 0.2, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.focusSearchInput()
            }
        }
        logger.info("CommandBar shown")
    }

    func hide(animate: Bool = true) {
        // 先摘掉面板级观察者：防止 close/orderOut 触发的 didResignKey 重入，
        // 也保证面板释放后没有陈旧的 didBecomeKey 回调引用。
        removePanelObservers()
        guard !isClosingPanel else { return }
        isClosingPanel = true
        stopMonitoringEvents()
        if animate {
            panel?.orderOut(nil)
        } else {
            panel?.close()
        }
        panel = nil
        logger.info("CommandBar hidden")
    }

    /// Whether the panel is currently on screen.
    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Panel construction

    private func createPanel() {
        let panel = FloatingCommandPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CommandBarMetrics.width,
                height: CommandBarMetrics.inputRowHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The rounded corners + material come from the SwiftUI CommandBarView
        // (radius-xxl 20 + ultraThinMaterial); the panel background is fully
        // transparent so the material shows through.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = false

        let viewModel = container.makeSearchPanelViewModel { [weak self] in
            self?.hide()
        }
        self.viewModel = viewModel

        // 用 `$query` 的流值判断，而不是重读 `viewModel.query`：`@Published`
        // 在 willSet 时发值，重读属性会拿到旧查询，面板就不会展开。
        searchStateCancellable = viewModel.$query
            .map(SearchPanelViewModel.isQueryPresent)
            .removeDuplicates()
            .sink { [weak self] shouldExpand in
                self?.resizePanel(isActive: shouldExpand)
            }

        let commandBarView = CommandBarView(viewModel: viewModel)
            .tint(JadeColor.primary) // 全局主色注入（Design Token T-004）
        let hostingView = NSHostingView(rootView: commandBarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView?.addSubview(hostingView)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        registerPanelObservers(for: panel)

        self.panel = panel
        logger.info("CommandBar panel created")
    }

    // MARK: - Panel observers & input focus

    /// 面板级通知观察者：
    /// - `didBecomeKey`：面板真正成为 key window 后立即驱动聚焦（事件驱动，
    ///   替代纯定时赌 makeKey/首次布局时序；重复触发幂等）。
    /// - `didResignKey`：失焦自动关闭（既有语义，保持不变）。
    /// 两者统一在 `hide()` 里清理，保证每次 show 重建面板后无陈旧引用。
    private func registerPanelObservers(for panel: NSPanel) {
        panelObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                // 下一轮 runloop：让 SwiftUI 在新 key window 里完成首次布局。
                DispatchQueue.main.async {
                    self?.focusSearchInput(force: true)
                }
            }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    private func removePanelObservers() {
        for observer in panelObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        panelObservers.removeAll()
        if let panel {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: panel
            )
        }
    }

    /// 聚焦命令栏输入框（didBecomeKey 事件与定时兜底共用）。
    ///
    /// `force`：每次 show 的首次聚焦为 true，保证 nonactivating 面板上也能
    /// 出现插入点。之后的重试若已把焦点落在该字段（或其 field editor）上则
    /// 跳过 `makeFirstResponder`，避免快速输入中途被 select-all 覆盖。
    private func focusSearchInput(force: Bool = false) {
        guard let panel, panel.isVisible else { return }

        let field = firstFocusableTextField(in: panel.contentView)
        let current = panel.firstResponder
        let alreadyFocused: Bool = {
            guard let field else { return false }
            if current === field { return true }
            if let editor = field.currentEditor(), current === editor { return true }
            return false
        }()

        if let field, force || !alreadyFocused {
            panel.makeFirstResponder(field)
            if let editor = field.currentEditor() {
                let end = (field.stringValue as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        } else if field == nil, force, let editor = firstFocusableTextView(in: panel.contentView) {
            // SwiftUI on newer macOS may host the field as a bare NSTextView.
            panel.makeFirstResponder(editor)
        }

        NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }

    /// Screen under the mouse pointer; falls back to the screen containing the
    /// panel, then `NSScreen.main`.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        if let panel, let screen = panel.screen {
            return screen
        }
        return NSScreen.main
    }

    /// 递归查找子树中第一个可聚焦的 `NSTextField`；找不到返回 nil。
    private func firstFocusableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.isEnabled, !field.isHidden, field.acceptsFirstResponder {
            return field
        }
        for subview in view.subviews {
            if let field = firstFocusableTextField(in: subview) {
                return field
            }
        }
        return nil
    }

    /// Fallback when SwiftUI vends a bare text view instead of NSTextField.
    private func firstFocusableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView,
           textView.isEditable, !textView.isHidden, textView.acceptsFirstResponder {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstFocusableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private func resizePanel(isActive: Bool) {
        guard let panel, panel.isVisible else { return }
        let targetHeight = isActive
            ? CommandBarMetrics.resultsHeight
            : CommandBarMetrics.inputRowHeight
        let panelWidth = CommandBarMetrics.width

        let newFrame: NSRect
        if let screen = activeScreen() {
            let frame = screen.visibleFrame
            let x = frame.midX - panelWidth / 2
            let y = CommandBarMetrics.panelOriginY(visibleFrame: frame, panelHeight: targetHeight)
            newFrame = NSRect(x: x, y: y, width: panelWidth, height: targetHeight)
        } else {
            let current = panel.frame
            let newY = current.origin.y + current.height - targetHeight
            newFrame = NSRect(x: current.origin.x, y: newY, width: panelWidth, height: targetHeight)
        }

        NSAnimationContext.runAnimationGroup { context in
            // PRD §9.8：尊重系统「减弱动态效果」——开启时用极短时长近似无动画。
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.001 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    @objc private func panelDidResignKey(_ notification: Notification) {
        logger.info("CommandBar lost key status, closing")
        hide()
    }

    // MARK: - Event monitoring

    private func startMonitoringEvents() {
        guard localEventMonitor == nil else { return }
        isClosingPanel = false
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible, !self.isClosingPanel else {
                return event
            }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
            return event
        }
    }

    private func stopMonitoringEvents() {
        guard let monitor = localEventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        localEventMonitor = nil
    }

    private func activateApp() {
        // 快捷键触发属于显式用户意图，必须强制激活：macOS 14+ 的协同式
        // `NSApp.activate()` 在其他应用前台时可能被系统静默忽略（macOS 26 实测
        // ⌥Space 后面板拿不到键盘焦点的根因之一）。`ignoringOtherApps:` 自 14
        // 起弃用但功能正常，deployment target 13.0 下编译无弃用警告。
        NSApp.activate(ignoringOtherApps: true)
    }
}
