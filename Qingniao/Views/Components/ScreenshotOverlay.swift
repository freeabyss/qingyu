import Cocoa
import os.log

/// 截图会话取消广播：`ScreenshotWindowController` 在统一会话取消时发出，
/// `ScreenshotToolbarController` 监听后关闭已打开的预览/工具条。
extension Notification.Name {
    static let screenshotOverlayDidCancel = Notification.Name("com.assistant.screenshotOverlayDidCancel")
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

    init(display: CaptureDisplay) {
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

        let view = CaptureOverlayContentView(frame: NSRect(origin: .zero, size: display.frame.size), display: display)
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
    var regionFrame: NSRect?
    var onEvent: ((CaptureInputEvent) -> Void)?

    fileprivate private(set) var hintsView: ScreenshotShortcutHintsView?
    private var isMouseDown = false

    init(frame frameRect: NSRect, display: CaptureDisplay) {
        self.display = display
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
    }

    func updateHints(_ hintKeys: [String]) {
        hintsView?.update(hintKeys: hintKeys)
    }

    private func updateHintsVisibility() {
        hintsView?.isHidden = !isActiveDisplay
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
        onEvent?(.pointerMoved(globalPoint(convert(event.locationInWindow, from: nil))))
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        onEvent?(.mouseDown(globalPoint(convert(event.locationInWindow, from: nil))))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseDown else { return }
        onEvent?(.mouseDragged(globalPoint(convert(event.locationInWindow, from: nil))))
    }

    override func mouseUp(with event: NSEvent) {
        guard isMouseDown else { return }
        isMouseDown = false
        onEvent?(.mouseUp(globalPoint(convert(event.locationInWindow, from: nil))))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEvent?(.cancel)                       // Esc
        case 0 where event.modifierFlags.contains(.command): onEvent?(.selectFullDisplay) // ⌘A
        default: super.keyDown(with: event)
        }
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
        }
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
    func makeWindow(for display: CaptureDisplay) -> CaptureOverlayWindow {
        CaptureOverlayWindowController(display: display)
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
