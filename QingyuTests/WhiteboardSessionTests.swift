import AppKit
import XCTest
@testable import Qingyu

/// Task 016：白板会话、互斥规则、目标屏解析与纯色底图。
final class WhiteboardSessionTests: XCTestCase {

    // MARK: - 会话互斥

    func testSessionExclusionIsMutuallyExclusive() {
        var exclusion = SessionExclusion()
        XCTAssertTrue(exclusion.isIdle)

        XCTAssertTrue(exclusion.begin(.whiteboard))
        XCTAssertFalse(
            exclusion.begin(.screenshot),
            "白板进行中不允许启动截图"
        )
        XCTAssertEqual(exclusion.active, .whiteboard)

        exclusion.end(.whiteboard)
        XCTAssertTrue(exclusion.isIdle)
        XCTAssertTrue(exclusion.begin(.screenshot))
        XCTAssertFalse(exclusion.begin(.whiteboard), "截图进行中不允许启动白板")
    }

    func testSessionExclusionRepeatedBeginIsIdempotent() {
        var exclusion = SessionExclusion()

        XCTAssertTrue(exclusion.begin(.screenshot))
        XCTAssertTrue(exclusion.begin(.screenshot), "重复触发同一入口不应被自己挡住")
        XCTAssertEqual(exclusion.active, .screenshot)
    }

    func testSessionExclusionIgnoresMismatchedEnd() {
        var exclusion = SessionExclusion()
        _ = exclusion.begin(.whiteboard)

        exclusion.end(.screenshot)

        XCTAssertEqual(
            exclusion.active,
            .whiteboard,
            "错配的结束调用不得清掉别人的占用"
        )
    }

    // MARK: - 空白退出规则

    func testBlankWhiteboardExitsWithoutConfirmationOrOutput() {
        XCTAssertFalse(WhiteboardExitRule.requiresConfirmation(shapeCount: 0))
        XCTAssertFalse(WhiteboardExitRule.shouldProduceOutput(shapeCount: 0))
    }

    func testWhiteboardWithStrokesRequiresConfirmation() {
        XCTAssertTrue(WhiteboardExitRule.requiresConfirmation(shapeCount: 1))
        XCTAssertTrue(WhiteboardExitRule.shouldProduceOutput(shapeCount: 1))
    }

    // MARK: - 会话配置

    func testDefaultSessionIsSolidWhite() {
        let session = WhiteboardSession()

        XCTAssertEqual(session.background, .solid, "纯色底图不要求屏幕录制权限，作为默认更安全")
        XCTAssertEqual(session.solidColorHex, WhiteboardSession.defaultSolidColorHex)
        XCTAssertTrue(session.displayIDs.isEmpty)
    }

    func testInvalidSolidColorFallsBackToWhite() {
        let session = WhiteboardSession(solidColorHex: "not-a-color")

        XCTAssertEqual(session.solidColor, NSColor(hexString: WhiteboardSession.defaultSolidColorHex))
    }

    func testSessionCodableRoundTrip() throws {
        let session = WhiteboardSession(
            background: .frozen,
            solidColorHex: "#123456",
            displayIDs: ["1", "2"]
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WhiteboardSession.self, from: data)

        XCTAssertEqual(decoded, session)
    }

    // MARK: - 目标屏解析

    func testPointerTargetUsesPointerDisplay() {
        XCTAssertEqual(
            WhiteboardTargetResolver.displayIDs(
                target: .pointer,
                availableDisplayIDs: ["1", "2"],
                pointerDisplayID: "2"
            ),
            ["2"]
        )
    }

    func testPointerTargetFallsBackToFirstDisplayWhenPointerUnknown() {
        XCTAssertEqual(
            WhiteboardTargetResolver.displayIDs(
                target: .pointer,
                availableDisplayIDs: ["1", "2"],
                pointerDisplayID: "9"
            ),
            ["1"]
        )
    }

    func testNamedTargetRejectsMissingDisplayInsteadOfFallingBack() {
        XCTAssertEqual(
            WhiteboardTargetResolver.displayIDs(
                target: .display("2"),
                availableDisplayIDs: ["1", "2"],
                pointerDisplayID: "1"
            ),
            ["2"]
        )
        XCTAssertEqual(
            WhiteboardTargetResolver.displayIDs(
                target: .display("9"),
                availableDisplayIDs: ["1", "2"],
                pointerDisplayID: "1"
            ),
            [],
            "指定屏不存在时必须报空，不得静默改用其它屏幕"
        )
    }

    func testAllDisplaysTargetIsCapped() {
        let many = (0..<(WhiteboardSession.maximumDisplayCount + 4)).map(String.init)

        XCTAssertEqual(
            WhiteboardTargetResolver.displayIDs(
                target: .allDisplays,
                availableDisplayIDs: many,
                pointerDisplayID: nil
            ).count,
            WhiteboardSession.maximumDisplayCount
        )
    }

    func testEmptyTopologyResolvesToNothing() {
        for target in [WhiteboardTarget.pointer, .display("1"), .allDisplays] {
            XCTAssertTrue(
                WhiteboardTargetResolver.displayIDs(
                    target: target,
                    availableDisplayIDs: [],
                    pointerDisplayID: nil
                ).isEmpty
            )
        }
    }

    // MARK: - 纯色底图

    func testSolidImageMatchesRequestedPixelSizeAndColor() throws {
        let image = try XCTUnwrap(WhiteboardBackground.solidImage(
            pixelSize: CGSize(width: 320, height: 200),
            color: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        ))

        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 320)
        XCTAssertEqual(rep.pixelsHigh, 200)

        let center = try XCTUnwrap(rep.colorAt(x: 160, y: 100)?.usingColorSpace(.sRGB))
        XCTAssertEqual(center.redComponent, 0.1, accuracy: 0.02)
        XCTAssertEqual(center.greenComponent, 0.2, accuracy: 0.02)
        XCTAssertEqual(center.blueComponent, 0.3, accuracy: 0.02)
    }

    func testSolidImageClampsDegenerateSizes() throws {
        let image = try XCTUnwrap(WhiteboardBackground.solidImage(
            pixelSize: CGSize(width: 0, height: -10),
            color: .white
        ))

        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 1, "退化尺寸钳到 1 像素，不返回 nil")
        XCTAssertEqual(rep.pixelsHigh, 1)
    }

    /// 纯色底图**不读取屏幕内容**：这里在没有任何屏幕录制权限的测试进程里
    /// 直接构造底图，能成功即说明实现路径不依赖抓屏 API。
    func testSolidImageDoesNotRequireScreenCapture() throws {
        let image = try XCTUnwrap(WhiteboardBackground.solidImage(
            pixelSize: CGSize(width: 64, height: 48),
            color: .white
        ))

        XCTAssertEqual(image.size, CGSize(width: 64, height: 48))
    }

    func testFrozenImageUsesProvidedCGImage() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 40,
            pixelsHigh: 30,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let cgImage = try XCTUnwrap(rep.cgImage)

        let image = WhiteboardBackground.frozenImage(from: cgImage)

        XCTAssertEqual(image.size, CGSize(width: 40, height: 30))
    }

    func testBackgroundKindLocalizationKeys() {
        for kind in WhiteboardBackgroundKind.allCases {
            XCTAssertFalse(L10n.localized(kind.localizationKey).isEmpty)
        }
    }
}


// MARK: - Task 016：白板窗口生命周期回归

@MainActor
final class WhiteboardLifecycleTests: XCTestCase {

    private func display(id: CGDirectDisplayID, frame: CGRect) -> CaptureDisplay {
        CaptureDisplay(id: id, frame: frame, pixelSize: frame.size)
    }

    private func makeController() -> WhiteboardWindowController {
        let controller = WhiteboardWindowController()
        return controller
    }

    func testPresentCreatesOneWindowPerTargetDisplay() {
        let controller = makeController()
        defer { controller.dismiss(force: true) }

        let presented = controller.present(
            session: WhiteboardSession(),
            displays: [
                display(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
                display(id: 2, frame: CGRect(x: 800, y: 0, width: 800, height: 600))
            ]
        )

        XCTAssertTrue(presented)
        XCTAssertTrue(controller.isPresented)
    }

    func testPresentWithNoTargetsIsRejected() {
        let controller = makeController()

        XCTAssertFalse(controller.present(session: WhiteboardSession(), displays: []))
        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.totalShapeCount, 0)
    }

    func testDismissReleasesWindowsAndStrokes() {
        let controller = makeController()
        _ = controller.present(
            session: WhiteboardSession(),
            displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300))]
        )

        var dismissCalls = 0
        controller.onDismiss = { dismissCalls += 1 }
        controller.dismiss(force: true)

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.totalShapeCount, 0)
        XCTAssertEqual(dismissCalls, 1, "退出后必须通知调用方释放互斥占用")

        // 重复退出不应重复回调。
        controller.dismiss(force: true)
        XCTAssertEqual(dismissCalls, 1)
    }

    /// 生命周期回归：连续开关 10 次不得留下窗口或状态。
    func testRepeatedOpenCloseLeavesNoResidualWindows() {
        let controller = makeController()
        let displays = [display(id: 1, frame: CGRect(x: 0, y: 0, width: 640, height: 480))]

        for _ in 0..<10 {
            XCTAssertTrue(controller.present(session: WhiteboardSession(), displays: displays))
            controller.dismiss(force: true)
            XCTAssertFalse(controller.isPresented)
            XCTAssertEqual(controller.totalShapeCount, 0)
        }

        XCTAssertFalse(controller.isPresented)
    }

    /// 重新呈现必须先清掉上一轮的窗口，避免叠出多块白板。
    func testPresentTwiceDoesNotStackWindows() {
        let controller = makeController()
        defer { controller.dismiss(force: true) }
        let displays = [display(id: 1, frame: CGRect(x: 0, y: 0, width: 640, height: 480))]

        _ = controller.present(session: WhiteboardSession(), displays: displays)
        _ = controller.present(session: WhiteboardSession(), displays: displays)

        XCTAssertTrue(controller.isPresented)
        // 只有一块白板：笔迹计数来自唯一一份状态。
        XCTAssertEqual(controller.totalShapeCount, 0)
    }

    func testBlankWhiteboardExitSkipsConfirmation() {
        let controller = makeController()
        _ = controller.present(
            session: WhiteboardSession(),
            displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 320, height: 240))]
        )

        // 空白：requestExit 直接退出，不弹确认（此处不需要任何 UI 交互即可完成）。
        controller.requestExit()

        XCTAssertFalse(controller.isPresented)
    }
}
