# 当前产品实现审计

> 审计日期：2026-08-22。自动化结果不替代 macOS 权限、真实截图和全局快捷键的人工验收。

| 范围 | 代码证据 | 自动化证据 | 结论 |
|---|---|---|---|
| 统一搜索 | `SearchService`、`SearchPanelViewModel`、`CommandBarController` | `SearchServiceCoreTests`、`SearchPanelViewModelTests`、`CommandBarUITests` | 自动化通过 |
| 应用、文件与计算 | `AppSearchSource`、`FileSearchSource`、`CalculatorSource` | `AppSearchSourceTests`、`FileSearchSourceTests`、`CalculatorSourceTests` | 自动化通过 |
| 剪贴板历史 | `ClipboardMonitor`、`ClipboardListViewModel`、`ClipboardHistoryWindowController` | `ClipboardListViewModelTests`、`AssistantClipboardRepositoryTests`、`ClipboardWindowUITests` | 自动化通过；真实剪贴板格式恢复待人工验收 |
| 截图与标注 | `ScreenshotService`、`ScreenshotWindowController`、`AnnotationCanvas` | `AnnotationTests`、菜单与入口 UI 测试 | 自动化通过；权限和三种真实截图待人工验收 |
| 内置安全命令 | `SystemCommandSource`、`SystemCommandExecutor` | `SystemCommandSourceTests` | 自动化通过；影响 Finder 和 Dock 的命令待人工验收 |
| 设置、权限与菜单栏 | `SettingsViewModel`、窗口与菜单栏控制器、`GlobalShortcutManager` | `SettingsServiceTests`、`SettingsWindowUITests`、`HotkeyConflictDetectorTests` | 自动化通过；真实全局快捷键和 TCC 待人工验收 |
| 欢迎向导 | `OnboardingView`、`OnboardingViewModel`、`AppDelegate` | `OnboardingViewModelTests`、`OnboardingUITests` | 自动化通过；真实首次授权流程待人工验收 |

## 人工验收项

- 屏幕录制、辅助功能和 Apple Events 权限的真实授权、拒绝、撤销及恢复。
- 全局快捷键在无冲突和有冲突的真实 macOS 会话中的表现。
- 区域、窗口和全屏截图的真实捕获、标注、复制和保存。
- Developer ID 签名、公证及另一台 Mac 的 Gatekeeper 首次启动。

