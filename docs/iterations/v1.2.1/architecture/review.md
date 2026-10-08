# v1.2.1 架构评审

> 评审对象：`doc/iterations/v1.2.1/architecture/design.md` + 实现 diff
> 基线：v1.2.0（8821b92）　Issue：#7　日期：2026-07-13

## 评审结论

**APPROVED**（开发自评；leader 独立评审待 ⑥ 上线前确认）。

改动聚焦、无跨层影响、无接口签名变更、无数据模型变更、无新依赖，符合 v1.2.1「紧急缺陷修复、仅涉及 Onboarding 呈现与门禁逻辑」的迭代边界（PRD §1）。

## 改动清单核对

| 设计项 | 文件 | 状态 |
|--------|------|------|
| Bug 2 布局：ScrollView 包裹中部 + footer 吸底 | `OnboardingView.swift` | ✅ 保持 720×520，删除 `Spacer` |
| Bug 1 门禁移除：5 controller + GlobalShortcutManager guard | `CommandBarController` / `ClipboardHistoryWindowController` / `SettingsWindowController` / `ScreenshotWindowController` / `GlobalShortcutManager` | ✅ 6 处 guard 全删 |
| 死接口清理 | `AppContainer.swift` | ✅ 删 `onboardingGate` / `ensureOnboardingReady()` |
| AppDelegate 门禁移除 + 引用清理 | `AppDelegate.swift` | ✅ 删 `ensureOnboardingGate()`；实现 `NSWindowDelegate.windowWillClose` |
| 服务幂等 | `AppDelegate.swift` | ✅ `hasStartedFullExperience` 守卫 |
| 菜单「欢迎向导」入口 | `StatusItemController.swift` + `Localizable.xcstrings` | ✅ `onShowOnboarding` 闭包 + 菜单项 + `menubar.onboarding`（中/英） |

## AC 映射核对（PRD §5）

| AC | 验证方式 | 结果 |
|----|---------|------|
| AC-01 首启显示欢迎页 | 代码审查：`applicationDidFinishLaunching` 首启分支不变 | ✅ 代码层满足；端到端待手动验证 |
| AC-02 完成后「打开搜索」可用 | 代码审查：`CommandBarController.show` 移除 guard | ✅ |
| AC-03 完成后「剪贴板」可用 | 代码审查：`ClipboardHistoryWindowController.show` 移除 guard | ✅ |
| AC-04 完成后「截图」走截图流程/权限提示 | 代码审查：`performCapture` 移除 guard，`ensureScreenRecordingPermission` 保留 | ✅ |
| AC-05 完成后「设置/关于」可用 | 代码审查：`SettingsWindowController.show` 移除 guard | ✅ |
| AC-06 「开始使用」可见可点 | 代码审查：footer 吸底，不进 ScrollView | ✅ 代码层满足；放大字号待手动验证 |
| AC-07 「跳过设置」可见可点 + 二次确认 | 代码审查：同上，Alert 沿用 v1.1 | ✅ |
| AC-08 完成后关窗 + 驻留 + 启动服务 | 代码审查：`onComplete` + 幂等 `startFullExperienceServices` | ✅ |
| AC-09 重启不自动弹 | 代码审查：`loadOnboardingCompletionState()` 不变 | ✅ |
| AC-10 720 宽不横裁 / 纵超高可滚 / footer 可达 | 代码审查：`ScrollView` + `.frame(maxWidth: .infinity)` | ✅ 代码层满足；待手动验证 |
| AC-11 菜单主动打开不改变已完成态 | 代码审查：`onShowOnboarding` → `showOnboardingWindow` 不改 `isOnboardingCompleted` | ✅ |
| AC-12 未授权+未跳过时开始禁用、跳过可用 | 单元测试 `OnboardingViewModelTests`（既有） | ✅ |

## 编译与测试

- `swift build`：Build complete（含全部改动文件）。
- `swift test`：**159/159 passed，0 failures**（与 v1.2.0 基线一致，无回归）。
- `xcodebuild -scheme Qingyu -configuration Debug build`：EXIT=0，0 errors，产物 `Qingyu.app` 重新链接（二进制时间戳已更新）。仅有 2 个 pre-existing Swift 6 mode warning（`HotkeyConflictDetector` / `AppSetting`，与本次改动无关，v1.2.0 即存在）。

## 风险与回归确认

- **v1.1.0 死锁修复未破坏**：`OnboardingViewModel.canStart` / `requestScreenRecording()` / `skipScreenshot()` / `skipOnboarding()` / 二次确认 Alert 全部未改，`OnboardingViewModelTests` 全绿。
- **持久化 key 一致性**：`SettingKey.onboardingCompletedAt` / legacy `onboardingCompleted` / `loadOnboardingCompletionState()` 读取路径未改。
- **菜单清单**：D-028 基线 6 项之外新增「欢迎向导」，为 PRD §4.3 明确建议的 bug 修复路径，迭代内追加，不视为违反 MVP 基线。
- **服务启动时机**：保持「完成 onboarding 后启动」（PRD §4.1）。未完成 onboarding 时功能入口可用但剪贴板监听/全局快捷键未启动--可接受边界，用户可经菜单「欢迎向导」完成 onboarding 后启动。

## 遗留（⑥ 上线前）

1. **手动 AC 端到端验证**：AC-01/06/07/10 涉及运行时布局与首启行为，需在真实环境（默认字号 + 放大字号 + 明暗模式）启动 app 手动确认。
2. **⑥ 上线部署**：Release 构建 + Developer ID 签名 + notarytool 公证 + staple + GitHub Releases（沿用 start.sh `build_for_release`，需 `DEVELOPER_ID_APP` / `AC_NOTARY_PROFILE` 环境变量）。

## 诚实标注

- 本次架构评审为开发自评，非 leader 独立评审会。建议 ⑥ 上线前由 leader 复核 design.md + diff + 本评审。
- 布局类 AC（06/07/10）的端到端验证依赖手动启动 app，未在本次自动化中覆盖。
