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

    init() {
        self.phase = .targetingWindow(nil)
    }

    /// 指针移动：仅在 targeting 阶段生效（跨屏移动时窗口候选随之切换）。
    mutating func pointerMoved(to point: CGPoint, display: CaptureDisplay, window: CaptureWindowCandidate?) {
        guard case .targetingWindow = phase else { return }
        lastWindowCandidate = window
        phase = .targetingWindow(window)
    }

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
        phase = .draggingRegion(start: start, current: point, display: display)
    }

    /// 左键抬起：
    /// - 无拖拽事件的单击 → 锁定当前窗口候选；
    /// - 拖拽达到最小选区 → 锁定区域；
    /// - 拖拽不足最小选区 → 回到 targeting，保留当前窗口候选。
    mutating func mouseUp(at point: CGPoint) {
        guard case .draggingRegion(let start, let current, let display) = phase else { return }

        if !dragMoved {
            if let window = lastWindowCandidate {
                phase = .locked(.window(window))
            } else {
                phase = .targetingWindow(nil)
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
