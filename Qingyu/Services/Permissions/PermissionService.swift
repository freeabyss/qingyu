import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Security
import os.log

/// MVP permissions that must be granted before Assistant can enter the full experience.
enum PermissionKind: String, Codable, CaseIterable, Hashable {
    case screenRecording
    case accessibility
}

enum PermissionStatus: String, Codable, Hashable {
    case authorized
    case denied
    case notDetermined
    case unknown

    var isAuthorized: Bool { self == .authorized }
}

protocol PermissionServiceProtocol {
    func status(for permission: PermissionKind) -> PermissionStatus
    func openSystemSettings(for permission: PermissionKind)
    func refreshStatuses() async -> [PermissionKind: PermissionStatus]

    /// 触发屏幕录制权限申请，会促使系统首次注册本 App 到 TCC 数据库并加入设置候选列表。
    /// - Returns: 当前是否已授权(`CGRequestScreenCaptureAccess()` 的直接返回值)。
    /// - Note: 首次调用会弹出系统权限 UI；必须在主线程调用。参见 Issue #3、v1.1.0 architecture §4.1。
    /// - Warning: **macOS 15 起本调用不再弹窗、也不再注册本 App**，详见
    ///   `ScreenRecordingConsentFlow`；截图入口应改用 `requestScreenRecordingAccess()`。
    @MainActor
    func requestScreenRecordingPrompt() -> Bool

    /// 触发系统的屏幕录制同意流程，并在用户回应后返回最终授权状态。
    ///
    /// 与 `requestScreenRecordingPrompt()` 的区别：后者只是一次性的老式申请，macOS 15 起
    /// 已被系统拒绝（不弹窗、不注册）；本方法补齐了「真的抓一次屏让系统弹同意窗」与
    /// 「等用户回应」两步，见 `ScreenRecordingConsentFlow`。
    ///
    /// - Returns: 用户回应（或超时）之后，本进程当前是否已获屏幕录制授权。
    /// - Note: 最多等 20 秒；等待期间取消所在 `Task`（用户再次触发入口）会立即返回。
    @MainActor
    func requestScreenRecordingAccess() async -> Bool

    /// 按需检查辅助功能权限（v1.2，PRD FR-ONBOARD-ACCESSIBILITY-ONDEMAND / AC-7）。
    ///
    /// Onboarding **不**触发辅助功能 TCC；仅当用户首次真正触发需要辅助功能的能力
    /// （如自动粘贴、模拟快捷键）时才调用本方法。若尚未授权，弹出说明 Alert，
    /// 用户可选择「打开系统设置」跳转到辅助功能设置页。
    ///
    /// - Returns: 当前辅助功能是否已授权（`AXIsProcessTrusted()`）。已授权时不弹 Alert 直接返回 true。
    @MainActor
    func onDemandAccessibilityCheck() -> Bool
}

// MARK: - App signature status

/// 本应用的代码签名状态。
///
/// 直接决定屏幕录制授权**能否跨构建保留**，因此是「明明授权了却仍提示未授权」
/// 的第一诊断项：
/// - 正式签名（开发者 ID / Apple 开发证书）：TCC 按 Team + Bundle ID 记录授权，
///   重新编译仍然有效；
/// - **ad-hoc 签名**（本地构建的默认结果）：TCC 只能按**代码哈希**记录身份，
///   每次重新编译都是「另一个 App」，旧授权立即失效 —— 而系统设置里那条旧条目
///   仍然显示为已授权，于是看起来就是「明明授权了却还说没授权」。
enum AppSignatureStatus: Equatable {
    case signed(teamIdentifier: String)
    case adhoc
    case unknown

    /// 是否为开发构建（ad-hoc），需要向用户解释「每次重新编译都要重新授权」。
    var isAdhoc: Bool { self == .adhoc }
}

/// 权限相关提示文案的纯逻辑（便于单测，不依赖真实签名）。
enum PermissionGuidance {
    /// 未授权且为 ad-hoc 构建时，额外展示的说明；正式签名下返回 nil。
    static func developmentSignatureNoteKey(for status: AppSignatureStatus) -> String? {
        status.isAdhoc ? "permission.adhocSignature.note" : nil
    }
}

// MARK: - Screen-recording recovery

/// 屏幕录制权限未授予时的恢复流程。
///
/// 两个真实的失败模式决定了这里的按钮设计：
///
/// 1. **App 未注册进 TCC**：从未调用过 `CGRequestScreenCaptureAccess()` 的进程
///    不会出现在「系统设置 → 隐私与安全性 → 屏幕录制」列表里，用户根本无从授权，
///    表现就是「授权后一直提示没有授权」。因此调用方必须先触发一次系统申请。
/// 2. **授权判定被进程内缓存**：用户在系统设置里打开开关后，**当前运行实例**
///    通常仍读到旧的「未授权」，必须重启才生效。因此把「重新启动清羽」作为
///    一等操作给出，而不是只让用户自己去关掉重开。
enum ScreenRecordingRecovery {
    enum Action: CaseIterable {
        /// 打开系统设置的屏幕录制页。
        case openSystemSettings
        /// 重启清羽，让新授权生效。
        case relaunch
        case cancel

        var localizationKey: String {
            switch self {
            case .openSystemSettings: return "screenshot.permission.openSettings"
            case .relaunch: return "screenshot.permission.relaunch"
            case .cancel: return "screenshot.permission.cancel"
            }
        }
    }

    /// 展示给用户的操作顺序（即 NSAlert 的按钮顺序）：先给「去授权」，再给
    /// 「让授权生效」，最后才是取消。
    static let actions: [Action] = [.openSystemSettings, .relaunch, .cancel]
}

// MARK: - Screen-recording consent flow

/// 触发屏幕录制同意流程的时序（依赖全部注入，便于单测）。
///
/// **为什么不能只调用 `CGRequestScreenCaptureAccess()`**：macOS 15 起该调用不再弹窗 ——
/// tccd 直接记一行
/// `Service kTCCServiceScreenCapture does not allow prompting; returning denied.`
/// 然后返回未授权：**既不弹窗，也不把 App 写进 TCC 数据库**。于是用户在
/// 「系统设置 → 隐私与安全性 → 屏幕与系统录音」里根本找不到清羽，无从授权 ——
/// 用户报告的现象（「申请屏幕权限时列表里没有自动出现清羽」）正是如此。
/// 本机实测（macOS 26.6.2、Apple Development 签名的正式安装包）确认了这条日志。
///
/// macOS 15 起系统只在**真的尝试抓屏**时才弹同意窗（Apple 在 Sequoia release notes 中把
/// 「继续使用 `CGWindowListCreateImage` 等废弃捕获 API 会反复弹窗」列为已知行为），
/// 因此正确的时序是：
/// 1. 先按老系统的办法申请一次（macOS 15 之前靠它弹窗；之后是无害的 no-op）；
/// 2. **真的抓一次屏**，给系统弹同意窗的机会；
/// 3. 给用户几秒回应时间，期间一旦读到已授权就立刻放行。
///
/// 第 3 步是必要的：系统同意窗是异步的，用户点「允许」之前状态一直是未授权；
/// 若不等，就会在系统弹窗还挂着的时候弹出我们自己的引导窗，把用户推到
/// 「到底点哪个」的混乱里。
///
/// 等待预算必须**按人的反应速度**给足：早期实现只等 3 秒，用户还在读系统弹窗里的
/// 三个按钮，我们的引导窗就已经弹出来了 —— 用户看到的是「同时弹出两个申请授权的窗」。
/// 默认 40 × 0.5 s = 20 秒，足够读完并点掉系统弹窗；用户若认为系统压根没弹窗，
/// 再按一次截图入口即可立刻结束等待（调用方通过 `Task` 取消实现，见
/// `ScreenshotWindowController.startCapture()`）。
struct ScreenRecordingConsentFlow {
    /// 读取当前是否已授权（生产实现为 `CGPreflightScreenCaptureAccess()`）。
    var isAuthorized: () -> Bool
    /// 老系统的申请入口（生产实现为 `CGRequestScreenCaptureAccess()`）。
    var requestLegacyPrompt: () -> Void
    /// 真的抓一次屏以触发系统同意窗（结果丢弃）。
    var triggerSystemConsent: () -> Void
    /// 两次复查之间的等待。
    var waitBeforeRecheck: () async -> Void
    /// 最多复查几次。默认 40 次 × 0.5 s = 约 20 秒。
    var maxRechecks: Int = 40

    /// 生产环境的两次复查间隔。
    static let recheckIntervalNanoseconds: UInt64 = 500_000_000

    /// 生产时序（真实系统调用 + 0.5 秒复查间隔）。
    static func live() -> ScreenRecordingConsentFlow {
        ScreenRecordingConsentFlow(
            isAuthorized: { CGPreflightScreenCaptureAccess() },
            requestLegacyPrompt: { _ = CGRequestScreenCaptureAccess() },
            triggerSystemConsent: { PermissionService.triggerSystemConsentPrompt() },
            waitBeforeRecheck: { try? await Task.sleep(nanoseconds: recheckIntervalNanoseconds) }
        )
    }

    /// - Returns: 最终是否已授权。等待被取消（用户再次触发入口）时立即返回当前状态。
    func run() async -> Bool {
        if isAuthorized() { return true }
        requestLegacyPrompt()
        triggerSystemConsent()
        // 先等再查：系统同意窗需要一点时间才会出现，立刻查必然读到「未授权」。
        for _ in 0..<maxRechecks {
            if Task.isCancelled { return isAuthorized() }
            await waitBeforeRecheck()
            if isAuthorized() { return true }
        }
        return isAuthorized()
    }
}

/// Thin macOS API wrapper for Screen Recording and Accessibility privacy permissions.
final class PermissionService: PermissionServiceProtocol {
    private let workspace: NSWorkspace
    private let logger = Logger.app

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func status(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .authorized : .denied
        case .accessibility:
            return AXIsProcessTrusted() ? .authorized : .denied
        }
    }

    func openSystemSettings(for permission: PermissionKind) {
        if permission == .accessibility {
            requestAccessibilityPromptIfNeeded()
        }

        guard let url = systemSettingsURL(for: permission) else { return }
        workspace.open(url)
        logger.info("Opened System Settings for permission: \(permission.rawValue, privacy: .public)")
    }

    func refreshStatuses() async -> [PermissionKind: PermissionStatus] {
        Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, status(for: $0)) })
    }

    @MainActor
    func requestScreenRecordingPrompt() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    func requestScreenRecordingAccess() async -> Bool {
        let granted = await ScreenRecordingConsentFlow.live().run()
        logger.info("Screen recording access request finished: granted=\(granted, privacy: .public)")
        return granted
    }

    /// 真的抓一次屏，以触发系统的屏幕录制同意窗。
    ///
    /// 未授权时系统返回的是**桌面壁纸占位图**（不含任何窗口），这里刻意丢弃结果 ——
    /// 本次调用的唯一目的是让系统有机会弹同意窗并把清羽写进 TCC（见
    /// `ScreenRecordingConsentFlow` 的说明）。1×1 的裁剪框已经足够触发权限判定，
    /// 不必抓整屏。
    static func triggerSystemConsentPrompt() {
        _ = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            []
        )
    }

    @MainActor
    func onDemandAccessibilityCheck() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.localized("permission.onDemand.accessibility.title")
        alert.informativeText = L10n.localized("permission.onDemand.accessibility.message")
        alert.addButton(withTitle: L10n.localized("permission.onDemand.accessibility.openSettings"))
        alert.addButton(withTitle: L10n.localized("permission.onDemand.accessibility.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
        return false
    }

    /// 打开系统设置的「辅助功能」隐私页，并触发系统 prompt 让本 App 出现在列表中。
    @MainActor
    private func openAccessibilitySettings() {
        openSystemSettings(for: .accessibility)
    }

    private func requestAccessibilityPromptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 读取自身签名状态。
    ///
    /// 取不到签名信息时返回 `.unknown`（此时不展示开发构建说明，避免误导）。
    static func appSignatureStatus() -> AppSignatureStatus {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unknown }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unknown }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &information
        ) == errSecSuccess, let dictionary = information as? [String: Any] else {
            return .unknown
        }

        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 {
            return .adhoc
        }
        if let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .signed(teamIdentifier: team)
        }
        return .unknown
    }

    /// 重启本应用。
    ///
    /// 屏幕录制授权在进程内被缓存，重启是让新状态生效的可靠手段。先请求系统启动
    /// 新实例（`createsNewApplicationInstance` 允许与当前实例并存），再退出当前
    /// 实例，避免出现「旧实例已退出但新实例没起来」的空窗。
    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    private func systemSettingsURL(for permission: PermissionKind) -> URL? {
        let anchor: String
        switch permission {
        case .screenRecording:
            anchor = "Privacy_ScreenCapture"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
