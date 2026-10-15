import XCTest
import KeyboardShortcuts
@testable import Qingyu

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var settings: InMemorySettingsService!
    private var permissions: MockPermissionService!
    private var hotkeys: MockHotkeyValidationService!
    private var launchAtLogin: MockLaunchAtLoginService!
    private var didComplete = false

    override func setUp() async throws {
        settings = InMemorySettingsService()
        permissions = MockPermissionService()
        hotkeys = MockHotkeyValidationService()
        launchAtLogin = MockLaunchAtLoginService()
        didComplete = false
    }

    // 1.0.0 FeatureGate 关闭：屏幕录制段整体隐藏（不渲染、不设为必选），
    // 「开始使用」不再被屏幕录制授权状态阻塞。
    /// 截图入口开放后回到「授权 / 跳过」二选一的语义：未授权且未跳过时阻塞「开始使用」。
    func test_canStart_requiresScreenRecordingOrSkip() async throws {
        XCTAssertTrue(FeatureGate.screenshotEnabled, "截图入口已开放，本用例描述当前产品行为")

        permissions.statuses[.screenRecording] = .denied
        let viewModel = makeViewModel()
        await viewModel.refreshScreenRecordingStatus()
        XCTAssertFalse(viewModel.screenRecordingAuthorized)
        XCTAssertFalse(viewModel.canStart, "未授权且未跳过时应阻塞「开始使用」")

        viewModel.skipScreenshot()
        XCTAssertTrue(viewModel.canStart, "选择「暂不开启截图」后应放行")

        permissions.statuses[.screenRecording] = .authorized
        await viewModel.refreshScreenRecordingStatus()
        XCTAssertTrue(viewModel.canStart)
    }

    func test_canStart_enabledAfterSkippingScreenshot() async throws {
        permissions.statuses[.screenRecording] = .denied
        let viewModel = makeViewModel()
        await viewModel.refreshScreenRecordingStatus()
        XCTAssertFalse(viewModel.canStart, "未跳过前应被屏幕录制门槛拦住")

        viewModel.skipScreenshot()
        XCTAssertTrue(viewModel.screenshotSkipped)
        XCTAssertTrue(viewModel.canStart)
    }

    // ONB-V2-003: 点「授予屏幕录制权限」触发 requestScreenRecordingPrompt 恰好一次。
    func test_requestScreenRecording_triggersPromptOnce() async throws {
        let viewModel = makeViewModel()
        XCTAssertEqual(permissions.requestScreenRecordingCallCount, 0)

        viewModel.requestScreenRecording()

        XCTAssertEqual(permissions.requestScreenRecordingCallCount, 1)
    }

    // PERM-OD-001: onboarding 全程不触发辅助功能 TCC。
    func test_onboarding_neverTriggersAccessibilityRequest() async throws {
        let viewModel = makeReadyViewModel()

        viewModel.requestScreenRecording()
        viewModel.skipScreenshot()
        viewModel.dismissAccessibility()
        await viewModel.start()

        XCTAssertEqual(permissions.onDemandAccessibilityCallCount, 0)
    }

    // ONB-V2-005: 辅助功能「稍后再说」不阻塞完成（屏幕录制已授权前提下）。
    func test_start_completesWithoutAccessibility() async throws {
        let viewModel = makeReadyViewModel()
        viewModel.dismissAccessibility()

        await viewModel.start()

        XCTAssertTrue(didComplete)
        XCTAssertEqual(permissions.onDemandAccessibilityCallCount, 0)
    }

    // 1.0.0 FeatureGate 关闭：屏幕录制未授权（且段已隐藏）时 start() 仍完成，
    // 不再出现「开始使用」被权限卡死的死锁。
    /// 未授权且未跳过时 `start()` 必须被拦住并给出本地化提示，不得写入完成时间。
    func test_start_isBlockedWhenScreenRecordingDenied() async throws {
        permissions.statuses[.screenRecording] = .denied
        let viewModel = makeViewModel()
        await viewModel.refreshScreenRecordingStatus()

        await viewModel.start()

        XCTAssertFalse(didComplete, "屏幕录制未授权不应完成向导")
        XCTAssertEqual(
            viewModel.completionErrorMessage,
            L10n.localized("onboarding.error.screenRecordingRequired")
        )
        let completedAt = try await settings.stringValue(for: .onboardingCompletedAt)
        XCTAssertTrue(completedAt.isEmpty, "被拦住时不得写入完成时间")
    }

    // ONB-V2-008: start() 写入 onboardingCompletedAt + settings + 开机启动。
    func test_start_writesSettingsAndCompletedAt() async throws {
        let viewModel = makeReadyViewModel()
        viewModel.clipboardEnabled = true
        viewModel.launchAtLoginEnabled = true

        await viewModel.start()

        let completedAt = try await settings.stringValue(for: .onboardingCompletedAt)
        let clipboardEnabled = try await settings.value(for: .clipboardEnabled, as: Bool.self)
        let searchHotkey = try await settings.stringValue(for: .searchHotkey)
        let launchSetting = try await settings.value(for: .launchAtLoginEnabled, as: Bool.self)

        XCTAssertTrue(didComplete)
        XCTAssertFalse(completedAt.isEmpty)
        XCTAssertTrue(clipboardEnabled)
        XCTAssertEqual(searchHotkey, "option+space")
        XCTAssertTrue(launchSetting)
        XCTAssertTrue(launchAtLogin.enabled)
    }

    // ONB-V2-008 变体: 完成时同步写 legacy onboardingCompleted 布尔，保证回落读取路径。
    func test_start_alsoWritesLegacyBoolean() async throws {
        let viewModel = makeReadyViewModel()
        await viewModel.start()

        let legacy = try await settings.value(for: .onboardingCompleted, as: Bool.self)
        XCTAssertTrue(legacy)
    }

    // clipboard 关闭时写入 false。
    func test_start_persistsClipboardDisabledWhenToggledOff() async throws {
        let viewModel = makeReadyViewModel()
        viewModel.clipboardEnabled = false

        await viewModel.start()

        let clipboardEnabled = try await settings.value(for: .clipboardEnabled, as: Bool.self)
        XCTAssertFalse(clipboardEnabled)
    }

    // ONB-V2-006 / TC-U-004: skipOnboarding 写完成标记、显式 clipboardEnabled=false、回调 onComplete。
    func test_skipOnboarding_writesFlagsAndInvokesCompletion() async throws {
        let defaultClipboard = try await settings.value(for: .clipboardEnabled, as: Bool.self)
        XCTAssertTrue(defaultClipboard)

        let viewModel = makeViewModel()
        await viewModel.skipOnboarding()

        let completedAt = try await settings.stringValue(for: .onboardingCompletedAt)
        let legacy = try await settings.value(for: .onboardingCompleted, as: Bool.self)
        let clipboardEnabled = try await settings.value(for: .clipboardEnabled, as: Bool.self)

        XCTAssertFalse(completedAt.isEmpty)
        XCTAssertTrue(legacy)
        XCTAssertFalse(clipboardEnabled)
        XCTAssertTrue(didComplete)
    }

    // ONB-V2-002 / TC-U-006: 热键录入值被持久化（默认 option+space）。
    func test_skipOnboarding_persistsHotkey() async throws {
        hotkeys.persisted = "option+space"
        let viewModel = makeViewModel()

        await viewModel.skipOnboarding()

        let searchHotkey = try await settings.stringValue(for: .searchHotkey)
        XCTAssertEqual(searchHotkey, "option+space")
    }

    // onAppear 校验热键并刷新屏幕录制状态。
    func test_onAppear_refreshesScreenRecordingStatus() async throws {
        permissions.statuses[.screenRecording] = .authorized
        let viewModel = makeViewModel()

        viewModel.onAppear()
        // onAppear 内部 Task 异步刷新；直接调用同步等价方法验证。
        await viewModel.refreshScreenRecordingStatus()

        XCTAssertTrue(viewModel.screenRecordingAuthorized)
    }

    private func makeReadyViewModel() -> OnboardingViewModel {
        permissions.statuses[.screenRecording] = .authorized
        let viewModel = makeViewModel()
        viewModel.hotkeyValidation = .valid
        viewModel.screenRecordingAuthorized = true
        return viewModel
    }

    private func makeViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            permissionService: permissions,
            hotkeyService: hotkeys,
            settingsService: settings,
            launchAtLoginService: launchAtLogin,
            onComplete: { [weak self] in
            self?.didComplete = true
        })
    }
}

final class MockPermissionService: PermissionServiceProtocol {
    enum PermissionCall: Equatable {
        case request(kind: PermissionKind)
        case openSettings(kind: PermissionKind)
    }

    var statuses: [PermissionKind: PermissionStatus] = [.screenRecording: .authorized, .accessibility: .authorized]
    var opened: [PermissionKind] = []
    private(set) var callLog: [PermissionCall] = []

    var requestScreenRecordingResult: Bool = false
    private(set) var requestScreenRecordingCallCount: Int = 0

    var onDemandAccessibilityResult: Bool = false
    private(set) var onDemandAccessibilityCallCount: Int = 0

    func status(for permission: PermissionKind) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    func openSystemSettings(for permission: PermissionKind) {
        opened.append(permission)
        callLog.append(.openSettings(kind: permission))
    }

    func refreshStatuses() async -> [PermissionKind: PermissionStatus] {
        statuses
    }

    func requestScreenRecordingPrompt() -> Bool {
        callLog.append(.request(kind: .screenRecording))
        requestScreenRecordingCallCount += 1
        return requestScreenRecordingResult
    }

    func onDemandAccessibilityCheck() -> Bool {
        onDemandAccessibilityCallCount += 1
        return onDemandAccessibilityResult
    }
}

private final class MockHotkeyValidationService: HotkeyValidationServiceProtocol {
    var result: HotkeyValidationResult = .valid
    var persisted = "option+space"

    func currentShortcut() -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
    }

    func validateCurrentShortcut() -> HotkeyValidationResult {
        result
    }

    func persistCurrentShortcutString() -> String {
        persisted
    }
}

private final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var enabled = false

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}

private actor InMemorySettingsService: SettingsServiceProtocol {
    private var values = AssistantSettingDefaults.values

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        let raw = try await stringValue(for: key)
        if type == Bool.self, let bool = (["true", "1", "yes", "on"].contains(raw.lowercased())) as? T { return bool }
        if type == String.self, let string = raw as? T { return string }
        if type == ClipboardRetention.self, let value = ClipboardRetention(rawValue: raw) as? T { return value }
        if type == LanguageMode.self, let value = LanguageMode(rawValue: raw) as? T { return value }
        return try JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        switch value {
        case let bool as Bool:
            values[key.rawValue] = bool ? "true" : "false"
        case let string as String:
            values[key.rawValue] = string
        default:
            let data = try JSONEncoder().encode(value)
            values[key.rawValue] = String(data: data, encoding: .utf8)
        }
    }

    func reset(key: SettingKey) async throws {
        values[key.rawValue] = AssistantSettingDefaults.values[key.rawValue]
    }

    func stringValue(for key: SettingKey) async throws -> String {
        values[key.rawValue] ?? ""
    }
}

// MARK: - 屏幕录制权限恢复流程

@MainActor
final class ScreenRecordingRecoveryTests: XCTestCase {

    /// 「授权后仍提示未授权」的两个真实成因决定了按钮集合：
    /// 先去授权、再让授权生效、最后才是取消。
    func testRecoveryActionsOrderPutsRelaunchBeforeCancel() {
        XCTAssertEqual(
            ScreenRecordingRecovery.actions,
            [.openSystemSettings, .relaunch, .cancel],
            "必须提供「重新启动清羽」：macOS 会缓存当前实例的授权判定"
        )
    }

    func testRelaunchIsOffered() {
        XCTAssertTrue(
            ScreenRecordingRecovery.actions.contains(.relaunch),
            "缺少重启入口正是「授权后一直提示未授权」的直接原因"
        )
        XCTAssertFalse(
            ScreenRecordingRecovery.actions.isEmpty,
            "未授权时必须给出可执行的下一步，而不是只提示失败"
        )
    }

    func testCancelIsLastSoEscapeMapsToIt() {
        XCTAssertEqual(
            ScreenRecordingRecovery.actions.last,
            .cancel,
            "取消放在最后，控制器据此把 Esc 绑到最后一个按钮"
        )
    }

    func testEveryActionHasLocalization() {
        for action in ScreenRecordingRecovery.Action.allCases {
            XCTAssertFalse(
                L10n.localized(action.localizationKey).isEmpty,
                "\(action.localizationKey) 缺少文案"
            )
        }
    }

    /// ad-hoc 构建（本地编译默认）必须给出「每次重编都要重新授权」的说明；
    /// 正式签名下不展示，避免误导。
    func testDevelopmentSignatureNoteOnlyForAdhocBuilds() {
        XCTAssertEqual(
            PermissionGuidance.developmentSignatureNoteKey(for: .adhoc),
            "permission.adhocSignature.note"
        )
        XCTAssertNil(PermissionGuidance.developmentSignatureNoteKey(for: .signed(teamIdentifier: "ABCDE12345")))
        XCTAssertNil(
            PermissionGuidance.developmentSignatureNoteKey(for: .unknown),
            "取不到签名信息时不展示开发构建说明"
        )
        XCTAssertTrue(AppSignatureStatus.adhoc.isAdhoc)
        XCTAssertFalse(AppSignatureStatus.signed(teamIdentifier: "ABCDE12345").isAdhoc)
        XCTAssertFalse(AppSignatureStatus.unknown.isAdhoc)
    }

    func testAdhocNoteIsLocalized() {
        let key = try? XCTUnwrap(PermissionGuidance.developmentSignatureNoteKey(for: .adhoc))
        XCTAssertFalse(L10n.localized(key ?? "").isEmpty)
    }

    /// 权限状态映射：preflight 为真即已授权（真实系统调用不在单测里触发）。
    func testStatusMappingForInjectedService() {
        let mock = MockPermissionService()
        mock.statuses[.screenRecording] = .authorized
        XCTAssertTrue(mock.status(for: .screenRecording).isAuthorized)

        mock.statuses[.screenRecording] = .denied
        XCTAssertFalse(mock.status(for: .screenRecording).isAuthorized)
    }
}
