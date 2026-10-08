import Foundation
import KeyboardShortcuts

/// 单屏 Onboarding 状态机（v1.2，PRD §9.4 P-06）。
///
/// 旧的多步向导（`OnboardingStep`）在 v1.2 被单屏布局取代：所有配置项与权限段
/// 同屏呈现，用户可自由操作，仅屏幕录制权限影响「开始使用」是否可用。
/// 辅助功能不在此触发 TCC —— 改为按需（`PermissionService.onDemandAccessibilityCheck()`）。
@MainActor
final class OnboardingViewModel: ObservableObject {
    // MARK: - 配置项状态

    /// ⌥Space 命令栏热键校验结果（用于卡内冲突提示，不阻塞完成）。
    @Published var hotkeyValidation: HotkeyValidationResult = .valid

    /// 剪贴板历史开关（默认开启，绑 `SettingKey.clipboardEnabled`）。
    @Published var clipboardEnabled: Bool = true

    /// 开机启动开关（onboarding 默认关闭，绑 `LaunchAtLogin.enabled`）。
    @Published var launchAtLoginEnabled: Bool = false

    // MARK: - 屏幕录制段

    /// 屏幕录制是否已授权（`CGPreflightScreenCaptureAccess()`）。
    @Published var screenRecordingAuthorized: Bool = false

    /// 用户是否点了「暂不开启截图」跳过屏幕录制（截图能力在用到时再申请）。
    @Published var screenshotSkipped: Bool = false

    // MARK: - 其他

    @Published var completionErrorMessage: String?

    private let permissionService: PermissionServiceProtocol
    private let hotkeyService: HotkeyValidationServiceProtocol
    private let settingsService: SettingsServiceProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let now: () -> Date
    private let onComplete: () -> Void

    init(
        permissionService: PermissionServiceProtocol = PermissionService(),
        hotkeyService: HotkeyValidationServiceProtocol = HotkeyValidationService(),
        settingsService: SettingsServiceProtocol = SettingsService(persistence: .shared),
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
        now: @escaping () -> Date = Date.init,
        onComplete: @escaping () -> Void = {}
    ) {
        self.permissionService = permissionService
        self.hotkeyService = hotkeyService
        self.settingsService = settingsService
        self.launchAtLoginService = launchAtLoginService
        self.now = now
        self.onComplete = onComplete
    }

    // MARK: - 可用性规则

    /// 「开始使用」是否可用。
    ///
    /// 规则（P-06，简单明确）：屏幕录制已授权，**或**用户已点「暂不开启截图」。
    /// 其余项（热键 / 剪贴板 / 开机启动）不阻塞完成。
    ///
    /// 1.0.0 FeatureGate：截图整体隐藏，屏幕录制段不渲染、不再是必选门槛，
    /// 「开始使用」恒可用；开关恢复后回到授权/跳过二选一的语义。
    var canStart: Bool {
        if !FeatureGate.screenshotEnabled { return true }
        return screenRecordingAuthorized || screenshotSkipped
    }

    // MARK: - 生命周期

    func onAppear() {
        validateHotkey()
        Task { await refreshScreenRecordingStatus() }
    }

    func validateHotkey() {
        hotkeyValidation = hotkeyService.validateCurrentShortcut()
    }

    // MARK: - 屏幕录制

    /// 点击「授予屏幕录制权限」：触发 TCC 申请并刷新授权态。
    func requestScreenRecording() {
        _ = permissionService.requestScreenRecordingPrompt()
        Task { await refreshScreenRecordingStatus() }
    }

    /// 点击「暂不开启截图」：跳过屏幕录制，允许继续使用（截图按需申请）。
    func skipScreenshot() {
        screenshotSkipped = true
    }

    func refreshScreenRecordingStatus() async {
        let statuses = await permissionService.refreshStatuses()
        screenRecordingAuthorized = statuses[.screenRecording]?.isAuthorized == true
    }

    // MARK: - 辅助功能（按需，不在 onboarding 触发 TCC）

    /// 说明文案入口——onboarding 不弹 TCC。真正的按需申请由
    /// `PermissionService.onDemandAccessibilityCheck()` 在功能首次触发时调用。
    /// 保留此方法仅为「稍后再说」按钮语义占位，不做任何权限请求。
    func dismissAccessibility() {
        // no-op: 辅助功能改为按需申请（FR-ONBOARD-ACCESSIBILITY-ONDEMAND）。
    }

    // MARK: - 完成 / 跳过

    /// 「开始使用」：写入设置与完成时间戳，关闭 onboarding。
    func start() async {
        guard canStart else {
            completionErrorMessage = L10n.localized("onboarding.error.screenRecordingRequired")
            return
        }
        completionErrorMessage = nil
        do {
            try await persistCommonSettings()
            try await settingsService.set(launchAtLoginEnabled, for: .launchAtLoginEnabled)
            try launchAtLoginService.setEnabled(launchAtLoginEnabled)
            try await markCompleted()
            onComplete()
        } catch {
            completionErrorMessage = error.localizedDescription
        }
    }

    /// 「跳过设置」：不校验权限，写完成标记后进入主界面（承接 v1.1 行为）。
    ///
    /// 与 `start()` 差异：跳过时显式写 `clipboardEnabled = false`（PRD P-2.3，
    /// 保留用户选择权 / 延后启用），且不改动开机启动。
    func skipOnboarding() async {
        completionErrorMessage = nil
        do {
            try await settingsService.set(hotkeyService.persistCurrentShortcutString(), for: .searchHotkey)
            try await settingsService.set(false, for: .clipboardEnabled)
            try await markCompleted()
            onComplete()
        } catch {
            completionErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func persistCommonSettings() async throws {
        try await settingsService.set(hotkeyService.persistCurrentShortcutString(), for: .searchHotkey)
        try await settingsService.set(clipboardEnabled, for: .clipboardEnabled)
    }

    /// 写入完成标记：`onboardingCompletedAt`（ISO8601 时间戳，非空即已完成）
    /// 以及 legacy `onboardingCompleted` 布尔（向后兼容旧读取路径）。
    private func markCompleted() async throws {
        let timestamp = ISO8601DateFormatter().string(from: now())
        try await settingsService.set(timestamp, for: .onboardingCompletedAt)
        try await settingsService.set(true, for: .onboardingCompleted)
    }
}
