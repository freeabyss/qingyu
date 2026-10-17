import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 011：放大镜纯几何换算契约。
///
/// 这些用例不依赖真实屏幕、窗口或屏幕录制权限，全部走纯函数，
/// 因此可以在无头环境下稳定运行（`scripts/verify.sh` 必跑）。
final class MagnifierGeometryTests: XCTestCase {

    // MARK: - 逻辑点 ⇄ 像素

    /// 主显示器：逻辑 1920×1080、原生 3840×2160（2×）。
    private let retina = CaptureDisplay(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 3840, height: 2160)
    )

    /// 负坐标副屏：逻辑原点在 (-1280, 200)，1× 屏。
    private let secondary = CaptureDisplay(
        id: 2,
        frame: CGRect(x: -1280, y: 200, width: 1280, height: 1024),
        pixelSize: CGSize(width: 1280, height: 1024)
    )

    func testSamplePointFlipsVerticallyAndScalesOnRetina() {
        let scale = MagnifierGeometry.displayScale(frame: retina.frame, pixelSize: retina.pixelSize)
        XCTAssertEqual(scale, 2, accuracy: 0.0001)

        // 屏幕左上角 → 像素 (0, 0)
        let topLeft = MagnifierGeometry.samplePoint(
            logicalPoint: CGPoint(x: 0, y: 1080),
            screenFrame: retina.frame,
            scale: scale
        )
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)

        // 屏幕右下角 → 像素 (3840, 2160)
        let bottomRight = MagnifierGeometry.samplePoint(
            logicalPoint: CGPoint(x: 1920, y: 0),
            screenFrame: retina.frame,
            scale: scale
        )
        XCTAssertEqual(bottomRight.x, 3840, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, 2160, accuracy: 0.0001)
    }

    func testSamplePointHandlesNegativeOriginDisplay() {
        let scale = MagnifierGeometry.displayScale(frame: secondary.frame, pixelSize: secondary.pixelSize)
        XCTAssertEqual(scale, 1, accuracy: 0.0001)

        // 该屏左上角在 AppKit 上是 (minX, maxY)。
        let topLeft = MagnifierGeometry.samplePoint(
            logicalPoint: CGPoint(x: secondary.frame.minX, y: secondary.frame.maxY),
            screenFrame: secondary.frame,
            scale: scale
        )
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)
    }

    /// `samplePoint` 与 `logicalPoint` 必须互为逆运算，否则放大镜中心与取色点会错位。
    func testSamplePointAndLogicalPointAreInverse() {
        let scale = MagnifierGeometry.displayScale(frame: retina.frame, pixelSize: retina.pixelSize)
        let original = CGPoint(x: 800, y: 300)
        let pixel = MagnifierGeometry.samplePoint(
            logicalPoint: original,
            screenFrame: retina.frame,
            scale: scale
        )
        let roundTrip = MagnifierGeometry.logicalPoint(
            pixelPoint: pixel,
            screenFrame: retina.frame,
            scale: scale
        )
        XCTAssertEqual(roundTrip.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.y, original.y, accuracy: 0.0001)
    }

    func testDisplayScaleFallsBackToOneForDegenerateInput() {
        XCTAssertEqual(
            MagnifierGeometry.displayScale(frame: .zero, pixelSize: CGSize(width: 100, height: 100)),
            1
        )
        XCTAssertEqual(
            MagnifierGeometry.displayScale(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                pixelSize: .zero
            ),
            1
        )
    }

    // MARK: - 采样窗口

    func testPixelCountFollowsViewSizeAndZoom() {
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 112, zoom: 2), 56)
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 112, zoom: 4), 28)
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 112, zoom: 8), 14)
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 112, zoom: 16), 7)
    }

    func testPixelCountNeverDropsBelowOne() {
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 8, zoom: 64), 1)
        XCTAssertEqual(MagnifierGeometry.pixelCount(viewSize: 112, zoom: 0), 112)
    }

    func testSourceRectIsCenteredAndClampedAtEdges() {
        let display = CGSize(width: 100, height: 100)

        let centered = MagnifierGeometry.sourceRect(
            centeredAt: CGPoint(x: 50, y: 50),
            pixelCount: 10,
            displayPixelSize: display
        )
        XCTAssertEqual(centered, CGRect(x: 45, y: 45, width: 10, height: 10))

        // 左上角越界 → 原点钳制到 0，尺寸不变。
        let topLeft = MagnifierGeometry.sourceRect(
            centeredAt: CGPoint(x: 1, y: 1),
            pixelCount: 10,
            displayPixelSize: display
        )
        XCTAssertEqual(topLeft, CGRect(x: 0, y: 0, width: 10, height: 10))

        // 右下角越界 → 原点钳制到 size - side。
        let bottomRight = MagnifierGeometry.sourceRect(
            centeredAt: CGPoint(x: 99, y: 99),
            pixelCount: 10,
            displayPixelSize: display
        )
        XCTAssertEqual(bottomRight, CGRect(x: 90, y: 90, width: 10, height: 10))
    }

    func testSourceRectStaysInsideDisplaySmallerThanSampleWindow() {
        let rect = MagnifierGeometry.sourceRect(
            centeredAt: CGPoint(x: 4, y: 4),
            pixelCount: 20,
            displayPixelSize: CGSize(width: 8, height: 8)
        )
        XCTAssertEqual(rect.origin, .zero)
        XCTAssertEqual(rect.width, 20)
    }

    // MARK: - 放大镜框位置

    func testMagnifierFrameSitsBelowRightOfAnchorWhenRoomExists() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = MagnifierGeometry.magnifierFrame(
            anchor: CGPoint(x: 500, y: 500),
            size: CGSize(width: 112, height: 112),
            visibleFrame: visible,
            gap: 18
        )
        // 默认右下：x = 500 + 18；y = 500 - 18 - 112（下边距 = 锚点 y - 间隙）。
        XCTAssertEqual(frame.origin.x, 518)
        XCTAssertEqual(frame.origin.y, 500 - 18 - 112)
    }

    func testMagnifierFrameFlipsToLeftAndTopWhenNoRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 112, height: 112)

        // 右侧空间不足 → 翻到锚点左侧。
        let nearRight = MagnifierGeometry.magnifierFrame(
            anchor: CGPoint(x: 1900, y: 500),
            size: size,
            visibleFrame: visible,
            gap: 18
        )
        XCTAssertEqual(nearRight.maxX, 1900 - 18)

        // 下方空间不足 → 翻到锚点上方。
        let nearBottom = MagnifierGeometry.magnifierFrame(
            anchor: CGPoint(x: 500, y: 60),
            size: size,
            visibleFrame: visible,
            gap: 18
        )
        XCTAssertEqual(nearBottom.minY, 60 + 18)
    }

    func testMagnifierFrameStaysInsideVisibleFrameForNegativeOriginDisplay() {
        let visible = CGRect(x: -1280, y: 200, width: 1280, height: 1024)
        let size = CGSize(width: 112, height: 112)
        let frame = MagnifierGeometry.magnifierFrame(
            anchor: CGPoint(x: -1280, y: 200),
            size: size,
            visibleFrame: visible,
            gap: 18
        )
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    // MARK: - Quartz 屏幕坐标

    func testQuartzRectFlipsYAgainstMainDisplayHeight() {
        // 主显示器高 1080；AppKit 上 (100, 900) 起、高 100 的矩形，
        // 对应 Quartz 的 y = 1080 - 1000 = 80。
        let appKit = CGRect(x: 100, y: 900, width: 200, height: 100)
        let quartz = MagnifierGeometry.quartzRect(fromAppKitRect: appKit, mainDisplayHeight: 1080)
        XCTAssertEqual(quartz, CGRect(x: 100, y: 80, width: 200, height: 100))
    }

    func testQuartzRectKeepsNegativeXForSecondaryDisplay() {
        let appKit = CGRect(x: -1280, y: 200, width: 100, height: 100)
        let quartz = MagnifierGeometry.quartzRect(fromAppKitRect: appKit, mainDisplayHeight: 1080)
        XCTAssertEqual(quartz.minX, -1280)
        XCTAssertEqual(quartz.minY, 1080 - 300)
    }
}

// MARK: - 取样结果

final class MagnifierSampleTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) where index % 4 == 0 {
            data[index * 4 + 3] = 255
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    func testCenterIndexIsRelativeToSourceRect() {
        let sample = MagnifierSample(
            displayID: 1,
            image: makeImage(width: 14, height: 14),
            sourceRect: CGRect(x: 100, y: 200, width: 14, height: 14),
            pixelCenter: CGPoint(x: 107, y: 207)
        )
        XCTAssertEqual(sample.centerIndex?.x, 7)
        XCTAssertEqual(sample.centerIndex?.y, 7)
    }

    func testCenterIndexIsNilWhenOutsideImage() {
        let sample = MagnifierSample(
            displayID: 1,
            image: makeImage(width: 4, height: 4),
            sourceRect: CGRect(x: 0, y: 0, width: 4, height: 4),
            pixelCenter: CGPoint(x: 40, y: 40)
        )
        XCTAssertNil(sample.centerIndex)
    }
}
