# Task 004：五页设置界面

**目标：** 将当前 11 页设置收敛为通用、快速启动、剪贴板、截图、关于 5 页。

**范围：** 侧栏、路由、页面内容归并、本地化、插件设置页渲染和 UI 测试。

**相关模块：** `SettingsView`、`SettingsViewModel`、`SettingsSource`、`SettingsWindowController`、插件注册表、现有截图设置。

**业务规则：** 通用和关于是固定页面；功能列表是分组标题；快速启动、剪贴板、截图由插件注册独立页面；语言提供“跟随系统”“简体中文”“English”三项，默认跟随系统，修改后立即切换并保存；跟随系统遇到不支持的语言时回退到 English；数据区域显示清羽全部本地数据占用空间，并仅提供打开数据目录等非破坏性操作，清空剪贴板历史仍只允许在剪贴板页执行；关于页仅提供用户主动触发的更新检查，不执行后台自动联网检查，手动检查打开项目 GitHub Releases 页面供用户查看和下载；开机启动默认开启，向导和通用页修改后立即保存并同步 macOS 登录项。

**技术约束：** 现有设置值和 Core Data key 保持兼容；关于页继续从 Bundle 读取版本；侧栏顺序固定为通用、功能列表三页、关于。

**验收标准：** 侧栏只出现 5 个可选页面；旧路由映射到正确新页；原 11 页的有效设置均可在新结构找到。

## 文件

- 修改：`Qingyu/Services/SearchEngine/SearchCore.swift`
- 修改：`Qingyu/Services/SearchEngine/SettingsSource.swift`
- 修改：`Qingyu/ViewModels/SettingsViewModel.swift`
- 修改：`Qingyu/Views/Settings/SettingsView.swift`
- 修改：`Qingyu/App/Controllers/AppContainer.swift`
- 修改：`Qingyu/Resources/Localizable.xcstrings`
- 新建：`Qingyu/Plugins/Screenshot/ScreenshotPlugin.swift`
- 新建：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 测试：`QingyuTests/SettingsNavigationTests.swift`
- 回归：`QingyuTests/SettingsServiceTests.swift`、`SettingsSourceTests.swift`、`ReleaseInfoServiceTests.swift`
- UI 测试：`QingyuUITests/SettingsWindowUITests.swift`

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
- [ ] 在通用页实现三项语言选择，默认跟随系统；修改后立即刷新界面并持久化设置；系统语言不受支持时验证回退到 English。
- [ ] 关于页保留手动更新检查入口；确认当前版本不注册后台自动更新任务，并将自动联网检查留待后续版本。
- [ ] 关于页手动检查打开 GitHub Releases 页面；不实现应用内自动下载、安装或重启更新。
- [ ] 数据区域显示清羽管理的全部本地数据占用空间，并仅保留打开数据目录；移除或隐藏“清空所有数据/重置数据”入口，清空剪贴板仍由剪贴板页负责。
- [ ] 验证欢迎向导与通用页的开机启动默认开启，修改后即时保存并同步登录项状态。
- [ ] 删除只服务旧导航的本地化 key，并添加五页标题、功能列表分组标题和 UI 测试标识符。
- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu \
  -only-testing:QingyuTests/SettingsNavigationTests \
  -only-testing:QingyuTests/SettingsServiceTests \
  -only-testing:QingyuTests/SettingsSourceTests \
  -only-testing:QingyuTests/ReleaseInfoServiceTests \
  -only-testing:QingyuUITests/SettingsWindowUITests
```

- [ ] 递增版本、校验 plist 与 Xcode 字段、运行 `git diff --check`。
- [ ] 提交：`refactor(settings): consolidate navigation into five pages`。

## 已知实现不一致（待后续修复）

- `SettingsViewModel.applyLanguagePreference()` 当前修改系统语言偏好后显示“需要重启”提示；产品规则要求语言修改后立即切换界面，不应要求重启。
- `SettingsViewModel` 当前仍保留 `autoCheckUpdates` 偏好字段；当前版本不提供后台自动联网检查，因此该偏好不应出现在设置 UI 或触发后台任务，自动检查留待后续版本重新定义。
- `SettingsView` 与 `SettingsViewModel` 当前仍提供“清空所有数据”及重置逻辑；产品规则要求通用页不提供破坏性数据清理，该入口及相关流程需后续移除或迁出本任务范围。
- `SettingsViewModel.refreshStorageUsage()` 当前通过剪贴板仓储统计占用空间；产品规则要求统计清羽管理的全部本地数据，需后续扩展统计范围。
