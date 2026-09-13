import Cocoa
import os.log

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


// MARK: - ScreenshotOverlayViewDelegate

/// Delegate protocol for the screenshot overlay view.
protocol ScreenshotOverlayViewDelegate: AnyObject {
    /// Called when the user completes a selection.
    func overlayView(_ view: ScreenshotOverlayView, didSelectRect rect: NSRect)

    /// Called when the user cancels the selection (ESC key).
    func overlayViewDidCancel(_ view: ScreenshotOverlayView)
}

// MARK: - ScreenshotOverlayView

/// Custom NSView that handles mouse tracking and drawing for region selection.
///
/// Displays a semi-transparent overlay covering the entire screen.
/// The user can drag to select a rectangular region. The selected area
/// is shown clear with a white border and dimension text.
/// Pressing ESC cancels the selection.
final class ScreenshotOverlayView: NSView {
    weak var delegate: ScreenshotOverlayViewDelegate?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelectionLocked = false

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // ESC key (keyCode 53) cancels the overlay
        if event.keyCode == 53 {
            delegate?.overlayViewDidCancel(self)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard !isSelectionLocked else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isSelectionLocked else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !isSelectionLocked else { return }
        guard let start = startPoint, let end = currentPoint else {
            delegate?.overlayViewDidCancel(self)
            return
        }

        let rect = normalizedRect(from: start, to: end)

        // Minimum selection size: 5x5 pixels
        guard rect.width > 5 && rect.height > 5 else {
            delegate?.overlayViewDidCancel(self)
            return
        }

        isSelectionLocked = true
        needsDisplay = true
        delegate?.overlayView(self, didSelectRect: rect)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw semi-transparent dark overlay over the entire screen
        NSColor.black.withAlphaComponent(0.3).set()
        dirtyRect.fill()

        guard let start = startPoint, let end = currentPoint else { return }

        let rect = normalizedRect(from: start, to: end)

        // Clear the selected area (make it fully transparent)
        NSColor.clear.set()
        rect.fill(using: .copy)

        // Draw white border around the selection
        NSColor.white.set()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw cross-hair guides (dashed lines through the center)
        NSColor.white.withAlphaComponent(0.5).set()
        let dashPattern: [CGFloat] = [4, 4]
        let centerHPath = NSBezierPath()
        centerHPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        centerHPath.move(to: NSPoint(x: rect.minX, y: rect.midY))
        centerHPath.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        centerHPath.stroke()

        let centerVPath = NSBezierPath()
        centerVPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        centerVPath.move(to: NSPoint(x: rect.midX, y: rect.minY))
        centerVPath.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        centerVPath.stroke()

        // The locked state reserves this space for the action toolbar.
        if !isSelectionLocked {
            drawDimensions(for: rect)
        }
    }

    // MARK: - Private Helpers

    /// Create a normalized rect (positive width/height) from two points.
    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }

    /// Draw the dimension text (width x height) below the selection rectangle.
    ///
    /// P-04 / T-014: Jade-style pill — black 0.7 background, white caption text,
    /// radius-md (8pt). The AppKit overlay is hand-drawn (NSBezierPath), so the
    /// Jade tokens are mirrored here as literals rather than SwiftUI values.
    private func drawDimensions(for rect: NSRect) {
        let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]

        let textSize = dimensionText.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let backgroundSize = NSSize(
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        // Position the label centered below the selection, with a small gap
        let labelRect = NSRect(
            x: rect.midX - backgroundSize.width / 2,
            y: rect.minY - backgroundSize.height - 4,
            width: backgroundSize.width,
            height: backgroundSize.height
        )

        // Draw background pill (radius-md = 8pt, Jade token)
        let backgroundPath = NSBezierPath(
            roundedRect: labelRect,
            xRadius: 8,
            yRadius: 8
        )
        NSColor.black.withAlphaComponent(0.7).set()
        backgroundPath.fill()

        // Draw text centered in the pill
        let textRect = NSRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding / 2,
            width: textSize.width,
            height: textSize.height
        )
        dimensionText.draw(in: textRect, withAttributes: attributes)
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

// MARK: - ScreenshotOverlayController

/// Manages the full-screen transparent overlay window for region selection.
///
/// Creates a borderless window at screen saver level on the display under the pointer.
/// The overlay view handles mouse drag selection and ESC cancellation.
/// The completion handler receives the display identity and global AppKit rect, or nil if cancelled.
final class ScreenshotOverlayController {
    private let logger = Logger.screenshot
    private var window: NSWindow?
    private var escMonitor: Any?
    private var didCallCompletion = false
    private let completion: (RegionCaptureSelection?) -> Void
    private let sessionID: UUID
    private var screen: NSScreen?

    /// Create a new overlay controller.
    ///
    /// - Parameter completion: Called when the user completes selection or cancels.
    ///   The rect is in AppKit coordinates (bottom-left origin). nil means cancelled.
    init(sessionID: UUID, completion: @escaping (RegionCaptureSelection?) -> Void) {
        self.sessionID = sessionID
        self.completion = completion
    }

    deinit {
        removeESCMonitor()
    }

    /// Show the overlay window on the display currently containing the pointer.
    func show() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            logger.error("No screen available for overlay")
            cancelScreenshotMode()
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
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

        let overlayView = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        overlayView.delegate = self
        window.contentView = overlayView

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)

        self.window = window
        self.screen = screen

        // NSEvent local monitor ensures ESC works even if the view loses first responder.
        setupESCMonitor()

        logger.debug("Overlay window shown on screen: \(screen.localizedName)")
    }

    /// Dismiss the overlay window.
    private func dismiss() {
        removeESCMonitor()
        window?.orderOut(nil)
        window = nil
    }

    /// Deliver the selected rect once. The service keeps the overlay alive only
    /// until WindowServer has captured a frame without it.
    private func completeSelection(_ rect: NSRect) {
        guard !didCallCompletion else { return }
        guard let screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            cancelScreenshotMode()
            return
        }
        didCallCompletion = true
        let globalRect = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        completion(RegionCaptureSelection(
            sessionID: sessionID,
            displayID: CGDirectDisplayID(screenNumber.uint32Value),
            screenFrame: screen.frame,
            globalRect: globalRect
        ))
    }

    /// Cancel screenshot mode. Before a selection this resumes the capture continuation with nil;
    /// after a selection it only dismisses the overlay and broadcasts cancellation.
    private func cancelScreenshotMode() {
        let shouldNotifyCompletion = !didCallCompletion
        didCallCompletion = true
        dismiss()
        NotificationCenter.default.post(name: .screenshotOverlayDidCancel, object: nil)
        if shouldNotifyCompletion {
            completion(nil)
        }
    }

    /// Temporarily hide the overlay so it does not appear in the captured bitmap.
    func hideForCapture() {
        window?.orderOut(nil)
    }

    /// Restore the locked selection after the overlay was excluded from capture.
    func restoreAfterCapture() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Cancel this capture, including a selection that has not completed yet.
    func cancel() {
        cancelScreenshotMode()
    }

    /// Finish a successful or failed capture without broadcasting a user cancel.
    /// The preview window can only become visible after this screen-saver-level
    /// overlay has been removed.
    func finishCapture() {
        dismiss()
        screen = nil
    }

    private func setupESCMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelScreenshotMode()
                return nil  // swallow the event
            }
            return event
        }
    }

    private func removeESCMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}

// MARK: - ScreenshotOverlayViewDelegate

extension ScreenshotOverlayController: ScreenshotOverlayViewDelegate {
    func overlayView(_ view: ScreenshotOverlayView, didSelectRect rect: NSRect) {
        completeSelection(rect)
    }

    func overlayViewDidCancel(_ view: ScreenshotOverlayView) {
        cancelScreenshotMode()
    }
}

// MARK: - WindowCaptureOverlayController

/// Manages a full-screen transparent overlay that highlights the window under the cursor
/// for window capture confirmation. Press ESC to cancel, click to confirm.
final class WindowCaptureOverlayController {
    private let logger = Logger.screenshot
    private var window: NSWindow?
    private var overlayView: WindowCaptureOverlayView?
    private var escMonitor: Any?
    private var didComplete = false
    private let completion: (Bool) -> Void  // true = confirm, false = cancel

    /// - Parameters:
    ///   - targetFrame: The frame of the window being captured (AppKit coordinates, bottom-left origin).
    ///   - completion: Called with `true` if the user confirms, `false` if cancelled.
    init(targetFrame: NSRect, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        self.targetFrame = targetFrame
    }

    private let targetFrame: NSRect

    deinit {
        removeESCMonitor()
    }

    func show() {
        guard let screen = NSScreen.main else {
            finish(false)
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
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

        let view = WindowCaptureOverlayView(frame: screen.frame, targetFrame: targetFrame)
        view.onConfirm = { [weak self] in
            self?.finish(true)
        }
        view.onCancel = { [weak self] in
            self?.finish(false)
        }
        window.contentView = view

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        self.overlayView = view
        setupESCMonitor()
        logger.debug("Window capture overlay shown")
    }

    private func dismiss() {
        removeESCMonitor()
        window?.orderOut(nil)
        window = nil
        overlayView = nil
    }

    private func finish(_ confirmed: Bool) {
        guard !didComplete else { return }
        didComplete = true
        dismiss()
        if !confirmed {
            NotificationCenter.default.post(name: .screenshotOverlayDidCancel, object: nil)
        }
        completion(confirmed)
    }

    private func setupESCMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(false)
                return nil
            }
            return event
        }
    }

    private func removeESCMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}

// MARK: - WindowCaptureOverlayView

/// Custom NSView that highlights the target window and handles confirm/cancel.
final class WindowCaptureOverlayView: NSView {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    /// The frame of the target window in AppKit coordinates (bottom-left origin).
    private let targetFrame: NSRect

    init(frame: NSRect, targetFrame: NSRect) {
        self.targetFrame = targetFrame
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // ESC
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onConfirm?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw semi-transparent dark overlay over the entire screen
        NSColor.black.withAlphaComponent(0.35).set()
        dirtyRect.fill()

        // Clear the target window area (make it visible through the overlay)
        NSColor.clear.set()
        targetFrame.fill(using: .copy)

        // P-04 / T-014: highlight the target window with Jade 20% fill + Jade 2pt border.
        JadeColor.primaryNS.withAlphaComponent(0.2).setFill()
        NSBezierPath(rect: targetFrame).fill()

        JadeColor.primaryNS.set()
        let borderPath = NSBezierPath(rect: targetFrame)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw hint text below the window
        let hintText = L10n.localized("screenshot.windowOverlay.hint")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = hintText.size(withAttributes: attributes)

        let labelX = targetFrame.midX - textSize.width / 2
        let labelY = targetFrame.minY - textSize.height - 24

        // Only draw if there's room below the window
        if labelY > 60 {
            // Background pill
            let padding: CGFloat = 12
            let pillRect = NSRect(
                x: labelX - padding,
                y: labelY - padding / 2,
                width: textSize.width + padding * 2,
                height: textSize.height + padding
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
            NSColor.black.withAlphaComponent(0.7).set()
            pillPath.fill()

            // Text
            let textRect = NSRect(
                x: labelX,
                y: labelY,
                width: textSize.width,
                height: textSize.height
            )
            hintText.draw(in: textRect, withAttributes: attributes)
        }
    }
}
