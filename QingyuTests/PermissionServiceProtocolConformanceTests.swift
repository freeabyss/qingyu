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

    /// 「重新启动清羽」必须是脱离进程的 shell：等本实例退净后再 open（0.4.217 回归）。
    ///
    /// 两代失败史：① NSWorkspace.openApplication + completion 里无条件 terminate
    /// （0.4.212 修，注册被退出中断、错误被吞）；② open(1) 直启、LaunchServices
    /// 注册与本实例退出并跑（0.4.216 用户再次报告「授权后没有成功重启」，
    /// 无日志无崩溃报告无法复盘，并跑是仅剩的可疑窗口）。v3 把时序变成硬约束：
    /// `/bin/sh -c 'sleep N && exec open -n <bundle>'`，N > 退出宽限——
    /// shell 孤儿进程等本实例退出后才触发启动，两个阶段不再重叠。
    func test_relaunch_usesDetachedShellWithDelayedOpen() {
        let command = AppRelauncher.relaunchShellCommand(
            bundlePath: "/Applications/Qingyu.app",
            delaySeconds: AppRelauncher.respawnDelaySeconds
        )
        XCTAssertTrue(command.hasPrefix("sleep "), "必须先 sleep：等本实例退出")
        XCTAssertTrue(command.contains("exec /usr/bin/open -n '/Applications/Qingyu.app'"),
                      "sleep 后必须 exec open -n 完整 bundle 路径（-n 兜底：宁可短暂双开也不要起不来）")
        XCTAssertGreaterThan(
            AppRelauncher.respawnDelaySeconds, AppRelauncher.terminateGraceSeconds,
            "核心约束：新实例的启动延迟必须大于退出宽限，否则启动注册与旧实例退出又并跑了"
        )
    }

    /// 带空格的 bundle 路径必须整体加引号，命令不能拼坏。
    func test_relaunch_shellCommandQuotesPathWithSpaces() {
        let command = AppRelauncher.relaunchShellCommand(
            bundlePath: "/Applications/My Apps/Qingyu.app",
            delaySeconds: 0.1
        )
        XCTAssertTrue(command.contains("'/Applications/My Apps/Qingyu.app'"), "路径必须整体加引号")
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
