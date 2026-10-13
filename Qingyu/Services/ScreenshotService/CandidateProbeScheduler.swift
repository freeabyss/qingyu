import CoreGraphics
import Foundation
import os.log

// MARK: - Candidate probe scheduler (Task 012)

/// 控件级探测的调度器：惰性探测、只保留最新请求、结果代次校验、可取消。
///
/// **必须在主线程使用**（未标注 `@MainActor`，避免在 `CaptureSessionController`
/// 这类非隔离类型上产生成片的隔离警告；内部状态只由主线程读写，后台队列只做探测）。
///
/// 设计要点（与产品规则对应）：
/// - **不做全量预扫描**：只在指针移动时按当前位置探测一次；
/// - **不阻塞主线程**：探测跑在串行后台队列；
/// - **只保留最新**：指针快速移动时丢弃中间请求，避免排队积压；
/// - **代次校验**：`cancel()` 之后迟到的结果不得回调（跨屏切换/会话结束）；
/// - **超时上限**：单次探测受 `ElementProbeOptions.timeout` 约束（AX 侧 messaging timeout）。
@MainActor
final class CandidateProbeScheduler {    /// 探测结果（主线程回调）：命中控件矩形；nil 表示无控件候选（降级为窗口级）。
    var onResult: ((CGRect?) -> Void)?

    private let logger = Logger.screenshot
    private let provider: ElementCandidateProviding
    private let queue = DispatchQueue(label: "com.freeabyss.qingyu.candidate-probe", qos: .userInitiated)

    private var pending: (point: CGPoint, display: CaptureDisplay, options: ElementProbeOptions)?
    private var isProbing = false
    private var generation = 0

    init(provider: ElementCandidateProviding) {
        self.provider = provider
    }

    /// 请求一次探测；连续请求只保留最后一次。
    func schedule(point: CGPoint, display: CaptureDisplay, options: ElementProbeOptions) {
        guard options.isElementProbingEnabled else {
            // 关闭控件探测时立即回落为窗口级，不产生任何系统调用。
            return
        }
        pending = (point, display, options)
        drainIfIdle()
    }

    /// 取消在途探测并丢弃其结果（会话结束、跨屏切换、开始拖拽时调用）。
    func cancel() {
        generation &+= 1
        pending = nil
    }

    // MARK: - Private

    private func drainIfIdle() {
        guard !isProbing, let request = pending else { return }
        pending = nil
        isProbing = true
        let token = generation
        let provider = self.provider

        queue.async { [weak self] in
            let frame = provider.elementFrame(
                at: request.point,
                on: request.display,
                options: request.options
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.isProbing = false
                if token == self.generation {
                    self.onResult?(frame)
                }
                self.drainIfIdle()
            }
        }
    }
}
