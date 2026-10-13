import Cocoa
import CoreImage

// MARK: - Annotation Model

/// 截图标注工具集（Task 007 六种 → Task 013 十三种）。
///
/// 工具数多于按钮数：`toolbarGroups` 把「矩形/椭圆」「马赛克/高斯模糊」合并为一个按钮，
/// 重复点击在同一组内循环（对应 Snipaste 的合并按钮语义）。
enum AnnotationTool: String, Codable, CaseIterable, Identifiable {
    case pencil
    case arrow
    case line
    case polyline
    case rectangle
    case ellipse
    case highlighter
    case mosaic
    case gaussianBlur
    case eraser
    case text
    case number
    case tooltip

    var id: String { rawValue }

    /// 工具条分组：一个按钮对应一组工具，重复点击在同一组内循环。
    static let toolbarGroups: [[AnnotationTool]] = [
        [.pencil],
        [.arrow],
        [.line],
        [.polyline],
        [.rectangle, .ellipse],
        [.highlighter],
        [.mosaic, .gaussianBlur],
        [.eraser],
        [.text],
        [.number],
        [.tooltip]
    ]

    /// 组内下一个工具；当前工具不在组内时选组内第一个。
    static func next(in group: [AnnotationTool], after tool: AnnotationTool) -> AnnotationTool {
        guard let index = group.firstIndex(of: tool), group.count > 1 else {
            return group.first ?? tool
        }
        return group[(index + 1) % group.count]
    }

    /// 自由手绘：拖拽过程累积采样点，落笔时做平滑。
    var isFreehand: Bool { self == .pencil || self == .highlighter }

    /// 点击即完成的工具（不依赖拖拽距离）。
    var isClickPlaced: Bool {
        switch self {
        case .text, .number, .tooltip, .eraser: return true
        default: return false
        }
    }

    var displayName: String {
        L10n.localized("annotation.tool.\(rawValue)")
    }

    var systemImage: String {
        switch self {
        case .pencil: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .polyline: return "point.topleft.down.curvedto.point.bottomright.up"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .highlighter: return "highlighter"
        case .mosaic: return "square.grid.3x3.square"
        case .gaussianBlur: return "drop.fill"
        case .eraser: return "eraser"
        case .text: return "textformat"
        case .number: return "number.circle"
        case .tooltip: return "bubble.left"
        }
    }
}

enum AnnotationColor: String, Codable, CaseIterable, Identifiable {
    case red, yellow, blue, green, white, black

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .white: return .white
        case .black: return .black
        }
    }

    var displayName: String {
        switch self {
        case .red: return L10n.localized("annotation.color.red")
        case .yellow: return L10n.localized("annotation.color.yellow")
        case .blue: return L10n.localized("annotation.color.blue")
        case .green: return L10n.localized("annotation.color.green")
        case .white: return L10n.localized("annotation.color.white")
        case .black: return L10n.localized("annotation.color.black")
        }
    }
}

enum AnnotationLineWidth: String, Codable, CaseIterable, Identifiable {
    case thin, medium, thick

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 4
        case .thick: return 8
        }
    }

    var displayName: String {
        switch self {
        case .thin: return L10n.localized("annotation.lineWidth.thin")
        case .medium: return L10n.localized("annotation.lineWidth.medium")
        case .thick: return L10n.localized("annotation.lineWidth.thick")
        }
    }
}

enum AnnotationTextSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 28
        case .large: return 42
        }
    }

    var displayName: String {
        switch self {
        case .small: return L10n.localized("annotation.textSize.small")
        case .medium: return L10n.localized("annotation.textSize.medium")
        case .large: return L10n.localized("annotation.textSize.large")
        }
    }
}

struct AnnotationStyle: Hashable, Codable {
    var color: AnnotationColor = .red
    var lineWidth: AnnotationLineWidth = .medium
    var textSize: AnnotationTextSize = .medium
}

struct AnnotationShape: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint?
    /// Task 007: polyline vertex list（≥2 个点构成折线）。
    var points: [CGPoint] = []
    /// Task 007: 文字等形状的旋转角（弧度，绕 startPoint）。
    var rotationRadians: CGFloat = 0
    var text: String?
    var style: AnnotationStyle

    var rect: CGRect {
        if !points.isEmpty {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            ).standardized
        }
        let end = endPoint ?? startPoint
        return CGRect(
            x: min(startPoint.x, end.x),
            y: min(startPoint.y, end.y),
            width: abs(startPoint.x - end.x),
            height: abs(startPoint.y - end.y)
        ).standardized
    }

    /// `⇧` 复位：撤销已应用的旋转（角度归零，不改变位置）。
    mutating func resetRotation() {
        rotationRadians = 0
    }

    /// 序号徽标半径（由文字大小派生）；序号以 `startPoint` 为圆心。
    var numberBadgeRadius: CGFloat {
        style.textSize.points * 0.75
    }
}

// MARK: - Rendering

enum AnnotationRenderer {
    private static let arrowHeadLength: CGFloat = 18
    private static let arrowHeadAngle: CGFloat = .pi / 6
    private static let mosaicScale: CGFloat = 10

    static func draw(_ shapes: [AnnotationShape], sourceImage: NSImage?) {
        for shape in shapes {
            switch shape.tool {
            case .pencil:
                drawFreehand(shape, isHighlighter: false)
            case .arrow:
                drawArrow(shape)
            case .line:
                drawLine(shape)
            case .polyline:
                drawPolyline(shape)
            case .rectangle:
                drawRectangle(shape)
            case .ellipse:
                drawEllipse(shape)
            case .highlighter:
                drawFreehand(shape, isHighlighter: true)
            case .mosaic:
                drawMosaic(shape, sourceImage: sourceImage, style: .pixellate)
            case .gaussianBlur:
                drawMosaic(shape, sourceImage: sourceImage, style: .gaussianBlur)
            case .eraser:
                break  // 橡皮擦不产生图形，只删除
            case .text:
                drawText(shape)
            case .number:
                drawNumber(shape)
            case .tooltip:
                drawTooltip(shape)
            }
        }
    }

    private static func drawRectangle(_ shape: AnnotationShape) {
        let path = NSBezierPath(rect: shape.rect)
        path.lineWidth = shape.style.lineWidth.points
        shape.style.color.nsColor.setStroke()
        path.stroke()
    }

    /// 椭圆：复用矩形的拖拽范围（Task 013 与矩形合并为一个按钮，形状由当前工具决定）。
    private static func drawEllipse(_ shape: AnnotationShape) {
        let path = NSBezierPath(ovalIn: shape.rect)
        path.lineWidth = shape.style.lineWidth.points
        shape.style.color.nsColor.setStroke()
        path.stroke()
    }

    /// 铅笔与荧光笔共用一条自由手绘路径。
    ///
    /// - 铅笔：不透明、按所选笔宽。
    /// - 荧光笔：半透明、约 3 倍笔宽，覆盖内容仍可辨识。
    private static func drawFreehand(_ shape: AnnotationShape, isHighlighter: Bool) {
        guard shape.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = isHighlighter ? shape.style.lineWidth.points * 3 : shape.style.lineWidth.points
        path.lineCapStyle = isHighlighter ? .square : .round
        path.lineJoinStyle = .round
        let color = shape.style.color.nsColor
        (isHighlighter ? color.withAlphaComponent(0.35) : color).setStroke()
        path.move(to: shape.points[0])
        for point in shape.points.dropFirst() {
            path.line(to: point)
        }
        path.stroke()
    }

    /// 序号徽标：实心圆 + 居中数字。
    private static func drawNumber(_ shape: AnnotationShape) {
        guard let text = shape.text, let value = Int(text) else { return }
        let radius = shape.numberBadgeRadius
        let center = shape.startPoint
        let circle = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        shape.style.color.nsColor.setFill()
        NSBezierPath(ovalIn: circle).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius * 1.1, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let value_ = "\(value)" as NSString
        let size = value_.size(withAttributes: attributes)
        value_.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
    }

    /// 提示框：多行文字气泡 + 指向 `startPoint` 的小三角。
    private static func drawTooltip(_ shape: AnnotationShape) {
        guard let text = shape.text, !text.isEmpty else { return }
        let bodyFont = NSFont.systemFont(ofSize: shape.style.textSize.points, weight: .medium)
        let padding: CGFloat = 10
        // 气泡几何与命中测试共用同一份推导，避免「看得见却点不中」。
        let body = AnnotationHitTest.tooltipBody(for: shape)

        let fill = shape.style.color.nsColor
        fill.setFill()
        NSBezierPath(roundedRect: body, xRadius: 8, yRadius: 8).fill()

        // 指向锚点的等腰三角。
        let tailPath = NSBezierPath()
        tailPath.move(to: shape.startPoint)
        tailPath.line(to: CGPoint(x: body.minX + 14, y: body.minY))
        tailPath.line(to: CGPoint(x: body.minX + 24, y: body.minY))
        tailPath.close()
        tailPath.fill()

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.white
        ]
        (text as NSString).draw(
            with: body.insetBy(dx: padding, dy: padding),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes
        )
    }

    private static func drawArrow(_ shape: AnnotationShape) {
        guard let end = shape.endPoint else { return }
        let start = shape.startPoint
        let color = shape.style.color.nsColor
        let width = shape.style.lineWidth.points
        color.setStroke()
        color.setFill()

        let shaft = NSBezierPath()
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.move(to: start)
        shaft.line(to: end)
        shaft.stroke()

        let dx = start.x - end.x
        let dy = start.y - end.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let ux = dx / length
        let uy = dy / length
        let cosA = cos(arrowHeadAngle)
        let sinA = sin(arrowHeadAngle)
        let head = arrowHeadLength + width
        let left = CGPoint(x: end.x + head * (ux * cosA - uy * sinA), y: end.y + head * (ux * sinA + uy * cosA))
        let right = CGPoint(x: end.x + head * (ux * cosA + uy * sinA), y: end.y + head * (-ux * sinA + uy * cosA))

        let headPath = NSBezierPath()
        headPath.move(to: end)
        headPath.line(to: left)
        headPath.line(to: right)
        headPath.close()
        headPath.fill()
    }

    private static func drawLine(_ shape: AnnotationShape) {
        guard let end = shape.endPoint else { return }
        let path = NSBezierPath()
        path.lineWidth = shape.style.lineWidth.points
        path.lineCapStyle = .round
        shape.style.color.nsColor.setStroke()
        path.move(to: shape.startPoint)
        path.line(to: end)
        path.stroke()
    }

    private static func drawPolyline(_ shape: AnnotationShape) {
        guard shape.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = shape.style.lineWidth.points
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        shape.style.color.nsColor.setStroke()
        path.move(to: shape.points[0])
        for point in shape.points.dropFirst() {
            path.line(to: point)
        }
        path.stroke()
    }

    private static func drawText(_ shape: AnnotationShape) {
        guard let text = shape.text, !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: shape.style.textSize.points, weight: .semibold),
            .foregroundColor: shape.style.color.nsColor,
            .strokeColor: NSColor.black.withAlphaComponent(shape.style.color == .black ? 0 : 0.35),
            .strokeWidth: -2.0
        ]
        guard shape.rotationRadians != 0 else {
            NSAttributedString(string: text, attributes: attributes).draw(at: shape.startPoint)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: shape.startPoint.x, y: shape.startPoint.y)
        context.rotate(by: shape.rotationRadians)
        NSAttributedString(string: text, attributes: attributes).draw(at: .zero)
        context.restoreGState()
    }

    /// 马赛克与高斯模糊共用的底图取样。
    ///
    /// 两者都从**原始截图**取样（不含已画上的标注），因此同一区域先画标注再打码时，
    /// 被码掉的是原图内容而不是标注 —— 与 Snipaste 行为一致。
    enum BlurStyle {
        case pixellate
        case gaussianBlur
    }

    private static func drawMosaic(_ shape: AnnotationShape, sourceImage: NSImage?, style: BlurStyle) {
        let target = shape.rect
        guard target.width > 1, target.height > 1 else { return }
        guard let image = sourceImage else {
            NSColor.gray.withAlphaComponent(0.65).setFill()
            target.fill()
            return
        }
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            NSColor.gray.withAlphaComponent(0.65).setFill()
            target.fill()
            return
        }

        let input = CIImage(cgImage: cgImage)
        let output: CIImage?
        switch style {
        case .pixellate:
            let filter = CIFilter(name: "CIPixellate")
            filter?.setValue(input, forKey: kCIInputImageKey)
            // 马赛克块大小与模糊半径都由笔宽派生，保证两种模式覆盖范围一致。
            filter?.setValue(mosaicScale + shape.style.lineWidth.points, forKey: kCIInputScaleKey)
            filter?.setValue(CIVector(x: target.midX, y: target.midY), forKey: kCIInputCenterKey)
            output = filter?.outputImage
        case .gaussianBlur:
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(input, forKey: kCIInputImageKey)
            filter?.setValue(shape.style.lineWidth.points * 2, forKey: kCIInputRadiusKey)
            output = filter?.outputImage
        }
        guard let output else { return }
        let context = CIContext(options: nil)
        guard let cgOutput = context.createCGImage(output, from: target),
              let graphics = NSGraphicsContext.current?.cgContext else { return }
        graphics.saveGState()
        graphics.draw(cgOutput, in: target)
        graphics.restoreGState()
    }
}

enum AnnotationFlattener {
    static func flatten(image: NSImage, shapes: [AnnotationShape]) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
        AnnotationRenderer.draw(shapes, sourceImage: image)
        output.unlockFocus()
        return output
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
