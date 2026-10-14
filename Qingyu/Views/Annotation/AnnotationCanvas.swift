import Cocoa
import SwiftUI

@MainActor
final class AnnotationCanvasState: ObservableObject {

    /// 一次可撤销的编辑。加入删除后不能再只靠 `shapes.popLast()` 回退，
    /// 因此统一成显式历史（同时让「撤销删除」与「撤销新增」语义一致）。
    enum Edit: Equatable {
        case add(AnnotationShape)
        case remove(index: Int, shape: AnnotationShape)
    }

    let sourceImage: NSImage
    let imageSize: CGSize

    @Published var shapes: [AnnotationShape] = []
    @Published var draftShape: AnnotationShape?
    @Published var tool: AnnotationTool = .rectangle
    @Published var style = AnnotationStyle()
    /// Task 013：悬停命中的标注（用于高亮与橡皮擦提示）。
    @Published var hoveredShapeID: AnnotationShape.ID?
    /// Task 014/04：指针最后一次落在图像上的位置（图像点坐标）。
    ///
    /// 取色快捷键由 SwiftUI 的隐藏按钮触发（任何焦点下都可用），因此需要状态
    /// 记住指针位置，而不是从画布的键盘事件里取。
    @Published var lastHoveredImagePoint: CGPoint?

    /// Task 013：序号工具的计数器，从 1 开始；清空或新建会话时重置。
    @Published private(set) var nextNumber: Int = 1

    private var history: [Edit] = []
    private var future: [Edit] = []

    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(image: NSImage) {
        self.sourceImage = image
        self.imageSize = image.size
    }

    // MARK: - Editing

    func append(_ shape: AnnotationShape) {
        shapes.append(shape)
        history.append(.add(shape))
        future.removeAll()
        objectWillChange.send()
    }

    /// 橡皮擦：删除命中的**整条**标注（不做像素级擦除）；可撤销。
    @discardableResult
    func erase(shapeID: AnnotationShape.ID) -> Bool {
        guard let index = shapes.firstIndex(where: { $0.id == shapeID }) else { return false }
        let shape = shapes.remove(at: index)
        history.append(.remove(index: index, shape: shape))
        future.removeAll()
        objectWillChange.send()
        return true
    }

    /// 分配下一个序号（从 1 递增）。
    func allocateNumber() -> Int {
        defer { nextNumber += 1 }
        return nextNumber
    }

    func undo() {
        guard let edit = history.popLast() else { return }
        apply(edit, reverse: true)
        future.append(edit)
        objectWillChange.send()
    }

    func redo() {
        guard let edit = future.popLast() else { return }
        apply(edit, reverse: false)
        history.append(edit)
        objectWillChange.send()
    }

    /// 清空全部标注；清空同时清掉历史（清空后不可重做），并重置序号。
    func clearAll() {
        guard !shapes.isEmpty || !history.isEmpty || !future.isEmpty else { return }
        shapes.removeAll()
        history.removeAll()
        future.removeAll()
        draftShape = nil
        hoveredShapeID = nil
        nextNumber = 1
        objectWillChange.send()
    }

    // MARK: - Color sampling (Task 014/04)

    /// 源图的**像素**尺寸（Retina 截图为点尺寸的 2 倍）。
    var sourcePixelSize: CGSize {
        if let rep = sourceImage.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return imageSize
    }

    /// 把画布上的图像点（点坐标，**左下**原点）换算成源图**像素**坐标（**左上**原点）。
    ///
    /// 标注画布不是 flipped 视图，因此 y 需要翻转 —— 否则取色会取到上下镜像的像素。
    /// 越界返回 nil，由调用方按「不响应」处理。
    func sourcePixel(atImagePoint point: CGPoint) -> CGPoint? {
        let pixels = sourcePixelSize
        guard pixels.width > 0, pixels.height > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scaleX = pixels.width / imageSize.width
        let scaleY = pixels.height / imageSize.height

        let x = Int((point.x * scaleX).rounded(.down))
        let y = Int(((imageSize.height - point.y) * scaleY).rounded(.down))
        guard x >= 0, y >= 0, x < Int(pixels.width), y < Int(pixels.height) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// 采样该图像点处的源图像素；越界或取不到位图时返回 nil。
    func sampledColor(atImagePoint point: CGPoint) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let pixel = sourcePixel(atImagePoint: point),
              let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return ColorSampler.samplePixel(at: pixel, in: cgImage)
    }

    func renderedPNGData() throws -> Data {
        let flattened = AnnotationFlattener.flatten(image: sourceImage, shapes: shapes)
        guard let png = AnnotationFlattener.pngData(from: flattened) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.pngConversionFailed"))
        }
        return png
    }

    // MARK: - Private

    private func apply(_ edit: Edit, reverse: Bool) {
        switch (edit, reverse) {
        case (.add(let shape), true):
            shapes.removeAll { $0.id == shape.id }
        case (.add(let shape), false):
            shapes.append(shape)
        case (.remove(let index, let shape), true):
            // 原位置若已被后续编辑改变，钳制到合法范围后插回。
            shapes.insert(shape, at: min(max(index, 0), shapes.count))
        case (.remove(_, let shape), false):
            shapes.removeAll { $0.id == shape.id }
        }
    }
}

final class AnnotationCanvasNSView: NSView {
    /// 命中容差（bps）：细线也要点得中，橡皮擦与悬停共用。
    private static let hitTolerance: CGFloat = 3

    weak var state: AnnotationCanvasState?
    var onRequestTextInput: ((CGPoint, @escaping (String?) -> Void) -> Void)?

    private var dragStart: CGPoint?
    private var freehandPoints: [CGPoint] = []
    private var drawnImageRect: CGRect = .zero
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let state else { return }
        let image = state.sourceImage
        let imageSize = state.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        drawnImageRect = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)

        NSColor.black.setFill()
        bounds.fill()
        image.draw(in: drawnImageRect, from: .zero, operation: .copy, fraction: 1)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: drawnImageRect.minX, y: drawnImageRect.minY)
        context.scaleBy(x: scale, y: scale)
        AnnotationRenderer.draw(state.shapes, sourceImage: image)
        if let draft = state.draftShape {
            AnnotationRenderer.draw([draft], sourceImage: image)
        }
        if let hoveredID = state.hoveredShapeID,
           let shape = state.shapes.first(where: { $0.id == hoveredID }) {
            drawHoverHighlight(for: shape)
        }
        context.restoreGState()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Task 013/014/02：标注模式下用 `[` `]` 与滚轮调笔宽。
        // 数字键留给 SwiftUI 的工具条分组快捷键，这里不占用。
        guard state != nil, !event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch characters {
        case "[":
            applyLineWidthStep(direction: -1)
        case "]":
            applyLineWidthStep(direction: 1)
        default:
            super.keyDown(with: event)
        }
    }

    /// 记录指针在图像上的位置（取色用）；移出图像时清空。
    private func recordHoveredImagePoint(_ point: CGPoint?) {
        guard let state, state.lastHoveredImagePoint != point else { return }
        state.lastHoveredImagePoint = point
    }

    override func scrollWheel(with event: NSEvent) {
        guard state != nil, !event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        applyLineWidthStep(direction: event.scrollingDeltaY > 0 ? 1 : -1)
    }

    private func applyLineWidthStep(direction: Int) {
        guard let state else { return }
        let next = AnnotationLineWidthStepper.step(state.style.lineWidth, direction: direction)
        guard next != state.style.lineWidth else { return }
        state.style.lineWidth = next
        needsDisplay = true
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let state, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        recordHoveredImagePoint(point)

        // 橡皮擦：整条删除，可撤销。
        if state.tool == .eraser {
            dragStart = nil
            if let hit = AnnotationHitTest.hit(point: point, shapes: state.shapes, tolerance: Self.hitTolerance) {
                state.erase(shapeID: hit)
                state.hoveredShapeID = nil
                needsDisplay = true
            }
            return
        }

        // 点击落点即完成的工具：序号、文字、提示框。
        if state.tool.isClickPlaced {
            dragStart = nil
            let capturedTool = state.tool
            let capturedStyle = state.style
            if capturedTool == .number {
                let value = state.allocateNumber()
                var shape = AnnotationShape(
                    tool: .number,
                    startPoint: point,
                    endPoint: nil,
                    text: "\(value)",
                    style: capturedStyle
                )
                shape.text = "\(value)"
                state.append(shape)
                needsDisplay = true
                return
            }
            onRequestTextInput?(point) { [weak self] text in
                guard let self, let state = self.state,
                      let text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                state.append(AnnotationShape(
                    tool: capturedTool,
                    startPoint: point,
                    endPoint: nil,
                    text: text,
                    style: capturedStyle
                ))
                self.needsDisplay = true
            }
            return
        }

        dragStart = point
        if state.tool.isFreehand {
            freehandPoints = [point]
            state.draftShape = freehandDraft(origin: point, style: state.style, tool: state.tool)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, let start = dragStart,
              let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        if state.tool.isFreehand {
            freehandPoints.append(point)
            state.draftShape = freehandDraft(origin: freehandPoints[0], style: state.style, tool: state.tool)
        } else {
            state.draftShape = makeShape(tool: state.tool, start: start, end: point, style: state.style)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let state, let start = dragStart else {
            dragStart = nil
            freehandPoints = []
            return
        }
        let point = imagePoint(from: convert(event.locationInWindow, from: nil))
        defer {
            dragStart = nil
            freehandPoints = []
            state.draftShape = nil
            needsDisplay = true
        }
        guard let point else { return }

        if state.tool.isFreehand {
            // 落笔时平滑 + 抽稀，避免折角与毛刺。
            let smoothed = StrokeSmoother.finish(points: freehandPoints + [point])
            guard smoothed.count >= 2 else { return }
            var shape = AnnotationShape(
                tool: state.tool,
                startPoint: smoothed[0],
                endPoint: nil,
                text: nil,
                style: state.style
            )
            shape.points = smoothed
            state.append(shape)
            return
        }

        let dx = point.x - start.x
        let dy = point.y - start.y
        guard (dx * dx + dy * dy) >= 9 else { return }
        state.append(makeShape(tool: state.tool, start: start, end: point, style: state.style))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let state else { return }
        let point = imagePoint(from: convert(event.locationInWindow, from: nil))
        recordHoveredImagePoint(point)
        let hovered = point.flatMap {
            AnnotationHitTest.hit(point: $0, shapes: state.shapes, tolerance: Self.hitTolerance)
        }
        guard hovered != state.hoveredShapeID else { return }
        state.hoveredShapeID = hovered
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard let state, state.hoveredShapeID != nil else { return }
        state.hoveredShapeID = nil
        needsDisplay = true
    }

    // MARK: - Helpers

    private func makeShape(tool: AnnotationTool, start: CGPoint, end: CGPoint, style: AnnotationStyle) -> AnnotationShape {
        AnnotationShape(tool: tool, startPoint: start, endPoint: end, text: nil, style: style)
    }

    private func freehandDraft(origin: CGPoint, style: AnnotationStyle, tool: AnnotationTool) -> AnnotationShape {
        var shape = AnnotationShape(tool: tool, startPoint: origin, endPoint: nil, text: nil, style: style)
        shape.points = freehandPoints
        return shape
    }

    /// 悬停高亮：虚线框提示"这一条会被改到"，不改变图形本身。
    private func drawHoverHighlight(for shape: AnnotationShape) {
        let frame: CGRect
        if shape.tool == .number {
            let radius = shape.numberBadgeRadius
            frame = CGRect(
                x: shape.startPoint.x - radius,
                y: shape.startPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        } else {
            frame = shape.rect.insetBy(dx: -4, dy: -4)
        }
        let path = NSBezierPath(rect: frame)
        path.lineWidth = 1
        let dash: [CGFloat] = [4, 3]
        path.setLineDash(dash, count: dash.count, phase: 0)
        JadeColor.primaryNS.setStroke()
        path.stroke()
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint? {
        guard let state, drawnImageRect.width > 0, drawnImageRect.height > 0, drawnImageRect.contains(viewPoint) else { return nil }
        let scale = drawnImageRect.width / state.imageSize.width
        return CGPoint(
            x: max(0, min(state.imageSize.width, (viewPoint.x - drawnImageRect.minX) / scale)),
            y: max(0, min(state.imageSize.height, (viewPoint.y - drawnImageRect.minY) / scale))
        )
    }
}

struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var state: AnnotationCanvasState
    let onRequestTextInput: (CGPoint, @escaping (String?) -> Void) -> Void

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.state = state
        view.onRequestTextInput = onRequestTextInput
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.state = state
        nsView.onRequestTextInput = onRequestTextInput
        nsView.needsDisplay = true
    }
}
