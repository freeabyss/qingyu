import Cocoa
import SwiftUI
import os.log

// MARK: - Whiteboard window controller (Task 016)

/// 白板会话的窗口层：每个目标屏幕一个无边框全屏窗口，承载**复用**的标注画布与工具条。
///
/// 明确不做的事：
/// - 不复制一份标注实现（画布 / 形状 / 工具条全部复用 `Views/Annotation`）；
/// - 不写入任何历史记录（与「清羽不做截图历史」的既有决策一致）；
/// - 退出后不残留窗口、层级或常驻定时器。
@MainActor
final class WhiteboardWindowController {
    private let logger = Logger.screenshot
    private var windows: [String: WhiteboardPanel] = [:]
    private var states: [String: AnnotationCanvasState] = [:]

    /// 退出（含被强制退出）后回调，供 AppContainer 释放互斥占用。
    var onDismiss: (() -> Void)?

    /// 导出动作：复制 / 保存 / 贴图；由调用方注入既有完成链路。
    var onCopy: ((Data) throws -> Void)?
    var onSave: ((Data, Date) async throws -> URL)?
    var onPin: ((Data) -> Void)?

    var isPresented: Bool { !windows.isEmpty }

    /// 当前所有屏幕上的笔迹总数（空白判定用）。
    var totalShapeCount: Int {
        states.values.reduce(0) { $0 + $1.shapes.count }
    }

    // MARK: - Presenting

    /// 呈现白板。返回是否成功。
    ///
    /// `displays` 为已解析好的目标屏幕；`frozenImages` 只在冻结底图模式下需要
    /// （抓屏由调用方完成，权限判定因此留在调用方，便于给出明确提示）。
    @discardableResult
    func present(
        session: WhiteboardSession,
        displays: [CaptureDisplay],
        frozenImages: [String: CGImage] = [:]
    ) -> Bool {
        dismiss(force: true)
        guard !displays.isEmpty else { return false }

        for display in displays {
            let key = String(display.id)
            let image: NSImage?
            switch session.background {
            case .solid:
                image = WhiteboardBackground.solidImage(pixelSize: display.pixelSize, color: session.solidColor)
            case .frozen:
                image = frozenImages[key].map(WhiteboardBackground.frozenImage(from:))
            }
            guard let baseImage = image else { continue }

            let state = AnnotationCanvasState(image: baseImage)
            let root = WhiteboardRootView(
                state: state,
                onSampleColor: { [weak self, weak state] shifted in
                    self?.sampleColor(from: state, shifted: shifted)
                },
                onUndo: { [weak state] in state?.undo() },
                onRedo: { [weak state] in state?.redo() },
                onClear: { [weak state] in state?.clearAll() },
                onCopy: { [weak self, weak state] in self?.copy(state) },
                onSave: { [weak self, weak state] in self?.save(state) },
                onPin: { [weak self, weak state] in self?.pin(state) },
                onExit: { [weak self] in self?.requestExit() }
            )

            let window = WhiteboardPanel(
                contentRect: NSRect(origin: display.frame.origin, size: display.frame.size),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentViewController = NSHostingController(rootView: root)
            window.onEscape = { [weak self] in self?.requestExit() }

            states[key] = state
            windows[key] = window
        }

        guard !windows.isEmpty else { return false }
        for window in windows.values {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        logger.info("Whiteboard presented on \(self.windows.count) display(s)")
        return true
    }

    /// 退出：有笔迹时二次确认；空白白板直接退出且**不产生任何产物**。
    func requestExit() {
        guard isPresented else { return }
        if WhiteboardExitRule.requiresConfirmation(shapeCount: totalShapeCount) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.localized("whiteboard.exit.confirm.title")
            alert.informativeText = L10n.localized("whiteboard.exit.confirm.message")
            alert.addButton(withTitle: L10n.localized("whiteboard.exit.confirm.discard"))
            alert.addButton(withTitle: L10n.localized("common.action.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        dismiss(force: true)
    }

    /// 关闭全部白板窗口并释放状态。
    func dismiss(force: Bool) {
        _ = force
        guard isPresented else { return }
        for window in windows.values {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        windows.removeAll()
        states.removeAll()
        logger.info("Whiteboard dismissed")
        onDismiss?()
    }

    // MARK: - Color sampling (Task 014/04)

    /// 白板同样支持取色：与标注窗口共用同一套采样与格式化实现。
    private func sampleColor(from state: AnnotationCanvasState?, shifted: Bool) {
        guard let state, let point = state.lastHoveredImagePoint,
              let color = state.sampledColor(atImagePoint: point) else { return }
        let text = ColorValueFormatter.string(
            red: color.red,
            green: color.green,
            blue: color.blue,
            style: shifted ? .components : .hex,
            options: colorValueOptions
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 取色输出格式（由调用方按设置注入）。
    var colorValueOptions: ColorValueOptions = .default

    /// 截图后行为策略（白板保存同样遵守「保存后同时复制」）。
    var postCapturePolicy: ScreenshotPostCapturePolicy = .default

    // MARK: - Actions

    private func copy(_ state: AnnotationCanvasState?) {
        guard let state, let onCopy, let png = try? state.renderedPNGData() else { return }
        try? onCopy(png)
        dismiss(force: true)
    }

    private func save(_ state: AnnotationCanvasState?) {
        guard let state, let onSave, let png = try? state.renderedPNGData() else { return }
        if postCapturePolicy.copiesToClipboardAfterSave {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        }
        Task { @MainActor in
            _ = try? await onSave(png, Date())
            self.dismiss(force: true)
        }
    }

    private func pin(_ state: AnnotationCanvasState?) {
        guard let state, let onPin, let png = try? state.renderedPNGData() else { return }
        onPin(png)
        dismiss(force: true)
    }
}

/// 白板窗口：无边框全屏，`Esc` 走退出流程（与标注编辑器一致的做法）。
final class WhiteboardPanel: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Root view

private struct WhiteboardRootView: View {
    @ObservedObject var state: AnnotationCanvasState
    let onSampleColor: (Bool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            AnnotationCanvasView(state: state) { _, completion in completion(nil) }
                .ignoresSafeArea()

            VStack {
                AnnotationTopToolbar(state: state)
                    .padding(.top, JadeSpace.x4.value)
                Spacer()
                HStack(spacing: JadeSpace.x2.value) {
                    AnnotationBottomToolbar(
                        state: state,
                        onUndo: onUndo,
                        onRedo: onRedo,
                        onCancel: onExit,
                        onCopy: onCopy,
                        onSave: onSave
                    )
                    WhiteboardActionButton(
                        systemName: "trash",
                        label: L10n.localized("whiteboard.action.clear"),
                        action: onClear
                    )
                    WhiteboardActionButton(
                        systemName: "pin",
                        label: L10n.localized("whiteboard.action.pin"),
                        action: onPin
                    )
                }
                .padding(.bottom, JadeSpace.x4.value)
            }
        }
        // 快捷键：⌘C 复制 / ⌘S 保存 / ⌘T 贴图 / ⇧⌘Z 清空 / ⎋ 退出。
        .background(shortcutButtons)
    }

    private var shortcutButtons: some View {
        ZStack {
            Button(action: onCopy) { EmptyView() }
                .keyboardShortcut("c", modifiers: .command)
            Button(action: onSave) { EmptyView() }
                .keyboardShortcut("s", modifiers: .command)
            Button(action: onPin) { EmptyView() }
                .keyboardShortcut("t", modifiers: .command)
            Button(action: onClear) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button(action: onUndo) { EmptyView() }
                .keyboardShortcut("z", modifiers: .command)
            Button(action: onRedo) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button(action: onExit) { EmptyView() }
                .keyboardShortcut(.cancelAction)
            // Task 014/04：`C` / `⇧C` 取色（与标注窗口一致）。
            Button { onSampleColor(false) } label: { EmptyView() }
                .keyboardShortcut("c", modifiers: [])
            Button { onSampleColor(true) } label: { EmptyView() }
                .keyboardShortcut("c", modifiers: [.shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

private struct WhiteboardActionButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemName)
                .font(JadeFont.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.jadeSecondary)
    }
}
