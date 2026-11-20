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

    /// 「重新启动清羽」必须用 `open -n <bundle 路径>`（0.4.212 回归）。    ///
    /// 用户报告：授权后点了「重新启动清羽」，应用关了但没再启动。旧实现用
    /// NSWorkspace.openApplication + completion handler 里无条件 terminate：
    /// completion handler 只是系统**接受**启动请求的回调，新实例还在
    /// LaunchServices 注册流程中就被调用方退出打断；openApplication 报错时
    /// 错误被吞掉、照样 terminate → 死局。现统一走 `AppRelauncher` 的
    /// open(1) 方案，这里锁死参数形状与退出宽限，防止回退。
    func test_relaunch_usesOpenNWithFullBundlePath() {
        let args = AppRelauncher.openArguments(bundlePath: "/Applications/Qingyu.app")
        XCTAssertEqual(args.first, "-n", "必须有 -n：允许与旧实例并存，否则系统只会激活旧进程")
        XCTAssertEqual(args.last, "/Applications/Qingyu.app", "必须传完整 bundle 路径")
        XCTAssertEqual(args.count, 2, "不得夹带其它参数（--args 透传会让新实例进入 UITest 态）")
        XCTAssertGreaterThan(AppRelauncher.terminateGraceSeconds, 0, "退出前必须给 LaunchServices 注册宽限")
    }

    /// 屏幕录制恢复流程的按钮顺序：先去授权、再让授权生效、最后取消。
    /// 「重新启动清羽」是一等操作（授权在进程内被缓存），不是兜底文案。
    func test_screenRecordingRecovery_ordersRelaunchBeforeCancel() {
        XCTAssertEqual(ScreenRecordingRecovery.actions, [.openSystemSettings, .relaunch, .cancel])
    }

    // MARK: - 完全磁盘访问（0.4.214：替代逐文件夹 TCC 弹窗）

    /// 探测结果必须如实映射到授权状态：系统没有查询 API，探测是唯一事实来源。
    func test_fullDiskAccess_statusReflectsProbeResult() {
        let service = PermissionService()
        let original = PermissionService.fullDiskAccessProbe
        defer { PermissionService.fullDiskAccessProbe = original }

        PermissionService.fullDiskAccessProbe = { true }
        XCTAssertEqual(service.status(for: .fullDiskAccess), .authorized, "探测可读 → 已授权")

        PermissionService.fullDiskAccessProbe = { false }
        XCTAssertEqual(service.status(for: .fullDiskAccess), .denied, "探测不可读 → 未授权")
    }

    /// 「打开系统设置」必须落到完全磁盘访问面板（Privacy_AllFiles 锚点），
    /// 落错面板用户会在隐私设置里找不到对应条目。
    func test_fullDiskAccess_opensPrivacyAllFilesPane() {
        let url = PermissionService().systemSettingsURL(for: .fullDiskAccess)
        XCTAssertEqual(
            url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }

    /// 权限区必须把完全磁盘访问纳入 allCases（设置页按 allCases 渲染行，
    /// 漏掉就等于没有入口），且刷新会带回它的状态。
    func test_fullDiskAccess_includedInPermissionKinds() async {
        XCTAssertTrue(PermissionKind.allCases.contains(.fullDiskAccess), "设置页权限区需要这一行")
        let statuses = await PermissionService().refreshStatuses()
        XCTAssertNotNil(statuses[.fullDiskAccess], "refreshStatuses 必须覆盖完全磁盘访问")
    }

    /// 启动引导的触发纯逻辑：未授权才问、每版本只问一次。
    func test_fullDiskAccessGuidance_promptsOnlyWhenNeeded() {
        XCTAssertFalse(FullDiskAccessGuidance.shouldPrompt(granted: true, promptedThisVersion: false), "已授权不问")
        XCTAssertFalse(FullDiskAccessGuidance.shouldPrompt(granted: false, promptedThisVersion: true), "本版本已问过不问")
        XCTAssertTrue(FullDiskAccessGuidance.shouldPrompt(granted: false, promptedThisVersion: false), "未授权且未问过 → 问")
    }
}
