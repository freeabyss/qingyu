import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 012：控件探测调度器的生命周期契约。
///
/// 与 Task 011 的放大镜取样源同构：只保留最新请求、取消后不回调、关闭时不产生系统调用。
/// 这些性质直接关系到截图会话结束后的生命周期回归（`docs/test/cases.md` 第 12 节）。
@MainActor
final class CandidateProbeSchedulerTests: XCTestCase {

    private final class StubProvider: ElementCandidateProviding, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [CGPoint] = []
        var result: CGRect?
        var onCall: (() -> Void)?

        func elementFrame(at point: CGPoint, on display: CaptureDisplay, options: ElementProbeOptions) -> CGRect? {
            lock.lock()
            calls.append(point)
            lock.unlock()
            onCall?()
            return result
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls.count
        }
    }

    private let display = CaptureDisplay(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 3840, height: 2160)
    )

    private func options(enabled: Bool = true) -> ElementProbeOptions {
        ElementProbeOptions(
            isElementProbingEnabled: enabled,
            ignoredBundleIDs: [],
            timeout: ElementProbeOptions.default.timeout
        )
    }

    private func drainMainQueue() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    func testDisabledOptionsNeverInvokeProvider() async {
        let provider = StubProvider()
        let scheduler = CandidateProbeScheduler(provider: provider)
        scheduler.schedule(point: CGPoint(x: 10, y: 10), display: display, options: options(enabled: false))
        await drainMainQueue()
        XCTAssertEqual(provider.callCount, 0)
    }

    func testResultIsDeliveredToMainThreadCallback() async {
        let provider = StubProvider()
        provider.result = CGRect(x: 5, y: 6, width: 7, height: 8)
        let scheduler = CandidateProbeScheduler(provider: provider)

        var delivered: CGRect?
        scheduler.onSampleLike { delivered = $0 }
        scheduler.schedule(point: CGPoint(x: 1, y: 1), display: display, options: options())
        await drainMainQueue()

        XCTAssertEqual(delivered, CGRect(x: 5, y: 6, width: 7, height: 8))
    }

    /// 取消后迟到的结果不得回调（会话结束/开始拖拽/跨屏切换都依赖这一点）。
    func testCancelDropsInFlightResult() async {
        let provider = StubProvider()
        provider.result = CGRect(x: 1, y: 1, width: 1, height: 1)
        let gate = DispatchSemaphore(value: 0)
        provider.onCall = { gate.wait() }

        let scheduler = CandidateProbeScheduler(provider: provider)
        var delivered = 0
        scheduler.onSampleLike { _ in delivered += 1 }

        scheduler.schedule(point: CGPoint(x: 2, y: 2), display: display, options: options())
        scheduler.cancel()
        gate.signal()
        await drainMainQueue()

        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(provider.callCount, 1)
    }

    /// 在途期间的连续请求只保留最新一次，不排队积压。
    func testRequestsAreCoalescedToLatest() async {
        let provider = StubProvider()
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var isFirstCall = true
        provider.onCall = {
            lock.lock()
            let shouldBlock = isFirstCall
            isFirstCall = false
            lock.unlock()
            if shouldBlock { gate.wait() }
        }

        let scheduler = CandidateProbeScheduler(provider: provider)
        scheduler.schedule(point: CGPoint(x: 10, y: 10), display: display, options: options())
        scheduler.schedule(point: CGPoint(x: 11, y: 11), display: display, options: options())
        scheduler.schedule(point: CGPoint(x: 12, y: 12), display: display, options: options())
        gate.signal()
        await drainMainQueue()

        XCTAssertEqual(provider.calls, [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 12)])
    }
}

private extension CandidateProbeScheduler {
    /// 语义化别名，让测试读起来像「取样结果到达」。
    func onSampleLike(_ handler: @escaping (CGRect?) -> Void) {
        onResult = handler
    }
}
