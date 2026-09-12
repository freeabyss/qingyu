import Cocoa
import SwiftUI
import os.log

// MARK: - Toolbar Action

/// Actions a user can trigger from the P-05 screenshot preview toolbar.
enum ScreenshotToolbarAction {
    case copy
    case save
    /// ⌥-click on Save (or explicit "save as") — opens an NSSavePanel.
    case saveAs
    /// Task 008: 贴图 — converts the capture into a runtime pin window.
    case pin
    case annotate(AnnotationTool)
    case cancel
    case dismiss
}

// MARK: - ScreenshotToolbarController

/// Presents a screenshot preview with a floating pill toolbar (P-05).
///
/// - capture result is previewed in-memory;
/// - Copy writes PNG/TIFF data to the system pasteboard, allowing the normal
///   clipboard monitor to persist it into history;
/// - Save writes PNG to the user-configured directory (default `~/Desktop`,
///   D-032) with the required timestamp name; ⌥-click opens an NSSavePanel;
/// - Annotate opens the P-05 annotation editor;
/// - Cancel/ESC discards the in-memory screenshot and closes the preview.
@MainActor
final class ScreenshotToolbarController {
    private let logger = Logger.screenshot
    /// Task 007: all terminal actions flow through the completion coordinator;
    /// successful outcomes only end the current capture session (no history).
    private let completionCoordinator: CaptureCompletionCoordinator
    /// Task 008: pin handler converts a successful capture into a pin window.
    private let pinHandler: ((ScreenshotResult) async throws -> UUID)?

    init(pinHandler: ((ScreenshotResult) async throws -> UUID)? = nil) {
        self.pinHandler = pinHandler
        var handlers = CaptureCompletionHandlers.live()
        handlers.pin = pinHandler
        self.completionCoordinator = CaptureCompletionCoordinator(handlers: handlers)
        overlayCancelObserver = NotificationCenter.default.addObserver(
            forName: .screenshotOverlayDidCancel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss(reason: .userEscape)
            }
        }
    }

    private var window: ScreenshotPreviewWindow?
    private var annotationWindow: AnnotationEditorWindow?
    private var overlayCancelObserver: NSObjectProtocol?
    private var toastWorkItem: DispatchWorkItem?
    private var regionCleanup: (() -> Void)?

    deinit {
        toastWorkItem?.cancel()
        if let overlayCancelObserver {
            NotificationCenter.default.removeObserver(overlayCancelObserver)
        }
    }

    func show(result: ScreenshotResult) {
        dismiss(reason: .superseded)

        let viewModel = ScreenshotPreviewViewModel(result: result)
        let view = ScreenshotPreviewView(
            viewModel: viewModel,
            onAction: { [weak self] action in
                self?.handle(action: action, result: result, viewModel: viewModel)
            }
        )

        let window = ScreenshotPreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in
            self?.dismiss(reason: .userEscape)
        }
        window.contentView = NSHostingView(rootView: view)
        position(window: window, for: result)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        logger.info("Screenshot preview shown for \(result.width)x\(result.height) capture")
    }

    /// Shows the region actions while the locked selection remains in place.
    func showRegion(
        result: ScreenshotResult,
        selection: RegionCaptureSelection,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(reason: .superseded)
        regionCleanup = onDismiss

        let viewModel = ScreenshotPreviewViewModel(result: result)
        let view = RegionScreenshotToolbarView(
            viewModel: viewModel,
            onAction: { [weak self] action in
                self?.handle(action: action, result: result, viewModel: viewModel)
            }
        )
        let toolbarSize = NSSize(width: 620, height: 64)
        let window = ScreenshotPreviewWindow(
            contentRect: NSRect(origin: .zero, size: toolbarSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in
            self?.dismiss(reason: .userEscape)
        }
        window.contentView = NSHostingView(rootView: view)
        window.setFrame(
            ScreenshotGeometry.toolbarFrame(
                selection: selection.globalRect,
                toolbarSize: toolbarSize,
                screenFrame: selection.screenFrame
            ),
            display: true
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        logger.info("Region screenshot toolbar shown below locked selection")
    }

    private enum DismissReason {
        case userEscape, action, cancel, superseded
    }

    private func dismiss(reason: DismissReason) {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        annotationWindow?.close()
        annotationWindow = nil
        if let window {
            window.orderOut(nil)
            logger.debug("Screenshot preview dismissed (reason: \(String(describing: reason)))")
        }
        window = nil
        let cleanup = regionCleanup
        regionCleanup = nil
        cleanup?()
    }

    private func position(window: NSWindow, for result: ScreenshotResult) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let maxWidth = min(860, visible.width - 80)
        let maxHeight = min(640, visible.height - 80)
        let imageAspect = result.height > 0 ? CGFloat(result.width) / CGFloat(result.height) : 1
        let chromeHeight: CGFloat = 112
        let targetImageHeight = min(maxHeight - chromeHeight, max(240, maxWidth / max(imageAspect, 0.1)))
        let targetWidth = min(maxWidth, max(520, targetImageHeight * imageAspect + 64))
        let targetHeight = min(maxHeight, targetImageHeight + chromeHeight)
        let frame = NSRect(
            x: visible.midX - targetWidth / 2,
            y: visible.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        window.setFrame(frame, display: true)
    }

    private func handle(action: ScreenshotToolbarAction, result: ScreenshotResult, viewModel: ScreenshotPreviewViewModel) {
        switch action {
        case .copy:
            do {
                try copyToPasteboard(result.imageData)
                if regionCleanup != nil {
                    dismiss(reason: .action)
                    return
                }
                viewModel.showToast(L10n.localized("screenshot.toast.copied"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.dismiss(reason: .action)
                }
            } catch {
                logger.error("Screenshot copy failed: \(error.localizedDescription, privacy: .public)")
                viewModel.showToast(L10n.localized("screenshot.toast.copyFailed", error.localizedDescription))
            }
        case .save:
            do {
                let url = try savePNG(result.imageData, date: result.captureDate)
                if regionCleanup != nil {
                    dismiss(reason: .action)
                    return
                }
                viewModel.showToast(L10n.localized("screenshot.toast.saved", url.deletingLastPathComponent().path))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.dismiss(reason: .action)
                }
            } catch {
                logger.error("Screenshot save failed: \(error.localizedDescription, privacy: .public)")
                viewModel.showToast(L10n.localized("screenshot.toast.saveFailed", error.localizedDescription))
            }
        case .saveAs:
            guard let url = presentSavePanel(defaultDate: result.captureDate) else {
                return  // user cancelled the panel; keep preview open
            }
            do {
                try result.imageData.write(to: url, options: .atomic)
                logger.info("Screenshot saved via panel to \(url.path, privacy: .public)")
                if regionCleanup != nil {
                    dismiss(reason: .action)
                    return
                }
                viewModel.showToast(L10n.localized("screenshot.toast.saved", url.deletingLastPathComponent().path))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.dismiss(reason: .action)
                }
            } catch {
                logger.error("Screenshot save-as failed: \(error.localizedDescription, privacy: .public)")
                viewModel.showToast(L10n.localized("screenshot.toast.saveFailed", error.localizedDescription))
            }
        case .pin:
            Task { @MainActor in
                do {
                    let outcome = try await completionCoordinator.perform(.pin, result: result)
                    if case .completed(.pinned) = outcome {
                        if regionCleanup != nil {
                            dismiss(reason: .action)
                        } else {
                            viewModel.showToast(L10n.localized("screenshot.toast.pinned"))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                                self?.dismiss(reason: .action)
                            }
                        }
                    }
                } catch {
                    logger.error("Screenshot pin failed: \(error.localizedDescription, privacy: .public)")
                    viewModel.showToast(L10n.localized("screenshot.toast.pinFailed", error.localizedDescription))
                }
            }
        case .annotate(let tool):
            presentAnnotationEditor(
                result: result,
                viewModel: viewModel,
                selection: result.regionSelection,
                initialTool: tool
            )
        case .cancel:
            dismiss(reason: .cancel)
        case .dismiss:
            dismiss(reason: .userEscape)
        }
    }

    private func presentAnnotationEditor(
        result: ScreenshotResult,
        viewModel: ScreenshotPreviewViewModel,
        selection: RegionCaptureSelection?,
        initialTool: AnnotationTool
    ) {
        guard let image = NSImage(data: result.imageData) else {
            viewModel.showToast(L10n.localized("screenshot.preview.unavailable"))
            return
        }
        let startedFromRegion = regionCleanup != nil
        // Keep the overlay and its locked selection alive during annotation.
        // A region editor is placed directly over the selected rectangle, so the
        // user never experiences a jump to a detached, pinned-looking image.
        window?.orderOut(nil)
        let editor = AnnotationEditorWindow(
            image: image,
            captureDate: result.captureDate,
            presentationFrame: startedFromRegion ? selection?.globalRect : nil,
            initialTool: initialTool,
            onCopy: { [weak self] pngData in
                try self?.copyToPasteboard(pngData)
            },
            onSave: { [weak self] pngData, date in
                guard let self else { throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.serviceDeallocated")) }
                return try self.savePNG(pngData, date: date)
            },
            onComplete: { [weak self, weak viewModel] completion in
                Task { @MainActor in
                    guard let self else { return }
                    self.annotationWindow = nil
                    switch completion {
                    case .copied:
                        viewModel?.showToast(L10n.localized("screenshot.toast.copied"))
                        self.dismiss(reason: .action)
                    case .saved(let url):
                        viewModel?.showToast(L10n.localized("screenshot.toast.saved", url.deletingLastPathComponent().path))
                        self.dismiss(reason: .action)
                    case .cancelled:
                        self.window?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    case .failed(let message):
                        self.window?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        viewModel?.showToast(message)
                    }
                }
            }
        )
        annotationWindow = editor
        editor.present()
        logger.info("Screenshot annotation editor opened")
    }

    private func copyToPasteboard(_ pngData: Data) throws {
        guard let image = NSImage(data: pngData), let tiff = image.tiffRepresentation else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.pngConversionFailed"))
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(tiff, forType: .tiff)
        logger.info("Screenshot copied to system pasteboard")
    }

    @discardableResult
    private func savePNG(_ pngData: Data, date: Date) throws -> URL {
        let fileManager = FileManager.default
        let directory = configuredSaveDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var url = directory.appendingPathComponent("Screenshot \(formatter.string(from: date)).png")
        if fileManager.fileExists(atPath: url.path) {
            url = uniqueURL(baseURL: url)
        }
        try pngData.write(to: url, options: .atomic)
        logger.info("Screenshot saved to \(url.path, privacy: .public)")
        return url
    }

    /// P-05 / D-032: the user-configured screenshot directory, defaulting to
    /// `~/Desktop`. Read synchronously from Core Data so the save path is ready
    /// the moment the user hits ⌘S; falls back to `~/Desktop` on any failure.
    private func configuredSaveDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fallback = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Desktop", isDirectory: true)

        let context = PersistenceController.shared.viewContext
        var stored: String?
        context.performAndWait {
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", SettingKey.screenshotSaveDirectory.rawValue)
            stored = try? context.fetch(request).first?.value
        }
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return fallback
        }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// P-05: ⌥-click on Save presents an NSSavePanel seeded with the default
    /// directory and timestamped filename. Returns nil if the user cancels.
    private func presentSavePanel(defaultDate: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let panel = NSSavePanel()
        panel.title = L10n.localized("screenshot.savePanel.title")
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = configuredSaveDirectory()
        panel.nameFieldStringValue = L10n.localized("screenshot.savePanel.filename", formatter.string(from: defaultDate))

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }

    private func uniqueURL(baseURL: URL) -> URL {
        let directory = baseURL.deletingLastPathComponent()
        let basename = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(basename) \(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return baseURL
    }
}

// MARK: - Preview Window

final class ScreenshotPreviewWindow: NSPanel {
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

// MARK: - Preview View Model

@MainActor
final class ScreenshotPreviewViewModel: ObservableObject {
    let result: ScreenshotResult
    @Published var toastMessage: String?

    init(result: ScreenshotResult) {
        self.result = result
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }
}

// MARK: - SwiftUI Preview

private struct RegionScreenshotToolbarView: View {
    @ObservedObject var viewModel: ScreenshotPreviewViewModel
    let onAction: (ScreenshotToolbarAction) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: JadeSpace.x1.value) {
                ToolbarButton(systemName: "doc.on.doc", label: L10n.localized("screenshot.toolbar.copy")) {
                    onAction(.copy)
                }
                ToolbarButton(systemName: "square.and.arrow.down", label: L10n.localized("screenshot.toolbar.save")) {
                    onAction(.save)
                }
                ToolbarButton(systemName: "pin", label: L10n.localized("screenshot.toolbar.pin")) {
                    onAction(.pin)
                }
                ForEach(AnnotationTool.allCases) { tool in
                    ToolbarButton(systemName: tool.systemImage, label: tool.displayName) {
                        onAction(.annotate(tool))
                    }
                }
                ToolbarButton(
                    systemName: "xmark",
                    label: L10n.localized("screenshot.toolbar.cancel"),
                    tint: JadeColor.danger
                ) {
                    onAction(.cancel)
                }
            }
            .padding(JadeSpace.x2.value)
            .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: 1))
            .jadeShadow(.md, radius: .xl)

            if let toast = viewModel.toastMessage {
                JadeToast(toast, variant: .info)
                    .offset(y: -48)
            }
        }
        .frame(width: 620, height: 64)
    }
}

private struct ScreenshotPreviewView: View {
    @ObservedObject var viewModel: ScreenshotPreviewViewModel
    let onAction: (ScreenshotToolbarAction) -> Void

    private var image: NSImage? {
        NSImage(data: viewModel.result.imageData)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Image canvas fills the panel; the toolbar floats above it.
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.8)  // P-05 canvas backing
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(JadeSpace.x6.value)
                } else {
                    Label(L10n.localized("screenshot.preview.unavailable"), systemImage: "exclamationmark.triangle")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                sourceBadge
                    .padding(JadeSpace.x3.value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(JadeMaterial.commandBar.material)
            .clipShape(JadeRadius.xxl.shape)
            .jadeShadow(.xl, radius: .xxl)

            floatingToolbar
                .padding(.bottom, JadeSpace.x6.value)

            if let toast = viewModel.toastMessage {
                // T-007: unified JadeToast. The preview is a standalone
                // NSHostingView, so render JadeToast directly (auto-dismiss is
                // handled by ScreenshotPreviewViewModel.showToast).
                JadeToast(toast, variant: .info)
                    .padding(.bottom, JadeSpace.x8.value * 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    /// Non-interactive badge (top-left) showing the capture source type.
    private var sourceBadge: some View {
        HStack(spacing: JadeSpace.x1.value) {
            Image(systemName: iconName(for: viewModel.result.sourceType))
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(sourceLabel(for: viewModel.result.sourceType))
                .font(JadeFont.caption)
            Text("\(viewModel.result.width)×\(viewModel.result.height)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .opacity(0.75)
        }
        .foregroundColor(.white)
        .padding(.horizontal, JadeSpace.x3.value)
        .padding(.vertical, JadeSpace.x2.value)
        .background(Color.black.opacity(0.55), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var floatingToolbar: some View {
        HStack(spacing: JadeSpace.x1.value) {
            ToolbarButton(systemName: "doc.on.doc", label: L10n.localized("screenshot.toolbar.copy")) {
                onAction(.copy)
            }
            ToolbarButton(systemName: "square.and.arrow.down", label: L10n.localized("screenshot.toolbar.save")) {
                // ⌥-click → NSSavePanel; plain click → save to default directory.
                if NSEvent.modifierFlags.contains(.option) {
                    onAction(.saveAs)
                } else {
                    onAction(.save)
                }
            }
            ToolbarButton(systemName: "pin", label: L10n.localized("screenshot.toolbar.pin")) {
                onAction(.pin)
            }
            ToolbarButton(systemName: "pencil.tip", label: L10n.localized("screenshot.toolbar.annotate")) {
                onAction(.annotate(.rectangle))
            }
            ToolbarButton(systemName: "xmark", label: L10n.localized("screenshot.toolbar.cancel"), tint: JadeColor.danger) {
                onAction(.cancel)
            }
        }
        .padding(JadeSpace.x2.value)
        .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: 1))
        .jadeShadow(.md, radius: .xl)
    }

    private func iconName(for source: CaptureSource) -> String {
        switch source {
        case .region: return "crop"
        case .window: return "macwindow"
        case .screen: return "rectangle.inset.filled"
        }
    }

    private func sourceLabel(for source: CaptureSource) -> String {
        switch source {
        case .region: return L10n.localized("screenshot.source.region")
        case .window: return L10n.localized("screenshot.source.window")
        case .screen: return L10n.localized("screenshot.source.screen")
        }
    }
}

private struct ToolbarButton: View {
    let systemName: String
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(JadeFont.caption)
            }
            .foregroundColor(tint ?? JadeColor.textPrimary)
            .frame(width: 72, height: 40)
            .background(
                JadeRadius.md.shape
                    .fill(hovering ? JadeColor.surface3 : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
        .onHover { hovering = $0 }
    }
}
