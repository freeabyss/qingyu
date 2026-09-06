import AppKit

// MARK: - Screenshot shortcut hints (Task 006)

/// 按会话阶段生成的左下角快捷键提示（本地化）。
enum ScreenshotShortcutHints {
    /// 窗口选择阶段。
    static let windowSelectionKeys = [
        "screenshot.hint.clickWindow",
        "screenshot.hint.dragRegion",
        "screenshot.hint.fullDisplay",
        "screenshot.hint.cancel"
    ]
    /// 区域拖拽阶段。
    static let regionDraggingKeys = [
        "screenshot.hint.releaseRegion",
        "screenshot.hint.cancel"
    ]
    /// 选区/目标锁定阶段。
    static let lockedKeys = [
        "screenshot.hint.enterCopy",
        "screenshot.hint.save",
        "screenshot.hint.toolbar",
        "screenshot.hint.cancel"
    ]
    /// 标注阶段（Task 007 消费）。
    static let annotationKeys = [
        "screenshot.hint.undo",
        "screenshot.hint.clear",
        "screenshot.hint.enterCopy",
        "screenshot.hint.cancel"
    ]

    static func hints(for phase: CaptureSessionPhase) -> [String] {
        switch phase {
        case .targetingWindow:
            return windowSelectionKeys.map { L10n.localized($0) }
        case .draggingRegion:
            return regionDraggingKeys.map { L10n.localized($0) }
        case .locked:
            return lockedKeys.map { L10n.localized($0) }
        case .cancelled:
            return []
        }
    }
}

/// 左下角快捷键提示视图：黑色半透明胶囊里横排若干「按键 操作」提示。
/// 固定锚在当前显示器 visible frame 左下 16pt 边距内；
/// 无障碍标识 `screenshot.shortcutHints` 供 UI 测试断言。
final class ScreenshotShortcutHintsView: NSView {
    static let accessibilityIdentifierValue = "screenshot.shortcutHints"
    static let edgeInset: CGFloat = 16

    private var hintKeys: [String] = []

    init(hintKeys: [String] = ScreenshotShortcutHints.windowSelectionKeys) {
        self.hintKeys = hintKeys
        super.init(frame: .zero)
        self.setAccessibilityIdentifier(Self.accessibilityIdentifierValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(hintKeys: [String]) {
        self.hintKeys = hintKeys
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let hints = hintKeys.map { L10n.localized($0) }
        guard !hints.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let keyGap: CGFloat = 18
        let padding: CGFloat = 10

        var pillFrames: [NSRect] = []
        var cursorX: CGFloat = 0
        let pillHeight: CGFloat = 24

        for hint in hints {
            let textSize = hint.size(withAttributes: attributes)
            let pillWidth = textSize.width + padding * 2
            let pillRect = NSRect(x: cursorX, y: 0, width: pillWidth, height: pillHeight)
            pillFrames.append(pillRect)
            cursorX += pillWidth + keyGap
        }

        let totalSize = NSSize(width: max(0, cursorX - keyGap), height: pillHeight)
        let originX = (bounds.width - totalSize.width) / 2
        let originY = (bounds.height - totalSize.height) / 2

        for (hint, pillRect) in zip(hints, pillFrames) {
            let frame = NSRect(
                x: pillRect.minX + originX,
                y: pillRect.minY + originY,
                width: pillRect.width,
                height: pillRect.height
            )
            let pill = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
            NSColor.black.withAlphaComponent(0.7).set()
            pill.fill()

            let textSize = hint.size(withAttributes: attributes)
            let textRect = NSRect(
                x: frame.midX - textSize.width / 2,
                y: frame.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            hint.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// 在显示器可见区域左下角（16pt 边距）计算提示视图的推荐 frame。
    static func frame(in display: CaptureDisplay, hintCount: Int) -> NSRect {
        guard hintCount > 0 else { return .zero }
        let insets: NSEdgeInsets = {
            if let screen = NSScreen.screens.first(where: { $0.frame == display.frame }) {
                let visible = screen.visibleFrame
                return NSEdgeInsets(
                    top: visible.maxY - display.frame.maxY,
                    left: visible.minX - display.frame.minX,
                    bottom: display.frame.minY - visible.minY,
                    right: display.frame.maxX - visible.maxX
                )
            }
            return NSEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)
        }()
        let estimatedWidth: CGFloat = 620
        let height: CGFloat = 24
        return NSRect(
            x: display.frame.minX + insets.left + Self.edgeInset,
            y: display.frame.minY + insets.bottom + Self.edgeInset,
            width: min(estimatedWidth, display.frame.width - insets.left - insets.right - Self.edgeInset * 2),
            height: height
        )
    }
}
