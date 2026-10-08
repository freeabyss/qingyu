import XCTest
@testable import Qingyu

// 采用 review.md 推荐的策略 A + spy 方式一（注入 UpdateCheckServiceProtocol）。
//
// 为什么选方式一而非方式二：
// UpdateService.checkNow() 直接、同步调用注入的 updateCheckService.openDownloadPage()，
// 而 UpdateService.init(updateCheckService:) 是现成的注入点。注入一个记录调用次数的
// UpdateCheckServiceProtocol spy 即可在最外层拦截"跳转意图"，无需再深入 WebUpdateCheckService
// 内部注入 opener。这样侵入最小，且完全不触碰真实 NSWorkspace.shared.open。
// （方式二只有在需要断言具体 URL 时才更合适，本用例断言的是"恰好一次跳转意图"。）

final class UpdateServiceTests: XCTestCase {

    // TC-U-001：启动期不主动启动 Sparkle updater（弹窗根因消除）。
    func test_startsUpdaterAutomatically_isFalse_toPreventStartupCrash() {
        XCTAssertFalse(
            UpdateService.startsUpdaterAutomatically,
            "Issue #1: 启动期禁止自动启动 Sparkle updater，否则会因 SUPublicEDKey 未配置弹出错误对话框"
        )
    }

    // TC-U-002：checkNow() 仍触发 GitHub Releases 跳转（恰好一次）。
    func test_checkNow_callsUpdateCheckService_openDownloadPage_exactlyOnce() {
        let spy = RecordingUpdateCheckService()
        let service = UpdateService(updateCheckService: spy)

        service.checkNow()

        XCTAssertEqual(spy.openDownloadPageCallCount, 1)
    }
}

/// Spy implementing UpdateCheckServiceProtocol; records how many times openDownloadPage() is invoked.
/// Never touches NSWorkspace, so no real browser is opened during tests.
private final class RecordingUpdateCheckService: UpdateCheckServiceProtocol {
    private(set) var openDownloadPageCallCount = 0

    func openDownloadPage() {
        openDownloadPageCallCount += 1
    }
}
