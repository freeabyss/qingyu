# Task 004：五页设置界面

**目标：** 将当前 11 页设置收敛为通用、快速启动、剪贴板、截图、关于 5 页。

**范围：** 侧栏、路由、页面内容归并、本地化、插件设置页渲染和 UI 测试。

**相关模块：** `SettingsView`、`SettingsViewModel`、`SettingsSource`、`SettingsWindowController`、插件注册表、现有截图设置。

**业务规则：** 通用和关于是固定页面；功能列表是分组标题；快速启动、剪贴板、截图由插件注册独立页面。

**技术约束：** 现有设置值和 Core Data key 保持兼容；关于页继续从 Bundle 读取版本；侧栏顺序固定为通用、功能列表三页、关于。

**验收标准：** 侧栏只出现 5 个可选页面；旧路由映射到正确新页；原 11 页的有效设置均可在新结构找到。

## 文件

- 修改：`Qingniao/Services/SearchEngine/SearchCore.swift`
- 修改：`Qingniao/Services/SearchEngine/SettingsSource.swift`
- 修改：`Qingniao/ViewModels/SettingsViewModel.swift`
- 修改：`Qingniao/Views/Settings/SettingsView.swift`
- 修改：`Qingniao/App/Controllers/AppContainer.swift`
- 修改：`Qingniao/Resources/Localizable.xcstrings`
- 新建：`Qingniao/Plugins/Screenshot/ScreenshotPlugin.swift`
- 新建：`Qingniao/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 测试：`QingniaoTests/SettingsNavigationTests.swift`
- 回归：`QingniaoTests/SettingsServiceTests.swift`、`SettingsSourceTests.swift`、`ReleaseInfoServiceTests.swift`
- UI 测试：`QingniaoUITests/SettingsWindowUITests.swift`

## 页面映射

| 新页面 | 迁入内容 |
|---|---|
| 通用 | Overview 的开机启动；Appearance；Data；Permissions；语言 |
| 快速启动 | Shortcuts 中搜索快捷键；Search Sources；搜索黑名单与结果行为 |
| 剪贴板 | Clipboard；剪贴板快捷键与保留周期 |
| 截图 | Screenshot；截图与贴图快捷键、保存、记录和行为设置 |
| 关于 | About；Updates；Feedback；隐私政策与开源许可 |

## 接口

```swift
enum SettingsPageID: Hashable {
    case general
    case plugin(PluginID)
    case about
}

extension PluginID { static let screenshot = PluginID(rawValue: "screenshot") }

enum SettingsRoute: String, Codable, Hashable {
    case general
    case quickLaunch
    case clipboard
    case screenshot
    case about
}
```

`SettingsViewModel.selectedPage` 改为 `SettingsPageID.general`；路由分别映射到 `.plugin(.quickLaunch)`、`.plugin(.clipboard)`、`.plugin(.screenshot)`。

## 步骤

- [ ] 写失败测试，断言固定页面、插件顺序和路由：

```swift
XCTAssertEqual(viewModel.visiblePageIDs, [
    .general, .plugin(.quickLaunch), .plugin(.clipboard), .plugin(.screenshot), .about
])
viewModel.select(route: .clipboard)
XCTAssertEqual(viewModel.selectedPage, .plugin(.clipboard))
let about = BundleAboutInfoProvider().info
XCTAssertFalse(about.version.isEmpty)
XCTAssertFalse(about.buildNumber.isEmpty)
```
- [ ] 更新 UI 测试，断言侧栏恰好存在 `settings.general`、`settings.quickLaunch`、`settings.clipboard`、`settings.screenshot`、`settings.about`。
- [ ] 运行定向单元与 UI 测试，确认当前 11 页结构导致失败。
- [ ] 实现 `SettingsPageID` 和新路由；移除侧栏搜索框与 11 页枚举，侧栏以两个固定页面包围 `pluginRegistry.settingsPages`。
- [ ] 创建截图插件壳：本任务只注册现有截图设置页，继续调用当前截图入口；Task 009 再替换为统一截图动作、菜单和快捷键贡献。
- [ ] 将各旧页面的控件按映射表搬入 5 个页面；保留现有绑定、确认框和自动保存行为。
- [ ] 删除只服务旧导航的本地化 key，并添加五页标题、功能列表分组标题和 UI 测试标识符。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/SettingsNavigationTests \
  -only-testing:QingniaoTests/SettingsServiceTests \
  -only-testing:QingniaoTests/SettingsSourceTests \
  -only-testing:QingniaoTests/ReleaseInfoServiceTests \
  -only-testing:QingniaoUITests/SettingsWindowUITests
```

- [ ] 递增版本、校验 plist 与 Xcode 字段、运行 `git diff --check`。
- [ ] 提交：`refactor(settings): consolidate navigation into five pages`。
