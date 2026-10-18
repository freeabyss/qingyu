import AppKit
import CoreGraphics
import os.log

// MARK: - Capture session controller (Task 006)

/// 截图会话的鼠标/键盘输入事件；坐标为全局 AppKit point。
enum CaptureInputEvent {
    case pointerMoved(CGPoint)
    case mouseDown(CGPoint)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case selectFullDisplay
    /// Task 014/01：可微调态下的方向键微调（步长已由叠层按显示器缩放换算为逻辑点）。
    case nudgeSelection(axis: SelectionNudge.Axis, delta: CGFloat, resize: Bool)
    /// Task 014/01：确认微调后的选区（Enter）。
    case confirmSelection
    /// Task 015：打开预设清单（`P`）。
    case openPresetPicker
    /// Task 015：清单内上下移动选择（方向键）。
    case movePresetSelection(delta: Int)
    /// Task 015：套用当前选中的预设（Enter）。
    case applySelectedPreset
    /// Task 015：关闭清单（Esc）。
    case closePresetPicker
    /// Task 015：把当前微调中的选区保存为预设（`⌘S` 区域 / `⌘⇧S` 尺寸）。
    case saveCurrentSelectionAsPreset(kind: CapturePresetKind)
    /// 原地区注：Esc 退出标注、回到「选区可微调」态（不结束会话）。
    case cancelAnnotation
    case cancel
}

/// 显示器来源抽象；单测注入虚拟显示器。
protocol DisplayProviding {
    var displays: [CaptureDisplay] { get }
    func display(containing point: CGPoint) -> CaptureDisplay?
}

/// 每显示器一个叠层窗口的抽象；单测注入记录型工厂，避免创建真实全屏窗口。
@MainActor
protocol CaptureOverlayWindow: AnyObject {
    var display: CaptureDisplay { get }

    /// 鼠标/键盘事件（全局 AppKit 坐标）上抛给会话控制器。
    var onEvent: ((CaptureInputEvent) -> Void)? { get set }

    /// 只有活动显示器展示窗口高亮与快捷键提示。
    func setActive(_ active: Bool)
    func updateHighlight(window: CaptureWindowCandidate?)
    /// Task 012：控件级高亮（AppKit 全局坐标）。窗口高亮与控件高亮可同时存在，
    /// 控件优先级更高（见 `CandidateHitTest.hit`）。
    func updateElementHighlight(frame: CGRect?)
    func updateRegion(rect: CGRect?)
    func updateHints(_ hintKeys: [String])
    /// Task 015：预设清单（`items` 为显示标签，`selectedIndex` 为 nil 表示清单未打开）。
    ///
    /// 必须是**协议要求**：只写在扩展里的方法对存在类型走静态派发，
    /// 具体实现（真实叠层、测试替身）永远不会被调用。
    func updatePresetPicker(items: [String], selectedIndex: Int?)
    /// Task 015：内联提示（屏幕已断开 / 预设已满等）。传 nil 清除。
    func updateNotice(_ text: String?)
    func orderFront()
    func hide()
    func close()

    // MARK: - 原地标注

    /// 在已锁定的选区上原地编辑：叠层外观（压暗 / 边框 / 尺寸徽标）保持不变，
    /// 只在选区内加一层可绘制区域。用户预期：点工具后除了光标与工具高亮之外无变化。
    @discardableResult
    func beginAnnotation(image: NSImage, regionGlobal: CGRect, tool: AnnotationTool, style: AnnotationStyle) -> Bool
    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle)
    func undoAnnotation()
    func redoAnnotation()
    var annotationShapes: [AnnotationShape] { get }
    var isAnnotating: Bool { get }
    func endAnnotation()
    /// 捕获前让出屏幕（隐藏放大镜）但不收起叠层。
    func prepareForAnnotationCapture()
    /// 文字/提示框工具需要输入框：叠层只上报「点在哪 + 输入完的回调」。
    func setAnnotationTextRequestHandler(_ handler: @escaping (CGPoint, @escaping (String?) -> Void) -> Void)
}

extension CaptureOverlayWindow {
    /// 默认空实现：既有替身无需为新增能力逐个补方法。
    func updatePresetPicker(items: [String], selectedIndex: Int?) {}

    func updateNotice(_ text: String?) {}

    func beginAnnotation(image: NSImage, regionGlobal: CGRect, tool: AnnotationTool, style: AnnotationStyle) -> Bool { false }
    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle) {}
    func undoAnnotation() {}
    func redoAnnotation() {}
    var annotationShapes: [AnnotationShape] { [] }
    var isAnnotating: Bool { false }
    func endAnnotation() {}
    /// 捕获前让出屏幕（隐藏放大镜）但不收起叠层。
    func prepareForAnnotationCapture() {}
    func setAnnotationTextRequestHandler(_ handler: @escaping (CGPoint, @escaping (String?) -> Void) -> Void) {}
}

// MARK: - 原地标注宿主

/// 会话即标注宿主：工具条只经由这组方法驱动选区上的编辑，
/// 「捕获前让位」「进入/退出标注」「导出用的形状与尺寸」都收在这里。
extension CaptureSessionController: RegionAnnotationHost {
    /// 捕获前隐藏放大镜：它压在选区里会被 `CGDisplayCreateImage` 拍进位图
    /// （实测取样窗口会把亮度从 243 拉到 215）。叠层本身必须留着。
    func prepareForAnnotationCapture() {
        for overlay in overlayWindows.values {
            overlay.prepareForAnnotationCapture()
        }
    }

    var annotationRegionSize: CGSize {
        annotationRegionRect?.size ?? .zero
    }

    /// 动作完成：收起标注画布。会话由捕获路径 `finish()` 统一收尾。
    func finishAnnotation() {
        isAnnotating = false
        for overlay in overlayWindows.values {
            overlay.endAnnotation()
        }
    }
}

@MainActor
protocol CaptureOverlayWindowFactory: AnyObject {
    func makeWindow(for display: CaptureDisplay) -> CaptureOverlayWindow
}

/// 统一截图会话协调器（PRD「截图与贴图」单一入口）：
/// 在所有显示器各建一个叠层窗口，全部窗口共享一个 `CaptureSessionState`；
/// 只有指针所在屏展示活动高亮与快捷键提示，跨屏即时切换；
/// 锁定目标回调 `onLocked`，取消回调 `onCancel`，关闭全部叠层由调用方经
/// `finish()` 触发（捕获完成后），`cancel()` 立即关闭全部。
@MainActor
final class CaptureSessionController {
    private let logger = Logger.screenshot

    private(set) var state = CaptureSessionState()
    private(set) var activeDisplayID: CGDirectDisplayID?
    private(set) var isSessionActive = false

    private let displayProvider: DisplayProviding
    private let windowProvider: WindowCandidateProviding
    private let overlayFactory: CaptureOverlayWindowFactory
    private let elementProvider: ElementCandidateProviding

    /// Task 012：控件级探测选项与吸附阈值。由 `AppContainer.syncRuntimeSettings()` 同步。
    var elementProbeOptions: ElementProbeOptions = .default
    /// 选区边缘吸附阈值（逻辑点）；<= 0 表示关闭吸附。
    var snapThreshold: CGFloat = 0
    /// Task 015：本会话可用的预设（进入会话时由调用方从仓库装入，会话期只读）。
    var presets: [CapturePreset] = []
    /// Task 015：保存预设；返回 false 表示已达上限。
    var onSavePreset: ((CapturePreset) async -> Bool)?
    /// Task 015：清单中当前高亮的预设下标；nil 表示清单未打开。
    private(set) var presetPickerSelection: Int?


    /// 控件级探测调度器；未启用控件探测时它不会产生任何系统调用。
    private let probeScheduler: CandidateProbeScheduler

    private var overlayWindows: [CGDirectDisplayID: CaptureOverlayWindow] = [:]
    private var screenChangeObserver: NSObjectProtocol?

    /// 激活期自持有：`start()` 赋 `self`，`finish()`/`cancel()` 清 nil（与 start 严格配对）。
    /// 防止调用方只以局部变量持有会话时 ARC 提前释放——否则键盘/事件回调的 `weak self`
    /// 全部失效，叠层窗口被 NSApp.windows 持有后沦为无法响应的"僵尸"暗幕。
    private var livenessReference: CaptureSessionController?

    /// 目标锁定（窗口/区域/整屏）。调用方完成捕获后必须调用 `finish()`。
    var onLocked: ((CaptureTarget) -> Void)?
    /// 用户取消（Esc）。控制器已关闭全部叠层。
    var onCancel: (() -> Void)?

    /// 区域进入**可微调态**时回调（拖拽松开、方向键微调后、套用预设后各触发一次）：
    /// 调用方据此在选区旁展示区域工具条。此时**尚未捕获**，动作触发时才按需抓屏
    /// （懒捕获：预捕获会在叠层仍可见时抓屏，且微调后画面立即过期）。
    var onRegionAdjustable: ((CaptureDisplay, CGRect) -> Void)?
    /// 可微调态已失效（例如显示器拓扑变化后重建叠层）：调用方应收起草稿工具条。
    /// 与 `onCancel` 的区别是会话**不结束**，只是选区作废、回到窗口选择态。
    var onRegionAdjustableEnded: (() -> Void)?

    /// 原地标注态（选区锁定、叠层保持压暗，鼠标归属标注画布）。
    ///
    /// 这是一个**子态**而不是新的 phase：选区、叠层、工具条全部沿用微调态那一套，
    /// 只有「谁吃掉鼠标事件」与「工具条显示什么」变了。放进 phase 会逼着所有
    /// 既有分支各补一个 case，而它们的行为在标注期间完全不变。
    private(set) var isAnnotating = false
    /// 文字/提示框工具的输入面板：由调用方提供（叠层自己不弹窗）。
    var annotationTextInputHandler: ((CGPoint, @escaping (String?) -> Void) -> Void)?
    /// 标注态已退出（Esc 或动作收尾）：调用方应把工具条收回「纯选区」形态。
    var onAnnotationExit: (() -> Void)?

    init(
        displayProvider: DisplayProviding,
        windowProvider: WindowCandidateProviding,
        overlayFactory: CaptureOverlayWindowFactory,
        elementProvider: ElementCandidateProviding = DisabledElementCandidateProvider()
    ) {
        self.displayProvider = displayProvider
        self.windowProvider = windowProvider
        self.overlayFactory = overlayFactory
        self.elementProvider = elementProvider
        self.probeScheduler = CandidateProbeScheduler(provider: elementProvider)
        // 探测结果到达后先写入会话状态，状态确有变化才刷新叠层，避免无谓重绘。
        self.probeScheduler.onResult = { [weak self] frame in
            guard let self else { return }
            if self.state.elementHovered(frame) {
                self.syncOverlays()
            }
        }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let globalKeyboardMonitor {
            NSEvent.removeMonitor(globalKeyboardMonitor)
        }
    }

    // MARK: - Lifecycle

    /// 进入截图状态：所有显示器建窗、高亮指针所在屏与其下窗口。
    func start() {
        guard !isSessionActive else { return }
        isSessionActive = true
        state = CaptureSessionState()
        buildWindows()

        let pointerLocation = NSEvent.mouseLocation
        switchActiveDisplay(to: pointerLocation, notifyState: false)
        observeScreenChanges()
        // 与 finish()/cancel() 严格配对：激活期间由会话自己持有自己。
        livenessReference = self
        logger.info("Capture session started on \(self.overlayWindows.count) display(s)")
    }

    /// 捕获前临时隐藏全部叠层，避免叠层出现在位图中；完成后调用 `finish()`。
    func hideForCapture() {
        for (_, window) in overlayWindows {
            window.hide()
        }
    }

    /// 捕获完成（成功或失败）后关闭全部叠层。
    /// 注意：清除自持有必须是最后一步——它可能立即触发 deinit。
    func finish() {
        isSessionActive = false
        cancelElementProbe()
        closeAllWindows()
        removeScreenObserver()
        removeKeyboardMonitor()
        livenessReference = nil
    }

    /// 用户取消：关闭全部叠层并广播取消回调。
    func cancel() {
        guard isSessionActive else { return }
        state.cancel()
        isSessionActive = false
        cancelElementProbe()
        closeAllWindows()
        removeScreenObserver()
        removeKeyboardMonitor()
        onCancel?()
        logger.info("Capture session cancelled")
        // 清除自持有必须是最后一步——它可能立即触发 deinit。
        livenessReference = nil
    }

    // MARK: - Input

    func handle(_ event: CaptureInputEvent) {
        guard isSessionActive else { return }

        switch event {
        case .pointerMoved(let point):
            // 只有在「窗口选择」阶段才跟随指针切换当前显示器：拖拽/可微调期间选区已绑定
            // 到它所属的显示器，此时切屏会把选区画到另一块屏上（坐标错位、看起来选区乱跳）。
            if case .targetingWindow = state.phase {
                switchActiveDisplay(to: point, notifyState: true)
            }
            scheduleElementProbe(at: point)

        case .mouseDown(let point):
            let display = displayProvider.display(containing: point)
                ?? display(for: activeDisplayID)
                ?? displayProvider.displays.first
            guard let display else { return }
            // 指针在非当前屏按下时，先把当前屏切到按下所在屏（不重置会话状态），
            // 否则选区会被画在另一块屏上。指针瞬移（未经 mouseMoved）时这条是唯一保障。
            if display.id != activeDisplayID {
                focusActiveDisplay(on: display)
            }
            state.mouseDown(at: point, display: display)
            syncOverlays()

        case .mouseDragged(let point):
            // 开始拖拽即放弃控件命中与在途探测：用户在自行圈区域。
            probeScheduler.cancel()
            state.mouseDragged(to: snapDragPoint(point))
            syncOverlays()

        case .mouseUp(let point):
            state.mouseUp(at: point)
            syncOverlays()
            if case .locked(let target) = state.phase {
                isSessionActive = false
                onLocked?(target)
            }
            // 松开即进入可微调态：立刻把工具条交给调用方，不再等 `Enter`。
            notifyRegionAdjustableIfNeeded()

        case .selectFullDisplay:
            if let display = display(for: activeDisplayID) ?? displayProvider.displays.first {
                state.selectFullDisplay(display)
                syncOverlays()
            }
            if case .locked(let target) = state.phase {
                isSessionActive = false
                onLocked?(target)
            }

        case .nudgeSelection(let axis, let delta, let resize):
            // Task 014/01：仅在可微调态生效；无变化时不重绘。
            if state.nudgeRegion(axis: axis, delta: delta, resize: resize) {
                syncOverlays()
                // 工具条跟着新选区走（否则微调后工具条会停在旧位置）。
                notifyRegionAdjustableIfNeeded()
            }

        case .confirmSelection:
            state.confirmRegion()
            syncOverlays()
            if case .locked(let target) = state.phase {
                isSessionActive = false
                onLocked?(target)
            }

        case .openPresetPicker:
            openPresetPicker()

        case .movePresetSelection(let delta):
            movePresetSelection(by: delta)

        case .applySelectedPreset:
            applySelectedPreset()

        case .closePresetPicker:
            closePresetPicker()

        case .saveCurrentSelectionAsPreset(let kind):
            saveCurrentSelectionAsPreset(kind: kind)

        case .cancelAnnotation:
            exitAnnotation()

        case .cancel:
            cancel()
        }
    }

    // MARK: - 原地标注

    /// 进入标注态：选区必须已可微调（叠层仍在上屏、选区仍可见）。
    ///
    /// 标记会话为标注中后，叠层内层的标注画布接管鼠标（见 `CaptureOverlayContentView`）；
    /// 叠层自身的压暗、选区边框与尺寸徽标一律不变 —— 这正是用户预期第 4 条。
    @discardableResult
    func beginAnnotation(image: NSImage, regionGlobal: CGRect, tool: AnnotationTool, style: AnnotationStyle) -> Bool {
        guard case .adjustingRegion = state.phase, !isAnnotating else { return false }
        guard let overlay = overlay(for: regionGlobal) else { return false }
        isAnnotating = true
        overlay.beginAnnotation(image: image, regionGlobal: regionGlobal, tool: tool, style: style)
        // 标注期间叠层必须保持 key：Esc/⌘Z 走 `keyDown`，不能落到工具条上。
        (overlay as? CaptureOverlayWindowController)?.makeKey()
        if let handler = annotationTextInputHandler {
            overlay.setAnnotationTextRequestHandler(handler)
        }
        logger.info("In-place annotation started on display \(overlay.display.id)")
        return true
    }

    /// 切换标注工具：只改高亮与光标，叠层与其他像素不动。
    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle) {
        guard isAnnotating else { return }
        annotationOverlay?.updateAnnotationTool(tool, style: style)
    }

    func undoAnnotation() { annotationOverlay?.undoAnnotation() }
    func redoAnnotation() { annotationOverlay?.redoAnnotation() }

    var annotationShapes: [AnnotationShape] { annotationOverlay?.annotationShapes ?? [] }
    /// 标注选区（AppKit 全局坐标）与尺寸；供导出时换算像素。
    var annotationRegionRect: CGRect? {
        guard case .adjustingRegion(_, let rect) = state.phase else { return nil }
        return rect
    }

    /// 退出标注态：叠层回到纯选区呈现，选区仍可微调（会话继续）。
    func exitAnnotation() {
        guard isAnnotating else { return }
        let overlay = annotationOverlay
        isAnnotating = false
        overlay?.endAnnotation()
        // 恢复叠层呈现（提示条、选区边框）并把选区工具条放回原位。
        syncOverlays()
        onAnnotationExit?()
        notifyRegionAdjustableIfNeeded()
    }

    /// 标注所在显示器：以选区中心判定，回落到活动屏。
    private var annotationOverlay: CaptureOverlayWindow? {
        guard case .adjustingRegion(_, let rect) = state.phase else { return nil }
        return overlay(for: rect)
    }

    /// 文字/提示框工具需要输入框：由叠层把「点在哪、输入完给谁」交给宿主，
    /// 宿主（调用方）决定用哪种输入面板，叠层自己不弹窗。

    private func overlay(for globalRect: CGRect) -> CaptureOverlayWindow? {
        let center = CGPoint(x: globalRect.midX, y: globalRect.midY)
        if let match = overlayWindows.values.first(where: { $0.display.frame.contains(center) }) {
            return match
        }
        return activeDisplayID.flatMap { overlayWindows[$0] }
    }

    /// 显示器拓扑变化时重建叠层与坐标映射。
    func rebuild() {
        guard isSessionActive else { return }
        closeAllWindows()
        state = CaptureSessionState()
        // 旧选区随状态一起作废：草稿工具条若还挂着，点动作会截到一个已经不对应的区域。
        onRegionAdjustableEnded?()
        buildWindows()
        switchActiveDisplay(to: NSEvent.mouseLocation, notifyState: false)
    }

    /// 进入可微调态后通知调用方展示区域工具条（尚未捕获）。
    /// 重复调用是幂等的：调用方只更新位置，不重建窗口。
    private func notifyRegionAdjustableIfNeeded() {
        guard case .adjustingRegion(let display, let rect) = state.phase else { return }
        onRegionAdjustable?(display, rect)
    }

    // MARK: - Presets (Task 015)

    /// 打开清单：预设为空时不响应（不弹空清单）；仅活动屏渲染。
    private func openPresetPicker() {
        guard !presets.isEmpty else {
            logger.info("Preset picker ignored: no presets")
            return
        }
        guard isSessionActive else { return }
        presetPickerSelection = 0
        syncPresetPicker()
    }

    private func movePresetSelection(by delta: Int) {
        guard let current = presetPickerSelection, !presets.isEmpty else { return }
        let count = presets.count
        let next = ((current + delta) % count + count) % count
        presetPickerSelection = next
        syncPresetPicker()
    }

    private func closePresetPicker() {
        guard presetPickerSelection != nil else { return }
        presetPickerSelection = nil
        syncPresetPicker()
    }

    /// 套用选中的预设：区域直接落位；尺寸以指针为中心生成。
    /// 套用**不结束会话**，失败时给出内联提示而不是静默改位置。
    private func applySelectedPreset() {
        guard let index = presetPickerSelection, presets.indices.contains(index) else { return }
        let preset = presets[index]
        apply(preset: preset)
        closePresetPicker()
    }

    /// 套用单条预设。返回 nil 表示成功，否则为内联提示文案。
    @discardableResult
    func apply(preset: CapturePreset) -> String? {
        switch preset.kind {
        case .region:
            let screens = displayProvider.displays.map { display in
                ScreenDescriptor(displayID: String(display.id), frame: display.frame)
            }
            switch PresetResolver.resolve(regionPreset: preset, availableScreens: screens) {
            case .success(let rect):
                guard let display = displayProvider.display(containing: CGPoint(x: rect.midX, y: rect.midY))
                    ?? displayProvider.displays.first else {
                    return showNotice(L10n.localized("capture.preset.screenUnavailable"))
                }
                state.applyPresetRegion(rect, display: display)
                // 焦点跟随到预设所在屏，但**不得**走 `switchActiveDisplay(notifyState: false)`：
                // 那是 `start()` 的首帧语义，会把刚套用的状态整个重置掉。
                focusActiveDisplay(on: display)
                notifyRegionAdjustableIfNeeded()
                return nil
            case .failure(.screenUnavailable):
                return showNotice(L10n.localized("capture.preset.screenUnavailable"))
            case .failure(.outOfBounds):
                return showNotice(L10n.localized("capture.preset.outOfBounds"))
            }

        case .size:
            let pointer = NSEvent.mouseLocation
            guard let display = displayProvider.display(containing: pointer) ?? displayProvider.displays.first else {
                return showNotice(L10n.localized("capture.preset.screenUnavailable"))
            }
            let screen = ScreenDescriptor(displayID: String(display.id), frame: display.frame)
            let rect = PresetResolver.resolve(sizePreset: preset, pointerLocation: pointer, screen: screen)
            state.applyPresetRegion(rect, display: display)
            focusActiveDisplay(on: display)
            notifyRegionAdjustableIfNeeded()
            return nil
        }
    }

    /// 把当前微调中的选区保存为预设（相对该屏原点的偏移 + 稳定显示器标识）。
    private func saveCurrentSelectionAsPreset(kind: CapturePresetKind) {
        guard case .adjustingRegion(let display, let rect) = state.phase else {
            _ = showNotice(L10n.localized("capture.preset.saveNeedsSelection"))
            return
        }
        let preset = CapturePreset(
            name: L10n.localized(kind == .region ? "capture.preset.defaultRegionName" : "capture.preset.defaultSizeName"),
            kind: kind,
            displayID: String(display.id),
            rect: kind == .region
                ? CGRect(
                    x: rect.minX - display.frame.minX,
                    y: rect.minY - display.frame.minY,
                    width: rect.width,
                    height: rect.height
                )
                : nil,
            size: kind == .size ? rect.size : nil
        )
        guard let onSavePreset else { return }
        Task { @MainActor in
            let accepted = await onSavePreset(preset)
            if accepted {
                self.presets = (self.presets + [preset])
                _ = self.showNotice(L10n.localized("capture.preset.saved"))
            } else {
                _ = self.showNotice(L10n.localized("capture.preset.limitReached"))
            }
        }
    }

    /// 只切换活动屏并刷新叠层，**不重置会话状态**。
    private func focusActiveDisplay(on display: CaptureDisplay) {
        if display.id != activeDisplayID {
            activeDisplayID = display.id
            logger.debug("Active capture display switched to \(display.id)")
        }
        syncOverlays()
    }

    /// 所有叠层同步清单状态（只有活动屏会真正绘制，非活动屏内容视图被隐藏）。
    private func syncPresetPicker() {
        let items = CapturePresetCatalog.displayLabels(for: presets)
        for overlay in overlayWindows.values {
            overlay.updatePresetPicker(items: items, selectedIndex: presetPickerSelection)
        }
    }

    @discardableResult
    private func showNotice(_ text: String) -> String {
        for overlay in overlayWindows.values {
            overlay.updateNotice(text)
        }
        return text
    }

    // MARK: - Keyboard

    private var keyboardMonitor: Any?
    private var globalKeyboardMonitor: Any?

    private func setupKeyboardMonitor() {
        guard keyboardMonitor == nil, globalKeyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53:                                       // Esc
                self?.handle(.cancel)
                return nil
            case 0 where event.modifierFlags.contains(.command):   // ⌘A
                self?.handle(.selectFullDisplay)
                return nil
            default:
                return event
            }
        }
        // 全局监听只接收其他应用派发的 keyDown（只读、不可拦截）：
        // 应用自身未激活时 Esc 仍可取消截图会话。
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }      // Esc
            self?.handle(.cancel)
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let globalKeyboardMonitor {
            NSEvent.removeMonitor(globalKeyboardMonitor)
            self.globalKeyboardMonitor = nil
        }
    }

    // MARK: - Private

    private func buildWindows() {
        for display in displayProvider.displays {
            let window = overlayFactory.makeWindow(for: display)
            window.onEvent = { [weak self] event in
                self?.handle(event)
            }
            overlayWindows[display.id] = window
        }
        for (displayID, window) in overlayWindows {
            window.setActive(displayID == activeDisplayID)
            window.orderFront()
        }
        setupKeyboardMonitor()
    }

    private func closeAllWindows() {
        for (_, window) in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        activeDisplayID = nil
    }

    private func display(for id: CGDirectDisplayID?) -> CaptureDisplay? {
        guard let id else { return nil }
        return displayProvider.displays.first { $0.id == id }
    }

    private func switchActiveDisplay(to point: CGPoint, notifyState: Bool) {
        let display = displayProvider.display(containing: point)
            ?? displayProvider.displays.first
        guard let display else { return }

        let changed = display.id != activeDisplayID
        activeDisplayID = display.id

        let candidate = windowProvider.candidate(at: point, on: display)
        if notifyState {
            state.pointerMoved(to: point, display: display, window: candidate)
        } else {
            // start() 的首帧：直接初始化 targeting 阶段。
            state = CaptureSessionState()
            state.pointerMoved(to: point, display: display, window: candidate)
        }
        syncOverlays()
        if changed {
            logger.debug("Active capture display switched to \(display.id)")
        }
    }

    /// 把当前状态同步到各叠层：仅活动屏显示高亮/区域/提示。
    private func syncOverlays() {
        // 标注态下 `syncOverlays` 仍会被会话内部调用（例如拓扑重建）：此时**不得**重画
        // 选区与提示，否则用户正编辑的画面会闪一下、甚至被重置。
        if isAnnotating { return }
        for (displayID, window) in overlayWindows {
            let isActive = displayID == activeDisplayID
            window.setActive(isActive)
            window.updateHints(ScreenshotShortcutHints.hints(for: state.phase))

            switch state.phase {
            case .targetingWindow(let candidate):
                window.updateHighlight(window: isActive ? candidate : nil)
                // Task 012：控件高亮与窗口高亮可并存，控件优先级更高。
                window.updateElementHighlight(frame: isActive ? state.hoveredElementFrame : nil)
                // PRD「截图与贴图」规则 2/5：候选为空（菜单栏/桌面空白悬停）时，
                // 活动屏按整屏范围复用区域选框绘制路径，让“默认选中当前显示器全屏”可见。
                window.updateRegion(rect: isActive && candidate == nil ? window.display.frame : nil)
            case .draggingRegion(let start, let current, _):
                window.updateHighlight(window: nil)
                window.updateElementHighlight(frame: nil)
                window.updateRegion(rect: isActive ? Self.regionRect(start: start, current: current) : nil)
            case .adjustingRegion(_, let globalRect):
                // Task 014/01：可微调态下持续显示选区，等待 Enter 确认。
                window.updateHighlight(window: nil)
                window.updateElementHighlight(frame: nil)
                window.updateRegion(rect: isActive ? globalRect : nil)
            case .locked(let target):
                window.updateHighlight(window: nil)
                window.updateElementHighlight(frame: nil)
                window.updateRegion(rect: isActive ? Self.lockedRect(for: target, displayID: displayID) : nil)
            case .cancelled:
                window.updateHighlight(window: nil)
                window.updateElementHighlight(frame: nil)
                window.updateRegion(rect: nil)
            }
        }
    }

    private static func regionRect(start: CGPoint, current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private static func lockedRect(for target: CaptureTarget, displayID: CGDirectDisplayID) -> CGRect? {        switch target {
        case .window(let candidate):
            return candidate.displayID == displayID ? candidate.frame : nil
        case .region(_, let globalRect):
            return globalRect
        case .display:
            return nil
        }
    }

    // MARK: - Element probe and snapping (Task 012)

    /// 惰性触发一次控件级探测；关闭时立即返回，不产生任何调用。
    private func scheduleElementProbe(at point: CGPoint) {
        guard elementProbeOptions.isElementProbingEnabled else { return }
        guard let display = displayProvider.display(containing: point) else { return }
        probeScheduler.schedule(point: point, display: display, options: elementProbeOptions)
    }

    /// 取消在途探测：会话结束、开始拖拽、跨屏切换时调用。
    private func cancelElementProbe() {
        probeScheduler.cancel()
    }

    /// 拖拽中的点吸附到最近的候选边；吸附关闭或没有候选时原样返回。
    private func snapDragPoint(_ point: CGPoint) -> CGPoint {
        guard snapThreshold > 0, let display = displayProvider.display(containing: point) else {
            return point
        }
        return CandidateHitTest.snap(
            point: point,
            candidates: candidateRegions(on: display),
            threshold: snapThreshold
        )
    }

    /// 吸附候选：该显示器上全部可见窗口 + 当前悬停控件。
    private func candidateRegions(on display: CaptureDisplay) -> [CandidateRegion] {
        var regions = windowProvider.regions(on: display)
        if let element = state.hoveredElementFrame {
            regions.append(CandidateRegion(kind: .element, frame: element))
        }
        return regions
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuild()
            }
        }
    }

    private func removeScreenObserver() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
    }
}

// MARK: - Live display provider

/// 真实显示器来源：映射 `NSScreen.screens`；UI 测试可用
/// `--uitest-screenshot-displays 2` 合成双显示器拓扑。
final class NSScreenDisplayProvider: DisplayProviding {
    private let forcedDisplayCount: Int?

    init(forcedDisplayCount: Int? = nil) {
        self.forcedDisplayCount = forcedDisplayCount
    }

    var displays: [CaptureDisplay] {
        if let forcedDisplayCount, forcedDisplayCount > 0,
           let base = NSScreen.screens.first {
            // UI 测试钩子：把主屏水平切成 N 份模拟多显示器拓扑。
            let width = base.frame.width / CGFloat(forcedDisplayCount)
            let pixelWidth = max(1, base.frame.width / CGFloat(forcedDisplayCount)) * 1
            return (0..<forcedDisplayCount).map { index in
                CaptureDisplay(
                    id: CGDirectDisplayID(9_000 + index),
                    frame: CGRect(
                        x: base.frame.minX + width * CGFloat(index),
                        y: base.frame.minY,
                        width: width,
                        height: base.frame.height
                    ),
                    pixelSize: CGSize(width: pixelWidth, height: base.frame.height)
                )
            }
        }
        return NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return CaptureDisplay(
                id: displayID,
                frame: screen.frame,
                pixelSize: CaptureDisplayInfo.pixelSize(displayID: displayID)
            )
        }
    }

    func display(containing point: CGPoint) -> CaptureDisplay? {
        displays.first { $0.frame.contains(point) }
    }
}
