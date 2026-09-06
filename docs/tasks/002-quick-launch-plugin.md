# Task 002：快速启动插件

**目标：** 将应用、文件、计算、系统命令和设置搜索源迁入首个第一方插件，证明插件能够提供搜索、动作和设置页。

**范围：** 快速启动插件组装、搜索源聚合、系统命令动作、插件设置页面描述；不调整设置窗口导航。

**相关模块：** `AppSearchSource`、`FileSearchSource`、`CalculatorSource`、`SystemCommandSource`、`SettingsSource`、`SearchService`。

**业务规则：** 搜索排序与 12 条上限保持不变；文件范围保持 Desktop/Documents/Downloads；受控命令继续执行确认规则。

**技术约束：** `AppContainer` 只负责注入依赖；快速启动插件负责构造自身搜索源和动作；跨功能动作通过 `PluginActionID` 路由。

**验收标准：** 禁用插件后五类搜索结果全部消失；重新启用后恢复；现有搜索、文件、计算和系统命令测试通过。

## 文件

- 新建：`Qingniao/Plugins/QuickLaunch/QuickLaunchPlugin.swift`
- 新建：`Qingniao/Plugins/QuickLaunch/QuickLaunchSettingsPage.swift`
- 修改：`Qingniao/Services/SearchEngine/SearchCore.swift`
- 修改：`Qingniao/Services/SearchEngine/SystemCommandSource.swift`
- 修改：`Qingniao/App/Controllers/AppContainer.swift`
- 修改：`Qingniao/ViewModels/SearchPanelViewModel.swift`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 测试：`QingniaoTests/QuickLaunchPluginTests.swift`
- 回归：`QingniaoTests/SearchServiceCoreTests.swift`、`SystemCommandSourceTests.swift`、`AppSearchSourceTests.swift`、`FileSearchSourceTests.swift`、`CalculatorSourceTests.swift`

## 接口

```swift
extension PluginID { static let quickLaunch = PluginID(rawValue: "quick-launch") }
extension PluginActionID {
    static func quickLaunchCommand(_ commandID: CommandID) -> PluginActionID {
        PluginActionID(rawValue: "quick-launch.command.\(commandID.rawValue)")
    }
}

@MainActor final class QuickLaunchPlugin: QingniaoPlugin {
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
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao -only-testing:QingniaoTests/QuickLaunchPluginTests
```

预期：`QuickLaunchPlugin` 尚不存在，测试编译失败。
- [ ] 实现 `QuickLaunchPlugin`，把来源构造和 `SettingsBackedSearchSource` 包装从 `AppContainer.makeSearchPanelViewModel` 移入插件。
- [ ] 将系统命令改为稳定 `PluginActionID`；危险动作仍由现有确认提供者确认后执行。
- [ ] 让 `SearchService` 从 `pluginRegistry.searchSources` 获取来源；保留剪贴板来源的临时硬编码接线，供 Task 003 迁移。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/QuickLaunchPluginTests \
  -only-testing:QingniaoTests/SearchServiceCoreTests \
  -only-testing:QingniaoTests/SystemCommandSourceTests \
  -only-testing:QingniaoTests/AppSearchSourceTests \
  -only-testing:QingniaoTests/FileSearchSourceTests \
  -only-testing:QingniaoTests/CalculatorSourceTests
```

- [ ] 加入工程 target，执行版本递增和 plist 校验，运行 `git diff --check`。
- [ ] 提交：`refactor(plugin): migrate quick launch capabilities`。
