# Task 009：插件集成、回归与发布检查

**目标：** 将截图能力注册为第三个第一方插件，删除旧三截图链路，并完成端到端、版本和发布验收。

**范围：** 截图插件、菜单栏、快捷键、搜索命令、应用生命周期、设置接线、旧 API 清理、全量回归和人工验收。

**相关模块：** Tasks 001–008 的全部产物、`AppDelegate`、`AppContainer`、`StatusItemController`、`GlobalShortcutManager`。

**业务规则：** 所有入口进入统一截图状态；菜单栏显示“截图”；F1 开始截图；F3 贴图/恢复；⇧F3 隐藏/显示贴图；系统控制内置命令包含重启 Finder、重启 Dock、重启系统、关机和注销；从统一搜索执行任何内置命令均直接运行，不显示二次确认，回车、鼠标点击和结果快捷键均遵循该规则，高风险命令显示风险提示或危险图标；重启系统、关机和注销立即调用 macOS 系统动作，不提供延时、定时或撤销；命令失败在结果区域显示错误，Apple Events 被拒绝时命令不可用并提供授权、重新检测和系统设置入口；其他专用入口执行系统控制命令时显示动作专属确认对话框，默认焦点为“取消”，取消后不执行且不改变命令状态。

**技术约束：** 应用启动按注册顺序激活插件，退出按逆序停止；截图插件声明屏幕录制权限并在欢迎向导阶段主动请求；测试不依赖真实 TCC 授权。

**验收标准：** 三个插件均由注册表提供贡献；代码中不再存在独立区域/窗口/全屏入口；全量自动化通过；真实多屏、权限、快捷键、签名和公证有记录。

## 文件

- 修改：`Qingniao/Plugins/Screenshot/ScreenshotPlugin.swift`
- 修改：`Qingniao/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 修改：`Qingniao/App/Controllers/AppContainer.swift`
- 修改：`Qingniao/App/AppDelegate.swift`
- 修改：`Qingniao/App/Controllers/StatusItemController.swift`
- 修改：`Qingniao/Services/Hotkey/GlobalShortcutManager.swift`
- 修改：`Qingniao/Services/Hotkey/HotkeyConflictDetector.swift`
- 修改：`Qingniao/Utilities/KeyboardShortcuts+Names.swift`
- 修改：`Qingniao/Services/SearchEngine/SystemCommandSource.swift`
- 修改：`Qingniao/Services/SearchEngine/SearchCore.swift`
- 修改：`Qingniao/Resources/Localizable.xcstrings`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 修改：`docs/test/cases.md`、`docs/test/report.md`、`docs/test/implementation-audit.md`
- 测试：`QingniaoTests/ScreenshotPluginTests.swift`
- UI 测试：`QingniaoUITests/MenuDispatchUITests.swift`、`CommandBarUITests.swift`、`SettingsWindowUITests.swift`、`ScreenshotOverlayUITests.swift`、`PinWindowUITests.swift`

## 接口

```swift
extension PluginActionID {
    static let startScreenshot = PluginActionID(rawValue: "screenshot.start")
    static let pinClipboard = PluginActionID(rawValue: "screenshot.pin-clipboard")
    static let togglePins = PluginActionID(rawValue: "screenshot.toggle-pins")
    static let togglePinPassthrough = PluginActionID(rawValue: "screenshot.toggle-pin-passthrough")
}
```

Screenshot plugin manifest 提供一个设置页、一个菜单项、四个动作、F1/F3/⇧F3 与用户录制的鼠标穿透快捷键，并声明 `.screenRecording`。

## 步骤

- [ ] 写失败测试，断言截图贡献及三个插件顺序：

```swift
XCTAssertEqual(plugin.manifest.descriptor.id, .screenshot)
XCTAssertEqual(plugin.manifest.requiredPermissions, [.screenRecording])
XCTAssertEqual(plugin.manifest.settingsPage?.id, .screenshot)
XCTAssertEqual(registry.settingsPages.map(\.id), [.quickLaunch, .clipboard, .screenshot])
XCTAssertEqual(plugin.manifest.shortcuts.map(\.actionID), [
    .startScreenshot, .pinClipboard, .togglePins, .togglePinPassthrough
])
```
- [ ] 更新搜索与菜单 UI 测试，只断言一个“截图”入口；验证空查询常用操作按 macOS 环境和用户历史操作频率动态选取；更新快捷键测试为 F1/F3/⇧F3。
- [ ] 验证 14 项内置命令均已登记；统一搜索通过回车、鼠标点击或结果快捷键直接执行，重启系统/关机/注销显示风险图标，重启 Finder/重启 Dock 不显示风险图标；菜单栏、设置或其他专用入口执行系统控制命令时显示二次确认。
- [ ] 验证新增系统控制命令的中英文名称、中文拼音和拼音首字母搜索；别名只参与匹配，不改变结果显示名称或执行动作。
- [ ] 验证空查询“常用操作”将截图与系统控制命令置于同一列表，不按风险等级拆分分区；高风险命令仍显示风险图标。
- [ ] 实现 `ScreenshotPlugin`，让菜单、搜索、快捷键和 UITest trigger 都执行 `.startScreenshot`。
- [ ] 从 `ScreenshotServiceProtocol`、`ScreenshotWindowController`、`SearchAction`、`SystemCommandSource`、通知和快捷键定义中删除 region/window/fullScreen 三套入口及兼容适配。
- [ ] `AppDelegate` 启动时注册三个插件；完成或跳过欢迎向导后启动需要后台服务的插件；退出时调用 `pluginRegistry.stopAll()` 并注销全局快捷键。
- [ ] 执行全量自动化：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao
```

预期：QingniaoTests 与 QingniaoUITests 全部 PASS。

- [ ] 在至少两台显示器上人工验证：跨屏窗口高亮、拖拽区域、`⌘A` 当前屏全屏、左下角提示、Retina/负坐标、截图完成与取消。
- [ ] 人工验证屏幕录制和辅助功能权限拒绝/授权/撤销；拒绝或暂不授权时仍可点击“开始使用”进入应用，受影响入口显示权限缺失并提供授权/重新检测/系统设置；验证 Apple Events 仅在首次执行相关内置命令前按需请求，拒绝后命令不可用；另验证 F1/F3/⇧F3 冲突与重录，贴图跨 Space 和全屏应用。

## 已知实现不一致（待后续修复）

- 当前欢迎向导实现已主动请求屏幕录制权限，但尚未主动请求辅助功能权限；需按产品规则补齐向导阶段请求，同时保持拒绝后仍可进入应用。
- 当前 `SystemCommandSource` 仅登记并执行重启 Finder、重启 Dock，代码注释仍声明不支持关机、重启系统和注销；需按当前 PRD 新增三项命令、风险标识及非统一搜索入口的确认流程。
- 当前截图插件仍按区域、窗口、全屏分别暴露入口或动作；需收敛为单一“截图”入口，并在截图状态内根据指针位置与鼠标操作自动判定模式。
- [ ] 更新测试文档，每条 PRD 规则记录自动化用例或人工证据。
- [ ] 运行 `./scripts/bump-version.sh --bump` 与：

```bash
plutil -lint Qingniao/Info.plist
test "$(plutil -extract CFBundleShortVersionString raw Qingniao/Info.plist)" = \
  "$(rg -o 'MARKETING_VERSION = [^;]+' Qingniao.xcodeproj/project.pbxproj | head -1 | awk '{print $3}')"
```

- [ ] 构建 Release，完成 Developer ID 签名、公证和另一台 Mac 的 Gatekeeper 首次启动验证。
- [ ] 运行 `git diff --check` 后提交：`feat(app): integrate first-party plugins and unified capture`。
