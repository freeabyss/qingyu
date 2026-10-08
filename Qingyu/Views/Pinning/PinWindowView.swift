import AppKit
import SwiftUI

// MARK: - Pin window view (Task 008)

/// 贴图内容视图：按载荷类型渲染，并应用缩放/不透明度/旋转/翻转。
struct PinWindowView: View {
    let item: PinItem

    var body: some View {
        content
            .scaleEffect(
                x: (item.transform.flippedHorizontally ? -1 : 1) * item.transform.scale,
                y: (item.transform.flippedVertically ? -1 : 1) * item.transform.scale
            )
            .opacity(Double(item.transform.opacity))
            .rotationEffect(.degrees(Double(item.transform.quarterTurns) * 90))
    }

    @ViewBuilder
    private var content: some View {
        switch item.payload {
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .color(let red, let green, let blue):
            Rectangle()
                .fill(Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255))
                .overlay(alignment: .bottom) {
                    Text(ColorString.hex(red: red, green: green, blue: blue))
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
        case .attributedText(let attributed):
            Text(AttributedString(attributed))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .text(let text):
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Key mapping (UI 规范「贴图」键位表)

/// 贴图键盘动作；由 `PinEventContainerView.keyAction` 从按键事件映射。
enum PinKeyAction: Equatable {
    case rotateClockwise        // `1` 顺时针旋转 90°
    case rotateCounterClockwise // `2` 逆时针旋转 90°
    case flipHorizontally       // `3` 水平翻转
    case flipVertically         // `4` 垂直翻转
    case zoomIn                 // `+`/`=` 放大
    case zoomOut                // `-` 缩小
    case opacityUp              // `⌘+`/`⌘=` 提高不透明度
    case opacityDown            // `⌘-` 降低不透明度
    case close                  // `Esc` / `⌘W` 关闭并进入恢复队列
    case destroy                // `⇧Esc` 销毁
    case replaceFromPasteboard  // `⌘V` 替换载荷
    case copyPlainText          // `⇧⌘C` 复制纯文本
    case openSettings           // `⇧⌘P` 打开截图与贴图设置
}

// MARK: - Event container

/// 承载贴图 SwiftUI 内容并处理键位表定义的键盘、滚轮与鼠标交互，以及右键上下文菜单。
final class PinEventContainerView: NSView {
    static let zoomStep: CGFloat = 1.1
    static let opacityStep: CGFloat = 0.1

    var onScale: ((CGFloat) -> Void)?                 // 滚轮 / `+/-`
    var onRotate: ((Int) -> Void)?                    // `1`/`2`，传入顺时针四分之一圈数
    var onFlipHorizontally: (() -> Void)?             // `3`
    var onFlipVertically: (() -> Void)?               // `4`
    var onAdjustOpacity: ((CGFloat) -> Void)?         // `⌘`+滚轮 / `⌘+/-`
    var onResetScaleAndOpacity: (() -> Void)?         // 中键：恢复 100% 缩放和不透明度
    var onClose: (() -> Void)?                        // `Esc` / `⌘W` / 左键双击
    var onDestroy: (() -> Void)?                      // `⇧Esc`
    var onCopyPlainText: (() -> Void)?                // `⇧⌘C`
    var onOpenSettings: (() -> Void)?                 // `⇧⌘P`
    var onReplaceFromPasteboard: (() -> Void)?        // `⌘V`

    private(set) var item: PinItem
    private let hostingView: NSHostingView<PinWindowView>

    init(item: PinItem, size: NSSize) {
        self.item = item
        hostingView = NSHostingView(rootView: PinWindowView(item: item))
        super.init(frame: NSRect(origin: .zero, size: size))
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(item: PinItem) {
        self.item = item
        hostingView.rootView = PinWindowView(item: item)
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    // MARK: Key mapping

    /// 按键 → 键位表动作（纯函数，便于单测）。
    /// `character` 取事件的 `charactersIgnoringModifiers`（⇧⌘C 场景返回大写 `C`，此处统一小写比较）。
    static func keyAction(forCharacter character: String, modifiers: NSEvent.ModifierFlags) -> PinKeyAction? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = character.lowercased()

        if command {
            switch key {
            case "w":
                return .close                             // ⌘W
            case "v" where !shift:
                return .replaceFromPasteboard             // ⌘V
            case "c" where shift:
                return .copyPlainText                     // ⇧⌘C
            case "p" where shift:
                return .openSettings                      // ⇧⌘P
            case "+", "=":
                return .opacityUp                         // ⌘+ / ⌘=
            case "-":
                return .opacityDown                       // ⌘-
            default:
                return nil
            }
        }

        switch key {
        case "1": return .rotateClockwise                 // 1
        case "2": return .rotateCounterClockwise          // 2
        case "3": return .flipHorizontally                // 3
        case "4": return .flipVertically                  // 4
        case "+", "=": return .zoomIn                     // + / =
        case "-": return .zoomOut                         // -
        case "\u{1B}": return shift ? .destroy : .close   // ⇧Esc / Esc
        default: return nil
        }
    }

    private func perform(_ action: PinKeyAction) {
        switch action {
        case .rotateClockwise: onRotate?(1)
        case .rotateCounterClockwise: onRotate?(-1)
        case .flipHorizontally: onFlipHorizontally?()
        case .flipVertically: onFlipVertically?()
        case .zoomIn: onScale?(Self.zoomStep)
        case .zoomOut: onScale?(1 / Self.zoomStep)
        case .opacityUp: onAdjustOpacity?(Self.opacityStep)
        case .opacityDown: onAdjustOpacity?(-Self.opacityStep)
        case .close: onClose?()
        case .destroy: onDestroy?()
        case .replaceFromPasteboard: onReplaceFromPasteboard?()
        case .copyPlainText: onCopyPlainText?()
        case .openSettings: onOpenSettings?()
        }
    }

    // MARK: Events

    override func keyDown(with event: NSEvent) {
        _ = handleKeyEvent(event)
    }

    /// `PinNSWindow.performKeyEquivalent` 优先把 ⌘ 组合派发给本方法，避免被主菜单拦截。
    func performKeyEquivalentIfHandled(_ event: NSEvent) -> Bool {
        handleKeyEvent(event)
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let action = Self.keyAction(
            forCharacter: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags
        ) else { return false }
        perform(action)
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else { return }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            onAdjustOpacity?(event.deltaY < 0 ? Self.opacityStep : -Self.opacityStep)
        } else {
            onScale?(event.deltaY < 0 ? Self.zoomStep : 1 / Self.zoomStep)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        onResetScaleAndOpacity?()  // 中键：仅恢复 100% 缩放和不透明度
    }

    override func mouseUp(with event: NSEvent) {
        // 左键双击：关闭并进入恢复队列。⇧+双击（缩略图模式）等其他组合不处理。
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty, event.clickCount == 2 else { return }
        onClose?()
    }

    // MARK: Context menu（右键）

    override func menu(for event: NSEvent) -> NSMenu? {
        buildContextMenu()
    }

    /// 上下文菜单：关闭（⌘W）、销毁（⇧Esc）、复制纯文本（⇧⌘C，仅文本/HTML）、打开截图与贴图设置（⇧⌘P）。
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let close = NSMenuItem(
            title: L10n.localized("pin.menu.close"),
            action: #selector(menuClose),
            keyEquivalent: "w"
        )
        close.keyEquivalentModifierMask = [.command]
        close.target = self

        let destroy = NSMenuItem(
            title: L10n.localized("pin.menu.destroy"),
            action: #selector(menuDestroy),
            keyEquivalent: "\u{1B}"
        )
        destroy.keyEquivalentModifierMask = [.shift]
        destroy.target = self

        let copy = NSMenuItem(
            title: L10n.localized("pin.menu.copyPlainText"),
            action: #selector(menuCopyPlainText),
            keyEquivalent: "c"
        )
        copy.keyEquivalentModifierMask = [.command, .shift]
        copy.target = self
        copy.isEnabled = supportsPlainText

        let openSettings = NSMenuItem(
            title: L10n.localized("pin.menu.openSettings"),
            action: #selector(menuOpenSettings),
            keyEquivalent: "p"
        )
        openSettings.keyEquivalentModifierMask = [.command, .shift]
        openSettings.target = self

        menu.addItem(close)
        menu.addItem(destroy)
        menu.addItem(.separator())
        menu.addItem(copy)
        menu.addItem(openSettings)
        return menu
    }

    /// 仅文本/HTML 载荷支持复制纯文本。
    var supportsPlainText: Bool {
        switch item.payload {
        case .text, .attributedText: return true
        case .image, .color: return false
        }
    }

    @objc private func menuClose() { onClose?() }
    @objc private func menuDestroy() { onDestroy?() }
    @objc private func menuCopyPlainText() { onCopyPlainText?() }
    @objc private func menuOpenSettings() { onOpenSettings?() }
}
