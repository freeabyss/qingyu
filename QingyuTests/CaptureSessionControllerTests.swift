import CoreGraphics
import XCTest
@testable import Qingyu

@MainActor
final class CaptureSessionControllerTests: XCTestCase {

    // MARK: - Fixtures

    private let leftDisplay = CaptureDisplay(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080)
    )
    private let rightDisplay = CaptureDisplay(
        id: 2,
        frame: CGRect(x: 1920, y: 0, width: 1080, height: 1920),
        pixelSize: CGSize(width: 2160, height: 3840)
    )
    private let leftWindow = CaptureWindowCandidate(
        windowID: 11,
        frame: CGRect(x: 100, y: 500, width: 800, height: 600),
        displayID: 1
    )
    private let rightWindow = CaptureWindowCandidate(
        windowID: 22,
        frame: CGRect(x: 2000, y: 700, width: 900, height: 700),
        displayID: 2
    )

    private final class RecordingWindow: CaptureOverlayWindow {
        let display: CaptureDisplay
        var onEvent: ((CaptureInputEvent) -> Void)?
        private(set) var activeStates: [Bool] = []
        private(set) var lastHighlight: CaptureWindowCandidate?
        private(set) var lastHints: [String] = []
        private(set) var isClosed = false

        weak var factory: RecordingOverlayWindowFactory?

        init(display: CaptureDisplay) {
            self.display = display
        }

        func setActive(_ active: Bool) {
            activeStates.append(active)
        }

        func updateHighlight(window: CaptureWindowCandidate?) {
            lastHighlight = window
        }

        /// Task 012：记录控件级高亮，供「控件优先于窗口」的集成断言使用。
        private(set) var lastElementHighlight: CGRect?

        func updateElementHighlight(frame: CGRect?) {
            lastElementHighlight = frame
        }

        func updateRegion(rect: CGRect?) {}

        func updateHints(_ hintKeys: [String]) {
            lastHints = hintKeys
        }

        func orderFront() {}
        func hide() {}

        func close() {
            guard !isClosed else { return }
            isClosed = true
            factory?.recordClose(display.id)
        }
    }

    private final class RecordingOverlayWindowFactory: CaptureOverlayWindowFactory {
        private(set) var createdDisplayIDs: [CGDirectDisplayID] = []
        private(set) var closedDisplayIDs: [CGDirectDisplayID] = []
        private var windows: [RecordingWindow] = []

        func makeWindow(for display: CaptureDisplay) -> CaptureOverlayWindow {
            createdDisplayIDs.append(display.id)
            let window = RecordingWindow(display: display)
            window.factory = self
            windows.append(window)
            return window
        }

        func recordClose(_ displayID: CGDirectDisplayID) {
            closedDisplayIDs.append(displayID)
        }

        func window(for displayID: CGDirectDisplayID) -> RecordingWindow? {
            windows.first { $0.display.id == displayID }
        }
    }

    private final class FakeDisplayProvider: DisplayProviding {
        let displays: [CaptureDisplay]

        init(_ displays: [CaptureDisplay]) {
            self.displays = displays
        }

        func display(containing point: CGPoint) -> CaptureDisplay? {
            displays.first { $0.frame.contains(point) }
        }
    }

    private final class FakeWindowProvider: WindowCandidateProviding {
        var candidates: [CGPoint: CaptureWindowCandidate] = [:]
        var windowRegions: [CandidateRegion] = []

        func candidate(at point: CGPoint, on display: CaptureDisplay) -> CaptureWindowCandidate? {
            candidates[point]
        }

        func regions(on display: CaptureDisplay) -> [CandidateRegion] {
            windowRegions
        }
    }

    /// Task 012：记录型控件探测替身；可注入固定命中矩形与调用计数。
    /// 测试内单线程使用，故 `@unchecked Sendable` 是安全的。
    private final class FakeElementProvider: ElementCandidateProviding, @unchecked Sendable {
        var frame: CGRect?
        private(set) var calls = 0

        func elementFrame(at point: CGPoint, on display: CaptureDisplay, options: ElementProbeOptions) -> CGRect? {
            calls += 1
            return frame
        }
    }

    private var displays: [CaptureDisplay] {
        [leftDisplay, rightDisplay]
    }

    private func makeController(
        windows: FakeWindowProvider = FakeWindowProvider()
    ) -> (CaptureSessionController, RecordingOverlayWindowFactory) {
        let factory = RecordingOverlayWindowFactory()
        let controller = CaptureSessionController(
            displayProvider: FakeDisplayProvider(displays),
            windowProvider: windows,
            overlayFactory: factory
        )
        return (controller, factory)
    }

    // MARK: - Lifecycle

    func testStartCreatesWindowsForAllDisplaysAndActivatesPointerDisplay() {
        let (controller, factory) = makeController()
        controller.start()

        XCTAssertEqual(factory.createdDisplayIDs, [leftDisplay.id, rightDisplay.id])
        // 真实指针位置不定：只要恰有一个活动显示器即可。
        XCTAssertNotNil(controller.activeDisplayID)
        let activeStates = displays.compactMap { factory.window(for: $0.id)?.activeStates.last }
        XCTAssertEqual(activeStates.filter { $0 }.count, 1)
        controller.cancel()
    }

    func testPointerMovedSwitchesActiveDisplay() {
        let (controller, factory) = makeController()
        controller.start()

        let rightPoint = CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)
        controller.handle(.pointerMoved(rightPoint))

        XCTAssertEqual(controller.activeDisplayID, rightDisplay.id)
        XCTAssertTrue(factory.window(for: rightDisplay.id)?.activeStates.last ?? false)
        XCTAssertFalse(factory.window(for: leftDisplay.id)?.activeStates.last ?? true)

        controller.cancel()
        XCTAssertEqual(factory.closedDisplayIDs.count, 2)
    }

    func testCancelClosesAllOverlaysAndCallsOnCancel() {
        let (controller, factory) = makeController()
        var cancelCalled = false
        controller.onCancel = { cancelCalled = true }
        controller.start()

        controller.cancel()

        XCTAssertTrue(cancelCalled)
        XCTAssertEqual(factory.closedDisplayIDs.count, 2)
        XCTAssertEqual(controller.state.phase, .cancelled)
    }

    func testFinishClosesAllOverlaysWithoutCancelCallback() {
        let (controller, factory) = makeController()
        var cancelCalled = false
        controller.onCancel = { cancelCalled = true }
        controller.start()

        controller.finish()

        XCTAssertFalse(cancelCalled)
        XCTAssertEqual(factory.closedDisplayIDs.count, 2)
    }

    /// 回归：调用方不持有会话时（如 `ScreenshotWindowController.startUnifiedCaptureSession`
    /// 的局部 `session`），`start()` 后必须靠自持有存活，否则叠层成"僵尸"暗幕。
    /// - `start()` 后释放外部引用 → 会话仍存活（激活期自持有）；
    /// - `finish()` 后 → 自持有解除，会话释放。`cancel()` 路径对称。
    func testSessionStaysAliveWhileActiveAndReleasesOnFinish() {
        var session: CaptureSessionController? = makeController().0
        weak var weakSession = session

        session?.start()
        session = nil
        XCTAssertNotNil(weakSession, "激活期间应自持有：调用方释放后会话仍存活")

        session = weakSession
        session?.finish()
        session = nil
        XCTAssertNil(weakSession, "finish() 应解除自持有并释放会话")
    }

    func testSessionStaysAliveWhileActiveAndReleasesOnCancel() {
        var session: CaptureSessionController? = makeController().0
        weak var weakSession = session

        session?.start()
        session = nil
        XCTAssertNotNil(weakSession, "激活期间应自持有：调用方释放后会话仍存活")

        session = weakSession
        session?.cancel()
        session = nil
        XCTAssertNil(weakSession, "cancel() 应解除自持有并释放会话")
    }

    /// 回归（僵尸叠层·行为级）：复现生产 bug 场景——`startUnifiedCaptureSession`
    /// 返回后调用方丢弃引用，从叠层窗口上抛的事件仍必须驱动会话锁定目标。
    /// 此前 `onEvent` 闭包的 weak self 已释放，表现为"屏幕压暗但点击/拖拽/Esc 全部无效"。
    func testOverlayEventsStillDriveSessionAfterCallerDropsReference() {
        let factory = RecordingOverlayWindowFactory()
        var session: CaptureSessionController? = CaptureSessionController(
            displayProvider: FakeDisplayProvider(displays),
            windowProvider: FakeWindowProvider(),
            overlayFactory: factory
        )
        weak var weakSession = session
        var lockedTarget: CaptureTarget?
        session?.onLocked = { lockedTarget = $0 }
        session?.start()
        session = nil
        XCTAssertNotNil(weakSession, "激活期间应自持有：调用方释放后会话仍存活")

        // 真实链路：CaptureOverlayContentView 鼠标事件 → 窗口 onEvent → 会话。
        let overlay = factory.window(for: leftDisplay.id)
        overlay?.onEvent?(.mouseDown(CGPoint(x: 10, y: 10)))
        overlay?.onEvent?(.mouseDragged(CGPoint(x: 110, y: 80)))
        overlay?.onEvent?(.mouseUp(CGPoint(x: 110, y: 80)))
        XCTAssertNil(lockedTarget, "松开后先进入可微调态，不立即交付")

        // Task 014/01：Enter（confirmSelection）是区域选区的确认动作。
        overlay?.onEvent?(.confirmSelection)
        XCTAssertEqual(
            lockedTarget,
            .region(display: leftDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70)),
            "调用方释放引用后，叠层事件仍应驱动会话确认并交付区域目标"
        )

        weakSession?.finish()
        XCTAssertNil(weakSession, "finish() 应解除自持有并释放会话")
    }

    /// 回归：borderless 叠层窗口必须能成为 key/main 窗口，否则 Esc/⌘A 键盘事件到不了叠层视图。
    func testOverlayWindowCanBecomeKeyAndMain() {
        let window = CaptureOverlayNSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        XCTAssertTrue(window.canBecomeKey, "borderless 叠层必须可成为 key 窗口")
        XCTAssertTrue(window.canBecomeMain, "borderless 叠层必须可成为 main 窗口")
    }

    // MARK: - Window flow

    func testClickLocksWindowUnderPointerAndDeliversTarget() {
        let windowProvider = FakeWindowProvider()
        windowProvider.candidates[CGPoint(x: 100, y: 100)] = leftWindow
        let (controller, factory) = makeController(windows: windowProvider)

        var lockedTarget: CaptureTarget?
        controller.onLocked = { lockedTarget = $0 }
        controller.start()

        controller.handle(.pointerMoved(CGPoint(x: 100, y: 100)))
        controller.handle(.mouseDown(CGPoint(x: 100, y: 100)))
        controller.handle(.mouseUp(CGPoint(x: 100, y: 100)))

        XCTAssertEqual(lockedTarget, .window(leftWindow))
        XCTAssertEqual(controller.state.phase, .locked(.window(leftWindow)))
        controller.cancel()
    }

    /// Task 014/01：拖拽松开进入可微调态，`Enter`（`confirmSelection`）才交付目标。
    func testDraggedEntersAdjustingThenConfirmDeliversRegionTarget() {
        let (controller, _) = makeController()
        var lockedTarget: CaptureTarget?
        controller.onLocked = { lockedTarget = $0 }
        controller.start()

        controller.handle(.mouseDown(CGPoint(x: 10, y: 10)))
        controller.handle(.mouseDragged(CGPoint(x: 110, y: 80)))
        controller.handle(.mouseUp(CGPoint(x: 110, y: 80)))

        XCTAssertNil(lockedTarget, "松开后不应立即交付目标")
        guard case .adjustingRegion = controller.state.phase else {
            return XCTFail("Expected adjusting region, got \(controller.state.phase)")
        }

        controller.handle(.confirmSelection)
        XCTAssertEqual(
            lockedTarget,
            .region(display: leftDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70))
        )
    }

    /// 可微调态下方向键事件驱动状态变化，并保持会话仍存活。
    func testNudgeSelectionEventAdjustsRegion() {
        let (controller, _) = makeController()
        controller.start()

        controller.handle(.mouseDown(CGPoint(x: 100, y: 100)))
        controller.handle(.mouseDragged(CGPoint(x: 200, y: 180)))
        controller.handle(.mouseUp(CGPoint(x: 200, y: 180)))
        controller.handle(.nudgeSelection(axis: .horizontal, delta: 2, resize: false))

        guard case .adjustingRegion(_, let rect) = controller.state.phase else {
            return XCTFail("Expected adjusting region, got \(controller.state.phase)")
        }
        XCTAssertEqual(rect.origin.x, 102)
        controller.cancel()
    }

    /// PRD「截图与贴图」规则 2/5：菜单栏/桌面空白悬停时单击 = 当前显示器全屏截图。
    func testClickWithoutWindowCandidateLocksActiveDisplay() {
        let (controller, _) = makeController()
        var lockedTarget: CaptureTarget?
        controller.onLocked = { lockedTarget = $0 }
        controller.start()
        controller.handle(.pointerMoved(CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)))

        controller.handle(.mouseDown(CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)))
        controller.handle(.mouseUp(CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)))

        XCTAssertEqual(lockedTarget, .display(rightDisplay))
    }

    func testSelectFullDisplayLocksActiveDisplay() {
        let (controller, _) = makeController()
        var lockedTarget: CaptureTarget?
        controller.onLocked = { lockedTarget = $0 }
        controller.start()
        controller.handle(.pointerMoved(CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)))

        controller.handle(.selectFullDisplay)

        XCTAssertEqual(lockedTarget, .display(rightDisplay))
    }

    // MARK: - Hints follow phase

    func testHintsFollowSessionPhase() {
        let (controller, factory) = makeController()
        controller.start()

        let leftWindowView = factory.window(for: leftDisplay.id)
        XCTAssertEqual(leftWindowView?.lastHints, ScreenshotShortcutHints.hints(for: .targetingWindow(nil)))

        controller.handle(.mouseDown(CGPoint(x: 10, y: 10)))
        controller.handle(.mouseDragged(CGPoint(x: 110, y: 80)))
        XCTAssertEqual(leftWindowView?.lastHints, ScreenshotShortcutHints.hints(for: .draggingRegion(start: .zero, current: .zero, display: leftDisplay)))

        controller.handle(.mouseUp(CGPoint(x: 110, y: 80)))
        guard case .adjustingRegion = controller.state.phase else {
            return XCTFail("Expected adjusting region phase")
        }
        XCTAssertEqual(
            leftWindowView?.lastHints,
            ScreenshotShortcutHints.hints(for: .adjustingRegion(display: leftDisplay, globalRect: .zero)),
            "可微调态应展示方向键/Enter 提示"
        )

        controller.handle(.confirmSelection)
        guard case .locked = controller.state.phase else {
            return XCTFail("Expected locked phase")
        }
        XCTAssertEqual(leftWindowView?.lastHints, ScreenshotShortcutHints.hints(for: .locked(.display(leftDisplay))))

        controller.finish()
    }

    // MARK: - Rebuild on display change

    func testRebuildRecreatesWindows() {
        let (controller, factory) = makeController()
        controller.start()

        controller.rebuild()

        XCTAssertEqual(factory.createdDisplayIDs.count, 4, "两个显示器各建一次（start + rebuild）")
        XCTAssertEqual(factory.closedDisplayIDs.count, 2)
        XCTAssertEqual(controller.state.phase, .targetingWindow(nil), "重建后回到 targeting")
        controller.cancel()
    }

    func testEventsIgnoredAfterFinish() {
        let (controller, factory) = makeController()
        var lockedTarget: CaptureTarget?
        controller.onLocked = { lockedTarget = $0 }
        controller.start()
        controller.finish()

        controller.handle(.mouseDown(CGPoint(x: 10, y: 10)))
        controller.handle(.selectFullDisplay)

        XCTAssertNil(lockedTarget)
        XCTAssertEqual(factory.closedDisplayIDs.count, 2)
    }
}
