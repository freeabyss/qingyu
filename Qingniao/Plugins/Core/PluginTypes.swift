import Foundation
import KeyboardShortcuts
import SwiftUI

// MARK: - First-party plugin contracts (Task 001 / ADR-001)

/// 插件唯一标识。第一方插件只在代码中注册，`rawValue` 一经发布即视为稳定 API。
struct PluginID: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 插件动作唯一标识。动作经 `PluginRegistry.execute(_:)` 按所有权路由，
/// 通知字符串不作为插件 API。
struct PluginActionID: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 插件静态元数据。
struct PluginDescriptor {
    let id: PluginID
    /// 本地化显示名 key（Localizable.xcstrings）。
    let displayNameKey: String
    let version: String
    /// 无用户持久化选择时的默认启停状态。
    let defaultEnabled: Bool
}

/// 插件贡献的设置页描述，`order` 决定侧栏排序。
struct PluginSettingsPageDescriptor {
    let id: PluginID
    let titleKey: String
    let systemImageName: String
    let order: Int
    let makeView: @MainActor () -> AnyView
}

/// 插件动作：稳定 ID + 主线程异步执行闭包。
struct PluginAction {
    let id: PluginActionID
    let perform: @MainActor () async throws -> Void

    init(id: PluginActionID, perform: @escaping @MainActor () async throws -> Void) {
        self.id = id
        self.perform = perform
    }
}

/// 插件贡献的菜单项，`actionID` 必须指向本插件清单中的动作。
struct PluginMenuItemDescriptor {
    let id: String
    let titleKey: String
    let systemImageName: String
    let order: Int
    let actionID: PluginActionID
}

/// 插件贡献的全局快捷键，绑定到本插件清单中的动作。
struct PluginShortcutDescriptor {
    let name: KeyboardShortcuts.Name
    let actionID: PluginActionID
}

/// 插件向注册表声明全部贡献的清单。
struct PluginManifest {
    let descriptor: PluginDescriptor
    let searchSources: [any SearchSource]
    let actions: [PluginAction]
    let settingsPage: PluginSettingsPageDescriptor?
    let menuItems: [PluginMenuItemDescriptor]
    let shortcuts: [PluginShortcutDescriptor]
    let requiredPermissions: Set<PermissionKind>
}

/// 第一方插件协议：编译期注册、随主应用进程运行（ADR-001）。
@MainActor
protocol QingniaoPlugin: AnyObject {
    var manifest: PluginManifest { get }

    /// 启动插件（注册后台任务、监听等）。抛错时注册表记录失败并隔离该插件。
    func start() async throws

    /// 停止插件并注销全部运行期任务；之后插件贡献不再可见。
    func stop() async
}

/// 插件启停状态的持久化边界；默认实现落在 UserDefaults。
protocol PluginEnablementStore {
    func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool
    func setEnabled(_ enabled: Bool, for id: PluginID)
}

/// 以 `plugin.<plugin-id>.enabled` 为键保存启停状态。
struct UserDefaultsPluginEnablementStore: PluginEnablementStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool {
        let key = Self.storageKey(for: id)
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for id: PluginID) {
        defaults.set(enabled, forKey: Self.storageKey(for: id))
    }

    private static func storageKey(for id: PluginID) -> String {
        "plugin.\(id.rawValue).enabled"
    }
}
