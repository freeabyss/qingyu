import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 011：放大镜配置收敛与取样来源契约。
///
/// 覆盖 `MagnifierConfiguration` 的非法输入收敛，以及 `MagnifierSourcing`
/// 的「关闭时不产生调用」「取消后不回调」等边界 —— 后者直接关系到截图会话
/// 结束后的生命周期回归（见 `docs/test/cases.md` 第 12 节）。
final class MagnifierStateTests: XCTestCase {

    // MARK: - 配置收敛

    func testDefaultConfigurationMatchesSnipasteBaseline() {
        let configuration = MagnifierConfiguration.default
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.zoom, 8)
        XCTAssertEqual(configuration.options, [.grid, .coordinate, .mask])
    }

    func testClampZoomFallsBackToDefaultForUnsupportedValues() {
        for zoom in MagnifierConfiguration.availableZooms {
            XCTAssertEqual(MagnifierConfiguration.clampZoom(zoom), zoom)
        }
        XCTAssertEqual(MagnifierConfiguration.clampZoom(0), MagnifierConfiguration.defaultZoom)
        XCTAssertEqual(MagnifierConfiguration.clampZoom(-4), MagnifierConfiguration.defaultZoom)
        XCTAssertEqual(MagnifierConfiguration.clampZoom(7), MagnifierConfiguration.defaultZoom)
        XCTAssertEqual(MagnifierConfiguration.clampZoom(1024), MagnifierConfiguration.defaultZoom)
    }

    func testSanitizedClampsZoomButKeepsOptionsVerbatim() {
        let configuration = MagnifierConfiguration(isEnabled: false, zoom: 99, options: [])
        let sanitized = configuration.sanitized()
        XCTAssertFalse(sanitized.isEnabled)
        XCTAssertEqual(sanitized.zoom, MagnifierConfiguration.defaultZoom)
        XCTAssertTrue(sanitized.options.isEmpty)
    }

    /// 放大倍数与采样像素数必须联动，否则放大镜会显示错误的像素范围。
    func testPixelCountTracksZoom() {
        for zoom in MagnifierConfiguration.availableZooms {
            let configuration = MagnifierConfiguration(isEnabled: true, zoom: zoom, options: [])
            XCTAssertEqual(
                configuration.pixelCount,
                MagnifierGeometry.pixelCount(viewSize: MagnifierConfiguration.viewSize, zoom: zoom)
            )
            XCTAssertGreaterThan(configuration.pixelCount, 0)
        }
    }

    // MARK: - 取样来源

    @MainActor
    private final class RecordingSource: MagnifierSourcing {
        var onSample: ((MagnifierSample) -> Void)?
        private(set) var requests: [MagnifierRequest] = []
        private(set) var cancelCount = 0

        func request(_ request: MagnifierRequest) { requests.append(request) }
        func cancel() { cancelCount += 1 }
    }

    @MainActor
    func testDisabledSourceNeverRequests() {
        let source = DisabledMagnifierSource()
        source.request(MagnifierRequest(
            displayID: 1,
            appKitSamplePoint: .zero,
            pixelCount: 14,
            screenFrame: .zero,
            displayPixelSize: CGSize(width: 10, height: 10),
            mainDisplayHeight: 1080,
            belowWindowNumber: 42
        ))
        XCTAssertNil(source.onSample)
    }

    @MainActor
    func testRecordingSourceKeepsOnlyLatestRequest() {
        let source = RecordingSource()
        for index in 0..<5 {
            source.request(MagnifierRequest(
                displayID: CGDirectDisplayID(index),
                appKitSamplePoint: CGPoint(x: index, y: index),
                pixelCount: 14,
                screenFrame: .zero,
                displayPixelSize: CGSize(width: 10, height: 10),
                mainDisplayHeight: 1080,
                belowWindowNumber: 42
            ))
        }
        XCTAssertEqual(source.requests.count, 5)
        XCTAssertEqual(source.requests.last?.appKitSamplePoint, CGPoint(x: 4, y: 4))
    }

    /// 取样点与取色点必须同源：放大镜中心像素就是取色采样点。
    ///
    /// 该用例把 `MagnifierGeometry.samplePoint`（放大镜取样）与
    /// `ScreenshotGeometry.cropRect`（最终捕获裁剪）的坐标约定钉在一起，
    /// 防止两条路径各自漂移后「放大镜中心」与「实际截到的像素」不一致。
    func testMagnifierSamplePointMatchesCaptureCropConvention() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let pixelSize = CGSize(width: 3840, height: 2160)
        let scale = MagnifierGeometry.displayScale(frame: frame, pixelSize: pixelSize)

        let logical = CGPoint(x: 960, y: 540)
        let sample = MagnifierGeometry.samplePoint(
            logicalPoint: logical,
            screenFrame: frame,
            scale: scale
        )
        XCTAssertEqual(sample.x, 1920, accuracy: 0.0001)
        XCTAssertEqual(sample.y, 1080, accuracy: 0.0001)

        // 同一逻辑点的 1×1 选区，捕获路径应裁出同一个像素。
        let onePixel = CGRect(x: logical.x, y: logical.y, width: 0.5, height: 0.5)
        let crop = ScreenshotGeometry.cropRect(
            globalSelection: onePixel,
            screenFrame: frame,
            imageSize: pixelSize
        )
        XCTAssertNotNil(crop)
        XCTAssertEqual(Double(crop!.minX), sample.x, accuracy: 1)
        XCTAssertEqual(Double(crop!.minY), sample.y, accuracy: 1)
    }

    // MARK: - 取样生命周期（叠层会话回归的放大镜侧）

    private func makeImage(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            data[index * 4 + 3] = 255
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func makeRequest(displayID: CGDirectDisplayID = 1) -> MagnifierRequest {
        MagnifierRequest(
            displayID: displayID,
            appKitSamplePoint: CGPoint(x: 10, y: 10),
            pixelCount: 14,
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            displayPixelSize: CGSize(width: 100, height: 100),
            mainDisplayHeight: 100,
            belowWindowNumber: 1
        )
    }

    /// 取消后不得再回调。
    ///
    /// 叠层关闭时 `CaptureOverlayContentView.cancelMagnifier()` 会取消在途取样；
    /// 若迟到的结果仍回调到已关闭的视图，就会重现「叠层已关但仍在动」的僵尸行为
    /// （`docs/test/cases.md` 第 12 节）。镜像 SHOT-LIFE-001/002 的判定方式。
    @MainActor
    func testCancelledSourceDropsInFlightSample() async {
        let source = BelowWindowMagnifierSource()
        let gate = DispatchSemaphore(value: 0)
        source.capture = { request in
            gate.wait()
            return MagnifierSample(
                displayID: request.displayID,
                image: self.makeImage(width: 4, height: 4),
                sourceRect: CGRect(x: 0, y: 0, width: 4, height: 4),
                pixelCenter: CGPoint(x: 1, y: 1)
            )
        }
        var delivered = 0
        source.onSample = { _ in delivered += 1 }

        source.request(makeRequest())
        source.cancel()
        gate.signal()

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(delivered, 0, "取消后不得再交付取样结果")
    }

    /// 取样在途时的连续请求只保留最新一次，不排队积压。
    @MainActor
    func testInFlightRequestsAreCoalescedToLatest() async {
        let source = BelowWindowMagnifierSource()
        let gate = DispatchSemaphore(value: 0)
        var captured: [CGDirectDisplayID] = []
        let lock = NSLock()
        var isFirstCall = true

        source.capture = { request in
            // 只阻塞第一次调用，制造「有在途请求」的窗口；
            // 后续调用直接完成，避免测试自我死锁。
            lock.lock()
            let shouldBlock = isFirstCall
            isFirstCall = false
            lock.unlock()
            if shouldBlock {
                gate.wait()
            }
            lock.lock()
            captured.append(request.displayID)
            lock.unlock()
            return nil
        }

        source.request(makeRequest(displayID: 10))
        source.request(makeRequest(displayID: 11))
        source.request(makeRequest(displayID: 12))
        gate.signal()

        try? await Task.sleep(nanoseconds: 300_000_000)
        lock.lock()
        let ids = captured
        lock.unlock()
        XCTAssertEqual(ids, [10, 12], "在途请求只应保留最新一次，丢弃中间请求")
    }
}
