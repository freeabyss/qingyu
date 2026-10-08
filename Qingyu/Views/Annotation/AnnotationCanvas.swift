import Cocoa
import SwiftUI

@MainActor
final class AnnotationCanvasState: ObservableObject {
    let sourceImage: NSImage
    let imageSize: CGSize

    @Published var shapes: [AnnotationShape] = []
    @Published var draftShape: AnnotationShape?
    @Published var tool: AnnotationTool = .rectangle
    @Published var style = AnnotationStyle()

    private var redoStack: [AnnotationShape] = []

    var canUndo: Bool { !shapes.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: NSImage) {
        self.sourceImage = image
        self.imageSize = image.size
    }

    func append(_ shape: AnnotationShape) {
        shapes.append(shape)
        redoStack.removeAll()
        objectWillChange.send()
    }

    func undo() {
        guard let shape = shapes.popLast() else { return }
        redoStack.append(shape)
        objectWillChange.send()
    }

    func redo() {
        guard let shape = redoStack.popLast() else { return }
        shapes.append(shape)
        objectWillChange.send()
    }

    /// 清空全部标注；清空同时清掉重做栈（清空后不可重做）。
    func clearAll() {
        guard !shapes.isEmpty || !redoStack.isEmpty else { return }
        shapes.removeAll()
        redoStack.removeAll()
        draftShape = nil
        objectWillChange.send()
    }

    func renderedPNGData() throws -> Data {
        let flattened = AnnotationFlattener.flatten(image: sourceImage, shapes: shapes)
        guard let png = AnnotationFlattener.pngData(from: flattened) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.pngConversionFailed"))
        }
        return png
    }
}

final class AnnotationCanvasNSView: NSView {
    weak var state: AnnotationCanvasState?
    var onRequestTextInput: ((CGPoint, @escaping (String?) -> Void) -> Void)?

    private var dragStart: CGPoint?
    private var drawnImageRect: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let state, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        dragStart = point
        if state.tool == .text {
            let capturedStyle = state.style
            onRequestTextInput?(point) { [weak self] text in
                guard let self, let state = self.state, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                state.append(AnnotationShape(tool: .text, startPoint: point, endPoint: nil, text: text, style: capturedStyle))
                self.needsDisplay = true
            }
            dragStart = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, let start = dragStart, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        state.draftShape = makeShape(tool: state.tool, start: start, end: point, style: state.style)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let state, let start = dragStart, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else {
            dragStart = nil
            return
        }
        defer {
            dragStart = nil
            state.draftShape = nil
            needsDisplay = true
        }
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard (dx * dx + dy * dy) >= 9 else { return }
        state.append(makeShape(tool: state.tool, start: start, end: point, style: state.style))
    }

    private func makeShape(tool: AnnotationTool, start: CGPoint, end: CGPoint, style: AnnotationStyle) -> AnnotationShape {
        AnnotationShape(tool: tool, startPoint: start, endPoint: end, text: nil, style: style)
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
