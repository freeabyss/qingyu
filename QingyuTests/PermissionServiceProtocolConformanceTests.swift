import XCTest
@testable import Qingyu

@MainActor
final class PermissionServiceProtocolConformanceTests: XCTestCase {

    // TC-U-001: 三个 conformer(MockPermissionService、StaticPermissionService、PermissionService)
    // 都实现了 requestScreenRecordingPrompt()。此测试只覆盖两个 mock；真实 PermissionService
    // 走 CGRequestScreenCaptureAccess 会真弹 UI,不在单测中调用。
    // 参见 docs/iterations/v1.1.0/architecture/review.md 阻塞级发现。

    func test_mockPermissionService_conformsToRequestScreenRecordingPrompt() {
        let mock = MockPermissionService()
        mock.requestScreenRecordingResult = true
        let result = mock.requestScreenRecordingPrompt()
        XCTAssertTrue(result)
        XCTAssertEqual(mock.requestScreenRecordingCallCount, 1)
    }

    func test_staticPermissionService_conformsToRequestScreenRecordingPrompt() {
        let staticService = StaticPermissionService()
        XCTAssertTrue(staticService.requestScreenRecordingPrompt())
    }

    // PERM-OD-003: onDemandAccessibilityCheck() 三 conformer 补齐。
    // 真实 PermissionService 走 AXIsProcessTrusted + NSAlert，会弹 UI，不在单测调用；
    // 此处覆盖 Mock/Static 两替身，编译即验证真实服务已实现（否则协议不满足）。
    func test_mockPermissionService_conformsToOnDemandAccessibilityCheck() {
        let mock = MockPermissionService()
        mock.onDemandAccessibilityResult = true
        XCTAssertTrue(mock.onDemandAccessibilityCheck())
        XCTAssertEqual(mock.onDemandAccessibilityCallCount, 1)
    }

    func test_staticPermissionService_conformsToOnDemandAccessibilityCheck() {
        let staticService = StaticPermissionService()
        XCTAssertTrue(staticService.onDemandAccessibilityCheck())
    }
}
