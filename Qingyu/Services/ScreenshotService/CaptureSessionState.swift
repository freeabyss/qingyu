import CoreGraphics
import Foundation

// MARK: - Capture session state machine (Task 005)

/// 截图会话的互斥状态：
/// - `targetingWindow`：初始状态，跟随指针高亮所在窗口；
/// - `draggingRegion`：左键按下后进入区域拖拽；
/// - `locked`：窗口/区域/整屏目标已确定，等待捕获；
/// - `cancelled`：会话被取消，终态。
enum CaptureSessionPhase: Equatable {
    case targetingWindow(CaptureWindowCandidate?)
    case draggingRegion(start: CGPoint, current: CGPoint, display: CaptureDisplay)
    /// Task 014/01：拖拽结束后进入**可微调态** —— 方向键或鼠标（拖边缩放 / 拖内移动）
    /// 调整选区，`Enter` 确认后才捕获。
    /// 窗口/整屏的单击仍即时锁定（它们本身不需要像素级微调）。
    case adjustingRegion(display: CaptureDisplay, globalRect: CGRect)
    case locked(CaptureTarget)
    case cancelled
}

// MARK: - 可微调态的鼠标交互（Snipaste 式）

/// 相对选区的一个交互区域：内部（移动）、八条边/角（缩放）、外部（重新圈选）。
enum RegionHandleZone: Equatable {
    case inside
    case topLeft, top, topRight
    case right, bottomRight
    case bottom, bottomLeft
    case left
    case outside
}

/// 可微调态的选区交互几何：命中判定 + 施加移动/缩放。纯 CoreGraphics，
/// 不依赖 AppKit，供状态机与叠层（光标矩形、手柄绘制）共用。
enum RegionAdjustment {
    /// 边/角手柄的命中半径（逻辑点）。选区外的命中带同样宽——
    /// 精确抓 1pt 边线不现实，命中带让「拖边缘」变成一个可操作的目标。
    static let handleTolerance: CGFloat = 8

    /// 判定点落在选区的哪个交互区。
    static func zone(at point: CGPoint, rect: CGRect, tolerance: CGFloat = handleTolerance) -> RegionHandleZone {
        let nearLeft = abs(point.x - rect.minX) <= tolerance
        let nearRight = abs(point.x - rect.maxX) <= tolerance
        let nearBottom = abs(point.y - rect.minY) <= tolerance
        let nearTop = abs(point.y - rect.maxY) <= tolerance

        if nearLeft && nearBottom { return .bottomLeft }
        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearBottom { return .bottomRight }
        if nearRight && nearTop { return .topRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearTop { return .top }
        return rect.contains(point) ? .inside : .outside
    }

    /// 某交互区的命中矩形（叠层光标矩形用）。角是整块 2t×2t 方块，
    /// 边带在两端各让出 t、内部从边带内缩——三种矩形互不重叠，
    /// `addCursorRect` 的先后顺序不影响结果。
    static func hitRect(zone: RegionHandleZone, rect: CGRect, tolerance: CGFloat) -> CGRect {
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        switch zone {
        case .bottomLeft: return CGRect(x: x0 - tolerance, y: y0 - tolerance, width: tolerance * 2, height: tolerance * 2)
        case .topLeft: return CGRect(x: x0 - tolerance, y: y1 - tolerance, width: tolerance * 2, height: tolerance * 2)
        case .bottomRight: return CGRect(x: x1 - tolerance, y: y0 - tolerance, width: tolerance * 2, height: tolerance * 2)
        case .topRight: return CGRect(x: x1 - tolerance, y: y1 - tolerance, width: tolerance * 2, height: tolerance * 2)
        case .left: return CGRect(x: x0 - tolerance, y: y0 + tolerance, width: tolerance * 2, height: rect.height - tolerance * 2)
        case .right: return CGRect(x: x1 - tolerance, y: y0 + tolerance, width: tolerance * 2, height: rect.height - tolerance * 2)
        case .bottom: return CGRect(x: x0 + tolerance, y: y0 - tolerance, width: rect.width - tolerance * 2, height: tolerance * 2)
        case .top: return CGRect(x: x0 + tolerance, y: y1 - tolerance, width: rect.width - tolerance * 2, height: tolerance * 2)
        case .inside: return rect.insetBy(dx: tolerance, dy: tolerance)
        case .outside: return .zero
        }
    }

    /// 把一次从 `start` 到 `current` 的拖拽施加到 `initialRect` 上。
    ///
    /// - `.inside`：整体平移（钳制在 `bounds` 内）；
    /// - 边/角：对侧边固定，拖拽边跟随指针；钳制到 `bounds` 并保证不小于
    ///   `minimum`（也不越过对侧边）。
    static func apply(
        zone: RegionHandleZone,
        to initialRect: CGRect,
        from start: CGPoint,
        to current: CGPoint,
        bounds: CGRect,
        minimum: CGFloat
    ) -> CGRect {
        let dx = current.x - start.x
        let dy = current.y - start.y

        if zone == .inside {
            // 平移：保持在显示器内；选区比屏幕大时钉在屏幕边缘。
            let x = min(max(initialRect.minX + dx, bounds.minX), max(bounds.maxX - initialRect.width, bounds.minX))
            let y = min(max(initialRect.minY + dy, bounds.minY), max(bounds.maxY - initialRect.height, bounds.minY))
            return CGRect(x: x, y: y, width: initialRect.width, height: initialRect.height)
        }

        var minX = initialRect.minX
        var minY = initialRect.minY
        var maxX = initialRect.maxX
        var maxY = initialRect.maxY

        if zone == .left || zone == .topLeft || zone == .bottomLeft {
            minX = min(max(minX + dx, bounds.minX), maxX - minimum)
        }
        if zone == .right || zone == .topRight || zone == .bottomRight {
            maxX = max(min(maxX + dx, bounds.maxX), minX + minimum)
        }
        if zone == .bottom || zone == .bottomLeft || zone == .bottomRight {
            minY = min(max(minY + dy, bounds.minY), maxY - minimum)
        }
        if zone == .top || zone == .topLeft || zone == .topRight {
            maxY = max(min(maxY + dy, bounds.maxY), minY + minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// 纯截图会话状态机：只操作 CoreGraphics 值类型，不依赖 `NSWindow`，
/// 可完全由单元测试驱动。坐标一律为全局 AppKit point（左下原点）。
struct CaptureSessionState {
    /// 区域拖拽锁定所需的最小选区边长（像素）。
    static let minimumRegionSize: CGFloat = 5

    private(set) var phase: CaptureSessionPhase

    /// targeting 阶段最近一次指针命中的窗口候选；单击锁定窗口时使用。
    private var lastWindowCandidate: CaptureWindowCandidate?

    /// targeting 阶段最近一次控件级探测命中（AppKit 全局坐标）；单击时优先于窗口。
    private var lastElementFrame: CGRect?

    /// targeting 阶段最近一次指针所在显示器；把控件命中锁定为区域目标时需要。
    private var lastDisplay: CaptureDisplay?

    init() {
        self.phase = .targetingWindow(nil)
    }

    /// 指针移动：仅在 targeting 阶段生效（跨屏移动时窗口候选随之切换）。
    mutating func pointerMoved(to point: CGPoint, display: CaptureDisplay, window: CaptureWindowCandidate?) {
        guard case .targetingWindow = phase else { return }
        lastWindowCandidate = window
        lastDisplay = display
        lastElementFrame = nil
        phase = .targetingWindow(window)
    }

    /// 控件级探测结果到达（异步）：只在 targeting 阶段、且指针仍在同一显示器时生效。
    ///
    /// 返回是否发生了变化，调用方据此决定要不要刷新叠层。
    @discardableResult
    mutating func elementHovered(_ frame: CGRect?) -> Bool {
        guard case .targetingWindow = phase else { return false }
        guard lastElementFrame != frame else { return false }
        lastElementFrame = frame
        return true
    }

    /// 当前悬停的控件矩形（AppKit 全局坐标）；无控件候选时为 nil。
    var hoveredElementFrame: CGRect? {
        guard case .targetingWindow = phase else { return nil }
        return lastElementFrame
    }

    /// 当前指针所在显示器（用于把控件命中锁定为区域目标）。
    var currentDisplay: CaptureDisplay? { lastDisplay }

    /// 左键按下：
    /// - targeting 阶段：进入区域拖拽；
    /// - 可微调阶段：命中选区（含边/角手柄带）→ 开始移动/缩放交互；
    ///   点在选区外 → 丢弃旧选区、从该点重新圈选（旧选区保留到本次失败时回滚）；
    /// - 其余阶段忽略。
    mutating func mouseDown(at point: CGPoint, display: CaptureDisplay) {
        if case .adjustingRegion(let regionDisplay, let rect) = phase {
            let zone = RegionAdjustment.zone(at: point, rect: rect)
            if zone != .outside {
                regionInteraction = (zone: zone, initialRect: rect, startPoint: point)
                return
            }
            // 重新圈选：记住旧选区，单击没拖起来 / 拖得太小时恢复它，
            // 避免一次误触把已经画好的选区弄丢。
            regionInteraction = nil
            regionBeforeRestart = (display: regionDisplay, rect: rect)
            dragMoved = false
            lastElementFrame = nil
            phase = .draggingRegion(start: point, current: point, display: regionDisplay)
            return
        }
        guard case .targetingWindow = phase else { return }
        dragMoved = false
        phase = .draggingRegion(start: point, current: point, display: display)
    }

    /// 拖拽移动：
    /// - 可微调阶段且手上有交互 → 施加移动/缩放；
    /// - draggingRegion 阶段 → 更新拖拽选区。
    mutating func mouseDragged(to point: CGPoint) {
        if let interaction = regionInteraction, case .adjustingRegion(let display, _) = phase {
            let adjusted = RegionAdjustment.apply(
                zone: interaction.zone,
                to: interaction.initialRect,
                from: interaction.startPoint,
                to: point,
                bounds: display.frame,
                minimum: Self.minimumRegionSize
            )
            phase = .adjustingRegion(display: display, globalRect: adjusted)
            return
        }
        guard case .draggingRegion(let start, _, let display) = phase else { return }
        dragMoved = true
        // 一旦真的开始拖拽，用户就是在自己圈区域；控件命中不再参与本次锁定。
        lastElementFrame = nil
        phase = .draggingRegion(start: start, current: point, display: display)
    }

    /// 左键抬起：
    /// - 可微调交互中 → 结束交互，停留在可微调态（选区已是拖后值）；
    /// - 无拖拽事件的单击 → 锁定悬停默认值：有窗口候选锁定窗口，否则锁定当前显示器全屏
    ///   （PRD「截图与贴图」规则 2/5：菜单栏或桌面空白悬停时单击 = 全屏截图）；
    /// - 拖拽达到最小选区 → 锁定区域（区域圈选优先于悬停默认值）；
    /// - 拖拽不足最小选区 → 回到 targeting（若是「选区外重圈」则恢复旧选区）。
    mutating func mouseUp(at point: CGPoint) {
        if regionInteraction != nil {
            regionInteraction = nil
            return
        }
        guard case .draggingRegion(let start, let current, let display) = phase else { return }

        if !dragMoved {
            if let saved = regionBeforeRestart {
                // 「选区外重圈」没拖起来：恢复旧选区，而不是把单击解释成锁定窗口/整屏
                // ——那会把一次误触变成一次意外截图。
                regionBeforeRestart = nil
                phase = .adjustingRegion(display: saved.display, globalRect: saved.rect)
                return
            }
            // 锁定优先级与 `CandidateHitTest.hit` 一致：控件 > 窗口 > 整屏。
            // 控件命中（已有）时把该矩形锁定为区域目标，与高亮所见一致。
            if let element = lastElementFrame {
                phase = .locked(.region(display: display, globalRect: element))
            } else if let window = lastWindowCandidate {
                phase = .locked(.window(window))
            } else {
                phase = .locked(.display(display))
            }
            return
        }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        if rect.width >= Self.minimumRegionSize, rect.height >= Self.minimumRegionSize {
            // Task 014/01：不再"松开即捕获"，先进入可微调态，由 `confirmRegion()`（Enter）确认。
            regionBeforeRestart = nil
            phase = .adjustingRegion(display: display, globalRect: rect)
        } else if let saved = regionBeforeRestart {
            // 「选区外重圈」拖得太小：恢复旧选区，不把用户丢回窗口选择态。
            regionBeforeRestart = nil
            phase = .adjustingRegion(display: saved.display, globalRect: saved.rect)
        } else {
            phase = .targetingWindow(lastWindowCandidate)
        }
    }

    /// 方向键微调（Task 014/01）：仅在可微调态生效。
    /// `resize == false` 平移，`resize == true` 沿该轴对称缩放；返回是否发生变化。
    @discardableResult
    mutating func nudgeRegion(axis: SelectionNudge.Axis, delta: CGFloat, resize: Bool) -> Bool {
        guard case .adjustingRegion(let display, let rect) = phase else { return false }
        let adjusted = resize
            ? SelectionNudge.resize(
                rect,
                axis: axis,
                delta: delta,
                bounds: display.frame,
                minimum: Self.minimumRegionSize
            )
            : SelectionNudge.move(rect, axis: axis, delta: delta, bounds: display.frame)
        guard adjusted != rect else { return false }
        phase = .adjustingRegion(display: display, globalRect: adjusted)
        return true
    }

    /// Task 015：套用预设选区 —— 直接进入可微调态，**不结束会话**，
    /// 用户可继续微调后再 `confirmRegion()`。
    ///
    /// 已锁定 / 已取消时拒绝（返回 false），避免预设覆盖用户已经确认的目标。
    @discardableResult
    mutating func applyPresetRegion(_ rect: CGRect, display: CaptureDisplay) -> Bool {
        switch phase {
        case .targetingWindow, .draggingRegion, .adjustingRegion:
            lastElementFrame = nil
            dragMoved = false
            phase = .adjustingRegion(display: display, globalRect: rect)
            return true
        case .locked, .cancelled:
            return false
        }
    }

    /// 确认微调后的选区（Enter）：进入锁定态，由调用方开始捕获。
    mutating func confirmRegion() {
        guard case .adjustingRegion(let display, let rect) = phase else { return }
        phase = .locked(.region(display: display, globalRect: rect))
    }

    /// `⌘A`：锁定整个当前显示器；targeting、拖拽与可微调阶段均可用。
    mutating func selectFullDisplay(_ display: CaptureDisplay) {
        switch phase {
        case .targetingWindow, .draggingRegion, .adjustingRegion:
            // 整屏锁定不受控件命中影响。
            lastElementFrame = nil
            phase = .locked(.display(display))
        case .locked, .cancelled:
            return
        }
    }

    /// 取消会话；终态，重复取消无副作用。
    mutating func cancel() {
        phase = .cancelled
    }

    // MARK: - Private

    /// 是否发生过拖拽事件：区分“单击锁定窗口”与“过小拖拽回到 targeting”。
    private var dragMoved = false
    /// 可微调态的进行中交互（移动或边/角缩放）。
    private var regionInteraction: (zone: RegionHandleZone, initialRect: CGRect, startPoint: CGPoint)?
    /// 「选区外重新圈选」启动时保留的旧选区：重圈失败（没拖起来 / 太小）时回滚。
    private var regionBeforeRestart: (display: CaptureDisplay, rect: CGRect)?
}
