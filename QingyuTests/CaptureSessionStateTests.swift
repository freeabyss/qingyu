import CoreGraphics
import XCTest
@testable import Qingyu

@MainActor
final class CaptureSessionStateTests: XCTestCase {

    // MARK: - Fixtures

    private let leftDisplay = CaptureDisplay(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 3840, height: 2160)
    )
    private let rightDisplay = CaptureDisplay(
        id: 2,
        frame: CGRect(x: 1920, y: 0, width: 1080, height: 1920),
        pixelSize: CGSize(width: 2160, height: 3840)
    )
    private let negativeDisplay = CaptureDisplay(
        id: 3,
        frame: CGRect(x: -1920, y: -300, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080)
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

    // MARK: - Window click flow

    func testWindowClickFlowLocksWindowUnderPointer() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(state.phase, .locked(.window(leftWindow)))
    }

    /// PRD「截图与贴图」规则 2/5：菜单栏或桌面空白区域悬停时单击 = 当前显示器全屏截图。
    func testClickOnEmptyAreaLocksFullDisplay() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 50, y: 50), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 50, y: 50))

        XCTAssertEqual(state.phase, .locked(.display(leftDisplay)))
    }

    /// PRD 规则 2：先悬停窗口、再移到空白处后单击，应按当前悬停默认值锁定全屏。
    func testClickOnEmptyAreaAfterWindowHoverLocksFullDisplayOfCurrentScreen() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.pointerMoved(to: CGPoint(x: 1900, y: 60), display: leftDisplay, window: nil)
        state.mouseDown(at: CGPoint(x: 1900, y: 60), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 1900, y: 60))

        XCTAssertEqual(state.phase, .locked(.display(leftDisplay)))
    }

    /// PRD 规则 2：窗口悬停单击 = 窗口截图。
    func testWindowHoverClickLocksWindow() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(state.phase, .locked(.window(leftWindow)))
    }

    // MARK: - Region drag flow

    /// Task 014/01：拖拽松开后进入**可微调态**（方向键可调整），`confirmRegion()`（Enter）才锁定。
    func testRegionDragEntersAdjustingThenConfirmLocks() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: rightDisplay)
        state.mouseDragged(to: CGPoint(x: 110, y: 80))
        state.mouseUp(at: CGPoint(x: 110, y: 80))

        let expected = CGRect(x: 10, y: 10, width: 100, height: 70)
        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: rightDisplay, globalRect: expected),
            "松开后应先进入可微调态，而不是立即锁定"
        )

        state.confirmRegion()
        XCTAssertEqual(
            state.phase,
            .locked(.region(display: rightDisplay, globalRect: expected))
        )
    }

    func testReverseDragNormalizesRegionRect() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 110, y: 80), display: rightDisplay)
        state.mouseDragged(to: CGPoint(x: 10, y: 10))
        state.mouseUp(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: rightDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70))
        )
    }

    func testDragBelowMinimumSizeReturnsToWindowTargeting() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 103, y: 102))
        state.mouseUp(at: CGPoint(x: 103, y: 102))

        XCTAssertEqual(state.phase, .targetingWindow(leftWindow), "不足最小选区应回到当前窗口候选")
    }

    func testTinyDragFromEmptyAreaReturnsToTargeting() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 1900, y: 60), display: leftDisplay, window: nil)
        state.mouseDown(at: CGPoint(x: 1900, y: 60), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 1902, y: 62))
        state.mouseUp(at: CGPoint(x: 1902, y: 62))

        XCTAssertEqual(state.phase, .targetingWindow(nil), "不足最小选区应回到 targeting")
    }

    /// PRD 规则 3：只要左键发生拖拽，区域圈选优先于窗口悬停默认值。
    func testDragFromWindowCandidateLocksRegionNotWindow() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 210, y: 180))
        state.mouseUp(at: CGPoint(x: 210, y: 180))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 110, height: 80)),
            "从窗口候选上拖拽应进入区域可微调态，而非锁定窗口"
        )
        state.confirmRegion()
        XCTAssertEqual(
            state.phase,
            .locked(.region(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 110, height: 80)))
        )
    }

    /// PRD 规则 5：桌面空白区域拖拽仍由区域圈选优先。
    func testDragFromEmptyAreaLocksRegion() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 1900, y: 60), display: leftDisplay, window: nil)
        state.mouseDown(at: CGPoint(x: 1900, y: 60), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 1910, y: 130))
        state.mouseUp(at: CGPoint(x: 1910, y: 130))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 1900, y: 60, width: 10, height: 70))
        )
    }

    func testExactlyMinimumSizeRegionLocks() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 15, y: 15))
        state.mouseUp(at: CGPoint(x: 15, y: 15))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 10, y: 10, width: 5, height: 5))
        )
    }

    // MARK: - 可微调态鼠标交互（Snipaste 式：拖内移动 / 拖边缩放 / 点外重圈）

    /// 进入可微调态的便捷夹具：在 (100,100)-(300,250) 圈一个 200×150 的选区。
    private func makeAdjustingState() -> CaptureSessionState {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 300, y: 250))
        state.mouseUp(at: CGPoint(x: 300, y: 250))
        return state
    }

    /// 命中判定：角 > 边 > 内部 > 外部，命中带以边线为中心。
    func testZoneHitTestPrioritizesCornersThenEdgesThenInside() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 150)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 2, y: 2), rect: rect), .bottomLeft)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 198, y: 148), rect: rect), .topRight)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 100, y: 4), rect: rect), .bottom)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 196, y: 75), rect: rect), .right)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 100, y: 75), rect: rect), .inside)
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: -30, y: 75), rect: rect), .outside)
        // 命中带延伸到选区外 8pt：拖「边缘」不需要精确落在 1pt 边线上。
        XCTAssertEqual(RegionAdjustment.zone(at: CGPoint(x: 204, y: 75), rect: rect), .right)
    }

    /// 施加移动：整体平移并钳制在显示器内。
    func testApplyMoveClampsInsideDisplayBounds() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        // 正常平移。
        let moved = RegionAdjustment.apply(zone: .inside, to: rect, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 170, y: 130), bounds: bounds, minimum: 5)
        XCTAssertEqual(moved, CGRect(x: 120, y: 80, width: 200, height: 150))
        // 向右下猛拖：贴边不越界。
        let clamped = RegionAdjustment.apply(zone: .inside, to: rect, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 900, y: -900), bounds: bounds, minimum: 5)
        XCTAssertEqual(clamped, CGRect(x: 300, y: 0, width: 200, height: 150))
    }

    /// 施加缩放：对侧边/角固定，拖拽边跟随指针；不小于最小尺寸、不越出屏幕。
    func testApplyResizeAnchorsOppositeEdgeAndClamps() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)

        // 拖右上角：左下角 (100,100) 固定。
        let corner = RegionAdjustment.apply(zone: .topRight, to: rect, from: CGPoint(x: 300, y: 250), to: CGPoint(x: 400, y: 320), bounds: bounds, minimum: 5)
        XCTAssertEqual(corner, CGRect(x: 100, y: 100, width: 300, height: 220))

        // 拖左边缘越过右边缘：宽度钳到最小值，不翻转。
        let inverted = RegionAdjustment.apply(zone: .left, to: rect, from: CGPoint(x: 100, y: 175), to: CGPoint(x: 350, y: 175), bounds: bounds, minimum: 5)
        XCTAssertEqual(inverted, CGRect(x: 295, y: 100, width: 5, height: 150))

        // 拖上边缘越出屏幕顶：钳在屏幕顶（bounds maxY=400 → 高度 300）。
        let overflow = RegionAdjustment.apply(zone: .top, to: rect, from: CGPoint(x: 200, y: 250), to: CGPoint(x: 200, y: 999), bounds: bounds, minimum: 5)
        XCTAssertEqual(overflow, CGRect(x: 100, y: 100, width: 200, height: 300))
    }

    /// 状态机：可微调态按下选区内部并拖拽 → 选区移动；抬起后仍处于可微调态。
    func testDraggingInsideAdjustingRegionMovesRegion() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 150, y: 150), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 120, y: 170))
        state.mouseDragged(to: CGPoint(x: 110, y: 180))
        state.mouseUp(at: CGPoint(x: 110, y: 180))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 60, y: 130, width: 200, height: 150)),
            "选区内拖拽应移动选区（位移 -40, +30），停留可微调态"
        )
    }

    /// 状态机：拖角缩放，对角固定。
    func testDraggingCornerInAdjustingRegionResizes() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 300, y: 250), display: leftDisplay)   // 右上角（命中带内）
        state.mouseDragged(to: CGPoint(x: 350, y: 300))
        state.mouseUp(at: CGPoint(x: 350, y: 300))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 250, height: 200)),
            "拖右上角应从对角 (100,100) 缩放到 (350,300)"
        )
    }

    /// 状态机：选区内按下但没拖就抬起 → 保持原选区，不误触发其它语义。
    func testPlainClickInsideAdjustingRegionKeepsRegion() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 150, y: 150), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 150, y: 150))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 200, height: 150))
        )
    }

    /// 状态机：选区外按下重新圈选；圈出足够大的新选区则替换。
    func testOutsideDragReplacesAdjustingRegion() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 400, y: 400), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 550, y: 500))
        state.mouseUp(at: CGPoint(x: 550, y: 500))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 400, y: 400, width: 150, height: 100)),
            "选区外拖拽应重新圈选"
        )
    }

    /// 状态机：选区外单击（没拖起来）→ 恢复旧选区，而不是把单击解释成「锁定窗口/整屏」。
    func testOutsidePlainClickRestoresAdjustingRegion() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 40, y: 40), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 40, y: 40))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 200, height: 150)),
            "选区外误点一下不应丢掉已画好的选区，更不应变成整屏截图"
        )
    }

    /// 状态机：选区外重圈但拖得太小 → 恢复旧选区。
    func testOutsideTinyDragRestoresAdjustingRegion() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 40, y: 40), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 43, y: 42))
        state.mouseUp(at: CGPoint(x: 43, y: 42))

        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 100, y: 100, width: 200, height: 150))
        )
    }

    /// 可微调交互后仍可 `Enter` 确认 / 方向键微调（与既有键盘流不冲突）。
    func testAdjustInteractionThenNudgeAndConfirmStillWork() {
        var state = makeAdjustingState()
        state.mouseDown(at: CGPoint(x: 300, y: 250), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 350, y: 300))
        state.mouseUp(at: CGPoint(x: 350, y: 300))

        XCTAssertTrue(state.nudgeRegion(axis: .horizontal, delta: 10, resize: false))
        state.confirmRegion()

        guard case .locked(.region(_, let rect)) = state.phase else {
            return XCTFail("调整后 Enter 应锁定区域，实际 \(state.phase)")
        }
        XCTAssertEqual(rect, CGRect(x: 110, y: 100, width: 250, height: 200))
    }

    func testPointerMovedDuringDragIsIgnored() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.pointerMoved(to: CGPoint(x: 900, y: 900), display: rightDisplay, window: rightWindow)
        state.mouseDragged(to: CGPoint(x: 110, y: 110))
        state.mouseUp(at: CGPoint(x: 110, y: 110))

        guard case .adjustingRegion(let display, let rect) = state.phase else {
            return XCTFail("Expected adjusting region, got \(state.phase)")
        }
        XCTAssertEqual(display.id, leftDisplay.id)
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 100, height: 100))

        state.confirmRegion()
        guard case .locked(.region(_, let lockedRect)) = state.phase else {
            return XCTFail("Expected locked region after confirm, got \(state.phase)")
        }
        XCTAssertEqual(lockedRect, CGRect(x: 10, y: 10, width: 100, height: 100))
    }

    func testMouseUpWithoutMouseDownIsIgnored() {
        var state = CaptureSessionState()
        state.mouseUp(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(state.phase, .targetingWindow(nil))
    }

    // MARK: - Full display selection

    func testSelectFullDisplayFromTargeting() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 10, y: 10), display: negativeDisplay, window: nil)
        state.selectFullDisplay(negativeDisplay)

        XCTAssertEqual(state.phase, .locked(.display(negativeDisplay)))
    }

    func testSelectFullDisplayDuringDrag() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 60, y: 60))
        state.selectFullDisplay(rightDisplay)

        XCTAssertEqual(state.phase, .locked(.display(rightDisplay)))
    }

    func testSelectFullDisplayIgnoredAfterLock() {
        var state = CaptureSessionState()
        state.selectFullDisplay(leftDisplay)
        state.selectFullDisplay(rightDisplay)

        XCTAssertEqual(state.phase, .locked(.display(leftDisplay)))
    }

    // MARK: - Cancellation

    func testCancelFromTargetingAndDragging() {
        var state = CaptureSessionState()
        state.cancel()
        XCTAssertEqual(state.phase, .cancelled)
        state.cancel()
        XCTAssertEqual(state.phase, .cancelled, "取消应幂等")

        var dragging = CaptureSessionState()
        dragging.mouseDown(at: CGPoint(x: 0, y: 0), display: leftDisplay)
        dragging.cancel()
        XCTAssertEqual(dragging.phase, .cancelled)

        var locked = CaptureSessionState()
        locked.selectFullDisplay(leftDisplay)
        locked.cancel()
        XCTAssertEqual(locked.phase, .cancelled)
    }

    func testEventsIgnoredAfterCancel() {
        var state = CaptureSessionState()
        state.cancel()
        state.pointerMoved(to: CGPoint(x: 10, y: 10), display: leftDisplay, window: leftWindow)
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)

        XCTAssertEqual(state.phase, .cancelled)
    }

    // MARK: - Cross-display pointer moves

    func testCrossDisplayPointerMoveSwitchesWindowCandidate() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.pointerMoved(to: CGPoint(x: 2000, y: 700), display: rightDisplay, window: rightWindow)

        XCTAssertEqual(state.phase, .targetingWindow(rightWindow))

        state.mouseDown(at: CGPoint(x: 2000, y: 700), display: rightDisplay)
        state.mouseUp(at: CGPoint(x: 2000, y: 700))
        XCTAssertEqual(state.phase, .locked(.window(rightWindow)))
    }

    func testPointerLeavingWindowClearsCandidate() {
        var state = CaptureSessionState()
        state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: leftWindow)
        state.pointerMoved(to: CGPoint(x: 1900, y: 100), display: leftDisplay, window: nil)

        XCTAssertEqual(state.phase, .targetingWindow(nil))
    }

    // MARK: - Backend coordinate conversion (pure)

    func testRegionCropScalesWithRetinaPixelSize() {
        let rect = ScreenCaptureBackend.cropRect(
            for: leftDisplay,
            globalRect: CGRect(x: 10, y: 10, width: 100, height: 70),
            imageSize: leftDisplay.pixelSize
        )

        // Retina 2x: pixel rect doubles; AppKit y is flipped inside the display.
        XCTAssertEqual(rect, CGRect(x: 20, y: 2000, width: 200, height: 140))
    }

    func testRegionCropClipsNegativeOriginDisplays() {
        let rect = ScreenCaptureBackend.cropRect(
            for: negativeDisplay,
            globalRect: CGRect(x: -100, y: 100, width: 500, height: 500),
            imageSize: negativeDisplay.pixelSize
        )

        // 选区跨出显示器左缘：裁剪到 [-100, 0) 段 → 相对显示器 1820..1920 px。
        XCTAssertEqual(rect, CGRect(x: 1820, y: 180, width: 100, height: 500))
    }

    // MARK: - Backend pixel capture

    func testDisplayCaptureReturnsPixelAccurateImage() async throws {
        let backend = ScreenCaptureBackend()
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(
            mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        )
        let display = CaptureDisplay(
            id: displayID,
            frame: mainScreen.frame,
            pixelSize: CaptureDisplayInfo.pixelSize(displayID: displayID)
        )

        let result = try await backend.capture(.display(display))

        XCTAssertFalse(result.id.uuidString.isEmpty)
        XCTAssertGreaterThan(result.imageData.count, 0)
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
        XCTAssertEqual(result.sourceType, .screen)
        XCTAssertNil(result.regionSelection)
    }

    func testWindowCaptureWithInvalidWindowIDThrows() async {
        let backend = ScreenCaptureBackend()
        let candidate = CaptureWindowCandidate(
            windowID: CGWindowID(0x7FFF_FFFF),
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            displayID: CGMainDisplayID()
        )

        do {
            _ = try await backend.capture(.window(candidate))
            XCTFail("Expected capture of an invalid window id to throw")
        } catch {
            // expected
        }
    }

    func testWindowCaptureCapturesWindowByID() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 240, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CaptureSessionStateTests Window"
        window.backgroundColor = .white
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let backend = ScreenCaptureBackend()
        let displayID = CaptureDisplayInfo.displayID(containing: window.frame) ?? CGMainDisplayID()
        let candidate = CaptureWindowCandidate(windowID: CGWindowID(window.windowNumber), frame: window.frame, displayID: displayID)

        let result = try await backend.capture(.window(candidate))

        XCTAssertGreaterThan(result.imageData.count, 0)
        XCTAssertEqual(result.sourceType, .window)
        XCTAssertNil(result.regionSelection)
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
    }

    func testRegionCaptureCropsToSelection() async throws {
        let backend = ScreenCaptureBackend()
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(
            mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        )
        let display = CaptureDisplay(
            id: displayID,
            frame: mainScreen.frame,
            pixelSize: CaptureDisplayInfo.pixelSize(displayID: displayID)
        )
        // 选区取自显示器 frame 内部（多屏下 frame 原点可能是正/负值）。
        let selection = CGRect(
            x: display.frame.minX + 50,
            y: display.frame.minY + 60,
            width: 120,
            height: 80
        )

        let result = try await backend.capture(.region(display: display, globalRect: selection))

        XCTAssertEqual(result.sourceType, .region)
        XCTAssertNotNil(result.regionSelection)
        XCTAssertEqual(result.selectionRect, selection)
        let scale = max(1, display.pixelSize.width / max(1, display.frame.width))
        XCTAssertEqual(result.width, Int(120 * scale))
        XCTAssertEqual(result.height, Int(80 * scale))
    }

    func testCaptureIssuesDistinctStableIDs() async throws {
        let backend = ScreenCaptureBackend()
        let mainScreen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(
            mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        )
        let display = CaptureDisplay(
            id: displayID,
            frame: mainScreen.frame,
            pixelSize: CaptureDisplayInfo.pixelSize(displayID: displayID)
        )

        let first = try await backend.capture(.display(display))
        let second = try await backend.capture(.display(display))

        XCTAssertNotEqual(first.id, second.id, "每次捕获应产生新的稳定 id")
    }
    // MARK: - Region nudging (Task 014/01)

    /// 方向键微调：步长由调用方换算（叠层按显示器缩放给出 1 物理像素对应的逻辑点）。
    func testNudgeMovesRegionInsideDisplay() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 200, y: 180))
        state.mouseUp(at: CGPoint(x: 200, y: 180))

        XCTAssertTrue(state.nudgeRegion(axis: .horizontal, delta: 2, resize: false))
        XCTAssertTrue(state.nudgeRegion(axis: .vertical, delta: -3, resize: false))
        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 102, y: 97, width: 100, height: 80))
        )
    }

    /// `⇧` + 方向键沿该轴对称伸缩，中心保持不变。
    func testNudgeWithResizeGrowsSymmetrically() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 200, y: 180))
        state.mouseUp(at: CGPoint(x: 200, y: 180))

        XCTAssertTrue(state.nudgeRegion(axis: .horizontal, delta: 5, resize: true))
        XCTAssertEqual(
            state.phase,
            .adjustingRegion(display: leftDisplay, globalRect: CGRect(x: 95, y: 100, width: 110, height: 80)),
            "两侧各扩 5pt，中心不变"
        )
    }

    /// 微调不得把选区推出显示器，也不得缩到最小尺寸以下。
    func testNudgeClampsAtDisplayBoundsAndMinimumSize() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 5, y: 5), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 45, y: 35))
        state.mouseUp(at: CGPoint(x: 45, y: 35))

        state.nudgeRegion(axis: .horizontal, delta: -100, resize: false)
        guard case .adjustingRegion(_, let movedRect) = state.phase else {
            return XCTFail("Expected adjusting region")
        }
        XCTAssertEqual(movedRect.minX, leftDisplay.frame.minX, "向左微调应贴到屏幕左缘")

        for _ in 0..<20 {
            state.nudgeRegion(axis: .horizontal, delta: -10, resize: true)
        }
        guard case .adjustingRegion(_, let shrunk) = state.phase else {
            return XCTFail("Expected adjusting region")
        }
        XCTAssertEqual(shrunk.width, CaptureSessionState.minimumRegionSize, "收缩到最小尺寸即停住")
    }

    /// 非可微调态下方向键不产生任何变化。
    func testNudgeIsIgnoredOutsideAdjustingPhase() {
        var state = CaptureSessionState()
        XCTAssertFalse(state.nudgeRegion(axis: .horizontal, delta: 1, resize: false))

        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 110, y: 80))
        XCTAssertFalse(state.nudgeRegion(axis: .horizontal, delta: 1, resize: false), "拖拽中不处理微调")
    }

    /// 可微调态下 `⌘A` 仍可切到整屏。
    func testSelectFullDisplayWorksFromAdjustingPhase() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 110, y: 80))
        state.mouseUp(at: CGPoint(x: 110, y: 80))
        state.selectFullDisplay(leftDisplay)

        XCTAssertEqual(state.phase, .locked(.display(leftDisplay)))
    }
}
