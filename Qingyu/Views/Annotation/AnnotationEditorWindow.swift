import Cocoa
import SwiftUI
import os.log

@MainActor
final class AnnotationEditorWindow: NSWindowController, NSWindowDelegate {
    private let logger = Logger.screenshot
    private let state: AnnotationCanvasState
    private let originalDate: Date
    private let onCopy: (Data) throws -> Void
    private let onSave: (Data, Date) throws -> URL
    private let onComplete: (AnnotationEditorCompletion) -> Void
    private let presentationFrame: NSRect?
    private let initialTool: AnnotationTool
    /// Task 014/04：取色输出格式；`present()` 时从设置装载。
    private var colorOptions: ColorValueOptions = .default
    /// Task 014/04：取色后的轻量反馈（复用了预览阶段「短提示」的做法）。
    private let toast = AnnotationToastModel()

    init(
        image: NSImage,
        captureDate: Date,
        presentationFrame: NSRect? = nil,
        initialTool: AnnotationTool = .rectangle,
        colorValueOptions: ColorValueOptions = .default,
        onCopy: @escaping (Data) throws -> Void,
        onSave: @escaping (Data, Date) throws -> URL,
        onComplete: @escaping (AnnotationEditorCompletion) -> Void
    ) {
        self.state = AnnotationCanvasState(image: image)
        self.originalDate = captureDate
        self.onCopy = onCopy
        self.onSave = onSave
        self.onComplete = onComplete
        self.presentationFrame = presentationFrame
        self.initialTool = initialTool
        self.colorOptions = colorValueOptions
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        state.tool = initialTool
        let root = AnnotationEditorRootView(
            state: state,
            toast: toast,
            onRequestColorSample: { [weak self] shifted in
                self?.sampleColor(shifted: shifted)
            },
            onUndo: { [weak self] in self?.undo() },
            onRedo: { [weak self] in self?.redo() },
            onCancel: { [weak self] in self?.cancel() },
            onCopy: { [weak self] in self?.copyAnnotatedImage() },
            onSave: { [weak self] in self?.saveAnnotatedImage() },
            onRequestTextInput: { [weak self] point, completion in
                self?.requestTextInput(at: point, completion: completion)
            }
        )

        let isRegionEditor = presentationFrame != nil
        let targetContent = presentationFrame ?? computeWindowRect()
        let window = AnnotationEditorPanel(
            contentRect: targetContent,
            styleMask: isRegionEditor ? [.borderless, .fullSizeContentView] : [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.localized("annotation.window.title")
        window.level = isRegionEditor
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            : .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: root)
        // 赋 `contentViewController` 会把窗口尺寸改成内容的**固有尺寸**：画布是
        // NSViewRepresentable（没有固有尺寸），只有上下工具条有，于是窗口会被缩成
        // 一条约 312×132 的窄条。区域截图下这表现为「点标注后截图突然缩小了」——
        // 窗口本该与选区严丝合缝。这里在赋完 VC 之后把尺寸钉回目标矩形（原点不动）。
        window.setContentSize(targetContent.size)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in self?.cancel() }
        if !isRegionEditor {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        Task { @MainActor in await loadColorOptions() }
    }

    // MARK: - Color sampling (Task 014/04)

    /// 跟随设置刷新（注入值作为首帧默认，避免设置读取延迟导致首次取色用错格式）。
    private func loadColorOptions() async {
        let service = SettingsService(persistence: .shared)
        colorOptions = (try? await service.value(for: .colorValueOptions, as: ColorValueOptions.self)) ?? colorOptions
    }

    /// `C` / `⇧C`：取指针所在像素的颜色并复制到剪贴板（PRD 键位表）。
    ///
    /// 采样直接来自画布底图，**不重新抓屏**：既不需要额外权限，也保证取到的
    /// 就是用户看到的那一个像素。
    private func sampleColor(shifted: Bool) {
        guard let point = state.lastHoveredImagePoint else {
            toast.show(L10n.localized("annotation.colorSample.unavailable"))
            return
        }
        copyColor(at: point, shifted: shifted)
    }

    private func copyColor(at point: CGPoint, shifted: Bool) {
        guard let color = state.sampledColor(atImagePoint: point) else {
            toast.show(L10n.localized("annotation.colorSample.unavailable"))
            return
        }
        let text = ColorValueFormatter.string(
            red: color.red,
            green: color.green,
            blue: color.blue,
            style: shifted ? .components : .hex,
            options: colorOptions
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Color copied: \(text, privacy: .public)")
        toast.show(text)
    }

    private func computeWindowRect() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: 900, height: 650)
        }
        let visible = screen.visibleFrame
        let maxW = min(1100, visible.width * 0.86)
        let maxH = min(820, visible.height * 0.86)
        let imageSize = state.imageSize
        let chromeHeight: CGFloat = 118
        let scale = min(maxW / max(imageSize.width, 1), (maxH - chromeHeight) / max(imageSize.height, 1), 1)
        let width = max(680, min(maxW, imageSize.width * scale + 40))
        let height = max(480, min(maxH, imageSize.height * scale + chromeHeight))
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    private func undo() {
        state.undo()
    }

    private func redo() {
        state.redo()
    }

    private func cancel() {
        onComplete(.cancelled)
        window?.close()
    }

    private func copyAnnotatedImage() {
        do {
            let png = try state.renderedPNGData()
            try onCopy(png)
            onComplete(.copied)
            window?.close()
        } catch {
            logger.error("Annotated copy failed: \(error.localizedDescription, privacy: .public)")
            onComplete(.failed(error.localizedDescription))
        }
    }

    private func saveAnnotatedImage() {
        do {
            let png = try state.renderedPNGData()
            let url = try onSave(png, originalDate)
            onComplete(.saved(url))
            window?.close()
        } catch {
            logger.error("Annotated save failed: \(error.localizedDescription, privacy: .public)")
            onComplete(.failed(error.localizedDescription))
        }
    }

    private func requestTextInput(at point: CGPoint, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = L10n.localized("annotation.textInput.title")
        alert.informativeText = L10n.localized("annotation.textInput.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.localized("annotation.textInput.add"))
        alert.addButton(withTitle: L10n.localized("annotation.textInput.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = L10n.localized("annotation.textInput.placeholder")
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField

        guard let window else {
            completion(nil)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn ? textField.stringValue : nil)
        }
    }

    func windowWillClose(_ notification: Notification) {}
}

enum AnnotationEditorCompletion {
    case copied
    case saved(URL)
    case cancelled
    case failed(String)
}

private final class AnnotationEditorPanel: NSWindow {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Task 014/04：标注窗口内的短提示（取色结果 / 取不到）。
@MainActor
final class AnnotationToastModel: ObservableObject {
    @Published var message: String?

    func show(_ message: String, duration: TimeInterval = 1.5) {
        self.message = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.message == message {
                self?.message = nil
            }
        }
    }
}

private struct AnnotationEditorRootView: View {
    @ObservedObject var state: AnnotationCanvasState
    @ObservedObject var toast: AnnotationToastModel
    let onRequestColorSample: (Bool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onRequestTextInput: (CGPoint, @escaping (String?) -> Void) -> Void

    var body: some View {
        ZStack {
            // Black canvas fills the whole window (P-05).
            AnnotationCanvasView(state: state, onRequestTextInput: onRequestTextInput)
                .ignoresSafeArea()

            if let message = toast.message {
                VStack {
                    Spacer()
                    Text(message)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(JadeColor.surface1)
                        .jadeRadius(.md)
                        .padding(.bottom, 96)
                }
                .allowsHitTesting(false)
            }

            VStack {
                AnnotationTopToolbar(state: state)
                    .padding(.top, JadeSpace.x4.value)
                Spacer()
                AnnotationBottomToolbar(
                    state: state,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onCancel: onCancel,
                    onCopy: onCopy,
                    onSave: onSave
                )
                .padding(.bottom, JadeSpace.x4.value)
            }
        }
        // Hidden buttons carry the ⌘C / ⌘S / ⎋ shortcuts so they fire regardless
        // of focus. ESC is also handled by the panel's keyDown as a fallback.
        .background(shortcutButtons)
    }

    private var shortcutButtons: some View {
        ZStack {
            Button(action: onCopy) { EmptyView() }
                .keyboardShortcut("c", modifiers: .command)
            // Task 014/04：`C` / `⇧C` 取色（PRD 键位表）。
            Button { onRequestColorSample(false) } label: { EmptyView() }
                .keyboardShortcut("c", modifiers: [])
            Button { onRequestColorSample(true) } label: { EmptyView() }
                .keyboardShortcut("c", modifiers: [.shift])
            Button(action: onSave) { EmptyView() }
                .keyboardShortcut("s", modifiers: .command)
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
            Button(action: onUndo) { EmptyView() }
                .keyboardShortcut("z", modifiers: .command)
            Button(action: onRedo) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            // 1-9 选择工具条分组（组内循环）；第 10/11 组（序号、提示框）无数字快捷键。
            ForEach(Array(AnnotationTool.toolbarGroups.enumerated().prefix(9)), id: \.offset) { index, group in
                Button { state.tool = AnnotationTool.next(in: group, after: state.tool) } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
