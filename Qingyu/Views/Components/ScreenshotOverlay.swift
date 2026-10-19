import Cocoa
import os.log

/// 截图会话取消广播：`ScreenshotWindowController` 在统一会话取消时发出，
/// `ScreenshotToolbarController` 监听后关闭已打开的预览/工具条。
extension Notification.Name {
    static let screenshotOverlayDidCancel = Notification.Name("com.freeabyss.qingyu.screenshotOverlayDidCancel")
}

// MARK: - CaptureOverlayWindowController (Task 006)

/// 截图叠层专用窗口：borderless 全屏压暗层。
/// borderless 窗口默认不能成为 key 窗口，而叠层键盘交互（Esc/⌘A）依赖 key 窗口
/// （同 Task 008 `PinNSWindow` 的处理）。
final class CaptureOverlayNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// `CaptureOverlayWindow` 的具体实现：每显示器一个 borderless 全屏窗口。
/// 只绘制与接收事件；会话状态保存在 `CaptureSessionController`。
final class CaptureOverlayWindowController: CaptureOverlayWindow {
    let display: CaptureDisplay
    var onEvent: ((CaptureInputEvent) -> Void)? {
        get { contentView.onEvent }
        set { contentView.onEvent = newValue }
    }
    private let window: NSWindow
    private let contentView: CaptureOverlayContentView
    private var closed = false

    init(display: CaptureDisplay, magnifierConfiguration: MagnifierConfiguration = .default) {
        self.display = display

        let window = CaptureOverlayNSWindow(
            contentRect: display.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        let view = CaptureOverlayContentView(
            frame: NSRect(origin: .zero, size: display.frame.size),
            display: display,
            magnifierConfiguration: magnifierConfiguration
        )
        window.contentView = view

        self.window = window
        self.contentView = view
    }

    func makeKey() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
    }

    func setActive(_ active: Bool) {
        // 指针在活动屏上移动时 syncOverlays 每帧都会调到这里；只有「切换到本屏」
        // 才需要 makeKeyAndOrderFront。此前无条件 makeKey，鼠标一动就重新排序窗口
        // （实测约 150 次/秒），既浪费合成，也会让正在进行的拖拽/落笔抖动。
        let wasActive = contentView.isActiveDisplay
        guard wasActive != active else { return }
        contentView.isActiveDisplay = active
        contentView.hintsView?.isHidden = !active
        // 只有活动显示器持有 key 窗口：Esc/⌘A 只路由到该屏，
        // 跨屏切换时旧屏让出 key，避免多窗互相争抢。
        if active {
            makeKey()
        }
    }

    func updateHighlight(window candidate: CaptureWindowCandidate?) {
        contentView.highlightFrame = candidate?.frame
        contentView.needsDisplay = true
    }

    /// Task 012：控件级高亮。
    func updateElementHighlight(frame: CGRect?) {
        contentView.elementFrame = frame
        contentView.needsDisplay = true
    }

    func updateRegion(rect: CGRect?) {
        contentView.regionFrame = rect
        contentView.needsDisplay = true
    }

    // MARK: - 原地标注

    /// 捕获前让位：只收放大镜（它压在选区里会被拍进位图），叠层本身不动。
    func prepareForAnnotationCapture() {
        contentView.prepareForAnnotationCapture()
    }

    /// 进入原地标注：叠层本身保持原样（压暗、边框、尺寸徽标都不变），
    /// 只在选区内新增一层可编辑的标注画布。
    ///
    /// **签名必须与 CaptureOverlayWindow 的协议要求完全一致（返回 Bool）**。
    /// 曾经这里写成 -> Void：协议于是静默地用了扩展里的默认实现（直接返回 false、
    /// 什么都不做），而会话仍然把 isAnnotating 置为 true —— 用户点方形后能进标注，
    /// 但内容视图没有 annotationSession，怎么拖都画不出图形。回归见 SHOT-LIFE-016。
    @discardableResult
    func beginAnnotation(
        image: NSImage,
        regionGlobal: CGRect,
        tool: AnnotationTool,
        style: AnnotationStyle
    ) -> Bool {
        contentView.beginAnnotation(
            image: image,
            regionGlobal: regionGlobal,
            tool: tool,
            style: style
        )
        return contentView.isAnnotating
    }

    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle) {
        contentView.updateAnnotationTool(tool, style: style)
    }

    /// 单测入口：落笔/命中都直接走内容视图的鼠标方法（测试宿主里无法合成真实全局事件）。
    var contentViewForTesting: CaptureOverlayContentView { contentView }

    func undoAnnotation() { contentView.undoAnnotation() }
    func redoAnnotation() { contentView.redoAnnotation() }
    var annotationShapes: [AnnotationShape] { contentView.annotationShapes }
    var isAnnotating: Bool { contentView.isAnnotating }

    /// 离开标注态（Esc 退回微调、或动作收尾）。标注结果一并丢弃（会话结束不留状态）。
    func endAnnotation() {
        contentView.clearAnnotation()
        contentView.needsDisplay = true
    }

    func setAnnotationTextRequestHandler(_ handler: @escaping (CGPoint, @escaping (String?) -> Void) -> Void) {
        contentView.onAnnotationTextRequest = handler
    }

    func updateHints(_ hintKeys: [String]) {
        contentView.updateHints(hintKeys)
    }

    // MARK: - Preset picker (Task 015)

    func updatePresetPicker(items: [String], selectedIndex: Int?) {
        contentView.updatePresetPicker(items: items, selectedIndex: selectedIndex)
        // 只有活动屏持有 key 窗口；非活动屏的清单不会渲染，但其内容仍需同步，
        // 以便跨屏切换后立即显示正确的高亮项。
    }

    func updateNotice(_ text: String?) {
        contentView.updateNotice(text)
    }

    func orderFront() {
        // 仅上屏，不争 key：makeKey 由 setActive(true) 分支统一负责。
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func close() {
        guard !closed else { return }
        closed = true
        contentView.cancelMagnifier()
        window.orderOut(nil)
        window.contentView = nil
    }
}

// MARK: - CaptureOverlayContentView

/// 统一叠层内容视图：压暗背景、窗口高亮、区域选框与快捷键提示。
/// 本地坐标 → 全局 AppKit 坐标经 `display.frame.origin` 偏移后上抛事件。
final class CaptureOverlayContentView: NSView, NSTextFieldDelegate {
    let display: CaptureDisplay
    var isActiveDisplay = false {
        didSet {
            guard isActiveDisplay != oldValue else { return }
            updateHintsVisibility()
            // 跨屏切换必须整屏重绘：新活动屏要压暗，旧活动屏要恢复透明。
            needsDisplay = true
        }
    }
    var highlightFrame: NSRect? {
        didSet { if highlightFrame != oldValue { needsDisplay = true } }
    }
    /// Task 012：控件级高亮（AppKit 全局坐标）。
    var elementFrame: NSRect? {
        didSet { if elementFrame != oldValue { needsDisplay = true } }
    }
    /// 选区（AppKit 全局坐标）。**每一次变化都必须整屏重绘**：只重绘一条带会把
    /// 上一次选区的「挖空」留在 backing store 里，画面上就是一块/一条更暗的区域。
    var regionFrame: NSRect? {
        didSet {
            if regionFrame != oldValue { needsDisplay = true }
            updateMagnifierMask()
        }
    }
    var onEvent: ((CaptureInputEvent) -> Void)?
    /// 已进入「原地标注」：选区已锁定，鼠标/键盘归属标注会话，不再上抛截图事件。
    ///
    /// 标注期间叠层的一切外观（压暗、选区边框与尺寸徽标）保持不变 —— 用户点工具
    /// 之后只该看到光标变化，这是 PRD「选中工具栏时页面无变化」的硬要求。
    var isAnnotating = false
    private var annotationSession: InPlaceAnnotationSession?
    /// 文字/提示框工具需要输入框；由叠层上抛给工具条控制器去弹。
    var onAnnotationTextRequest: ((CGPoint, @escaping (String?) -> Void) -> Void)?
    /// 原地文字输入：直接在光标处放一个 NSTextField，不再弹系统对话框。
    private var inlineTextEditor: NSTextField?
    private var inlineTextPoint: CGPoint?
    private var inlineTextTool: AnnotationTool?
    private var inlineTextStyle: AnnotationStyle?

    /// Task 015：预设清单（`selectedIndex` 为 nil 表示清单未打开）。
    var presetPickerItems: [String] = [] {
        didSet { if presetPickerItems != oldValue { needsDisplay = true } }
    }
    var presetPickerSelection: Int? {
        didSet { if presetPickerSelection != oldValue { needsDisplay = true } }
    }
    /// Task 015：内联提示（屏幕已断开 / 预设已满等）。
    var noticeText: String? {
        didSet { if noticeText != oldValue { needsDisplay = true } }
    }

    fileprivate private(set) var hintsView: ScreenshotShortcutHintsView?
    /// Task 014/06：本次拖拽的起点与锁定的长宽比。
    private var dragStartPoint: CGPoint?
    private var lockedAspectRatio: CGFloat?
    /// Task 014/01：`Tab` 是否按下（按下期间显示对齐辅助线）。
    private var showsAlignmentGuides = false

    // Task 011：放大镜。取样在叠层下方进行，因此关闭时不会拍到自己的暗幕。
    private let magnifierConfiguration: MagnifierConfiguration
    private let magnifierSource: MagnifierSourcing?
    private let magnifierView = MagnifierOverlayView(frame: .zero)
    private var lastPointerGlobal: CGPoint?
    /// 选区已落定（拖拽结束/进入标注）后不再显示放大镜：它会压在选区边缘上，
    /// 用户会读成一块跟着光标走的暗色方块（2026-10-19 报告）。
    private var magnifierSuppressed = false

    init(
        frame frameRect: NSRect,
        display: CaptureDisplay,
        magnifierConfiguration: MagnifierConfiguration = .default
    ) {
        self.display = display
        let configuration = magnifierConfiguration.sanitized()
        self.magnifierConfiguration = configuration
        self.magnifierSource = configuration.isEnabled ? BelowWindowMagnifierSource() : nil
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
        let hints = ScreenshotShortcutHintsView()
        hints.frame = ScreenshotShortcutHintsView.frame(in: display, hintCount: ScreenshotShortcutHints.windowSelectionKeys.count)
        addSubview(hints)
        hintsView = hints
        hints.isHidden = !isActiveDisplay

        magnifierView.configuration = magnifierConfiguration
        magnifierView.isHidden = true
        addSubview(magnifierView)
        magnifierSource?.onSample = { [weak self] sample in
            self?.applyMagnifierSample(sample)
        }
    }

    func updateHints(_ hintKeys: [String]) {
        hintsView?.update(hintKeys: hintKeys)
    }

    // MARK: - Preset picker (Task 015)

    func updatePresetPicker(items: [String], selectedIndex: Int?) {
        presetPickerItems = items
        presetPickerSelection = selectedIndex
    }

    func updateNotice(_ text: String?) {
        noticeText = text
    }

    private func updateHintsVisibility() {
        hintsView?.isHidden = !isActiveDisplay
        if !isActiveDisplay {
            hideMagnifier()
        }
    }

    // MARK: - Magnifier (Task 011)

    /// 请求一次放大镜取样。放大镜关闭或窗口号不可用时直接返回，不产生系统调用。
    private func requestMagnifierSample(at global: CGPoint) {
        guard let magnifierSource, magnifierConfiguration.isEnabled else { return }
        guard let windowNumber = window?.windowNumber, windowNumber > 0 else { return }
        lastPointerGlobal = global
        magnifierSource.request(MagnifierRequest(
            displayID: display.id,
            appKitSamplePoint: global,
            pixelCount: magnifierConfiguration.pixelCount,
            screenFrame: display.frame,
            displayPixelSize: display.pixelSize,
            mainDisplayHeight: Self.mainDisplayHeight,
            belowWindowNumber: CGWindowID(windowNumber)
        ))
    }

    /// 取样到达：更新画面并按当前指针定位放大镜框。
    private func applyMagnifierSample(_ sample: MagnifierSample) {
        guard isActiveDisplay, magnifierConfiguration.isEnabled, let anchor = lastPointerGlobal else { return }
        magnifierView.update(sample: sample)
        let size = CGSize(
            width: MagnifierConfiguration.viewSize,
            height: MagnifierConfiguration.viewSize
        )
        let globalFrame = MagnifierGeometry.magnifierFrame(
            anchor: anchor,
            size: size,
            visibleFrame: display.frame,
            gap: MagnifierConfiguration.anchorGap
        )
        magnifierView.frame = globalFrame.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        updateMagnifierMask()
        magnifierView.isHidden = false
    }

    /// 把当前选区换算到显示器像素坐标，供放大镜内的遮罩使用。
    private func updateMagnifierMask() {
        guard let region = regionFrame else {
            magnifierView.maskRectInPixels = nil
            return
        }
        let scale = MagnifierGeometry.displayScale(frame: display.frame, pixelSize: display.pixelSize)
        let topLeft = MagnifierGeometry.samplePoint(
            logicalPoint: CGPoint(x: region.minX, y: region.maxY),
            screenFrame: display.frame,
            scale: scale
        )
        magnifierView.maskRectInPixels = CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: region.width * scale,
            height: region.height * scale
        )
    }

    private func hideMagnifier() {
        magnifierSource?.cancel()
        magnifierView.clearSample()
        magnifierView.isHidden = true
    }

    /// 会话结束时调用：取消在途取样并断开回调，避免结果打到已关闭的视图。
    func cancelMagnifier() {
        hideMagnifier()
        magnifierSource?.onSample = nil
    }

    /// AppKit 原点所在显示器的逻辑高度，用于换算 `CGWindowListCreateImage` 的屏幕坐标。
    private static var mainDisplayHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    override var acceptsFirstResponder: Bool { true }

    /// 第一次点击就要落到叠层上，而不是只被用来「激活窗口」。
    ///
    /// 区域工具条是独立窗口；用户点完某个工具（尤其是工具条短暂成为 key 时）
    /// 再回选区内落笔，第一次按下会被 AppKit 当作激活窗口吃掉 —— 表现就是
    /// 「选中方形后拖不出方形」。与旧标注窗 AnnotationCanvasNSView 同一处理。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func globalPoint(_ localPoint: NSPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x + display.frame.minX,
            y: localPoint.y + display.frame.minY
        )
    }

    // MARK: - 原地标注（选区上直接编辑）

    /// 进入原地标注：选区已锁定，叠层继续压暗、继续画选区边框，只在选区内加一层可绘制区域。
    ///
    /// - Parameters:
    ///   - image: 选区的原始像素（懒捕获得到，不含放大镜）。
    ///   - regionGlobal: 选区（AppKit 全局坐标）。
    ///   - tool / style: 工具条上刚刚选中的工具与样式。
    func beginAnnotation(
        image: NSImage,
        regionGlobal: NSRect,
        tool: AnnotationTool,
        style: AnnotationStyle
    ) {
        let session = InPlaceAnnotationSession(
            image: image,
            regionGlobalRect: regionGlobal,
            displayFrame: display.frame
        )
        session.state.tool = tool
        session.state.style = style
        annotationSession = session
        isAnnotating = true
        regionFrame = regionGlobal
        // 标注期间不再需要放大镜：它压在选区里会遮挡正在编辑的画面，
        // 也会被后续的「复制/保存」渲染路径读到。标注模式由光标提示工具。
        magnifierSuppressed = true
        hideMagnifier()
        Self.setAnnotationCursor(for: tool, style: style)
        window?.invalidateCursorRects(for: self)
        // 叠层上的一切（提示条、预设清单、内联提示）**保持原样**：
        // 用户预期「点工具之后除了光标与工具高亮之外没有变化」。
        needsDisplay = true
    }

    /// 切换工具：只换高亮与光标，画面其余部分一动不动。
    func updateAnnotationTool(_ tool: AnnotationTool, style: AnnotationStyle) {
        guard let session = annotationSession else { return }
        session.state.tool = tool
        session.state.style = style
        Self.setAnnotationCursor(for: tool, style: style)
    }

    /// 当前标注结果（按选择顺序排列）。未进入标注时返回空。
    var annotationShapes: [AnnotationShape] {
        annotationSession?.state.shapes ?? []
    }

    /// 捕获前让位：只收放大镜。放大镜是本 App 自己的窗口、不在叠层之内，
    /// 但会盖在选区上被 `CGDisplayCreateImage` 一起拍进去（实测亮度 243 → 215）。
    func prepareForAnnotationCapture() {
        hideMagnifier()
    }

    /// 离开标注态：丢弃本次标注（会话结束后不再保留任何状态）。
    func clearAnnotation() {
        cancelInlineText()
        annotationSession = nil
        isAnnotating = false
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - 原地文字输入

    /// 文字 / 提示框：在当前落点处直接出现输入框，不再弹系统对话框。
    ///
    /// 输入框是叠层上的一个子视图，坐标用「选区局部点」；回车提交、Esc 取消、
    /// 点到框外也提交。提交后由标注会话把文字追加成一条标注。
    private func beginInlineText(at point: CGPoint, tool: AnnotationTool, style: AnnotationStyle) {
        guard let session = annotationSession else { return }
        commitInlineText()

        let region = session.localRect
        let fontSize = max(14, style.textSize.points)
        let width = min(260, max(120, region.width - 12))
        let height = max(24, fontSize + 12)
        var origin = CGPoint(x: region.minX + point.x, y: region.minY + point.y)
        origin.x = min(max(origin.x, region.minX + 4), max(region.minX + 4, region.maxX - width - 4))
        origin.y = min(max(origin.y, region.minY + 4), max(region.minY + 4, region.maxY - height - 4))

        let field = NSTextField(frame: NSRect(origin: origin, size: NSSize(width: width, height: height)))
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        field.textColor = style.color.nsColor
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        field.focusRingType = .none
        field.placeholderString = L10n.localized("annotation.textInput.placeholder")
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.delegate = self
        addSubview(field)

        inlineTextPoint = point
        inlineTextTool = tool
        inlineTextStyle = style
        inlineTextEditor = field
        window?.makeFirstResponder(field)
    }

    /// 提交输入框内容（空内容等于取消）。
    private func commitInlineText() {
        guard let field = inlineTextEditor else { return }
        let text = field.stringValue
        let point = inlineTextPoint
        let tool = inlineTextTool
        let style = inlineTextStyle
        teardownInlineText()
        guard let point, let tool, let style,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let session = annotationSession else { return }
        session.appendText(at: point, text: text, tool: tool, style: style)
        needsDisplay = true
    }

    private func cancelInlineText() {
        teardownInlineText()
    }

    private func teardownInlineText() {
        guard let field = inlineTextEditor else { return }
        inlineTextEditor = nil
        inlineTextPoint = nil
        inlineTextTool = nil
        inlineTextStyle = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitInlineText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelInlineText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // 失焦（例如点工具条）按提交处理；teardown 已清空时不再递归。
        if inlineTextEditor != nil {
            commitInlineText()
        }
    }

    /// 撤销/重做（工具条或 ⌘Z/⌘⇧Z）。
    func undoAnnotation() {
        annotationSession?.state.undo()
        needsDisplay = true
    }

    func redoAnnotation() {
        annotationSession?.state.redo()
        needsDisplay = true
    }

    /// 光标：每个工具有自己的「十字准星 + 工具徽标」，且只在选区上出现。
    private static func setAnnotationCursor(for tool: AnnotationTool, style: AnnotationStyle) {
        AnnotationToolCursor.cursor(for: tool, style: style).set()
    }

    /// 指针是否在选区内：标注光标只在选区内生效，选区外恢复箭头（用户预期第 2 条）。
    private func updateAnnotationCursor(at global: CGPoint, inRegion: Bool) {
        guard isAnnotating, let session = annotationSession else { return }
        if inRegion {
            AnnotationToolCursor.cursor(for: session.state.tool, style: session.state.style).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Events

    override func resetCursorRects() {
        super.resetCursorRects()
        // 标注期间：选区内用工具光标，选区外保持箭头（「光标只有在截图区域才会变化」）。
        guard isAnnotating, let session = annotationSession else { return }
        addCursorRect(
            session.localRect,
            cursor: AnnotationToolCursor.cursor(for: session.state.tool, style: session.state.style)
        )
    }

    /// 光标离开叠层：标注光标不得粘在选区外（`resetCursorRects` 只覆盖选区，
    /// 但显式 `set()` 过的光标不会自动回弹）。
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard isAnnotating else { return }
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let global = globalPoint(convert(event.locationInWindow, from: nil))
        if isAnnotating, let session = annotationSession {
            let inside = session.contains(global: global)
            updateAnnotationCursor(at: global, inRegion: inside)
            if session.mouseMoved(to: global) {
                needsDisplay = true
            }
            return
        }
        // 非活动屏也必须上报指针：会话据此把「当前截图显示器」切到指针所在屏
        // （压暗、高亮与提示随之切换）。放大镜只在活动屏取样，避免无谓抓屏。
        onEvent?(.pointerMoved(global))
        if isActiveDisplay, !magnifierSuppressed {
            requestMagnifierSample(at: global)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // 文字输入框还开着：点框外视为提交，不要在输入过程中误画图形。
        if inlineTextEditor != nil {
            commitInlineText()
            return
        }
        // 落笔同时把叠层重新拿回 key：工具条/输入面板可能刚短暂夺过 key，
        // 不拿回来则后续 Esc、⌘Z、方向键会落到工具条上。
        window?.makeKey()
        window?.makeFirstResponder(self)
        let global = globalPoint(convert(event.locationInWindow, from: nil))
        if isAnnotating, let session = annotationSession {
            guard session.contains(global: global) else { return }
            switch session.mouseDown(at: global) {
            case .consumed:
                needsDisplay = true
            case .needsText(let local):
                beginInlineText(at: local, tool: session.state.tool, style: session.state.style)
            case .ignored:
                break
            }
            return
        }
        // Task 014/06：每次拖拽重新捕获长宽比。
        magnifierSuppressed = false
        dragStartPoint = global
        lockedAspectRatio = nil
        onEvent?(.mouseDown(global))
    }

    override func mouseDragged(with event: NSEvent) {
        // 拖拽可能跨屏：起点在本窗口、后续事件落在对侧窗口时，只有对侧能收到。
        // 因此这里不按本窗口的按下状态过滤，是否处于拖拽一律由会话状态机判定。
        var global = globalPoint(convert(event.locationInWindow, from: nil))

        if isAnnotating, let session = annotationSession {
            if session.mouseDragged(to: global) {
                needsDisplay = true
            }
            return
        }

        // Task 014/06：按住 ⇧ 锁定长宽比 —— 首次按下时以"当时的选区比例"为准，
        // 之后沿该比例投影；松开 ⇧ 立即恢复自由拖拽。
        if event.modifierFlags.contains(.shift), let start = dragStartPoint {
            if lockedAspectRatio == nil {
                lockedAspectRatio = SelectionAspectLock.ratio(
                    of: Self.regionRect(from: start, to: global)
                )
            }
            if let ratio = lockedAspectRatio {
                global = SelectionAspectLock.project(start: start, current: global, ratio: ratio)
            }
        } else {
            lockedAspectRatio = nil
        }

        onEvent?(.mouseDragged(global))
        // 拖拽过程不产生 mouseMoved；放大镜必须跟随，否则圈选时画面会停住。
        requestMagnifierSample(at: global)
    }

    override func mouseUp(with event: NSEvent) {
        // 同上：抬起可能落在另一个显示器的窗口上（拖拽跨屏），这里不再过滤。
        // 会话状态机只在拖拽态响应抬起，窗口/整屏之外的杂散抬起天然被忽略。
        if isAnnotating, let session = annotationSession {
            if session.mouseUp(at: globalPoint(convert(event.locationInWindow, from: nil))) {
                needsDisplay = true
            }
            return
        }
        dragStartPoint = nil
        lockedAspectRatio = nil
        onEvent?(.mouseUp(globalPoint(convert(event.locationInWindow, from: nil))))
        // 选区已落定：收起放大镜，之后鼠标在选区里移动也不再弹出。
        magnifierSuppressed = true
        hideMagnifier()
    }

    /// 两点构成的标准化矩形（与控制器里的选区推导一致）。
    private static func regionRect(from start: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func keyDown(with event: NSEvent) {
        // 原地标注：Esc 退回「选区可微调」态，⌘Z/⌘⇧Z 撤销重做，
        // `[` `]` 调笔宽；其余按键交回叠层原有语义。
        if isAnnotating, let session = annotationSession {
            switch event.keyCode {
            case 53:
                onEvent?(.cancelAnnotation)
                return
            case 6 where event.modifierFlags.contains(.command):      // ⌘Z
                if event.modifierFlags.contains(.shift) {
                    session.state.redo()
                } else {
                    session.state.undo()
                }
                needsDisplay = true
                return
            default:
                break
            }
            if let characters = event.charactersIgnoringModifiers, !event.modifierFlags.contains(.command) {
                if characters == "[" || characters == "]" {
                    let step = AnnotationLineWidthStepper.step(
                        session.state.style.lineWidth,
                        direction: characters == "]" ? 1 : -1
                    )
                    session.state.style.lineWidth = step
                    return
                }
            }
            super.keyDown(with: event)
            return
        }
        // Task 015：清单打开时独占方向键 / Enter / Esc，避免与选区微调冲突。
        if presetPickerSelection != nil {
            switch event.keyCode {
            case 126: onEvent?(.movePresetSelection(delta: -1)); return   // ↑
            case 125: onEvent?(.movePresetSelection(delta: 1)); return    // ↓
            case 36, 76: onEvent?(.applySelectedPreset); return           // Return / Enter
            case 53: onEvent?(.closePresetPicker); return                 // Esc
            default:
                super.keyDown(with: event)
                return
            }
        }
        // Task 015：`P` 打开清单；`⌘S` / `⌘⇧S` 把当前选区存为区域 / 尺寸预设。
        if event.keyCode == 35, !event.modifierFlags.contains(.command) {
            onEvent?(.openPresetPicker)
            return
        }
        if event.keyCode == 1, event.modifierFlags.contains(.command) {   // ⌘S
            onEvent?(.saveCurrentSelectionAsPreset(
                kind: event.modifierFlags.contains(.shift) ? .size : .region
            ))
            return
        }
        // Task 014/01：`Tab` 按住显示对齐辅助线。
        if event.keyCode == 48 {
            showsAlignmentGuides = true
            needsDisplay = true
            return
        }
        // Task 014/01：方向键微调 1 物理像素；`⇧` + 方向键沿该轴对称伸缩。
        if let axis = Self.nudgeAxis(for: event.keyCode) {
            let direction: CGFloat = (event.keyCode == 123 || event.keyCode == 125) ? -1 : 1
            onEvent?(.nudgeSelection(
                axis: axis,
                delta: nudgeStep * direction,
                resize: event.modifierFlags.contains(.shift)
            ))
            return
        }
        switch event.keyCode {
        case 36, 76: onEvent?(.confirmSelection)         // Return / 小键盘 Enter
        case 53: onEvent?(.cancel)                       // Esc
        case 0 where event.modifierFlags.contains(.command): onEvent?(.selectFullDisplay) // ⌘A
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 48 {
            showsAlignmentGuides = false
            needsDisplay = true
            return
        }
        super.keyUp(with: event)
    }

    /// 方向键 → 轴：左右为水平，上下为垂直。
    private static func nudgeAxis(for keyCode: UInt16) -> SelectionNudge.Axis? {
        switch keyCode {
        case 123, 124: return .horizontal
        case 125, 126: return .vertical
        default: return nil
        }
    }

    /// 1 个**物理像素**换算成逻辑点；1×/2× 屏上「一格」都是 1px。
    private var nudgeStep: CGFloat {
        let scale = MagnifierGeometry.displayScale(frame: display.frame, pixelSize: display.pixelSize)
        return 1 / max(scale, 0.0001)
    }

    // MARK: - Preset picker 布局（纯函数，便于单测）

    /// 清单每一项的行高。
    static let presetPickerRowHeight: CGFloat = 26
    /// 清单面板宽度。
    static let presetPickerWidth: CGFloat = 260

    /// 清单面板矩形（叠层本地坐标，居中偏上）。
    static func presetPickerFrame(itemCount: Int, in bounds: NSRect) -> NSRect {
        let height = CGFloat(max(itemCount, 1)) * presetPickerRowHeight + 16
        return NSRect(
            x: bounds.midX - presetPickerWidth / 2,
            y: bounds.midY - height / 2,
            width: presetPickerWidth,
            height: height
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 每一步都必须**只在干净的原始画布上**叠一次。此前直接用 `dirtyRect.fill()`
        // 铺 30% 黑：叠层是半透明窗口，合成结果留在 backing store 里，下一次重绘
        // 又在这一层之上再铺一次，于是被重绘过的区域越叠越黑 —— 用户看到的是
        // 「选区左上角多出一块暗色方块」（旧窗口高亮/旧选区的那块矩形被重绘过两次以上）。
        //
        // 做法：先把本屏整张画布清成透明，再按 =30% 黑一次性铺满；之后所有挖空
        // （`.copy` 填 clear）与边框、标注都只作用在这一层之上。
        //
        // 清空必须在 `isActiveDisplay` 判断**之前**：非活动屏同样会收到 `needsDisplay`
        // （跨屏切换时原活动屏正是这样），若在这里早退，窗口会把上一次的压暗与挖空
        // 原样留在 backing store 里 —— 用户看到的就是「一块滞留的暗色区域」。
        //
        // **先解除 AppKit 的 dirtyRect 裁剪**：只清 dirtyRect 时，上一次选区挖空的
        // 透明区域若不在这次 dirtyRect 内就会原样留着；等它变成压暗区时就成了
        // 「一条贯穿全屏的竖向暗带」。整屏重算一次，压暗永远只有一层。
        NSGraphicsContext.current?.cgContext.resetClip()
        NSColor.clear.set()
        bounds.fill(using: .copy)

        // 只有当前指针所在显示器压暗，其他显示器保持原样：指针移到哪块屏，
        // 哪块屏变暗、原屏恢复（跨屏由 `mouseMoved` 上报的 `.pointerMoved` 驱动）。
        // 非活动屏仍保留窗口以接收指针事件，否则指针移过去时无人上报、会话卡在原屏。
        guard isActiveDisplay else { return }

        NSColor.black.withAlphaComponent(0.3).set()
        bounds.fill()

        // 活动屏：窗口高亮（穿透显示 + Jade 边框）。
        if isActiveDisplay, let highlight = highlightFrame {
            let local = highlight.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            NSColor.clear.set()
            local.fill(using: .copy)

            JadeColor.primaryNS.withAlphaComponent(0.2).setFill()
            NSBezierPath(rect: local).fill()
            JadeColor.primaryNS.set()
            let border = NSBezierPath(rect: local)
            border.lineWidth = 2
            border.stroke()
        }

        // Task 012：控件高亮。用更细的边框与更淡的填充与窗口高亮区分，
        // 两者嵌套时仍能看清「控件落在哪个窗口里」。
        if isActiveDisplay, let element = elementFrame {
            let local = element.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            NSColor.clear.set()
            local.fill(using: .copy)

            JadeColor.primaryNS.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: local).fill()
            JadeColor.primaryNS.set()
            let elementBorder = NSBezierPath(rect: local)
            elementBorder.lineWidth = 1
            elementBorder.stroke()
        }

        // 区域选框（拖拽中或已锁定）。
        if let region = regionFrame {
            let local = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            NSColor.clear.set()
            local.fill(using: .copy)

            NSColor.white.set()
            let border = NSBezierPath(rect: local)
            border.lineWidth = 2
            border.stroke()

            drawDimensions(for: local)

            // Task 014/01：`Tab` 按住时显示对齐辅助线（标注期间不画，免得盖住编辑内容）。
            if showsAlignmentGuides, !isAnnotating {
                drawAlignmentGuides(for: local)
            }

            // 原地标注：形状坐标就是「选区局部点」，平移到选区左下角即可绘制。
            if isAnnotating, let session = annotationSession {
                let context = NSGraphicsContext.current?.cgContext
                context?.saveGState()
                context?.clip(to: local)
                context?.translateBy(x: local.minX, y: local.minY)
                session.draw()
                context?.restoreGState()
            }
        }

        // Task 015：仅在活动屏绘制预设清单与内联提示。
        if isActiveDisplay {
            drawPresetPicker()
            drawNotice()
        }
    }

    /// 预设清单面板：高亮当前项，并在每项左侧标出种类。
    private func drawPresetPicker() {
        guard let selection = presetPickerSelection, !presetPickerItems.isEmpty else { return }
        let panel = Self.presetPickerFrame(itemCount: presetPickerItems.count, in: bounds)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()

        for (index, label) in presetPickerItems.enumerated() {
            // 自下而上排列：第 0 项在最上方。
            let rowY = panel.maxY - 8 - CGFloat(index + 1) * Self.presetPickerRowHeight
            let row = NSRect(
                x: panel.minX + 8,
                y: rowY,
                width: panel.width - 16,
                height: Self.presetPickerRowHeight
            )
            if index == selection {
                JadeColor.primaryNS.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: row.minX + 8, y: row.midY - size.height / 2))
        }
    }

    /// 内联提示：底部居中一行，用于「目标屏幕已断开」「预设已满」等。
    private func drawNotice() {
        guard let noticeText, !noticeText.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: noticeText, attributes: attributes)
        let size = text.size()
        let box = NSRect(
            x: bounds.midX - size.width / 2 - 12,
            y: bounds.minY + 72,
            width: size.width + 24,
            height: size.height + 12
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: box.minX + 12, y: box.midY - size.height / 2))
    }

    /// 对齐辅助线：把选区四边与中线延伸到整屏，并叠一层屏幕中心十字。
    private func drawAlignmentGuides(for rect: NSRect) {
        let dash: [CGFloat] = [4, 3]

        let regionPath = NSBezierPath()
        regionPath.setLineDash(dash, count: dash.count, phase: 0)
        regionPath.lineWidth = 1
        for x in [rect.minX, rect.midX, rect.maxX] {
            regionPath.move(to: NSPoint(x: x, y: bounds.minY))
            regionPath.line(to: NSPoint(x: x, y: bounds.maxY))
        }
        for y in [rect.minY, rect.midY, rect.maxY] {
            regionPath.move(to: NSPoint(x: bounds.minX, y: y))
            regionPath.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        JadeColor.primaryNS.withAlphaComponent(0.65).setStroke()
        regionPath.stroke()

        let centerPath = NSBezierPath()
        centerPath.setLineDash(dash, count: dash.count, phase: 0)
        centerPath.lineWidth = 1
        centerPath.move(to: NSPoint(x: bounds.midX, y: bounds.minY))
        centerPath.line(to: NSPoint(x: bounds.midX, y: bounds.maxY))
        centerPath.move(to: NSPoint(x: bounds.minX, y: bounds.midY))
        centerPath.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
        NSColor.white.withAlphaComponent(0.35).setStroke()
        centerPath.stroke()
    }

    private func drawDimensions(for rect: NSRect) {
        let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = dimensionText.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let labelRect = NSRect(
            x: rect.midX - textSize.width / 2 - padding,
            y: rect.minY - textSize.height - padding - 4,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        let background = NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.7).set()
        background.fill()

        let textRect = NSRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding / 2,
            width: textSize.width,
            height: textSize.height
        )
        dimensionText.draw(in: textRect, withAttributes: attributes)
    }
}

// MARK: - Concrete overlay factory

/// 生产用叠层窗口工厂。
@MainActor
final class ConcreteCaptureOverlayWindowFactory: CaptureOverlayWindowFactory {
    private let magnifierConfiguration: MagnifierConfiguration

    init(magnifierConfiguration: MagnifierConfiguration = .default) {
        self.magnifierConfiguration = magnifierConfiguration
    }

    func makeWindow(for display: CaptureDisplay) -> CaptureOverlayWindow {
        CaptureOverlayWindowController(
            display: display,
            magnifierConfiguration: magnifierConfiguration
        )
    }
}

// MARK: - Region Capture Geometry

/// Identifies the display and AppKit-space rectangle chosen for a region capture.
struct RegionCaptureSelection {
    let sessionID: UUID
    let displayID: CGDirectDisplayID
    let screenFrame: NSRect
    let globalRect: NSRect
}

/// Pure coordinate helpers shared by capture and presentation code.
enum ScreenshotGeometry {
    /// Converts a global AppKit rectangle into top-left-origin native display pixels.
    static func cropRect(
        globalSelection: NSRect,
        screenFrame: NSRect,
        imageSize: CGSize
    ) -> CGRect? {
        guard screenFrame.width > 0, screenFrame.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }

        let clipped = globalSelection.standardized.intersection(screenFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }

        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        let pixelRect = CGRect(
            x: (clipped.minX - screenFrame.minX) * scaleX,
            y: (screenFrame.maxY - clipped.maxY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        )
        let integralRect = CGRect(
            x: floor(pixelRect.minX),
            y: floor(pixelRect.minY),
            width: ceil(pixelRect.maxX) - floor(pixelRect.minX),
            height: ceil(pixelRect.maxY) - floor(pixelRect.minY)
        )
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let bounded = integralRect.intersection(imageBounds)
        return bounded.isNull || bounded.isEmpty ? nil : bounded
    }

    /// Positions the compact region toolbar below the selection, falling back above it.
    static func toolbarFrame(
        selection: NSRect,
        toolbarSize: NSSize,
        screenFrame: NSRect,
        gap: CGFloat = 12
    ) -> NSRect {
        let minimumX = screenFrame.minX
        let maximumX = max(minimumX, screenFrame.maxX - toolbarSize.width)
        let centeredX = selection.midX - toolbarSize.width / 2
        let x = min(max(centeredX, minimumX), maximumX)
        let belowY = selection.minY - gap - toolbarSize.height
        let y = belowY >= screenFrame.minY
            ? belowY
            : min(selection.maxY + gap, screenFrame.maxY - toolbarSize.height)
        return NSRect(origin: NSPoint(x: x, y: max(screenFrame.minY, y)), size: toolbarSize)
    }
}
