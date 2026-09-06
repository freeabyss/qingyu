import Foundation
import os.log

/// 聚合第一方插件贡献的中心注册表（Task 001 / ADR-001）。
///
/// - 只接受代码内注册，不扫描磁盘、不加载外部 Bundle。
/// - 全部 API 在 `@MainActor`；插件启动失败只影响自身，不阻断其他插件。
/// - 贡献可见性规则：已注册 && 已启用 && 未失败 && 未停止。停用即注销贡献。
@MainActor
final class PluginRegistry {
    enum RegistryError: Error, Equatable {
        case duplicatePluginID(PluginID)
        case duplicateActionID(PluginActionID)
        case actionNotAvailable(PluginActionID)
    }

    /// 插件运行期状态；`failed` 表示 `start()` 抛错并被隔离。
    enum PluginState: Equatable {
        case registered
        case started
        case failed
        case stopped
    }

    struct PluginContributions {
        let searchSources: [any SearchSource]
        let settingsPage: PluginSettingsPageDescriptor?
        let menuItems: [PluginMenuItemDescriptor]
        let shortcuts: [PluginShortcutDescriptor]
    }

    private struct Entry {
        let plugin: QingniaoPlugin
        var state: PluginState = .registered
    }

    private var entries: [PluginID: Entry] = [:]
    private var insertionOrder: [PluginID] = []
    private var actionOwners: [PluginActionID: PluginID] = [:]
    private let enablementStore: PluginEnablementStore
    private let logger = Logger.app

    init(enablementStore: PluginEnablementStore = UserDefaultsPluginEnablementStore()) {
        self.enablementStore = enablementStore
    }

    // MARK: - Registration

    /// 注册插件。重复插件 ID 或跨插件重复动作 ID 都会被拒绝。
    func register(_ plugin: QingniaoPlugin) throws {
        let id = plugin.manifest.descriptor.id
        guard entries[id] == nil else {
            throw RegistryError.duplicatePluginID(id)
        }
        for action in plugin.manifest.actions {
            guard actionOwners[action.id] == nil else {
                throw RegistryError.duplicateActionID(action.id)
            }
        }

        entries[id] = Entry(plugin: plugin)
        insertionOrder.append(id)
        for action in plugin.manifest.actions {
            actionOwners[action.id] = id
        }
    }

    // MARK: - Lifecycle

    /// 启动所有默认启用或被用户启用的插件；单个失败只记录并隔离。
    func startAll() async {
        for id in insertionOrder {
            guard let entry = entries[id] else { continue }
            guard enablementStore.isEnabled(id, default: entry.plugin.manifest.descriptor.defaultEnabled) else {
                continue
            }
            await startPlugin(id)
        }
    }

    /// 停止全部已启动插件（应用退出或全量注销时使用）。
    func stopAll() async {
        for id in insertionOrder {
            await stopPlugin(id)
        }
    }

    /// 持久化启停选择，并同步启动或停止对应插件。
    func setEnabled(_ enabled: Bool, for id: PluginID) async {
        guard entries[id] != nil else { return }
        enablementStore.setEnabled(enabled, for: id)
        if enabled {
            await startPlugin(id)
        } else {
            await stopPlugin(id)
        }
    }

    func isEnabled(_ id: PluginID) -> Bool {
        guard let entry = entries[id] else { return false }
        return enablementStore.isEnabled(id, default: entry.plugin.manifest.descriptor.defaultEnabled)
    }

    func state(of id: PluginID) -> PluginState? {
        entries[id]?.state
    }

    func pluginIDs() -> [PluginID] {
        insertionOrder
    }

    private func startPlugin(_ id: PluginID) async {
        guard let entry = entries[id], entry.state != .started else { return }
        do {
            try await entry.plugin.start()
            entries[id]?.state = .started
            logger.info("Plugin started: \(id.rawValue, privacy: .public)")
        } catch {
            entries[id]?.state = .failed
            logger.error("Plugin \(id.rawValue, privacy: .public) failed to start: \(error, privacy: .public)")
        }
    }

    private func stopPlugin(_ id: PluginID) async {
        guard let entry = entries[id] else { return }
        guard entry.state == .started || entry.state == .failed else { return }
        await entry.plugin.stop()
        entries[id]?.state = .stopped
        logger.info("Plugin stopped: \(id.rawValue, privacy: .public)")
    }

    // MARK: - Action routing

    /// 按动作 ID 执行；只有当前可见（所属插件启用且未被隔离）的动作可执行。
    func execute(_ actionID: PluginActionID) async throws {
        guard let ownerID = actionOwners[actionID], isVisible(ownerID),
              let entry = entries[ownerID],
              let action = entry.plugin.manifest.actions.first(where: { $0.id == actionID }) else {
            throw RegistryError.actionNotAvailable(actionID)
        }
        try await action.perform()
    }

    // MARK: - Contributions

    /// 全部可见插件的搜索源（按注册顺序）。
    var searchSources: [any SearchSource] {
        visibleIDs.flatMap { entries[$0]?.plugin.manifest.searchSources ?? [] }
    }

    /// 全部可见插件的设置页，按 `order` 升序。
    var settingsPages: [PluginSettingsPageDescriptor] {
        visibleIDs
            .compactMap { entries[$0]?.plugin.manifest.settingsPage }
            .sorted { $0.order < $1.order }
    }

    /// 全部可见插件的菜单项，按 `order` 升序。
    var menuItems: [PluginMenuItemDescriptor] {
        visibleIDs
            .flatMap { entries[$0]?.plugin.manifest.menuItems ?? [] }
            .sorted { $0.order < $1.order }
    }

    /// 全部可见插件声明的全局快捷键。
    var shortcuts: [PluginShortcutDescriptor] {
        visibleIDs.flatMap { entries[$0]?.plugin.manifest.shortcuts ?? [] }
    }

    /// 按插件查询当前可见贡献；插件被停用、失败或未知时返回 `nil`。
    func contributions(of id: PluginID) -> PluginContributions? {
        guard let entry = entries[id], isVisible(id) else { return nil }
        return PluginContributions(
            searchSources: entry.plugin.manifest.searchSources,
            settingsPage: entry.plugin.manifest.settingsPage,
            menuItems: entry.plugin.manifest.menuItems,
            shortcuts: entry.plugin.manifest.shortcuts
        )
    }

    /// 按插件查询当前可见的搜索源。
    func searchSources(of id: PluginID) -> [any SearchSource] {
        contributions(of: id)?.searchSources ?? []
    }

    private var visibleIDs: [PluginID] {
        insertionOrder.filter { isVisible($0) }
    }

    private func isVisible(_ id: PluginID) -> Bool {
        guard let entry = entries[id] else { return false }
        guard entry.state != .failed, entry.state != .stopped else { return false }
        return isEnabled(id)
    }
}
