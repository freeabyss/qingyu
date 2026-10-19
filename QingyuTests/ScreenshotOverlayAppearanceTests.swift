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

    /// 同一块画布上重绘两次，压暗层**不得**叠加变深。
    ///
    /// 用户报告（2026-10-18）：「在选中区域外边有一层暗色的方块，位于左上角」。
    /// 成因是 `draw` 直接在 dirtyRect 上铺 30% 黑：叠层是半透明窗口，合成结果留在
    /// backing store 里，凡是被重绘过的矩形（旧窗口高亮、旧选区所在的左上角）就会
    /// 再叠一层，越叠越黑。现在每次重绘先把整张画布清成透明再铺一次。
    func testRedrawingDoesNotDeepenTheDimLayer() {
        let view = makeView(isActive: true, region: CGRect(x: 120, y: 80, width: 200, height: 160))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("无法创建缓存位图")
        }
        // 第一次：选区在左下；第二次：选区挪到别处，原选区位置与全屏都重绘一遍。
        view.cacheDisplay(in: view.bounds, to: rep)
        let first = alpha(rep, x: 40, y: 40)
        view.regionFrame = CGRect(x: 420, y: 300, width: 200, height: 160)
        view.cacheDisplay(in: view.bounds, to: rep)
        let second = alpha(rep, x: 40, y: 40)

        XCTAssertEqual(first, 0.3, accuracy: 0.03, "压暗层应是 30% 黑")
        XCTAssertEqual(second, 0.3, accuracy: 0.03, "重绘不得叠加压暗（会变成一块更黑的方块）")
    }

    /// 局部重绘：只重绘一条竖带时，带内外亮度必须完全一致。
    ///
    /// 用户报告（2026-10-18）：「还是有暗色区域」。复核其后上传的截图可见一条**贯穿全屏
    /// 高度（连菜单栏都覆盖）的竖直接缝**，接缝左侧亮度恰为右侧的 0.7 倍 —— 即压暗层
    /// 被叠了两次。这正是 `draw` 直接用 `dirtyRect` 铺黑的结果：压暗的合成结果留在
    /// backing store 里，哪块被重绘两次，哪块就更黑。
    ///
    /// 现在 `draw` 先把整张画布清成透明，因此「只重绘一条竖带」与「整屏重绘」结果相同。
    func testPartialRedrawDoesNotDeepenTheDimLayer() {
        let view = makeView(isActive: true)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("无法创建缓存位图")
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        // 只重绘中间一条竖带（真实场景：高亮框/光标所在列发生变化）。
        let band = NSRect(x: 380, y: 0, width: 40, height: height)
        view.setNeedsDisplay(band)
        view.displayIfNeeded()
        view.cacheDisplay(in: band, to: rep)

        let insideBand = alpha(rep, x: 400, y: 40)
        let outsideBand = alpha(rep, x: 40, y: 40)
        XCTAssertEqual(outsideBand, 0.3, accuracy: 0.03, "带外应保持一次压暗")
        XCTAssertEqual(
            insideBand, outsideBand, accuracy: 0.02,
            "局部重绘不得让该竖带比周围更黑（用户看到的就是这条更暗的竖带）"
        )
    }

    /// 只重绘一条竖带时，**上一次选区留在画布上的透明挖空也必须一起重算**。
    ///
    /// 这是「暗色区域」的另一种形态：旧选区的挖空不在本次 dirtyRect 内时，
    /// 若只清 dirtyRect，它会一直保持透明；等它应当被压暗时就成了边界笔直的
    /// 亮/暗块。draw 现在先解除裁剪、整屏重算，因此旧挖空会被重新压暗。
    func testPartialRedrawRefreshesHolesFromPreviousRegion() {
        let oldRegion = CGRect(x: 200, y: 150, width: 400, height: 200)
        let view = makeView(isActive: true, region: oldRegion)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("无法创建缓存位图")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        XCTAssertEqual(alpha(rep, x: 400, y: 250), 0, accuracy: 0.05, "旧选区中心应为透明挖空")

        // 选区移到左上角；只重绘中间一条竖带（旧挖空在这条带之外）。
        view.regionFrame = CGRect(x: 20, y: 20, width: 100, height: 80)
        let band = NSRect(x: 380, y: 0, width: 40, height: height)
        view.cacheDisplay(in: band, to: rep)

        XCTAssertEqual(
            alpha(rep, x: 400, y: 250), 0.3, accuracy: 0.05,
            "旧选区的透明挖空必须被重新压暗；否则会留下边界笔直的亮/暗块"
        )
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

    /// 放大镜**不得有暗色底板**：它显示的就该是被放大的那几像素本身。
    ///
    /// 用户报告（2026-10-18）：「拖拽时还是有发暗的方块，应该去掉暗色方块」。
    /// 成因是视图先铺一层 78% 黑的圆角底板、再把取样图内缩 6pt 画上去：取样未到
    /// （或内容本身偏暗）时，整块就是一块看不出内容的暗方块。
    func testMagnifierHasNoDarkPlateAroundTheSample() {
        let view = makeMagnifier()
        let rep = render(view, dump: "magnifier-no-plate")

        // 取样图为纯白：留着底板时，四条内缩边带会明显发暗（约 56 而不是 255）。
        XCTAssertEqual(luminance(rep, x: 4, y: 56), 255, accuracy: 8, "左边缘应是画面本身，不是暗色底板")
        XCTAssertEqual(luminance(rep, x: 107, y: 56), 255, accuracy: 8, "右边缘应是画面本身，不是暗色底板")
        XCTAssertEqual(luminance(rep, x: 56, y: 4), 255, accuracy: 8, "上边缘应是画面本身，不是暗色底板")
        XCTAssertEqual(luminance(rep, x: 56, y: 107), 255, accuracy: 8, "下边缘应是画面本身，不是暗色底板")
    }

    /// 选区边界落在取样窗口内时，只描出边界，**不得压暗**任何画面。
    ///
    /// 2026-10-19 用户复测：「暗色的区域在拖拽过程中，以及拖拽结束后，光标移到
    /// 圈选区域时，会出现」—— 半透明黑色遮罩即使只有 0.18，压在放大镜边缘上仍
    /// 会被读成一块暗色区域。边界现在只用一深一浅两条描边表示。
    func testMagnifierMarksBoundaryWithoutDimmingContent() {
        let view = makeMagnifier()
        // 选区覆盖取样窗口左半（显示像素、左上原点）：左半在选区内，右半在选区外。
        view.maskRectInPixels = CGRect(x: 1000, y: 1000, width: 7, height: 14)
        let rep = render(view, dump: "magnifier-straddle")

        let inside = luminance(rep, x: 30, y: 56)
        let outside = luminance(rep, x: 80, y: 56)
        XCTAssertEqual(inside, 255, accuracy: 8, "选区内一侧不应压暗")
        XCTAssertEqual(outside, 255, accuracy: 8, "选区外一侧也不得压暗，只保留边界描边")
    }
}
