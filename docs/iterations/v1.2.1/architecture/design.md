# v1.2.1 架构设计：欢迎页路由 bug 修复 + 关闭按钮

> 关联 PRD：`doc/iterations/v1.2.1/prd.md`　基线：v1.2.0（8821b92）　Issue：#7
> 范围：仅 Onboarding 呈现与门禁逻辑，不改动业务功能本身。

## 一、问题与根因（复述 PRD §2）

- **Bug 1（P0）**：所有功能入口被 onboarding 门禁劫持，`ensureOnboardingGate()` 在 `isOnboardingCompleted == false` 时强制 `makeKeyAndOrderFront` 欢迎窗并 `return false`，导致 5 个 controller 的 `guard container.ensureOnboardingReady() else { return }` 全部静默返回。又因 Bug 2 让 onboarding 永远无法完成，形成“点什么都是欢迎页”死循环。
- **Bug 2（P1）**：`OnboardingView` 根 VStack `.frame(width: 720, height: 520)` 固定高度 + 承载窗口 `contentRect` 同样 520pt + 无 `ScrollView`，内容自然高度约 780–820pt 溢出，footer（「跳过设置」「开始使用」）被裁到可视区外。

两个 Bug 互为因果：Bug 2 是根因，Bug 1 是症状。必须一并修复。

## 二、影响模块（改动清单）

| 模块 | 文件 | 改动性质 |
|------|------|---------|
| Onboarding 视图 | `Qingyu/Views/Onboarding/OnboardingView.swift` | 布局重构（Bug 2） |
| App 生命周期 | `Qingyu/App/AppDelegate.swift` | 门禁移除 + 引用清理 + 服务幂等 + 菜单接线 |
| DI 根 | `Qingyu/App/Controllers/AppContainer.swift` | 移除 `onboardingGate` / `ensureOnboardingReady()` 死接口 |
| 命令栏 | `Qingyu/App/Controllers/CommandBarController.swift` | 移除门禁 guard（toggle/show） |
| 剪贴板窗口 | `Qingyu/App/Controllers/ClipboardHistoryWindowController.swift` | 移除门禁 guard |
| 设置窗口 | `Qingyu/App/Controllers/SettingsWindowController.swift` | 移除门禁 guard |
| 截图窗口 | `Qingyu/App/Controllers/ScreenshotWindowController.swift` | 移除门禁 guard |
| 全局快捷键 | `Qingyu/Services/Hotkey/GlobalShortcutManager.swift` | 移除门禁 guard（冗余） |
| 菜单栏 | `Qingyu/App/Controllers/StatusItemController.swift` | 新增“欢迎向导”入口 |
| 文案 | `Qingyu/Resources/Localizable.xcstrings` | 新增 `menubar.onboarding` |

无数据模型变更、无 Core Data migration、无新依赖、无接口签名变更（仅删除内部死接口）。

## 三、详细设计

### 3.1 Bug 2：Onboarding 布局（AC-06 / AC-07 / AC-10）

**约束**：PRD §9.4 P-06 与 D-116 规定 Onboarding 单屏 720×520，不改窗口尺寸。PRD §4.2 方案①（推荐）：`ScrollView` 包裹中部可变内容，footer 固定吸底。

**结构**（`OnboardingView.body`）：

```
VStack(spacing: x6) {
    header                      // 固定顶部（bird + 标题 + 副标题）
    ScrollView {                // 中部可滚动
        VStack(spacing: x6) {
            configCards
            screenRecordingSection
            accessibilitySection
        }
        .frame(maxWidth: .infinity)
    }
    footer                      // 固定吸底（错误提示 + 跳过/开始/隐私）
}
.jadePadding(.x8)
.frame(width: 720, height: 520)
.background(JadeColor.surface1)
.jadeRadius(.xl)
.jadeShadow(.xl, radius: .xl)
```

- 删除原 `Spacer(minLength: 0)`——其“把 footer 推到底”的职责由 `ScrollView` 自动占据中部剩余空间承担。
- header / footer 不进 ScrollView，保证任意字号下 footer 恒定可见可点（AC-06/07）。
- 中部内容默认字号下不滚动（高度足够），放大字号下可滚动（AC-10“纵向若超高则可滚动”）。
- `.frame(maxWidth: .infinity)` 保证横向不裁剪（AC-10“720pt 宽窗口内不被横向裁剪”）。
- 外层 `.jadePadding(.x8)`（32pt）保持，圆角/阴影 token 不变。

**不改**：`OnboardingViewModel`、`canStart` 规则、`start()`/`skipOnboarding()` 语义、二次确认 Alert、辅助功能按需申请——全部沿用 v1.1/v1.2 既有实现（PRD §6 风险项）。

### 3.2 Bug 1：门禁移除（AC-02 ~ AC-05、AC-11）

**决策**：彻底移除门禁对功能入口的劫持。理由：
- PRD §4.1：“门禁不得劫持功能入口”“未完成时若用户关掉欢迎窗，需有明确路径重新进入（菜单入口），而不是靠‘点任意功能被动弹回’”。
- 保留门禁“阻止但不弹回”会让用户点击无反应，体验更差且不符合 AC-02~05“完成后可用”的放行语义。
- 移除后功能入口始终可用；onboarding 仅作为首启引导，不再阻塞功能。

**改动**：
1. 删除 5 个 controller 与 `GlobalShortcutManager` 中的 `guard container.ensureOnboardingReady() else { return }`。
2. 删除 `AppContainer.onboardingGate` 属性与 `ensureOnboardingReady()` 方法（死代码，符合 D-106 清理精神）。
3. 删除 `AppDelegate.ensureOnboardingGate()` 与 `container.onboardingGate = …` 安装行。
4. `AppDelegate.applicationDidFinishLaunching` 首启逻辑不变：`isOnboardingCompleted` 为假则 `showOnboardingWindow()`，为真则 `startFullExperienceServices()`。

**边界**：首启未完成 onboarding 时用户若直接用功能，`startFullExperienceServices()` 尚未调用——剪贴板监听未启动、全局快捷键未注册。此为可接受边界：
- 菜单「打开搜索」/「设置」/「关于」不依赖运行时服务，可用。
- 「剪贴板」窗口可打开，显示空态（FR §9.7）。
- 「截图」走既有 `ensureScreenRecordingPermission()`，无权限走提示而非欢迎页（AC-04）。
- 用户随时可经菜单「欢迎向导」完成 onboarding，随后服务启动。

### 3.3 欢迎窗引用清理（PRD §2.1 补充 / §4.1 防再次被困）

`AppDelegate` 声明 `NSWindowDelegate`，`showOnboardingWindow()` 设置 `window.delegate = self`，实现：

```swift
func windowWillClose(_ notification: Notification) {
    if (notification.object as? NSWindow) === onboardingWindow {
        onboardingWindow = nil
    }
}
```

效果：用户点标题栏红色关闭按钮 `close()` 后引用被清理，下次门禁（已移除）或菜单入口重新 `showOnboardingWindow()` 走全新创建路径，不会 `makeKeyAndOrderFront` 拉回僵尸窗口。`isOnboardingCompleted` 不因关闭而改变（AC-11）。

### 3.4 菜单“欢迎向导”入口（AC-11）

- `StatusItemController` 新增 `var onShowOnboarding: (() -> Void)?`，仿 `onStartScreenshot` 模式。
- `makeMenu()` 在「关于」之后、「退出」分隔符前新增「欢迎向导」菜单项（`menubar.onboarding`），`@objc openOnboardingFromMenu()` 调用 `onShowOnboarding?()`。
- `AppDelegate.applicationDidFinishLaunching` 设置 `container.statusItemController.onShowOnboarding = { [weak self] in self?.showOnboardingWindow() }`。
- 此路径打开的欢迎页：`showOnboardingWindow()` 不改 `isOnboardingCompleted`；用户若再次点「开始使用」/「跳过设置」会再次 `markCompleted()`（仅刷新时间戳，布尔态不变），`onComplete` 关窗 + 幂等启动服务。重启仍不自动弹出（AC-11）。

**菜单清单影响**：D-028 基线菜单为 6 项（打开搜索/剪贴板/截图/设置/关于/退出）。本次新增“欢迎向导”为 PRD §4.3 明确建议的 bug 修复路径，不视为违反 MVP 菜单基线，而在 v1.2.1 迭代内追加。

### 3.5 服务启动幂等

`startFullExperienceServices()` 在 `AppDelegate` 内加 `hasStartedFullExperience` 守卫，确保菜单再次完成 onboarding 时不重复 `startClipboardMonitoring()` / `cleanupService.start()` / `setupShortcuts()`：

```swift
private var hasStartedFullExperience = false
private func startFullExperienceServices() {
    guard !hasStartedFullExperience else { return }
    hasStartedFullExperience = true
    container.startFullExperienceServices()
    container.globalShortcutManager.setupShortcuts()
}
```

`onComplete` 闭包统一为：置 `isOnboardingCompleted = true` → 关窗 → 置 nil → `startFullExperienceServices()`（幂等）。

### 3.6 L10n

新增 `menubar.onboarding`：
- zh-Hans：欢迎向导
- en：Welcome Guide

沿用既有 `onboarding.start` / `onboarding.skip` / `onboarding.skip.confirm.*`，不新增其他文案键。

## 四、验收标准映射

| AC | 满足方式 |
|----|---------|
| AC-01 首启显示欢迎页 | `applicationDidFinishLaunching` 首启分支不变 |
| AC-02~05 完成后各入口可用 | 移除门禁 guard，各入口直走自身逻辑 |
| AC-06 「开始使用」可见可点 | ScrollView 布局，footer 吸底 |
| AC-07 「跳过设置」可见可点 + 二次确认 | 同上，Alert 沿用 |
| AC-08 完成后关窗 + 驻留 + 启动服务 | `onComplete` + 幂等 `startFullExperienceServices` |
| AC-09 重启不自动弹 | `loadOnboardingCompletionState()` 不变 |
| AC-10 720 宽不横裁 / 纵超高可滚 / footer 可达 | ScrollView + maxWidth:.infinity |
| AC-11 菜单主动打开不改变已完成态 | 「欢迎向导」入口 + `showOnboardingWindow` 不改状态 |
| AC-12 未授权+未跳过时开始禁用、跳过可用 | `canStart` 规则不变 |

## 五、风险与回归

- **v1.1.0 死锁修复回归**：不改 `canStart` / `requestScreenRecording()` / `skipScreenshot()` / `skipOnboarding()` / 二次确认，语义保留（PRD §6）。
- **持久化 key 一致性**：`SettingKey.onboardingCompletedAt` / legacy `onboardingCompleted` / `loadOnboardingCompletionState()` 读取路径不变（PRD §6）。
- **测试**：`OnboardingViewModelTests` 仅覆盖 ViewModel，本改动在 View/Controller/AppDelegate 层，不破坏既有用例；`canStart`/`start`/`skip` 行为不变。
- **Sparkle/更新**：`updateService.setup()` 在 `applicationDidFinishLaunching` 末尾无条件调用，本次不触及（PRD §6）。

## 六、不做的事

- 不改窗口尺寸（保持 720×520，P-06）。
- 不改 onboarding 配置项内容、权限段顺序、文案。
- 不改数据模型、存储栈、搜索源、截图子系统。
- 不实现 PRD §4.2 方案②（提高窗口高度）——方案①已满足 AC。
