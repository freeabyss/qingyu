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

    /// 导出格式读取（默认读设置；测试可注入固定值）。
    ///
    /// 保存时才读取而不是启动时快照：用户改完设置无需重启即可生效。
    var imageFormatProvider: () -> ScreenshotImageFormat = { ScreenshotImageFormat.current() }

    /// 截图后行为策略（保存后同时复制）。
    var postCapturePolicy: ScreenshotPostCapturePolicy = .default

    /// Task 014/04：取色输出格式（标注窗口内 `C` / `⇧C` 使用）。
    var colorValueOptions: ColorValueOptions = .default

    /// Task 014/05：预览阶段的手势绑定（默认 Enter 复制并结束，其余不响应）。
    var gestureBindings: ScreenshotGestureBindings = .default

    /// 全局鼠标监听：只在预览可见期间存在，点击落在本应用之外（即截取画面上）
    /// 才会被识别 —— 因此天然不会与工具条按钮抢事件，也不会有「自己点自己」的歧义。
    private var gestureMonitor: Any?

    /// 当前工具条/预览窗口。`private(set)` 供测试断言窗口位置、可见性与复用情况。
    private(set) var window: ScreenshotPreviewWindow?
    private var annotationWindow: AnnotationEditorWindow?
    private var overlayCancelObserver: NSObjectProtocol?
    private var toastWorkItem: DispatchWorkItem?
    private var regionCleanup: (() -> Void)?
    /// 草稿态（区域已定、尚未捕获）的按需捕获闭包；nil 表示当前不是草稿态。
    private var draftCapture: (() async throws -> ScreenshotResult)?
    /// 是否正显示区域草稿工具条（选区已定、**尚未**捕获）。
    private(set) var isShowingRegionDraft = false

    deinit {
        toastWorkItem?.cancel()
        if let gestureMonitor {
            NSEvent.removeMonitor(gestureMonitor)
        }
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
        window.onGesture = { [weak self] gesture in
            self?.handleGesture(gesture, result: result, viewModel: viewModel)
        }
        window.onGesture = { [weak self] gesture in
            self?.handleGesture(gesture, result: result, viewModel: viewModel)
        }
        window.contentView = NSHostingView(rootView: view)
        position(window: window, for: result)
        window.makeKeyAndOrderFront(nil)
        installGestureMonitor(result: result, viewModel: viewModel)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        installGestureMonitor(result: result, viewModel: viewModel)
        logger.info("Screenshot preview shown for \(result.width)x\(result.height) capture")
    }

    /// Shows the region actions while the locked selection remains in place.
    ///
    /// 返回新建的视图模型：草稿态动作需要把同一个视图模型交给
    /// `handle(action:result:viewModel:)` 继续走既有动作路径。
    @discardableResult
    func showRegion(
        result: ScreenshotResult,
        selection: RegionCaptureSelection,
        onDismiss: @escaping () -> Void
    ) -> ScreenshotPreviewViewModel {
        dismiss(reason: .superseded)
        regionCleanup = onDismiss

        let viewModel = ScreenshotPreviewViewModel(result: result)
        let view = RegionScreenshotToolbarView(
            viewModel: viewModel,
            onAction: { [weak self] action in
                self?.handle(action: action, result: result, viewModel: viewModel)
            }
        )
        let window = makeRegionToolbarWindow(
            rootView: view,
            globalRect: selection.globalRect,
            screenFrame: selection.screenFrame,
            stealsKey: true
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        logger.info("Region screenshot toolbar shown below locked selection")
        return viewModel
    }

    // MARK: - Region toolbar: draft (deferred capture)

    /// 区域「草稿」工具条：选区已定但**尚未捕获**，用户点动作时才按需抓屏。
    ///
    /// 与 `showRegion` 的区别只有两点：没有现成的 `ScreenshotResult`，且窗口**不夺 key**
    /// ——会话仍在进行，活动叠层必须继续持有键盘（方向键微调、`Tab` 辅助线、`Enter`
    /// 确认、`P` / `⌘S` 预设全部依赖它）。
    ///
    /// 重复调用（方向键微调后）只更新位置与捕获闭包，不重建窗口，避免闪烁。
    func showRegionDraft(
        globalRect: NSRect,
        screenFrame: NSRect,
        capture: @escaping () async throws -> ScreenshotResult,
        onDismiss: @escaping () -> Void
    ) {
        // 已在草稿态：只更新位置与捕获闭包（微调后的选区由最新的闭包负责捕获），
        // 不重建窗口，避免闪烁。
        if isShowingRegionDraft, let window {
            draftCapture = capture
            window.setFrame(
                ScreenshotGeometry.toolbarFrame(
                    selection: globalRect,
                    toolbarSize: regionToolbarSize,
                    screenFrame: screenFrame
                ),
                display: true
            )
            return
        }

        // 先收掉上一块（`dismiss` 会清空草稿态字段），**之后**再写入本次的闭包，
        // 否则刚写入就被清掉——表现是点工具条任何按钮都毫无反应。
        dismiss(reason: .superseded)
        draftCapture = capture
        isShowingRegionDraft = true
        regionCleanup = onDismiss

        let viewModel = ScreenshotPreviewViewModel(result: nil)
        let view = RegionScreenshotToolbarView(
            viewModel: viewModel,
            onAction: { [weak self] action in
                self?.handleDraft(action: action)
            }
        )
        let window = makeRegionToolbarWindow(
            rootView: view,
            globalRect: globalRect,
            screenFrame: screenFrame,
            stealsKey: false
        )
        // 只上屏、不 makeKey：见 `makeRegionToolbarWindow` 里对 `stealsKey` 的说明。
        window.orderFrontRegardless()
        self.window = window
        logger.info("Region draft toolbar shown; capture deferred until an action")
    }

    /// 收起区域草稿工具条（选区已失效，例如显示器拓扑变化后重建叠层）。
    /// **不**结束会话：会话自身仍在 targeting 态继续。
    func dismissRegionDraft() {
        guard isShowingRegionDraft else { return }
        // 作废不是「用户放弃」，不该连带取消会话。
        regionCleanup = nil
        dismiss(reason: .superseded)
    }

    private func handleDraft(action: ScreenshotToolbarAction) {
        switch action {
        case .cancel, .dismiss:
            // 放弃工具条 = 放弃这次框选：结束会话（收尾闭包由调用方提供）。
            dismiss(reason: .cancel)
        default:
            Task { @MainActor in
                await self.performDraftAction(action)
            }
        }
    }

    /// 草稿态动作：先按需捕获，再把「已捕获」的区域工具条换上去并执行同一动作，
    /// 从而复用 copy / save / pin / annotate 的既有路径（含标注编辑器与手势）。
    ///
    /// 非 private：工具条按钮的点击无法在单测宿主里合成（SwiftUI 手势需要真实事件流），
    /// 测试直接驱动这条链路，覆盖「点动作才抓屏」与失败收尾。
    func performDraftAction(_ action: ScreenshotToolbarAction) async {
        guard let capture = draftCapture else { return }
        // 捕获前先让出屏幕：工具条是独立窗口，若压在选区内会被 `CGDisplayCreateImage`
        // 一起拍进去（叠层已隐藏，但工具条不在叠层里）。
        window?.orderOut(nil)
        // 摘掉草稿态：`showRegion` 内部的 `dismiss(.superseded)` 不得再触发草稿的收尾
        // 闭包——那会去 cancel 一个已经结束的会话，重复广播取消。
        draftCapture = nil
        isShowingRegionDraft = false
        regionCleanup = nil

        do {
            let result = try await capture()
            guard let selection = result.regionSelection else {
                dismiss(reason: .action)
                return
            }
            let resultViewModel = showRegion(result: result, selection: selection) { }
            handle(action: action, result: result, viewModel: resultViewModel)
        } catch {
            // 捕获失败：错误提示与命令条恢复由捕获侧统一处理，这里只收掉工具条。
            logger.error("Deferred region capture failed: \(error.localizedDescription, privacy: .public)")
            dismiss(reason: .action)
        }
    }

    /// 区域工具条尺寸：**由内容决定**，建窗时记录、重定位时复用（两处必须一致，
    /// 否则工具条会与位置计算错位）。
    private(set) var regionToolbarSize = NSSize(width: 620, height: 64)

    /// 区域工具条窗口的公共构造。
    ///
    /// `stealsKey == false`（草稿态）时**禁止夺 key**：会话期间活动叠层必须保持 key，
    /// 否则方向键微调、`Tab` 辅助线、`Enter` 确认、`P` / `⌘S` 预设全部失效。
    /// `becomesKeyOnlyIfNeeded` 让普通按钮点击直接生效且不夺 key（只有文本框这类
    /// 真正需要键盘的控件才会），因此不需要额外转发键盘事件。
    private func makeRegionToolbarWindow<Content: View>(
        rootView: Content,
        globalRect: NSRect,
        screenFrame: NSRect,
        stealsKey: Bool
    ) -> ScreenshotPreviewWindow {
        let hosting = NSHostingView(rootView: rootView)
        // 宽度必须跟着内容走：这条工具条有 17 个按钮，写死宽度会让两侧的
        // 复制 / 保存 / 贴图 / 关闭落到窗口之外（看不见也点不到）。
        let fitting = hosting.fittingSize
        let size = NSSize(
            width: min(max(fitting.width, 200), screenFrame.width),
            height: max(fitting.height, 44)
        )
        regionToolbarSize = size
        let window = ScreenshotPreviewWindow(
            contentRect: NSRect(origin: .zero, size: size),
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
        window.becomesKeyOnlyIfNeeded = !stealsKey
        window.onEscape = { [weak self] in
            self?.dismiss(reason: .userEscape)
        }
        window.contentView = hosting
        window.setFrame(
            ScreenshotGeometry.toolbarFrame(
                selection: globalRect,
                toolbarSize: size,
                screenFrame: screenFrame
            ),
            display: true
        )
        return window
    }

    private enum DismissReason {
        case userEscape, action, cancel, superseded
    }

    private func dismiss(reason: DismissReason) {
        removeGestureMonitor()
        toastWorkItem?.cancel()
        toastWorkItem = nil
        annotationWindow?.close()
        annotationWindow = nil
        draftCapture = nil
        isShowingRegionDraft = false
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

    // MARK: - Post-capture policy

    /// 保存成功后按策略再写一份到剪贴板（失败不影响保存结果，仅记录日志）。
    private func copyAfterSaveIfNeeded(_ pngData: Data) {
        guard postCapturePolicy.copiesToClipboardAfterSave else { return }
        do {
            try copyToPasteboard(pngData)
        } catch {
            logger.error("Post-save clipboard copy failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Gestures (Task 014/05)

    /// 安装全局鼠标监听（仅预览可见期间）。
    ///
    /// 只监听**其它应用**派发的鼠标事件：点在自己面板上的事件不会进来，
    /// 因此不存在与工具条按钮抢事件的歧义；而点在被截取画面上（或任意应用上）
    /// 的点击会被识别 —— 正是「对刚截到的画面下指令」的手感。
    private func installGestureMonitor(result: ScreenshotResult, viewModel: ScreenshotPreviewViewModel) {
        removeGestureMonitor()
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .otherMouseUp, .rightMouseUp]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                guard let gesture = ScreenshotGestureDispatcher.gesture(
                    eventType: event.type,
                    buttonNumber: event.buttonNumber,
                    clickCount: event.clickCount,
                    isOutsidePanel: true
                ) else { return }
                self.handleGesture(gesture, result: result, viewModel: viewModel)
            }
        }
    }

    private func removeGestureMonitor() {
        if let gestureMonitor {
            NSEvent.removeMonitor(gestureMonitor)
        }
        gestureMonitor = nil
    }

    /// 手势 → 动作。`.ignore`（默认）时什么都不做，事件已由系统交给目标应用，
    /// 本应用不做任何拦截。
    private func handleGesture(
        _ gesture: ScreenshotGesture,
        result: ScreenshotResult,
        viewModel: ScreenshotPreviewViewModel
    ) {
        switch ScreenshotGestureDispatcher.action(for: gesture, bindings: gestureBindings) {
        case .copyAndEnd:
            handle(action: .copy, result: result, viewModel: viewModel)
        case .save:
            handle(action: .save, result: result, viewModel: viewModel)
        case .pin:
            handle(action: .pin, result: result, viewModel: viewModel)
        case .ignore:
            break
        }
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
                let url = try saveImage(result.imageData, date: result.captureDate)
                copyAfterSaveIfNeeded(result.imageData)
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
            // Capture `viewModel` explicitly: it is a function parameter, not `self`.
            Task { @MainActor [weak self, viewModel] in
                guard let self else { return }
                do {
                    let outcome = try await self.completionCoordinator.perform(.pin, result: result)
                    if case .completed(.pinned) = outcome {
                        if self.regionCleanup != nil {
                            self.dismiss(reason: .action)
                        } else {
                            viewModel.showToast(L10n.localized("screenshot.toast.pinned"))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                                self?.dismiss(reason: .action)
                            }
                        }
                    }
                } catch {
                    self.logger.error("Screenshot pin failed: \(error.localizedDescription, privacy: .public)")
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
            colorValueOptions: colorValueOptions,
            onCopy: { [weak self] pngData in
                try self?.copyToPasteboard(pngData)
            },
            onSave: { [weak self] pngData, date in
                guard let self else { throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.serviceDeallocated")) }
                return try self.saveImage(pngData, date: date)
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
    /// 按当前导出格式落盘（PNG 逐字节原样；JPEG 白底压平后重新编码）。
    private func saveImage(_ imageData: Data, date: Date) throws -> URL {
        let fileManager = FileManager.default
        let directory = configuredSaveDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let format = imageFormatProvider()
        let encoded = ScreenshotImageEncoder.encode(imageData, format: format)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var url = directory.appendingPathComponent(
            "Screenshot \(formatter.string(from: date)).\(format.fileExtension)"
        )
        if fileManager.fileExists(atPath: url.path) {
            url = uniqueURL(baseURL: url)
        }
        try encoded.write(to: url, options: .atomic)
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
    /// Task 014/05：`Enter` / 小键盘 Enter。
    var onGesture: ((ScreenshotGesture) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onEscape?()
        case 36, 76:
            onGesture?(.enter)
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Preview View Model

@MainActor
final class ScreenshotPreviewViewModel: ObservableObject {
    /// nil 表示「区域草稿」态：选区已定但尚未捕获，此时只有工具条与提示文案，
    /// 没有可预览的画面（捕获在用户点动作时才发生）。
    let result: ScreenshotResult?
    @Published var toastMessage: String?

    init(result: ScreenshotResult?) {
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

/// 选区旁的区域工具条（草稿态与已捕获态共用）。
///
/// 一律用**紧凑图标按钮**：这条工具条横跨 17 个动作（复制/保存/贴图 + 13 个标注工具 + 关闭），
/// 带文字的 72pt 按钮排下来有 1300pt 宽，会远超窗口宽度——两侧的复制/保存/贴图/关闭
/// 直接落在窗口之外，看得见也点不到。图标态只有 ~590pt，正好一条紧凑色带。
/// 名称仍通过悬停说明与辅助功能标签提供。
private struct RegionScreenshotToolbarView: View {
    @ObservedObject var viewModel: ScreenshotPreviewViewModel
    let onAction: (ScreenshotToolbarAction) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: JadeSpace.x1.value) {
                ToolbarButton(systemName: "doc.on.doc", label: L10n.localized("screenshot.toolbar.copy"), isCompact: true) {
                    onAction(.copy)
                }
                ToolbarButton(systemName: "square.and.arrow.down", label: L10n.localized("screenshot.toolbar.save"), isCompact: true) {
                    onAction(.save)
                }
                ToolbarButton(systemName: "pin", label: L10n.localized("screenshot.toolbar.pin"), isCompact: true) {
                    onAction(.pin)
                }
                ForEach(AnnotationTool.allCases) { tool in
                    ToolbarButton(systemName: tool.systemImage, label: tool.displayName, isCompact: true) {
                        onAction(.annotate(tool))
                    }
                }
                ToolbarButton(
                    systemName: "xmark",
                    label: L10n.localized("screenshot.toolbar.cancel"),
                    tint: JadeColor.danger,
                    isCompact: true
                ) {
                    onAction(.cancel)
                }
            }
            .padding(JadeSpace.x1.value)
            .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: 1))
            .jadeShadow(.md, radius: .xl)

            if let toast = viewModel.toastMessage {
                JadeToast(toast, variant: .info)
                    .offset(y: -48)
            }
        }
    }
}

private struct ScreenshotPreviewView: View {
    @ObservedObject var viewModel: ScreenshotPreviewViewModel
    let onAction: (ScreenshotToolbarAction) -> Void

    private var image: NSImage? {
        viewModel.result.flatMap { NSImage(data: $0.imageData) }
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
    /// 草稿态（尚无捕获结果）不显示。
    @ViewBuilder
    private var sourceBadge: some View {
        if let result = viewModel.result {
            HStack(spacing: JadeSpace.x1.value) {
                Image(systemName: iconName(for: result.sourceType))
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(sourceLabel(for: result.sourceType))
                    .font(JadeFont.caption)
                Text("\(result.width)×\(result.height)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .opacity(0.75)
            }
            .foregroundColor(.white)
            .padding(.horizontal, JadeSpace.x3.value)
            .padding(.vertical, JadeSpace.x2.value)
            .background(Color.black.opacity(0.55), in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
        }
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
    /// 紧凑态：只画图标（选区旁的横条动作多、空间窄），名称走悬停说明与辅助功能标签。
    var isCompact: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isCompact {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: systemName)
                            .font(.system(size: 15, weight: .medium))
                        Text(label)
                            .font(JadeFont.caption)
                    }
                    .frame(width: 72, height: 40)
                }
            }
            .foregroundColor(tint ?? JadeColor.textPrimary)
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
