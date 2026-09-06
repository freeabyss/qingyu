import CoreGraphics
import XCTest
@testable import Qingniao

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

    func testClickWithoutWindowCandidateStaysTargeting() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 50, y: 50), display: leftDisplay)
        state.mouseUp(at: CGPoint(x: 50, y: 50))

        XCTAssertEqual(state.phase, .targetingWindow(nil))
    }

    // MARK: - Region drag flow

    func testRegionDragFlowLocksRegion() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: rightDisplay)
        state.mouseDragged(to: CGPoint(x: 110, y: 80))
        state.mouseUp(at: CGPoint(x: 110, y: 80))

        XCTAssertEqual(
            state.phase,
            .locked(.region(display: rightDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70)))
        )
    }

    func testReverseDragNormalizesRegionRect() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 110, y: 80), display: rightDisplay)
        state.mouseDragged(to: CGPoint(x: 10, y: 10))
        state.mouseUp(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(
            state.phase,
            .locked(.region(display: rightDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70)))
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

    func testExactlyMinimumSizeRegionLocks() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.mouseDragged(to: CGPoint(x: 15, y: 15))
        state.mouseUp(at: CGPoint(x: 15, y: 15))

        XCTAssertEqual(
            state.phase,
            .locked(.region(display: leftDisplay, globalRect: CGRect(x: 10, y: 10, width: 5, height: 5)))
        )
    }

    func testPointerMovedDuringDragIsIgnored() {
        var state = CaptureSessionState()
        state.mouseDown(at: CGPoint(x: 10, y: 10), display: leftDisplay)
        state.pointerMoved(to: CGPoint(x: 900, y: 900), display: rightDisplay, window: rightWindow)
        state.mouseDragged(to: CGPoint(x: 110, y: 110))
        state.mouseUp(at: CGPoint(x: 110, y: 110))

        guard case .locked(.region(let display, let rect)) = state.phase else {
            return XCTFail("Expected locked region, got \(state.phase)")
        }
        XCTAssertEqual(display.id, leftDisplay.id)
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 100, height: 100))
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
}
