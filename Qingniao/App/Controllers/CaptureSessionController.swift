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
    func updateRegion(rect: CGRect?)
    func updateHints(_ hintKeys: [String])
    func orderFront()
    func hide()
    func close()
}

@MainActor
protocol CaptureOverlayWindowFactory: AnyObject {
    func makeWindow(for display: CaptureDisplay) -> CaptureOverlayWindow
}

/// 统一截图会话协调器（重构自单屏 `ScreenshotOverlayController`）：
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

    init(
        displayProvider: DisplayProviding,
        windowProvider: WindowCandidateProviding,
        overlayFactory: CaptureOverlayWindowFactory
    ) {
        self.displayProvider = displayProvider
        self.windowProvider = windowProvider
        self.overlayFactory = overlayFactory
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
            switchActiveDisplay(to: point, notifyState: true)

        case .mouseDown(let point):
            let display = displayProvider.display(containing: point)
                ?? display(for: activeDisplayID)
                ?? displayProvider.displays.first
            guard let display else { return }
            state.mouseDown(at: point, display: display)
            syncOverlays()

        case .mouseDragged(let point):
            state.mouseDragged(to: point)
            syncOverlays()

        case .mouseUp(let point):
            state.mouseUp(at: point)
            syncOverlays()
            if case .locked(let target) = state.phase {
                isSessionActive = false
                onLocked?(target)
            }

        case .selectFullDisplay:
            if let display = display(for: activeDisplayID) ?? displayProvider.displays.first {
                state.selectFullDisplay(display)
                syncOverlays()
            }
            if case .locked(let target) = state.phase {
                isSessionActive = false
                onLocked?(target)
            }

        case .cancel:
            cancel()
        }
    }

    /// 显示器拓扑变化时重建叠层与坐标映射。
    func rebuild() {
        guard isSessionActive else { return }
        closeAllWindows()
        state = CaptureSessionState()
        buildWindows()
        switchActiveDisplay(to: NSEvent.mouseLocation, notifyState: false)
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
        for (displayID, window) in overlayWindows {
            let isActive = displayID == activeDisplayID
            window.setActive(isActive)
            window.updateHints(ScreenshotShortcutHints.hints(for: state.phase))

            switch state.phase {
            case .targetingWindow(let candidate):
                window.updateHighlight(window: isActive ? candidate : nil)
                window.updateRegion(rect: nil)
            case .draggingRegion(let start, let current, _):
                window.updateHighlight(window: nil)
                window.updateRegion(rect: isActive ? Self.regionRect(start: start, current: current) : nil)
            case .locked(let target):
                window.updateHighlight(window: nil)
                window.updateRegion(rect: isActive ? Self.lockedRect(for: target, displayID: displayID) : nil)
            case .cancelled:
                window.updateHighlight(window: nil)
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

    private static func lockedRect(for target: CaptureTarget, displayID: CGDirectDisplayID) -> CGRect? {
        switch target {
        case .window(let candidate):
            return candidate.displayID == displayID ? candidate.frame : nil
        case .region(_, let globalRect):
            return globalRect
        case .display:
            return nil
        }
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
