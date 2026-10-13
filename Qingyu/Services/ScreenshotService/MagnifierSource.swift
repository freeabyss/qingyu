import AppKit
import CoreGraphics
import os.log

// MARK: - Magnifier sampling (Task 011)

/// 一次放大镜取样请求。
///
/// 含义说明：清羽的截图会话**不冻结屏幕**（`ScreenCaptureBackend` 在目标锁定后才
/// `CGDisplayCreateImage`）。因此放大镜不能像 Snipaste 那样读取「本次捕获的原始位图」，
/// 而是在叠层窗口**下方**按需取样 —— 用 `CGWindowListCreateImage` 的
/// `.optionOnScreenBelowWindow` 排除清羽自己的暗幕与选框，得到与最终捕获一致的原始像素。
struct MagnifierRequest: Equatable {
    let displayID: CGDirectDisplayID
    /// 光标位置（AppKit 全局逻辑点）。
    let appKitSamplePoint: CGPoint
    /// 每边采样的源像素数。
    let pixelCount: Int
    /// 显示器逻辑框（AppKit 全局）。
    let screenFrame: CGRect
    /// 显示器原生像素尺寸。
    let displayPixelSize: CGSize
    /// AppKit 原点所在显示器的逻辑高度；`CGWindowListCreateImage` 坐标换算需要。
    let mainDisplayHeight: CGFloat
    /// 叠层窗口号：取样时排除该窗口及其之上的一切内容。
    let belowWindowNumber: CGWindowID
}

/// 一次放大镜取样结果。
struct MagnifierSample: Equatable {
    let displayID: CGDirectDisplayID
    /// 采样窗口位图（Retina 下为物理像素）。
    let image: CGImage
    /// 采样窗口在显示器像素坐标中的位置（左上原点）。
    let sourceRect: CGRect
    /// 光标所在像素（显示器像素坐标）。
    let pixelCenter: CGPoint

    /// 光标像素在 `image` 中的整数索引；越界返回 nil。
    var centerIndex: (x: Int, y: Int)? {
        let x = Int((pixelCenter.x - sourceRect.minX).rounded(.down))
        let y = Int((pixelCenter.y - sourceRect.minY).rounded(.down))
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        return (x, y)
    }

    static func == (lhs: MagnifierSample, rhs: MagnifierSample) -> Bool {
        lhs.displayID == rhs.displayID
            && lhs.sourceRect == rhs.sourceRect
            && lhs.pixelCenter == rhs.pixelCenter
            && lhs.image === rhs.image
    }
}

/// 放大镜取样来源抽象；单测注入记录型替身，避免真实抓屏。
@MainActor
protocol MagnifierSourcing: AnyObject {
    /// 取样完成回调（主线程）。
    var onSample: ((MagnifierSample) -> Void)? { get set }
    /// 请求一次取样；连续请求只保留最后一次（合并）。
    func request(_ request: MagnifierRequest)
    /// 取消在途取样并丢弃其结果。
    func cancel()
}

/// 基于 `CGWindowListCreateImage` 的取样实现：
/// 串行后台队列 + 只保留最新请求 + 代次校验丢弃过期结果，
/// 保证指针快速移动时既不阻塞主线程也不出现「旧画面盖住新画面」。
@MainActor
final class BelowWindowMagnifierSource: MagnifierSourcing {
    var onSample: ((MagnifierSample) -> Void)?

    /// 取样实现。默认走真实的 `CGWindowListCreateImage`；单测可注入替身，
    /// 从而在**不依赖真实抓屏与屏幕录制权限**的前提下验证「请求合并」与「取消后不回调」。
    var capture: @Sendable (MagnifierRequest) -> MagnifierSample? = BelowWindowMagnifierSource.captureScreen

    private let logger = Logger.screenshot
    private let queue = DispatchQueue(label: "com.freeabyss.qingyu.magnifier.sample", qos: .userInteractive)

    private var pendingRequest: MagnifierRequest?
    private var isSampling = false
    private var generation = 0

    func request(_ request: MagnifierRequest) {
        pendingRequest = request
        drainIfIdle()
    }

    func cancel() {
        generation &+= 1
        pendingRequest = nil
    }

    // MARK: - Private

    private func drainIfIdle() {
        guard !isSampling, let request = pendingRequest else { return }
        pendingRequest = nil
        isSampling = true
        let token = generation
        // 复制一份实现，避免在后台队列上访问主线程隔离的存储属性。
        let capture = self.capture

        queue.async { [weak self] in
            let sample = capture(request)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSampling = false
                if token == self.generation, let sample {
                    self.onSample?(sample)
                }
                self.drainIfIdle()
            }
        }
    }

    /// 真正的抓屏：只取放大镜需要的一小块，且排除清羽自己的叠层窗口。
    ///
    /// `nonisolated`：本函数只依赖 CoreGraphics 与传入值类型，跑在后台串行队列上，
    /// 不碰任何主线程状态。
    nonisolated static func captureScreen(_ request: MagnifierRequest) -> MagnifierSample? {
        guard request.belowWindowNumber != 0 else { return nil }

        let scale = MagnifierGeometry.displayScale(
            frame: request.screenFrame,
            pixelSize: request.displayPixelSize
        )
        let pixelCenter = MagnifierGeometry.samplePoint(
            logicalPoint: request.appKitSamplePoint,
            screenFrame: request.screenFrame,
            scale: scale
        )
        let sourceRect = MagnifierGeometry.sourceRect(
            centeredAt: pixelCenter,
            pixelCount: request.pixelCount,
            displayPixelSize: request.displayPixelSize
        )

        // 采样窗口（像素）→ AppKit 全局逻辑矩形 → Quartz 屏幕坐标。
        let appKitRect = CGRect(
            x: request.screenFrame.minX + sourceRect.minX / scale,
            y: request.screenFrame.maxY - sourceRect.maxY / scale,
            width: sourceRect.width / scale,
            height: sourceRect.height / scale
        )
        let quartzRect = MagnifierGeometry.quartzRect(
            fromAppKitRect: appKitRect,
            mainDisplayHeight: request.mainDisplayHeight
        )

        guard let image = CGWindowListCreateImage(
            quartzRect,
            .optionOnScreenBelowWindow,
            request.belowWindowNumber,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        return MagnifierSample(
            displayID: request.displayID,
            image: image,
            sourceRect: sourceRect,
            pixelCenter: pixelCenter
        )
    }
}

/// 无操作替身：放大镜关闭或环境不支持取样时使用。
@MainActor
final class DisabledMagnifierSource: MagnifierSourcing {
    var onSample: ((MagnifierSample) -> Void)?
    func request(_ request: MagnifierRequest) {}
    func cancel() {}
}
