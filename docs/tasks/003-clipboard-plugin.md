# Task 003：剪贴板插件

**目标：** 将剪贴板搜索、监听生命周期、历史窗口入口、菜单、快捷键和设置页迁入第一方插件。

**范围：** 剪贴板插件接线；保留现有数据仓库、索引和窗口实现。

**相关模块：** `ClipboardMonitor`、`ClipboardService`、`AssistantClipboardSource`、`ClipboardHistoryWindowController`、`AppContainer`。

**业务规则：** 剪贴板记录默认开启，默认保留 30 天，记录文件引用；用户可在欢迎向导或剪贴板设置页暂停/恢复；统一搜索、菜单栏或快捷键打开“剪贴板”时激活窗口、清空上次搜索关键词并聚焦搜索框；删除和清空行为保持不变；插件停用时停止监听但保留历史与设置。

**技术约束：** `start()` 和 `stop()` 幂等；监控 Task 由插件持有并取消；数据栈仍由应用核心初始化。

## 已知实现不一致（待后续修复）

- 当前剪贴板窗口可激活但未保证通过统一搜索、菜单栏或快捷键打开时清空上次搜索关键词并自动聚焦搜索框；需按 PRD 补齐打开行为。

**验收标准：** 启用时只创建一个监听 Task；停用后不接收新事件；历史窗口和搜索动作仍使用同一仓库。

## 文件

- 新建：`Qingyu/Plugins/Clipboard/ClipboardPlugin.swift`
- 新建：`Qingyu/Plugins/Clipboard/ClipboardSettingsPage.swift`
- 修改：`Qingyu/App/Controllers/AppContainer.swift`
- 修改：`Qingyu/App/AppDelegate.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/ClipboardPluginTests.swift`
- 回归：`QingyuTests/ClipboardMonitorTests.swift`、`AssistantClipboardRepositoryTests.swift`、`ClipboardListViewModelTests.swift`

## 接口

```swift
extension PluginID { static let clipboard = PluginID(rawValue: "clipboard") }
extension PluginActionID {
    static let openClipboardHistory = PluginActionID(rawValue: "clipboard.open-history")
    static let toggleClipboardRecording = PluginActionID(rawValue: "clipboard.toggle-recording")
    static let clearClipboardHistory = PluginActionID(rawValue: "clipboard.clear-history")
}

@MainActor final class ClipboardPlugin: QingyuPlugin {
    let manifest: PluginManifest
    private var monitorTask: Task<Void, Never>?
    func start() async throws
    func stop() async
}
```

## 步骤

- [ ] 写失败测试，使用假的 monitor event stream 验证幂等生命周期与贡献：

```swift
try await plugin.start()
try await plugin.start()
XCTAssertEqual(monitor.startCallCount, 1)
XCTAssertEqual(plugin.manifest.settingsPage?.id, .clipboard)
XCTAssertEqual(plugin.manifest.searchSources.map(\.id), [.clipboard])
await plugin.stop()
XCTAssertEqual(monitor.stopCallCount, 1)
```

- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu -only-testing:QingyuTests/ClipboardPluginTests
```

预期：`ClipboardPlugin` 尚不存在，测试编译失败。
- [ ] 把 `AppContainer.startClipboardMonitoring()` 和 `monitorTask` 移入 `ClipboardPlugin`，由构造器注入 repository、resource store、settings service 和历史窗口动作。
- [ ] 将 `AssistantClipboardSource` 加入插件 manifest；从 `makeSearchPanelViewModel` 删除临时硬编码来源。
- [ ] 让应用完成或跳过欢迎向导后调用 `pluginRegistry.start(.clipboard)`；退出时由 `stopAll()` 停止监听。
- [ ] 验证剪贴板记录默认开启，欢迎向导和剪贴板设置页均可暂停/恢复，状态即时保存。
- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu \
  -only-testing:QingyuTests/ClipboardPluginTests \
  -only-testing:QingyuTests/ClipboardMonitorTests \
  -only-testing:QingyuTests/AssistantClipboardRepositoryTests \
  -only-testing:QingyuTests/ClipboardListViewModelTests
```

- [ ] 加入工程 target，递增版本并校验，运行 `git diff --check`。
- [ ] 提交：`refactor(plugin): migrate clipboard lifecycle and contributions`。
