import AppKit
import ApplicationServices
import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 012：控件级探测的纯逻辑与降级行为。
///
/// 真实 AX 探测需要辅助功能权限与活动 UI，因此这里覆盖：
/// 关闭态不产生调用、坐标换算、`AXValue` 解析的类型守卫；
/// 需要权限的真机行为见 `docs/test/cases.md` SHOT-LIFE-005 手工冒烟。
final class ElementCandidateProviderTests: XCTestCase {

    private let display = CaptureDisplay(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 3840, height: 2160)
    )

    func testDisabledProviderNeverReturnsFrame() {
        let provider = DisabledElementCandidateProvider()
        let frame = provider.elementFrame(
            at: CGPoint(x: 100, y: 100),
            on: display,
            options: .default
        )
        XCTAssertNil(frame)
    }

    /// 选项关闭时，即使构造了真实 AX 实现也不得发起系统调用（返回 nil）。
    func testRealProviderReturnsNilWhenOptionDisabled() {
        var options = ElementProbeOptions.default
        options.isElementProbingEnabled = false
        let provider = AXElementCandidateProvider()
        XCTAssertNil(provider.elementFrame(at: CGPoint(x: 10, y: 10), on: display, options: options))
    }

    // MARK: - 坐标换算

    /// AX 的 Quartz 坐标（左上原点）→ AppKit 全局坐标（左下原点）。
    func testAppKitFrameFlipsYAgainstMainDisplayHeight() {
        let frame = AXElementCandidateProvider.appKitFrame(
            fromQuartz: CGPoint(x: 100, y: 200),
            size: CGSize(width: 300, height: 150),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(frame, CGRect(x: 100, y: 730, width: 300, height: 150))
    }

    func testAppKitFrameHandlesNegativeQuartzOrigin() {
        let frame = AXElementCandidateProvider.appKitFrame(
            fromQuartz: CGPoint(x: -1280, y: 0),
            size: CGSize(width: 100, height: 100),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(frame.minX, -1280)
        XCTAssertEqual(frame.minY, 980)
    }

    // MARK: - AXValue 解析守卫

    func testPointReaderParsesCGPointAXValue() {
        var point = CGPoint(x: 12, y: 34)
        let value = AXValueCreate(.cgPoint, &point)
        XCTAssertEqual(AXElementCandidateProvider.point(from: value), point)
    }

    func testSizeReaderParsesCGSizeAXValue() {
        var size = CGSize(width: 56, height: 78)
        let value = AXValueCreate(.cgSize, &size)
        XCTAssertEqual(AXElementCandidateProvider.size(from: value), size)
    }

    /// 类型不符（CFBoolean 而非 AXValue）时必须返回 nil，而不是崩溃或读出垃圾值。
    func testReadersRejectNonAXValueInput() {
        XCTAssertNil(AXElementCandidateProvider.point(from: kCFBooleanTrue))
        XCTAssertNil(AXElementCandidateProvider.size(from: kCFBooleanTrue))
        XCTAssertNil(AXElementCandidateProvider.point(from: nil))
        XCTAssertNil(AXElementCandidateProvider.size(from: nil))
    }

    /// CGPoint 类型的 AXValue 不能被当成 CGSize 解析。
    func testSizeReaderRejectsPointTypedValue() {
        var point = CGPoint(x: 1, y: 2)
        let value = AXValueCreate(.cgPoint, &point)
        XCTAssertNil(AXElementCandidateProvider.size(from: value))
    }
}
