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
    case locked(CaptureTarget)
    case cancelled
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

    /// 左键按下：targeting 阶段进入区域拖拽；其余阶段忽略。
    mutating func mouseDown(at point: CGPoint, display: CaptureDisplay) {
        guard case .targetingWindow = phase else { return }
        dragMoved = false
        phase = .draggingRegion(start: point, current: point, display: display)
    }

    /// 拖拽移动：仅在 draggingRegion 阶段生效。
    mutating func mouseDragged(to point: CGPoint) {
        guard case .draggingRegion(let start, _, let display) = phase else { return }
        dragMoved = true
        // 一旦真的开始拖拽，用户就是在自己圈区域；控件命中不再参与本次锁定。
        lastElementFrame = nil
        phase = .draggingRegion(start: start, current: point, display: display)
    }

    /// 左键抬起：
    /// - 无拖拽事件的单击 → 锁定悬停默认值：有窗口候选锁定窗口，否则锁定当前显示器全屏
    ///   （PRD「截图与贴图」规则 2/5：菜单栏或桌面空白悬停时单击 = 全屏截图）；
    /// - 拖拽达到最小选区 → 锁定区域（区域圈选优先于悬停默认值）；
    /// - 拖拽不足最小选区 → 回到 targeting，保留当前窗口候选。
    mutating func mouseUp(at point: CGPoint) {
        guard case .draggingRegion(let start, let current, let display) = phase else { return }

        if !dragMoved {
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
            phase = .locked(.region(display: display, globalRect: rect))
        } else {
            phase = .targetingWindow(lastWindowCandidate)
        }
    }

    /// `⌘A`：锁定整个当前显示器；targeting 与拖拽阶段均可用。
    mutating func selectFullDisplay(_ display: CaptureDisplay) {
        switch phase {
        case .targetingWindow, .draggingRegion:
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
}
