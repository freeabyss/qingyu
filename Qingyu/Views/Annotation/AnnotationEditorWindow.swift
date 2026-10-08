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

    init(
        image: NSImage,
        captureDate: Date,
        presentationFrame: NSRect? = nil,
        initialTool: AnnotationTool = .rectangle,
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
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        state.tool = initialTool
        let root = AnnotationEditorRootView(
            state: state,
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
        let window = AnnotationEditorPanel(
            contentRect: presentationFrame ?? computeWindowRect(),
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
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in self?.cancel() }
        if !isRegionEditor {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
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

private struct AnnotationEditorRootView: View {
    @ObservedObject var state: AnnotationCanvasState
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
            Button(action: onSave) { EmptyView() }
                .keyboardShortcut("s", modifiers: .command)
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
            Button(action: onUndo) { EmptyView() }
                .keyboardShortcut("z", modifiers: .command)
            Button(action: onRedo) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            // 1-4 select rectangle / arrow / text / mosaic.
            ForEach(Array(AnnotationTool.allCases.enumerated()), id: \.element) { index, tool in
                Button { state.tool = tool } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
