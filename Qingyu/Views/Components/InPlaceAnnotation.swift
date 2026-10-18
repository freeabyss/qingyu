import AppKit
import CoreGraphics

// MARK: - 原地标注（选区上直接编辑）

/// 选区上的**原地标注**会话。
///
/// 与旧的 `AnnotationEditorWindow` 的根本差异：不再新开一个窗口，而是留在**已经压暗的
/// 截图叠层**里，只在选区内绘制与响应鼠标。这样用户点工具之后，选区外的压暗、选区边框、
/// 工具条全部保持原样 —— 变的只有光标形状与选中工具的高亮。
///
/// 坐标约定：形状点一律用**选区局部点**（左下原点），因此绘制时只需平移到选区左上角；
/// 导出时按「选区点 → 图像像素」的比例整体缩放。
@MainActor
final class InPlaceAnnotationSession {
    let state: AnnotationCanvasState
    /// 选区（AppKit 全局坐标，左下原点）。
    let regionGlobalRect: CGRect
    private let displayFrame: CGRect

    private var dragStart: CGPoint?
    private var freehandPoints: [CGPoint] = []

    init(image: NSImage, regionGlobalRect: CGRect, displayFrame: CGRect) {
        // 把图像逻辑尺寸归一成选区尺寸：形状坐标于是天然就是「选区局部点」，
        // 绘制、命中、导出三处不必各自换算一次。
        image.size = regionGlobalRect.size
        self.state = AnnotationCanvasState(image: image)
        self.regionGlobalRect = regionGlobalRect
        self.displayFrame = displayFrame
    }

    /// 选区在本显示器内的局部矩形（叠层视图坐标）。
    var localRect: CGRect {
        regionGlobalRect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    func contains(global point: CGPoint) -> Bool {
        regionGlobalRect.contains(point)
    }

    /// 全局点 → 选区局部点（左下原点），并钳制进选区（拖出选区时图形贴边继续）。
    func localPoint(_ global: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(global.x - regionGlobalRect.minX, 0), regionGlobalRect.width),
            y: min(max(global.y - regionGlobalRect.minY, 0), regionGlobalRect.height)
        )
    }

    var isDragging: Bool { dragStart != nil }

    // MARK: - Mouse

    enum MouseResult: Equatable {
        case ignored
        /// 视图需要重绘。
        case consumed
        /// 文字类工具：调用方负责弹输入框，完成后回调 `appendText`。
        case needsText(CGPoint)
    }

    func mouseDown(at global: CGPoint) -> MouseResult {
        let point = localPoint(global)

        if state.tool == .eraser {
            dragStart = nil
            if let hit = AnnotationHitTest.hit(
                point: point,
                shapes: state.shapes,
                tolerance: AnnotationCanvasNSView.hitTolerance
            ) {
                state.erase(shapeID: hit)
                state.hoveredShapeID = nil
            }
            return .consumed
        }

        if state.tool.isClickPlaced {
            dragStart = nil
            if state.tool == .number {
                appendNumber(at: point)
                return .consumed
            }
            return .needsText(point)
        }

        dragStart = point
        if state.tool.isFreehand {
            freehandPoints = [point]
            state.draftShape = draftShape(at: point)
        }
        return .consumed
    }

    func mouseDragged(to global: CGPoint) -> Bool {
        guard let start = dragStart else { return false }
        let point = localPoint(global)
        if state.tool.isFreehand {
            freehandPoints.append(point)
            state.draftShape = draftShape(at: start)
        } else {
            state.draftShape = AnnotationShape(
                tool: state.tool,
                startPoint: start,
                endPoint: point,
                text: nil,
                style: state.style
            )
        }
        return true
    }

    func mouseUp(at global: CGPoint) -> Bool {
        guard let start = dragStart else { return false }
        defer {
            dragStart = nil
            freehandPoints = []
            state.draftShape = nil
        }
        let point = localPoint(global)

        if state.tool.isFreehand {
            let smoothed = StrokeSmoother.finish(points: freehandPoints + [point])
            guard smoothed.count >= 2 else { return true }
            var shape = AnnotationShape(
                tool: state.tool,
                startPoint: smoothed[0],
                endPoint: nil,
                text: nil,
                style: state.style
            )
            shape.points = smoothed
            state.append(shape)
            return true
        }

        let dx = point.x - start.x
        let dy = point.y - start.y
        guard (dx * dx + dy * dy) >= 9 else { return true }
        state.append(AnnotationShape(
            tool: state.tool,
            startPoint: start,
            endPoint: point,
            text: nil,
            style: state.style
        ))
        return true
    }

    /// 悬停命中（橡皮擦提示）；返回是否需要重绘。
    func mouseMoved(to global: CGPoint) -> Bool {
        guard contains(global: global) else {
            guard state.hoveredShapeID != nil else { return false }
            state.hoveredShapeID = nil
            return true
        }
        let hit = AnnotationHitTest.hit(
            point: localPoint(global),
            shapes: state.shapes,
            tolerance: AnnotationCanvasNSView.hitTolerance
        )
        guard hit != state.hoveredShapeID else { return false }
        state.hoveredShapeID = hit
        return true
    }

    func appendText(at point: CGPoint, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.append(AnnotationShape(
            tool: state.tool,
            startPoint: point,
            endPoint: nil,
            text: text,
            style: state.style
        ))
    }

    private func appendNumber(at point: CGPoint) {
        let value = state.allocateNumber()
        state.append(AnnotationShape(
            tool: .number,
            startPoint: point,
            endPoint: nil,
            text: "\(value)",
            style: state.style
        ))
    }

    private func draftShape(at origin: CGPoint) -> AnnotationShape {
        var shape = AnnotationShape(
            tool: state.tool,
            startPoint: origin,
            endPoint: nil,
            text: nil,
            style: state.style
        )
        shape.points = freehandPoints
        return shape
    }

    // MARK: - Drawing

    /// 在叠层上绘制选区内的标注。调用方需已把坐标系平移到选区左下角。
    func draw() {
        AnnotationRenderer.draw(state.shapes, sourceImage: state.sourceImage)
        if let draft = state.draftShape {
            AnnotationRenderer.draw([draft], sourceImage: state.sourceImage)
        }
        if let hoveredID = state.hoveredShapeID,
           let shape = state.shapes.first(where: { $0.id == hoveredID }) {
            let frame = shape.rect.insetBy(dx: -4, dy: -4)
            let path = NSBezierPath(rect: frame)
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            JadeColor.primaryNS.setStroke()
            path.stroke()
        }
    }
}

// MARK: - 工具光标

/// 每个标注工具一个光标：十字准星 + 右下角该工具的小图标。
///
/// 用户预期「光标随选中的工具不同而变化」，系统光标里没有与工具一一对应的可用形状，
/// 因此这里用十字准星托住工具图标自己合成。
@MainActor
enum AnnotationToolCursor {
    private static var cache: [AnnotationTool: NSCursor] = [:]

    static func cursor(for tool: AnnotationTool) -> NSCursor {
        if let cached = cache[tool] { return cached }

        let size = NSSize(width: 36, height: 36)
        let image = NSImage(size: size)
        image.lockFocus()

        // 十字准星：先黑后白双色，深浅背景上都看得见。
        let center = CGPoint(x: 12, y: 24)
        let arm: CGFloat = 9
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: center.x - arm, y: center.y))
        cross.line(to: CGPoint(x: center.x + arm, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - arm))
        cross.line(to: CGPoint(x: center.x, y: center.y + arm))
        cross.lineWidth = 3
        NSColor.black.withAlphaComponent(0.85).setStroke()
        cross.stroke()
        cross.lineWidth = 1
        NSColor.white.setStroke()
        cross.stroke()

        // 工具徽标。
        let badge = CGRect(x: 18, y: 0, width: 18, height: 18)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: badge).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            symbol.draw(in: badge.insetBy(dx: 3.5, dy: 3.5))
        }

        image.unlockFocus()
        // 热点在图像坐标（左上原点）的十字中心。
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: center.x, y: size.height - center.y))
        cache[tool] = cursor
        return cursor
    }
}

// MARK: - 导出

/// 把原地标注合成为最终截图位图。
///
/// 形状坐标是「选区局部点」，因此按 `像素宽 / 选区点宽` 整体缩放后再绘制 ——
/// Retina 屏上截图是点尺寸的 2 倍，不换算会只画到左上四分之一。
enum InPlaceAnnotationFlattener {
    static func flatten(
        result: ScreenshotResult,
        shapes: [AnnotationShape],
        regionSize: CGSize
    ) -> ScreenshotResult {
        guard !shapes.isEmpty,
              regionSize.width > 0, regionSize.height > 0,
              let image = NSImage(data: result.imageData),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: source.width,
                height: source.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return result }

        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let scale = CGFloat(source.width) / regionSize.width
        context.saveGState()
        context.scaleBy(x: scale, y: scale)

        // `AnnotationRenderer` 读取 `NSGraphicsContext.current`，因此必须临时装上位图上下文。
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        AnnotationRenderer.draw(
            shapes,
            sourceImage: NSImage(cgImage: source, size: regionSize),
            sourcePixelScale: scale
        )
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()

        guard let flattened = context.makeImage(), let png = flattened.pngData() else { return result }
        return ScreenshotResult(
            id: result.id,
            imageData: png,
            width: flattened.width,
            height: flattened.height,
            captureDate: result.captureDate,
            sourceType: result.sourceType,
            regionSelection: result.regionSelection
        )
    }
}
