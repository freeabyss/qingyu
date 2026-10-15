import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
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
    @MainActor
    func requestScreenRecordingPrompt() -> Bool

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
