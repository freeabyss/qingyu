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
        contentView.isActiveDisplay = active
        contentView.needsDisplay = true
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

    func updateHints(_ hintKeys: [String]) {
        contentView.updateHints(hintKeys)
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
final class CaptureOverlayContentView: NSView {
    let display: CaptureDisplay
    var isActiveDisplay = false {
        didSet { updateHintsVisibility() }
    }
    var highlightFrame: NSRect?
    /// Task 012：控件级高亮（AppKit 全局坐标）。
    var elementFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var regionFrame: NSRect? {
        didSet { updateMagnifierMask() }
    }
    var onEvent: ((CaptureInputEvent) -> Void)?

    fileprivate private(set) var hintsView: ScreenshotShortcutHintsView?
    private var isMouseDown = false
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
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
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

    private func globalPoint(_ localPoint: NSPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x + display.frame.minX,
            y: localPoint.y + display.frame.minY
        )
    }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        guard isActiveDisplay else { return }
        let global = globalPoint(convert(event.locationInWindow, from: nil))
        onEvent?(.pointerMoved(global))
        requestMagnifierSample(at: global)
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        let global = globalPoint(convert(event.locationInWindow, from: nil))
        // Task 014/06：每次拖拽重新捕获长宽比。
        dragStartPoint = global
        lockedAspectRatio = nil
        onEvent?(.mouseDown(global))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseDown else { return }
        var global = globalPoint(convert(event.locationInWindow, from: nil))

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
        guard isMouseDown else { return }
        isMouseDown = false
        dragStartPoint = nil
        lockedAspectRatio = nil
        onEvent?(.mouseUp(globalPoint(convert(event.locationInWindow, from: nil))))
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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.3).set()
        dirtyRect.fill()

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

            // Task 014/01：`Tab` 按住时显示对齐辅助线。
            if showsAlignmentGuides {
                drawAlignmentGuides(for: local)
            }
        }
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
