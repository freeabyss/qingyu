import AppKit
import XCTest
@testable import Qingyu

/// 截图叠层的**外观**回归：压暗范围与选区"透出"。
///
/// 这两条都是用户可感知的画面行为，且无法由状态机单测覆盖：
/// - 只有当前指针所在显示器压暗，其他显示器保持原样（跨屏后随之切换）；
/// - 选区内必须"透出"原始画面（抠掉压暗层），而不是一块同样发暗的方块。
@MainActor
final class ScreenshotOverlayAppearanceTests: XCTestCase {

    private let width: CGFloat = 800
    private let height: CGFloat = 500

    private var display: CaptureDisplay {
        CaptureDisplay(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            pixelSize: CGSize(width: width, height: height)
        )
    }

    private func makeView(isActive: Bool, region: CGRect? = nil, highlight: CGRect? = nil) -> CaptureOverlayContentView {
        let view = CaptureOverlayContentView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            display: display
        )
        view.isActiveDisplay = isActive
        view.highlightFrame = highlight
        view.regionFrame = region
        view.layoutSubtreeIfNeeded()
        return view
    }

    @discardableResult
    private func render(_ view: NSView, dump name: String? = nil) -> NSBitmapImageRep {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        if let name, let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/overlay-\(name).png"))
        }
        return rep
    }

    /// 位图坐标（左上原点）取样点的 alpha。
    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        guard let color = rep.colorAt(x: x, y: y) else { return -1 }
        return color.alphaComponent
    }

    // MARK: - 压暗范围

    func testInactiveDisplayIsNotDimmed() {
        let view = makeView(isActive: false)
        let rep = render(view, dump: "inactive")

        let corner = alpha(rep, x: 40, y: 40)
        let center = alpha(rep, x: Int(width / 2), y: Int(height / 2))
        XCTAssertEqual(corner, 0, accuracy: 0.02, "非当前显示器不应压暗（左上角 alpha）")
        XCTAssertEqual(center, 0, accuracy: 0.02, "非当前显示器不应压暗（中心 alpha）")
    }

    func testActiveDisplayIsDimmed() {
        let view = makeView(isActive: true)
        let rep = render(view, dump: "active")

        let alphaValue = alpha(rep, x: Int(width / 2), y: Int(height / 2))
        XCTAssertEqual(alphaValue, 0.3, accuracy: 0.05, "当前显示器应整体压暗")
    }

    // MARK: - 选区透出

    func testRegionIsPunchedClearWhileOutsideStaysDimmed() {
        // 选区取屏幕中央 400×200（局部坐标即全局坐标，显示器原点在 0,0）。
        let region = CGRect(x: 200, y: 150, width: 400, height: 200)
        let view = makeView(isActive: true, region: region)
        let rep = render(view, dump: "region")

        // 位图 y 轴向下：region 在 AppKit 中 y∈[150,350] → 位图 y∈[150,350] 同样成立，
        // 因为 height 500 时上边距 500-350=150、下边距 150。
        let inside = alpha(rep, x: 400, y: 250)
        let outside = alpha(rep, x: 40, y: 40)
        XCTAssertEqual(inside, 0, accuracy: 0.05, "选区内部必须透出原始画面（不应发暗）")
        XCTAssertEqual(outside, 0.3, accuracy: 0.05, "选区之外应保持压暗")
    }

    func testDraggingRegionKeepsSelectionTransparent() {
        let region = CGRect(x: 100, y: 100, width: 300, height: 300)
        let view = makeView(isActive: true, region: region)
        let rep = render(view, dump: "dragging")
        XCTAssertEqual(alpha(rep, x: 200, y: 200), 0, accuracy: 0.05, "拖拽中的选区内应透出画面")
    }

    // MARK: - 放大镜（选区外遮罩）

    /// 纯白取样位图：放大镜内容是否被压暗，用它的亮度直接量出来。
    private func makeWhiteSample(pixels: Int = 14) -> MagnifierSample {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        NSGraphicsContext.restoreGraphicsState()

        return MagnifierSample(
            displayID: 1,
            image: rep.cgImage!,
            sourceRect: CGRect(x: 1000, y: 1000, width: CGFloat(pixels), height: CGFloat(pixels)),
            pixelCenter: CGPoint(x: 1000 + CGFloat(pixels) / 2, y: 1000 + CGFloat(pixels) / 2)
        )
    }

    private func makeMagnifier() -> MagnifierOverlayView {
        let view = MagnifierOverlayView(frame: NSRect(x: 0, y: 0, width: 112, height: 112))
        view.configuration = MagnifierConfiguration(isEnabled: true, zoom: 8, options: [.mask])
        view.update(sample: makeWhiteSample())
        view.isHidden = false
        return view
    }

    private func luminance(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        guard let color = rep.colorAt(x: x, y: y) else { return -1 }
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255
    }

    /// 放大区域整块落在选区之外时不得压暗：否则放大镜就是一块看不出内容的暗方块。
    func testMagnifierDoesNotDimWhenSelectionIsEntirelyOutsideSample() {
        let view = makeMagnifier()
        // 选区在取样窗口左侧很远处（完全不相交）。
        view.maskRectInPixels = CGRect(x: 500, y: 500, width: 400, height: 300)
        let rep = render(view, dump: "magnifier-no-overlap")

        XCTAssertEqual(luminance(rep, x: 30, y: 56), 255, accuracy: 8, "放大画面应保持清晰（左半）")
        XCTAssertEqual(luminance(rep, x: 80, y: 56), 255, accuracy: 8, "放大画面应保持清晰（右半）")
    }

    /// 选区边界落在取样窗口内时，仅「选区之外」的一侧轻微压暗，用来指示边界。
    func testMagnifierDimsOnlySlightlyOutsideSelection() {
        let view = makeMagnifier()
        // 选区覆盖取样窗口左半（显示像素、左上原点）：左半在选区内，右半在选区外。
        view.maskRectInPixels = CGRect(x: 1000, y: 1000, width: 7, height: 14)
        let rep = render(view, dump: "magnifier-straddle")

        let inside = luminance(rep, x: 30, y: 56)
        let outside = luminance(rep, x: 80, y: 56)
        XCTAssertEqual(inside, 255, accuracy: 8, "选区内一侧不应压暗")
        XCTAssertLessThan(outside, inside, "选区外一侧应被压暗以指示边界")
        XCTAssertGreaterThan(outside, 180, "压暗必须轻微，保证放大画面仍然可读")
    }
}
