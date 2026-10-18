import XCTest
@testable import Qingyu

/// `ScreenRecordingConsentFlow` 的时序契约。
///
/// 背景（用户报告 2026-10-18：「打开截图申请屏幕权限时，系统设置里没有自动出现清羽」）：
/// macOS 15 起 tccd 对 `kTCCServiceScreenCapture` 直接返回
/// `does not allow prompting; returning denied` —— 只调 `CGRequestScreenCaptureAccess()`
/// **既不弹窗、也不把 App 写进 TCC**，于是用户去列表里找根本找不到。
/// 因此流程必须补齐两步：**真的抓一次屏**（这才是系统弹同意窗的触发点）**并等用户回应**。
/// 这三步少任何一步，用户都会卡在「系统设置里没有清羽」。
@MainActor
final class ScreenRecordingConsentTests: XCTestCase {

    /// 记录各步骤的调用次数，并按脚本决定何时「授权」。
    private final class Recorder {
        private(set) var legacyPrompts = 0
        private(set) var consentCaptures = 0
        private(set) var waits = 0

        /// 一开始就已授权（正常路径）。
        var initiallyAuthorized = false
        /// 等待若干次之后才授权（用户在系统弹窗上点了「允许」）；nil = 始终未授权。
        var authorizedAfterWaits: Int?

        func isAuthorized() -> Bool {
            if initiallyAuthorized { return true }
            guard let threshold = authorizedAfterWaits else { return false }
            return waits >= threshold
        }

        func recordLegacyPrompt() { legacyPrompts += 1 }
        func recordConsentCapture() { consentCaptures += 1 }
        func recordWait() { waits += 1 }
    }

    private func makeFlow(_ recorder: Recorder, maxRechecks: Int = 6) -> ScreenRecordingConsentFlow {
        ScreenRecordingConsentFlow(
            isAuthorized: { recorder.isAuthorized() },
            requestLegacyPrompt: { recorder.recordLegacyPrompt() },
            triggerSystemConsent: { recorder.recordConsentCapture() },
            waitBeforeRecheck: { recorder.recordWait() },
            maxRechecks: maxRechecks
        )
    }

    /// 已授权：一次多余的系统调用都不该发生（避免无谓地打扰用户）。
    func testAlreadyAuthorizedSkipsEveryStep() async {
        let recorder = Recorder()
        recorder.initiallyAuthorized = true

        let granted = await makeFlow(recorder).run()

        XCTAssertTrue(granted)
        XCTAssertEqual(recorder.legacyPrompts, 0, "已授权时不得再调老式申请接口")
        XCTAssertEqual(recorder.consentCaptures, 0, "已授权时不得再抓屏")
        XCTAssertEqual(recorder.waits, 0, "已授权时不得等待")
    }

    /// 核心契约：先申请 → **真的抓一次屏**（触发系统同意窗）→ 等用户回应 → 放行。
    func testTriggersConsentCaptureThenWaitsUntilGranted() async {
        let recorder = Recorder()
        recorder.authorizedAfterWaits = 2   // 用户在第 2 次复查前点了「允许」

        let granted = await makeFlow(recorder).run()

        XCTAssertTrue(granted)
        XCTAssertEqual(recorder.legacyPrompts, 1, "老式申请接口仍要调一次（macOS 15 之前靠它弹窗）")
        XCTAssertEqual(recorder.consentCaptures, 1, "必须真的抓一次屏：这才是 macOS 15 起系统弹同意窗的触发点")
        XCTAssertEqual(recorder.waits, 2, "授权一到就立刻放行，不把剩余等待跑完")
    }

    /// 用户始终未回应（或点了「不允许」）：跑满复查次数后返回未授权，
    /// 由调用方展示「用 + 手动添加」的引导。
    func testReturnsFalseAfterAllRechecksWhenNeverGranted() async {
        let recorder = Recorder()

        let granted = await makeFlow(recorder, maxRechecks: 4).run()

        XCTAssertFalse(granted)
        XCTAssertEqual(recorder.consentCaptures, 1)
        XCTAssertEqual(recorder.waits, 4, "必须把复查跑满，给用户足够的回应时间")
    }

    /// 最后一次复查才授权：仍要判定为已授权（差一次就白等）。
    func testGrantOnTheLastRecheckStillSucceeds() async {
        let recorder = Recorder()
        recorder.authorizedAfterWaits = 3

        let granted = await makeFlow(recorder, maxRechecks: 3).run()

        XCTAssertTrue(granted)
        XCTAssertEqual(recorder.waits, 3)
    }

    /// 先等再查：立刻查必然读到「未授权」（系统弹窗还没出现），
    /// 因此第一次复查必须发生在第一次等待之后。
    func testFirstRecheckHappensAfterAWait() async {
        let recorder = Recorder()
        recorder.authorizedAfterWaits = 1

        let granted = await makeFlow(recorder, maxRechecks: 2).run()

        XCTAssertTrue(granted)
        XCTAssertEqual(recorder.waits, 1, "第一次等待之后就应读到授权")
    }
}
