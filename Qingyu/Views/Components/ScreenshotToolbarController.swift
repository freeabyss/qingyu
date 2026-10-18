import Cocoa
import SwiftUI
import os.log

// MARK: - Region annotation host

/// 「在选区上原地标注」的宿主（由截图会话的叠层实现）。
///
/// 工具条只经由这组方法驱动标注：它不认识叠层、不认识窗口，也不知道压暗层怎么画。
/// 这样单测里可以注入记录型替身，验证「点工具只换高亮、不动别处」的契约。
@MainActor
protocol RegionAnnotationHost: AnyObject {
    /// 捕获前让出屏幕：隐藏放大镜等会污染位图的叠层内容。
    /// **不**隐藏叠层本身、**不**结束会话 —— 标注期间选区与压暗必须留在屏幕上。
    func prepareForAnnotationCapture()
    /// 进入标注态；返回 false 表示当前状态不允许（调用方收尾）。
    func beginAnnotation(
        image: NSImage,
        regionGlobal: CGRect,
        tool: AnnotationTool,
        style: AnnotationStyle
    ) -> Bool
    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle)
    /// 当前标注形状（导出时合成）。
    var annotationShapes: [AnnotationShape] { get }
    /// 选区逻辑尺寸（形状坐标 → 位图像素的换算基准）。
    var annotationRegionSize: CGSize { get }
    var isAnnotating: Bool { get }
    /// 动作完成：收起标注画布（选区与压暗层仍由会话统一收尾）。
    func finishAnnotation()
}

// MARK: - Toolbar Action

/// Actions a user can trigger from the P-05 screenshot preview toolbar.
enum ScreenshotToolbarAction: Equatable {
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
    /// 原地标注宿主：把「在选区上直接编辑」的实现（叠层）交给工具条。
    private var annotationHost: RegionAnnotationHost?
    /// 原地标注专用捕获（不隐藏叠层、不结束会话）；nil 时退回 `draftCapture`。
    private var annotationCapture: (() async throws -> ScreenshotResult)?
    /// 离开标注态（Esc）：工具条退回「未选中任何工具」的形态，窗口与位置不变。
    func exitAnnotationMode() {
        draftSelectedTool = nil
        refreshDraftToolbarContent()
    }

    /// 标注态当前工具（工具条据此高亮；切工具不重建窗口）。
    private var draftSelectedTool: AnnotationTool?
    /// 标注样式（颜色/笔宽/字号）：原地编辑与导出共用同一份。
    private var annotationStyle = AnnotationStyle()
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
        let window = makeRegionToolbarWindow(
            globalRect: selection.globalRect,
            screenFrame: selection.screenFrame,
            stealsKey: true
        )
        if let content = window.contentView as? RegionToolbarView {
            content.onAction = { [weak self, weak viewModel] action in
                guard let self, let viewModel else { return }
                self.handle(action: action, result: result, viewModel: viewModel)
            }
        }
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
    ///
    /// `annotationHost` 提供「在选区上原地标注」的实现（由截图会话侧的叠层提供）。
    /// 没有它时（单测/无叠层宿主）`.annotate` 行为保持老样子：懒捕获后弹出编辑器。
    ///
    /// `annotationCapture` 是原地标注专用的捕获：**不得**隐藏叠层、**不得**结束会话
    /// （选区与压暗层必须原样留在屏幕上）。缺省时退回 `capture`。
    func showRegionDraft(
        globalRect: NSRect,
        screenFrame: NSRect,
        capture: @escaping () async throws -> ScreenshotResult,
        annotationCapture: (() async throws -> ScreenshotResult)? = nil,
        onDismiss: @escaping () -> Void,
        annotationHost: RegionAnnotationHost? = nil
    ) {
        self.annotationHost = annotationHost
        // 标注进行中再次进来（会话侧任何重同步）绝不能换掉标注捕获：
        // 换掉之后下一次点复制会走「隐藏叠层 + 结束会话」的老闭包。
        if !(annotationHost?.isAnnotating == true) {
            self.annotationCapture = annotationCapture
        }
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

        let window = makeRegionToolbarWindow(
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
        // 标注已在进行：切工具只换高亮与光标；其余动作照走（结果带上标注一起合成）。
        if annotationHost?.isAnnotating == true {
            if case .annotate(let tool) = action {
                selectAnnotationTool(tool)
                return
            }
            Task { @MainActor in
                await self.performAnnotatedAction(action)
            }
            return
        }
        switch action {
        case .cancel, .dismiss:
            // 放弃工具条 = 放弃这次框选：结束会话（收尾闭包由调用方提供）。
            dismiss(reason: .cancel)
        case .annotate(let tool):
            // 点标注工具 = 在选区上原地编辑，**不**换窗口、**不**动叠层外观。
            Task { @MainActor in
                await self.performDraftAnnotation(tool: tool)
            }
        default:
            Task { @MainActor in
                await self.performDraftAction(action)
            }
        }
    }

    /// 原地标注的文字/提示框输入面板。
    ///
    /// 它挂在**工具条窗口**上而不是叠层上：叠层是 `.screenSaver` 层级、且正在被编辑，
    /// 在上面挂 sheet 会把选区状态搅乱；工具条是普通浮动窗口，回车即提交。
    func requestAnnotationTextInput(completion: @escaping (String?) -> Void) {
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

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn ? textField.stringValue : nil)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// 标注态动作：先让叠层压暗层离场（否则会被拍进「复制/保存」的位图），
    /// 再把标注形状合成到已捕获的原始位图上，最后复用既有的复制/保存/贴图路径。
    private func performAnnotatedAction(_ action: ScreenshotToolbarAction) async {
        guard let host = annotationHost else {
            await performDraftAction(action)
            return
        }
        guard let capture = annotationCapture ?? draftCapture else { return }
        let shapes = host.annotationShapes
        let regionSize = host.annotationRegionSize

        host.prepareForAnnotationCapture()
        window?.orderOut(nil)

        do {
            let raw = try await capture()
            let flattened = InPlaceAnnotationFlattener.flatten(
                result: raw,
                shapes: shapes,
                regionSize: regionSize
            )
            // 形状已经烘进位图，叠层上的临时画布可以收了。
            host.finishAnnotation()
            draftCapture = nil
            isShowingRegionDraft = false
            draftSelectedTool = nil
            let resultViewModel = ScreenshotPreviewViewModel(result: flattened)
            handle(action: action, result: flattened, viewModel: resultViewModel)
        } catch {
            logger.error("Annotated action failed: \(error.localizedDescription, privacy: .public)")
            dismiss(reason: .action)
        }
    }

    /// 单测入口：工具条按钮的点击无法在测试宿主里合成，直接驱动同一段逻辑。
    func selectAnnotationToolForTesting(_ tool: AnnotationTool) {
        selectAnnotationTool(tool)
    }

    /// 单测入口：`performAnnotatedAction` 是私有实现细节，测试只关心它的外部效果。
    func performAnnotatedActionForTesting(_ action: ScreenshotToolbarAction) async {
        await performAnnotatedAction(action)
    }

    /// 已在标注态时选工具：只换工具与光标，不重复捕获、不重建工具条。
    private func selectAnnotationTool(_ tool: AnnotationTool) {
        draftSelectedTool = tool
        annotationHost?.updateAnnotationTool(tool, style: annotationStyle)
        // 工具条只重排高亮：窗口尺寸与位置都不变（用户预期第 4 条）。
        refreshDraftToolbarContent()
    }

    /// 进入原地标注：懒捕获 → 把画面交给叠层 → 工具条留在原位并高亮选中工具。
    ///
    /// 关键顺序（每一步都对应一次用户可见的现象）：
    /// 1. 先隐藏放大镜 —— 它压在选区里会被 `CGDisplayCreateImage` 拍进位图；
    /// 2. 再让工具条让位 —— 同理，它是独立窗口；
    /// 3. 捕获完成、叠层仍在上屏（**不** `hideForCapture`、**不** `finish`）；
    /// 4. 叠层进入标注态、工具条重新上屏并贴着原位置。
    func performDraftAnnotation(tool: AnnotationTool) async {
        guard let annotationHost else {
            // 没有原地标注宿主（无叠层场景）：退回老路径，懒捕获后开编辑器。
            await performDraftAction(.annotate(tool))
            return
        }
        guard let capture = annotationCapture ?? draftCapture else { return }
        let wasSelected = tool

        annotationHost.prepareForAnnotationCapture()
        window?.orderOut(nil)
        // 摘掉草稿态字段，但保留 `regionCleanup`：标注期间会话仍在进行。
        draftCapture = nil
        isShowingRegionDraft = false

        do {
            let result = try await capture()
            guard let selection = result.regionSelection, let image = NSImage(data: result.imageData) else {
                dismiss(reason: .action)
                return
            }
            // 标注期间仍可再次点复制/保存：`draftCapture` 换成直接返回本次结果。
            draftCapture = { result }
            draftSelectedTool = wasSelected
            annotationStyle = AnnotationStyle()
            guard annotationHost.beginAnnotation(
                image: image,
                regionGlobal: selection.globalRect,
                tool: wasSelected,
                style: annotationStyle
            ) else {
                dismiss(reason: .action)
                return
            }
            isShowingRegionDraft = true
            showAnnotationToolbar(selection: selection, selectedTool: wasSelected)
            logger.info("In-place annotation active for the locked region")
        } catch {
            logger.error("Annotation capture failed: \(error.localizedDescription, privacy: .public)")
            dismiss(reason: .action)
        }
    }

    /// 标注态工具条：与草稿态同尺寸、同位置、同层级，只是复制/保存/贴图点击后
    /// 会把当前标注一起合成进结果。窗口不夺 key（叠层继续持有键盘）。
    private func showAnnotationToolbar(selection: RegionCaptureSelection, selectedTool: AnnotationTool) {
        draftSelectedTool = selectedTool
        if let window {
            window.setFrame(
                ScreenshotGeometry.toolbarFrame(
                    selection: selection.globalRect,
                    toolbarSize: regionToolbarSize,
                    screenFrame: selection.screenFrame
                ),
                display: true
            )
            refreshDraftToolbarContent()
            window.orderFrontRegardless()
            return
        }
        let window = makeRegionToolbarWindow(
            globalRect: selection.globalRect,
            screenFrame: selection.screenFrame,
            stealsKey: false
        )
        window.orderFrontRegardless()
        self.window = window
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
    /// `stealsKey == false`（草稿态与标注态）时**禁止夺 key**：会话期间活动叠层必须保持
    /// key，否则方向键微调、`Tab` 辅助线、`Enter` 确认、`P` / `⌘S` 预设全部失效。
    ///
    /// 按钮用 AppKit 的 `NSButton`（见 `RegionToolbarView`）：SwiftUI `Button` 在非 key
    /// 窗口里不会触发动作，用户看到的正是「只有复制/贴图能用」。
    private func makeRegionToolbarWindow(
        globalRect: NSRect,
        screenFrame: NSRect,
        stealsKey: Bool
    ) -> ScreenshotPreviewWindow {
        // 尺寸由按钮数量推导：写死宽度会让两侧的复制 / 保存 / 贴图 / 关闭落到窗口之外。
        let size = RegionToolbarView.fittingSize()
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
        window.contentView = makeRegionToolbarContent()
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

    /// 区域工具条的内容视图（AppKit 按钮条），点击回调统一走 `handleDraft`。
    private func makeRegionToolbarContent() -> RegionToolbarView {
        let view = RegionToolbarView(frame: NSRect(origin: .zero, size: RegionToolbarView.fittingSize()))
        view.onAction = { [weak self] action in
            self?.handleDraft(action: action)
        }
        view.updateSelection(selectedTool: draftSelectedTool)
        return view
    }

    /// 只替换工具条的内容（选中高亮），窗口实例、尺寸、位置一律不动。
    private func refreshDraftToolbarContent() {
        (window?.contentView as? RegionToolbarView)?.updateSelection(selectedTool: draftSelectedTool)
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

// MARK: - Region Toolbar (AppKit)

/// 区域工具条（草稿态与已捕获态共用）：**AppKit 原生按钮条**。
///
/// 为什么不用 SwiftUI `Button`：区域工具条必须在截图会话进行中**不夺 key**——
/// 活动叠层要一直持着键盘（方向键微调、`Tab` 辅助线、`Enter` 确认、`P` / `⌘S` 预设）。
/// 而 SwiftUI 的 `Button` 在非 key 窗口里只把点击当作「激活窗口」吃掉，动作不触发：
/// 用户报告「除了复制/贴图，其他工具都不能用」，日志里能看到的正是
/// `acceptsFirstMouse asked` 之后什么都没有。`NSButton` 走的是同一条 AppKit
/// 鼠标追踪路径，非 key 窗口里的第一次点击就能直接触发 action。
///
/// 布局与外观延续原来的紧凑色带：17 个 30pt 图标按钮、4pt 间距、胶囊底。
final class RegionToolbarView: NSView {
    /// 工具条按钮：**第一次点击就触发**，即使窗口不是 key。
    ///
    /// 区域工具条在截图会话期间故意不夺 key（键盘留在叠层上），此时 AppKit 默认把
    /// 落在非 key 窗口上的第一次点击当作「激活窗口」吃掉；实现 `acceptsFirstMouse`
    /// 后按下事件直接进入按钮的追踪循环。SwiftUI 的 `Button` 没有这个开关。
    private final class ToolbarButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// 单个按钮的点击回调。用 `.tag` 携带索引，避免为每个动作各建一个 selector。
    var onAction: ((ScreenshotToolbarAction) -> Void)?

    private static let buttonSize: CGFloat = 30
    private static let spacing: CGFloat = JadeSpace.x1.value
    private static let padding: CGFloat = JadeSpace.x1.value
    private static let buttonCount = 3 + AnnotationTool.allCases.count + 1

    /// 工具条尺寸：**由按钮数量推导**，与 `regionToolbarSize` 共用同一来源。
    static func fittingSize() -> NSSize {
        let buttons = CGFloat(buttonCount) * buttonSize
        let gaps = CGFloat(buttonCount - 1) * spacing
        let insets = padding * 2
        return NSSize(width: buttons + gaps + insets, height: buttonSize + insets * 2)
    }

    /// 每个按钮对应的动作，顺序即界面顺序：复制 / 保存 / 贴图 / 标注工具… / 关闭。
    private static var actions: [ScreenshotToolbarAction] {
        [.copy, .save, .pin] + AnnotationTool.allCases.map { .annotate($0) } + [.cancel]
    }

    private var buttons: [NSButton] = []
    /// 当前高亮的标注工具（nil = 未选中）。
    private var selectedTool: AnnotationTool? {
        didSet { updateSelection() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 只换选中高亮：窗口、尺寸、位置都不动（用户预期第 4 条）。
    func updateSelection(selectedTool: AnnotationTool?) {
        self.selectedTool = selectedTool
    }

    private func buildButtons() {
        var x = Self.padding
        let y = Self.padding
        for (index, action) in Self.actions.enumerated() {
            let button = ToolbarButton(frame: NSRect(x: x, y: y, width: Self.buttonSize, height: Self.buttonSize))
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            // 选中高亮靠 `layer.backgroundColor`：NSButton 默认不是 layer-backed，
            // 不打开这一项时 `button.layer` 为 nil，高亮永远画不出来。
            button.wantsLayer = true
            button.image = Self.icon(for: action)
            button.tag = index
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.toolTip = Self.label(for: action)
            button.setAccessibilityLabel(Self.label(for: action))
            addSubview(button)
            buttons.append(button)
            x += Self.buttonSize + Self.spacing
        }
        updateSelection()
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard Self.actions.indices.contains(sender.tag) else { return }
        onAction?(Self.actions[sender.tag])
    }

    /// 单测入口：按钮总数与按序取按钮。点击无法在测试宿主里合成真实全局事件，
    /// 用例改为直接走 `mouseDown`（见 `RegionDraftToolbarTests`）。
    var buttonCountForTesting: Int { buttons.count }
    func buttonForTesting(_ index: Int) -> NSButton? {
        buttons.indices.contains(index) ? buttons[index] : nil
    }

    private func updateSelection() {
        for (index, action) in Self.actions.enumerated() where index < buttons.count {
            let button = buttons[index]
            let isTool: Bool
            if case .annotate(let tool) = action {
                isTool = tool == selectedTool
            } else {
                isTool = false
            }
            button.contentTintColor = isTool ? JadeColor.primaryNS : Self.tint(for: action)
            button.layer?.backgroundColor = isTool
                ? JadeColor.primaryNS.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
            button.layer?.cornerRadius = JadeRadius.md.value
        }
    }

    // MARK: - Appearance

    private static func icon(for action: ScreenshotToolbarAction) -> NSImage? {
        let name: String
        switch action {
        case .copy: name = "doc.on.doc"
        case .save, .saveAs: name = "square.and.arrow.down"
        case .pin: name = "pin"
        case .annotate(let tool): name = tool.systemImage
        case .cancel, .dismiss: name = "xmark"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return image?.withSymbolConfiguration(configuration)
    }

    private static func label(for action: ScreenshotToolbarAction) -> String {
        switch action {
        case .copy: return L10n.localized("screenshot.toolbar.copy")
        case .save, .saveAs: return L10n.localized("screenshot.toolbar.save")
        case .pin: return L10n.localized("screenshot.toolbar.pin")
        case .annotate(let tool): return tool.displayName
        case .cancel, .dismiss: return L10n.localized("screenshot.toolbar.cancel")
        }
    }

    private static func tint(for action: ScreenshotToolbarAction) -> NSColor {
        switch action {
        case .cancel, .dismiss: return .systemRed
        default: return .labelColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 胶囊底与描边：与预览工具条同一套材质语言（半透明胶囊 + 细描边）。
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        NSColor.windowBackgroundColor.withAlphaComponent(0.82).setFill()
        pill.fill()
        JadeColor.borderNS.setStroke()
        pill.lineWidth = 1
        pill.stroke()
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
    /// 选中态：当前生效的工具用 Jade 底色与主色图标标出（唯一允许的视觉变化）。
    var isSelected: Bool = false
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
            .foregroundColor(isSelected ? JadeColor.primary : (tint ?? JadeColor.textPrimary))
            .background(
                JadeRadius.md.shape
                    .fill(isSelected
                          ? JadeColor.primary.opacity(0.18)
                          : (hovering ? JadeColor.surface3 : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
        .onHover { hovering = $0 }
    }
}
