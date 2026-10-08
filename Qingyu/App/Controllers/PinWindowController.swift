import AppKit
import KeyboardShortcuts
import os.log

// MARK: - Pin window layout (PRD 规则 12–15)

/// 贴图窗口尺寸/位置纯函数（PRD「截图与贴图」规则 12–15、UI 规范「贴图」窗口尺寸）。
/// 输入载荷/屏幕可见区/级联序号，输出尺寸与原点，便于单测。
enum PinWindowLayout {
    /// 纯文本/HTML/颜色/文件路径贴图初始尺寸（PRD 规则 13）。
    static let textPinSize = NSSize(width: 420, height: 280)
    /// 所有贴图最小窗口尺寸（PRD 规则 13）。
    static let minimumSize = NSSize(width: 80, height: 60)
    /// 图片贴图宽/高相对当前操作显示器可见区的上限（PRD 规则 12）。
    static let maximumVisibleFraction: CGFloat = 0.4
    /// 连续创建贴图时每张向右下的偏移（PRD 规则 15）。
    static let cascadeOffset: CGFloat = 24

    /// 内容默认窗口尺寸：图片 = 原始点尺寸（超限缩小、小图不放大）；其余 420×280。
    static func defaultSize(forPayload payload: PinPayload, visibleFrame: NSRect) -> NSSize {
        switch payload {
        case .image(let data):
            guard let image = NSImage(data: data) else { return textPinSize }
            return imageSize(forPointSize: image.size, visibleFrame: visibleFrame)
        case .color, .attributedText, .text:
            return textPinSize
        }
    }

    /// 图片贴图尺寸（PRD 规则 12/13）：原始点尺寸为基准；宽或高超过可见区 40% 时等比缩小；
    /// 小图不放大；最小 80×60。
    static func imageSize(forPointSize pointSize: NSSize, visibleFrame: NSRect) -> NSSize {
        let maxWidth = max(visibleFrame.width * maximumVisibleFraction, 0)
        let maxHeight = max(visibleFrame.height * maximumVisibleFraction, 0)
        // 只缩小不放大；宽/高任一超限即等比缩小。
        let shrink = min(1, maxWidth / max(pointSize.width, 1), maxHeight / max(pointSize.height, 1))
        let width = max(minimumSize.width, pointSize.width * shrink)
        let height = max(minimumSize.height, pointSize.height * shrink)
        return NSSize(width: width, height: height)
    }

    /// 剪贴板贴图位置（PRD 规则 15）：可见区中央；`index` 每增加 1 向右下偏移 24pt；
    /// 到达可见区边缘后从中央重新开始（按可用步数取模回卷）。
    static func cascadeOrigin(index: Int, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let centerX = visibleFrame.minX + (visibleFrame.width - size.width) / 2
        let centerY = visibleFrame.minY + (visibleFrame.height - size.height) / 2

        // 右移不越过可见区右缘、下移不越过下缘的可容纳步数。
        let stepsX = ((visibleFrame.maxX - (centerX + size.width)) / cascadeOffset).rounded(.down)
        let stepsY = ((centerY - visibleFrame.minY) / cascadeOffset).rounded(.down)
        let maxSteps = max(0, Int(min(stepsX, stepsY)))

        // 周期 = 可用步数 + 1（中央算一步）；越界序号回卷到中央重新开始。
        let cycle = maxSteps + 1
        let effective = ((index % cycle) + cycle) % cycle
        guard effective > 0 else {
            return NSPoint(x: centerX, y: centerY)
        }
        return NSPoint(
            x: centerX + cascadeOffset * CGFloat(effective),
            y: centerY - cascadeOffset * CGFloat(effective)
        )
    }

    /// 截图贴图原位（PRD 规则 14）：直接沿用选区全局矩形（原位原尺寸，不级联、不居中、
    /// 不受 40% 上限与最小尺寸约束）；选区为空返回 nil，调用方回退默认规则。
    static func screenshotFrame(forSelectionRect selectionRect: NSRect?) -> NSRect? {
        guard let selectionRect else { return nil }
        return NSRect(origin: selectionRect.origin, size: selectionRect.size)
    }
}

// MARK: - Pin window controller

/// 贴图窗口协调器：为 `PinStore` 的每个条目维护一个跨 Space 置顶窗口。
/// 窗口使用 `.floating` + `.canJoinAllSpaces` + `.fullScreenAuxiliary`；
/// 状态不持久化，`destroyAll()` 在应用退出时清空全部运行期贴图。
@MainActor
final class PinWindowController {
    private let logger = Logger.screenshot
    /// internal for tests：单测直接断言 store 状态。
    let store: PinStore
    private let payloadFactory: PinPayloadFactory
    /// `⇧⌘P` / 上下文菜单：打开截图与贴图设置（AppContainer 装配时接入现有设置窗口路由）。
    let onOpenSettings: () -> Void

    private var windows: [UUID: PinNSWindow] = [:]
    /// 同一运行期内连续创建剪贴板贴图的级联序号（PRD 规则 15）。
    private var cascadeIndex = 0

    init(
        store: PinStore,
        payloadFactory: PinPayloadFactory,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.store = store
        self.payloadFactory = payloadFactory
        self.onOpenSettings = onOpenSettings
        attachMouseEventsShortcut()
    }

    var windowCount: Int { windows.count }

    /// 测试辅助：按贴图 id 取窗口。
    func window(for id: UUID) -> NSWindow? {
        windows[id]
    }

    /// 鼠标穿透全局快捷键（设置页可改键；不属于六个核心槽位）。
    /// 1.0.0 FeatureGate：截图/贴图入口整体隐藏，快捷键不注册；
    /// 贴图窗口只能在截图工具条/剪贴板贴图入口恢复后出现。
    private func attachMouseEventsShortcut() {
        guard FeatureGate.screenshotEnabled else { return }
        KeyboardShortcuts.onKeyUp(for: .pinToggleMouseEvents) { [weak self] in
            Task { @MainActor in self?.toggleIgnoresMouseEventsForAll() }
        }
    }

    /// 应用持久化设置（文件路径转图片、恢复队列容量）。
    func applySettings(filePathToImage: Bool, restoreCapacity: Int) {
        payloadFactory.filePathToImage = filePathToImage
        store.setRestoreCapacity(restoreCapacity)
    }

    /// 为全部活跃贴图开关鼠标穿透。
    func toggleIgnoresMouseEventsForAll() {
        let shouldIgnore = !(store.items.first?.ignoresMouseEvents ?? false)
        for item in store.items {
            store.setIgnoresMouseEvents(shouldIgnore, for: item.id)
            if let window = windows[item.id] {
                window.ignoresMouseEvents = shouldIgnore
            }
        }
        logger.info("Pin mouse-events passthrough: \(shouldIgnore)")
    }

    // MARK: - Presenting

    /// 从系统剪贴板创建贴图。
    @discardableResult
    func presentFromPasteboard(_ pasteboard: NSPasteboard = .general) throws -> PinItem {
        let payload = try payloadFactory.makePayload(from: pasteboard)
        return present(payload: payload)
    }

    /// Task 007 `.pinned`：把成功截图转为贴图；成功终局仅结束截图会话，不保留历史。
    @discardableResult
    func present(_ result: ScreenshotResult) -> PinItem {
        let item = store.add(payload: .image(result.imageData))
        // PRD 规则 14：截图贴图沿用原选区原位原尺寸；无选区时回退图片默认规则。
        makeWindow(for: item, preferredFrame: PinWindowLayout.screenshotFrame(forSelectionRect: result.selectionRect))
        logger.info("Screenshot pin presented: \(String(describing: item.payload.kind), privacy: .public)")
        return item
    }

    @discardableResult
    func present(payload: PinPayload) -> PinItem {
        let item = store.add(payload: payload)
        makeWindow(for: item, preferredFrame: nil)
        logger.info("Pin presented: \(String(describing: item.payload.kind), privacy: .public)")
        return item
    }

    // MARK: - Lifecycle

    /// 关闭：进入恢复队列并撤下窗口（可恢复）。
    func close(_ id: UUID) {
        store.close(id)
        windows[id]?.orderOut(nil)
        windows[id] = nil
    }

    /// 恢复最近关闭的贴图并重新呈现窗口。
    @discardableResult
    func restoreLatestClosed() -> PinItem? {
        guard let item = store.restoreLatestClosed() else { return nil }
        makeWindow(for: item, preferredFrame: nil)
        return item
    }

    /// 销毁：移除窗口与全部状态（不可恢复）。
    func destroy(_ id: UUID) {
        windows[id]?.orderOut(nil)
        windows[id] = nil
        store.destroy(id)
    }

    /// 退出应用：销毁全部运行期贴图。
    func destroyAll() {
        for (_, window) in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        store.destroyAll()
        logger.info("All runtime pins destroyed")
    }

    /// 隐藏全部活跃贴图（窗口撤下但保留状态，可 showAll 恢复）。
    func hideAll() {
        store.hideAll()
        for (id, window) in windows where store.item(id: id)?.isHidden == true {
            window.orderOut(nil)
        }
    }

    /// 重新显示全部活跃贴图。
    func showAll() {
        store.showAll()
        for (id, _) in windows {
            store.item(id: id).map { refreshWindow($0) }
        }
    }

    // MARK: - Private

    /// 当前操作显示器可见区：指针所在屏，回退 `NSScreen.main`（PRD 规则 15）。
    static func activeScreenVisibleFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    private func makeWindow(for item: PinItem, preferredFrame: NSRect?) {
        let frame: NSRect
        if let preferredFrame {
            frame = preferredFrame
        } else {
            let visibleFrame = Self.activeScreenVisibleFrame()
            let size = PinWindowLayout.defaultSize(forPayload: item.payload, visibleFrame: visibleFrame)
            let origin = PinWindowLayout.cascadeOrigin(index: cascadeIndex, size: size, visibleFrame: visibleFrame)
            cascadeIndex += 1
            frame = NSRect(origin: origin, size: size)
        }

        let container = PinEventContainerView(item: item, size: frame.size)
        let window = PinNSWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = container

        // MARK: 键位表回调（docs/prd/02-ui-spec.md「贴图」）

        container.onScale = { [weak self] multiplier in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.scale(by: multiplier)
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onRotate = { [weak self] turns in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.rotate(byQuarterTurns: turns)
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onFlipHorizontally = { [weak self] in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.toggleHorizontalFlip()
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onFlipVertically = { [weak self] in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.toggleVerticalFlip()
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onAdjustOpacity = { [weak self] delta in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.adjustOpacity(by: delta)
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onResetScaleAndOpacity = { [weak self] in
            guard let self, var item = self.store.item(id: item.id) else { return }
            item.transform.resetScaleAndOpacity()  // 中键：仅恢复 100% 缩放和不透明度
            self.store.updateTransform(item.transform, for: item.id)
            self.refreshWindow(item)
        }
        container.onClose = { [weak self] in
            self?.close(item.id)  // Esc / ⌘W / 左键双击：关闭并进入恢复队列
        }
        container.onDestroy = { [weak self] in
            self?.destroy(item.id)  // ⇧Esc：销毁
        }
        container.onCopyPlainText = { [weak self] in
            self?.copyPlainText(for: item.id)  // ⇧⌘C
        }
        container.onOpenSettings = { [weak self] in
            self?.onOpenSettings()  // ⇧⌘P：打开截图与贴图设置
        }
        container.onReplaceFromPasteboard = { [weak self] in
            guard let self else { return }
            if let payload = try? self.payloadFactory.makePayload(from: .general) {
                self.store.replacePayload(payload, for: item.id)
                if let updated = self.store.item(id: item.id) {
                    self.refreshWindow(updated)
                }
            }
        }

        windows[item.id] = window
        refreshWindow(item)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(container)  // borderless 窗口键盘焦点
    }

    /// `⇧⌘C`：文本/HTML 贴图复制纯文本到剪贴板；图像/颜色载荷 no-op（UI 规范键位表）。
    func copyPlainText(for id: UUID) {
        guard let item = store.item(id: id) else { return }
        let text: String
        switch item.payload {
        case .text(let value):
            text = value
        case .attributedText(let attributed):
            text = attributed.string
        case .image, .color:
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Pin plain text copied: \(text.count) chars")
    }

    /// 依据 store 快照刷新窗口内容与透明度；隐藏时撤下。
    private func refreshWindow(_ item: PinItem) {
        guard let window = windows[item.id], let container = window.contentView as? PinEventContainerView else { return }
        container.update(item: item)
        window.alphaValue = item.isHidden ? 0 : item.transform.opacity
        if item.isHidden {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// 贴图专用窗口：borderless 置顶，跨 Space 显示。
/// borderless 窗口默认不能成为 key 窗口，而贴图键盘交互（`Esc`/`⌘` 组合）依赖 key 窗口。
final class PinNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// ⌘ 组合优先派发给贴图容器，避免主菜单（如默认 ⌘W `performClose:`）拦截。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let container = contentView as? PinEventContainerView,
           container.performKeyEquivalentIfHandled(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
