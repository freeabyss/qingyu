import AppKit
import CoreGraphics

// MARK: - Magnifier view (Task 011)

/// 放大镜视图：最近邻放大光标周围的屏幕像素，叠加网格、坐标、倍数与选区遮罩。
///
/// 只负责绘制，取样由 `MagnifierSourcing` 提供；视图不发起任何系统调用，
/// 因此可以在离屏渲染中直接喂入 `MagnifierSample` 做验证。
final class MagnifierOverlayView: NSView {

    var configuration: MagnifierConfiguration = .default {
        didSet { needsDisplay = true }
    }

    private(set) var sample: MagnifierSample?

    /// 当前选区（显示器像素坐标，左上原点）；仅在开启遮罩且已有选区时生效。
    var maskRectInPixels: CGRect? {
        didSet { needsDisplay = true }
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        isHidden = true
    }

    // MARK: - Content

    func update(sample: MagnifierSample?) {
        self.sample = sample
        needsDisplay = true
    }

    /// 清空画面但保留配置（例如指针离开当前屏幕）。
    func clearSample() {
        sample = nil
        needsDisplay = true
    }

    // MARK: - Drawing

    private enum Metrics {
        static let borderWidth: CGFloat = 1
        /// 徽标与画面边缘的间距。画面本身**满幅**（不留内边距），间距只用于放徽标。
        static let labelInset: CGFloat = 4
        static let cornerRadius: CGFloat = 8
        static let labelPadding: CGFloat = 5
        static let labelFontSize: CGFloat = 10
        static let minimumCellSizeForGrid: CGFloat = 3
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 放大镜**不画底板**：它显示的就是「被放大的那几像素」本身。
        //
        // 这里原先先铺一层 78% 黑的圆角底板、再把取样图内缩 6pt 画上去，于是
        // 「取样尚未到达」或「取样内容本身偏暗」时，用户看到的就是一个跟着光标走、
        // 看不出任何内容的**发暗方块** —— 正是用户报告的现象。底板没有任何信息价值，
        // 只留一圈描边把画面从屏幕上托起来。
        guard let sample else { return }

        let content = bounds
        let imageWidth = CGFloat(sample.image.width)
        let imageHeight = CGFloat(sample.image.height)
        guard imageWidth > 0, imageHeight > 0, content.width > 0, content.height > 0 else { return }

        // 每个源像素占据的点数；实际图像尺寸与请求可能有 ±1 像素的取整差，
        // 因此统一按图像自身尺寸推导，保证中心像素高亮位置自洽。
        let cell = min(content.width / imageWidth, content.height / imageHeight)
        let drawnSize = CGSize(width: imageWidth * cell, height: imageHeight * cell)
        let origin = CGPoint(
            x: content.minX + (content.width - drawnSize.width) / 2,
            y: content.minY + (content.height - drawnSize.height) / 2
        )
        let drawnRect = CGRect(origin: origin, size: drawnSize)

        drawImage(sample.image, in: drawnRect, clip: content)

        if configuration.options.contains(.mask) {
            drawMask(sample: sample, drawnRect: drawnRect, clip: content)
        }
        if configuration.options.contains(.grid), cell >= Metrics.minimumCellSizeForGrid {
            drawGrid(imageWidth: Int(imageWidth), imageHeight: Int(imageHeight), cell: cell, drawnRect: drawnRect)
        }
        drawCenterPixel(sample: sample, cell: cell, drawnRect: drawnRect)
        drawLabels(sample: sample, content: content.insetBy(dx: Metrics.labelInset, dy: Metrics.labelInset))
        drawLensEdge()
    }

    /// 镜片边缘：一深一浅两条细描边。浅色画面靠深描边分界、深色画面靠浅描边分界，
    /// 因此放大镜压在任何内容上都读得出来（底板去掉后，边界只能靠它）。
    private func drawLensEdge() {
        let lens = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Metrics.borderWidth / 2, dy: Metrics.borderWidth / 2),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        lens.lineWidth = Metrics.borderWidth
        NSColor.black.withAlphaComponent(0.45).set()
        lens.stroke()

        let inner = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Metrics.borderWidth * 1.5, dy: Metrics.borderWidth * 1.5),
            xRadius: Metrics.cornerRadius - Metrics.borderWidth,
            yRadius: Metrics.cornerRadius - Metrics.borderWidth
        )
        inner.lineWidth = Metrics.borderWidth
        NSColor.white.withAlphaComponent(0.7).set()
        inner.stroke()
    }

    private func drawImage(_ image: CGImage, in rect: CGRect, clip: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // 圆角裁切：画面满幅，圆角只能靠裁剪得到，否则四角会露出方角。
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        ).addClip()
        context.clip(to: clip)
        // 最近邻：放大必须看到真实像素边界，插值会让边界失真。
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func drawGrid(imageWidth: Int, imageHeight: Int, cell: CGFloat, drawnRect: CGRect) {
        let path = NSBezierPath()
        for column in 1..<max(1, imageWidth) {
            let x = drawnRect.minX + CGFloat(column) * cell
            path.move(to: NSPoint(x: x, y: drawnRect.minY))
            path.line(to: NSPoint(x: x, y: drawnRect.maxY))
        }
        for row in 1..<max(1, imageHeight) {
            let y = drawnRect.minY + CGFloat(row) * cell
            path.move(to: NSPoint(x: drawnRect.minX, y: y))
            path.line(to: NSPoint(x: drawnRect.maxX, y: y))
        }
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.12).set()
        path.stroke()
    }

    private func drawCenterPixel(sample: MagnifierSample, cell: CGFloat, drawnRect: CGRect) {
        guard let center = sample.centerIndex else { return }
        let rect = CGRect(
            x: drawnRect.minX + CGFloat(center.x) * cell,
            y: drawnRect.minY + CGFloat((sample.image.height - 1) - center.y) * cell,
            width: cell,
            height: cell
        )
        let path = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        JadeColor.primaryNS.set()
        path.stroke()
    }

    private func drawMask(sample: MagnifierSample, drawnRect: CGRect, clip: CGRect) {
        guard let maskRect = maskRectInPixels, !maskRect.isNull, !maskRect.isEmpty else { return }
        let relative = CGRect(
            x: maskRect.minX - sample.sourceRect.minX,
            y: maskRect.minY - sample.sourceRect.minY,
            width: maskRect.width,
            height: maskRect.height
        )
        // 像素坐标（左上原点）→ 视图坐标（左下原点）。
        let inView = CGRect(
            x: drawnRect.minX + relative.minX * (drawnRect.width / CGFloat(sample.image.width)),
            y: drawnRect.minY + (CGFloat(sample.image.height) - relative.maxY) * (drawnRect.height / CGFloat(sample.image.height)),
            width: relative.width * (drawnRect.width / CGFloat(sample.image.width)),
            height: relative.height * (drawnRect.height / CGFloat(sample.image.height))
        )
        // 放大区域与选区**完全没有交集**时整块都在选区之外：此时遮罩没有任何可指示的
        // 边界，只会把放大镜糊成一块看不出内容的暗方块（放大镜的本职是始终清晰显示
        // 光标周围的像素）。因此无交集即不遮罩；有交集时只**描边**边界。
        guard inView.intersects(clip) else { return }

        // 2026-10-19 用户复测：拖拽中/拖拽结束后把光标移到选区里，仍会出现一块暗色
        // 区域 —— 正是这里的半透明黑色填充。放大镜的职责是显示真实像素，边界用一圈
        // 描边就已足够；不要再压暗任何内容。
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        ).addClip()
        let boundary = NSBezierPath(rect: inView)
        boundary.lineWidth = 2
        NSColor.black.withAlphaComponent(0.55).setStroke()
        boundary.stroke()
        boundary.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        boundary.stroke()
        context.restoreGState()
    }

    private func drawLabels(sample: MagnifierSample, content: CGRect) {
        if configuration.options.contains(.coordinate), let center = sample.centerIndex {
            let text = "\(Int(sample.sourceRect.minX) + center.x), \(Int(sample.sourceRect.minY) + center.y)"
            drawBadge(text: text, alignRight: false, content: content)
        }
        if configuration.options.contains(.zoomLabel) {
            drawBadge(text: "\(configuration.zoom)×", alignRight: true, content: content)
        }
    }

    private func drawBadge(text: String, alignRight: Bool, content: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Metrics.labelFontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeSize = CGSize(
            width: textSize.width + Metrics.labelPadding * 2,
            height: textSize.height + Metrics.labelPadding
        )
        let x = alignRight ? content.maxX - badgeSize.width : content.minX
        let y = content.minY
        let badgeRect = CGRect(origin: CGPoint(x: x, y: y), size: badgeSize)

        let background = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.65).set()
        background.fill()

        text.draw(
            at: NSPoint(x: badgeRect.minX + Metrics.labelPadding, y: badgeRect.minY + Metrics.labelPadding / 2),
            withAttributes: attributes
        )
    }
}
