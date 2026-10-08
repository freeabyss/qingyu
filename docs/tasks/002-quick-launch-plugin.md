# Task 002：快速启动插件

**目标：** 将应用、文件、计算、系统命令和设置搜索源迁入首个第一方插件，证明插件能够提供搜索、动作和设置页。

**范围：** 快速启动插件组装、搜索源聚合、系统命令动作、插件设置页面描述；不调整设置窗口导航。

**相关模块：** `AppSearchSource`、`FileSearchSource`、`CalculatorSource`、`SystemCommandSource`、`SettingsSource`、`SearchService`。

**业务规则：** 搜索排序与 12 条上限保持不变；空查询常用操作根据当前 macOS 环境和用户历史操作频率动态选取，无记录时使用“截图”“剪贴板”“系统设置”作为固定 macOS 基础操作；操作频率记录仅保存在本机，不上传、不跨设备同步、不进入剪贴板历史，也不保存截图内容；不提供清除或重置频率记录入口；文件范围保持 Desktop/Documents/Downloads；统一搜索执行命令不二次确认，其他专用入口执行系统控制命令时显示确认。

**技术约束：** `AppContainer` 只负责注入依赖；快速启动插件负责构造自身搜索源和动作；跨功能动作通过 `PluginActionID` 路由。

**验收标准：** 禁用插件后五类搜索结果全部消失；重新启用后恢复；现有搜索、文件、计算和系统命令测试通过。

## P2 实现默认值

- 高频排序使用本地操作标识、次数和最近使用时间计算；采用 30 天半衰期衰减，避免旧操作永久占据常用位置。
- 频率记录写入应用本地设置或数据目录，不保存查询原文、截图内容或剪贴板内容；并发更新按稳定标识合并。
- 分数相同时按固定来源优先级和稳定标识排序，确保空查询结果不抖动。

## 文件

- 新建：`Qingyu/Plugins/QuickLaunch/QuickLaunchPlugin.swift`
- 新建：`Qingyu/Plugins/QuickLaunch/QuickLaunchSettingsPage.swift`
- 修改：`Qingyu/Services/SearchEngine/SearchCore.swift`
- 修改：`Qingyu/Services/SearchEngine/SystemCommandSource.swift`
- 修改：`Qingyu/App/Controllers/AppContainer.swift`
- 修改：`Qingyu/ViewModels/SearchPanelViewModel.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/QuickLaunchPluginTests.swift`
- 回归：`QingyuTests/SearchServiceCoreTests.swift`、`SystemCommandSourceTests.swift`、`AppSearchSourceTests.swift`、`FileSearchSourceTests.swift`、`CalculatorSourceTests.swift`

## 接口

```swift
extension PluginID { static let quickLaunch = PluginID(rawValue: "quick-launch") }
extension PluginActionID {
    static func quickLaunchCommand(_ commandID: CommandID) -> PluginActionID {
        PluginActionID(rawValue: "quick-launch.command.\(commandID.rawValue)")
    }
}

@MainActor final class QuickLaunchPlugin: QingyuPlugin {
    let manifest: PluginManifest
    func start() async throws {}
    func stop() async {}
}
```

`SearchAction` 新增 `.runPluginAction(PluginActionID)`；应用和文件继续使用现有带参数的强类型 case，每条系统命令映射为一个 `quick-launch.command.*` 动作 ID。

## 步骤

- [ ] 写失败测试：

```swift
let plugin = makeQuickLaunchPlugin()
XCTAssertEqual(plugin.manifest.descriptor.id, .quickLaunch)
XCTAssertEqual(Set(plugin.manifest.searchSources.map(\.id)), [.app, .file, .calculator, .command, .settings])
XCTAssertEqual(plugin.manifest.settingsPage?.id, .quickLaunch)
```

测试内的 `makeQuickLaunchPlugin()` 使用临时 Core Data settings service 和假的 action executor 构造真实 `QuickLaunchPlugin`。

- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu -only-testing:QingyuTests/QuickLaunchPluginTests
```

预期：`QuickLaunchPlugin` 尚不存在，测试编译失败。
- [ ] 实现 `QuickLaunchPlugin`，把来源构造和 `SettingsBackedSearchSource` 包装从 `AppContainer.makeSearchPanelViewModel` 移入插件。
- [ ] 将系统命令改为稳定 `PluginActionID`；危险动作仍由现有确认提供者确认后执行。
- [ ] 让 `SearchService` 从 `pluginRegistry.searchSources` 获取来源；保留剪贴板来源的临时硬编码接线，供 Task 003 迁移。
- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu \
  -only-testing:QingyuTests/QuickLaunchPluginTests \
  -only-testing:QingyuTests/SearchServiceCoreTests \
  -only-testing:QingyuTests/SystemCommandSourceTests \
  -only-testing:QingyuTests/AppSearchSourceTests \
  -only-testing:QingyuTests/FileSearchSourceTests \
  -only-testing:QingyuTests/CalculatorSourceTests
```

- [ ] 加入工程 target，执行版本递增和 plist 校验，运行 `git diff --check`。
- [ ] 提交：`refactor(plugin): migrate quick launch capabilities`。
