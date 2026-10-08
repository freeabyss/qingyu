# v1.2.1 PRD：欢迎页面路由 bug 修复 + 关闭按钮

> 关联 Issue：#7　分支：v1.2.1　基线：v1.2.0（8821b92）
> 本次是 v1.2.0 上线后的紧急缺陷修复迭代，仅涉及 Onboarding（欢迎页）呈现与门禁逻辑，不改动业务功能本身。

## 1. Bug 描述与复现

### Bug 1（P0 阻塞）：所有功能入口都跳到欢迎页
- **复现步骤**：
  1. 全新安装（或清除数据）后首次启动清羽。
  2. 点击菜单栏图标，在弹出菜单中点击「打开搜索」/「剪贴板」/「截图」/「设置…」/「关于」任意一项。
- **实际行为**：无论点哪一项，弹出的都是欢迎（Onboarding）页面，对应的搜索面板 / 剪贴板窗口 / 截图 / 设置窗口都打不开。
- **预期行为**：各入口应各自打开对应面板/窗口；欢迎页仅在首次启动引导阶段出现，或用户主动触发时出现。

### Bug 2（P1）：欢迎页无可见的关闭/开始按钮
- **复现步骤**：首次启动进入欢迎页后，尝试完成引导或关闭该页。
- **实际行为**：欢迎页底部的「开始使用」「跳过设置」按钮不可见（被裁剪在窗口可视区域之外），用户无法完成或退出引导；即便点系统标题栏红色关闭按钮，下次点击任意菜单项又会把欢迎页重新拉起。
- **预期行为**：欢迎页底部有清晰可见、可点击的「开始使用」（主）与「跳过设置」（次）按钮；点击后引导结束、永久不再自动弹出。

### 两个 Bug 的关系（关键）
Bug 2 是根因、Bug 1 是可见症状：因为「开始使用」被裁剪到屏幕外，用户**永远无法完成 onboarding**；而所有功能入口都被 onboarding 门禁拦截并强制重新弹出欢迎页 —— 于是表现为"点什么都是欢迎页"。两者必须一并修复。

## 2. 根因分析

### 2.1 Bug 1 根因：所有入口都被 onboarding 门禁拦截，且门禁永远无法解锁

真实根因是**门禁（gate）设计 + 无法完成引导**的叠加，而不是路由 mapping 写错。逐条追踪：

1. `Qingyu/App/AppDelegate.swift:38-42`：启动时若 `isOnboardingCompleted == false`（首启）则 `showOnboardingWindow()`，并在 `:32` 安装门禁闭包
   `container.onboardingGate = { self.ensureOnboardingGate() }`。
2. `AppContainer.swift:60` 定义 `var onboardingGate: () -> Bool`，`:69` `ensureOnboardingReady()` 转发调用。
3. **每一个功能入口在动作开头都做门禁 guard**，未完成引导时直接 `return` 并转而弹回欢迎窗：
   - 搜索：`CommandBarController.swift:41`（toggle）与 `:50`（show）`guard container.ensureOnboardingReady() else { return }`
   - 剪贴板：`ClipboardHistoryWindowController.swift:25`
   - 设置/关于：`SettingsWindowController.swift:30`（菜单项经 `StatusItemController.swift:109-117` 分发到此）
   - 截图：`ScreenshotWindowController.swift:37`
4. `AppDelegate.swift:102-112` `ensureOnboardingGate()`：只要 `isOnboardingCompleted == false`，就 `showOnboardingWindow()` / 把已存在的欢迎窗 `makeKeyAndOrderFront` 并返回 `false`。

因此：只要 onboarding 没被标记完成，用户点任意菜单项 → 对应 controller guard 失败 → 门禁把欢迎窗重新推到最前。**菜单分发本身是正确的**（`StatusItemController` 的 5 个 `@objc` 方法各自 mapping 正确，`makeMenu()` 也没有 default 兜底错误），错在"引导没完成前一切入口都被劫持到欢迎页"，而引导又因 Bug 2 无法完成，形成死循环。

补充：`styleMask` 含 `.closable`（`AppDelegate.swift:90`），用户点标题栏关闭按钮只会 `close()`，但 `onboardingWindow` 引用未置 nil、`isOnboardingCompleted` 仍为 false，下次门禁又 `makeKeyAndOrderFront` 拉回，用户彻底被困。

### 2.2 Bug 2 根因：欢迎页内容高度远超固定 520pt 窗口，footer 按钮被裁到可视区外

按钮**在代码里是存在的**（并非漏写、hidden 或 action 为 nil）：`OnboardingView.swift:171-203` 的 `footer` 里有「跳过设置」(`onboarding.skip`, `:180`) 和「开始使用」(`onboarding.start`, `:187`) 两个按钮。问题是它们被布局裁剪到窗口外，根因是**固定尺寸容不下内容且无滚动**：

1. `OnboardingView.swift:28` 根 VStack `.frame(width: 720, height: 520)` —— 高度写死 520pt。
2. 承载窗口 `AppDelegate.swift:88` `contentRect: NSRect(... width: 720, height: 520)` —— 窗口内容区同样写死 520pt，`NSHostingView` 不会随内容自适应。
3. 该单屏 VStack（`:19` `spacing: JadeSpace.x6 = 24`，外层 `jadePadding(.x8) = 32`）实际堆叠了：header（`bird` 图标 80pt + `JadeFont.display` 40pt 标题 + 多行副标题）+ 三张配置卡片 + 屏幕录制段 + 辅助功能段 + `Spacer(minLength: 0)` + footer。粗算内容自然高度约 780–820pt，**远超 520pt**。
4. `VStack` 被强制约束到比内容小的固定高度且无 `ScrollView`（`OnboardingView.swift` 中 `ScrollView` 出现次数 = 0），内容会溢出并以居中方式向上下两端外扩，底部的 footer 因此被推到窗口可视区之外 —— 按钮渲染了但看不见、点不到。

综上，Bug 2 是**固定高度 + 无滚动导致的布局溢出裁剪**，不是按钮缺失或逻辑错误。

## 3. 影响范围
- **受影响功能**：搜索、剪贴板、截图、设置、关于 —— 全部主入口在首次启动后不可用。
- **受影响用户**：所有全新安装用户 / 清除过数据的用户（首启即遇到）。老用户若 `onboarding.completedAt` 已写入则不受 Bug 1 影响，但仍会在主动打开欢迎页时遇到 Bug 2。
- **用户体验影响等级**：P0（阻断级）——新用户完全无法使用产品，等同"装了打不开"。

## 4. 修复方案（产品层面）

### 4.1 Bug 1 修复目标
- **欢迎页显示时机收敛**：欢迎页只在两种情况显示 —— (a) 真正的首次启动（`onboarding.completedAt` 为空且 legacy `onboarding.completed` 为 false）；(b) 用户从菜单主动触发（见 4.3 新增"欢迎向导/关于"入口）。
- **门禁不得劫持功能入口**：修复 Bug 2 让引导可被完成/跳过是首要前提。完成或跳过后，`isOnboardingCompleted` 置真、门禁放行，各入口点击后打开各自面板：
  - 「打开搜索」→ 命令栏浮层（`CommandBarController.show`）
  - 「剪贴板」→ 剪贴板历史窗口
  - 「截图」→ 区域截图流程
  - 「设置…」→ 设置窗口（route `.settings`）
  - 「关于」→ 设置窗口（route `.about`）
- **首次启动流程**：欢迎页（单屏引导）→ 用户配置/授权（或跳过）→ 点「开始使用」→ 标记完成 → 关闭欢迎页 → 启动完整体验服务、菜单栏常驻待命。
- **防再次被困**：欢迎窗关闭时必须把 `onboardingWindow` 引用清理干净，且在已完成状态下门禁恒放行；未完成时若用户关掉欢迎窗，需有明确路径重新进入（菜单入口），而不是靠"点任意功能被动弹回"。

### 4.2 Bug 2 修复目标
- 欢迎页底部必须有**始终可见、可点击**的操作区：
  - **主按钮：「开始使用」**（`onboarding.start`）—— 点击后写入 onboarding 完成标记（`SettingKey.onboardingCompletedAt` + legacy `onboardingCompleted`），关闭欢迎页，进入菜单栏待命；沿用现有 `viewModel.canStart` 门槛（屏幕录制已授权 **或** 已点「暂不开启截图」）。
  - **次按钮：「跳过设置」**（`onboarding.skip`）—— 沿用 v1.1.0 既有"跳过向导"设计与二次确认弹窗（`onboarding.skip.confirm.*`），点击后同样写完成标记并离开。
- 文案沿用现有 L10n（与应用中文风格一致，已存在于 `Localizable.xcstrings`）：
  - `onboarding.start` = "开始使用"
  - `onboarding.skip` = "跳过设置"
  - 无需新增文案键；若新增菜单入口再补 `menubar.onboarding` 类键（见 4.3）。
- **布局修复思路**（交由架构/开发定方案，二选一或组合）：
  1. 用 `ScrollView` 包裹中部可变内容，footer 固定吸底在窗口底部（推荐，保证按钮永远可见）；
  2. 或提高窗口与 `.frame` 高度到能容纳全部内容（如 ≥ 820pt）并随系统字体缩放留出余量。
  - 硬约束：footer 必须在任意字体大小 / 明暗模式下都可见可点，不得被裁剪。

### 4.3 欢迎页显示规则（修复后）
- **首次启动**（`onboarding.completedAt` 空且 legacy 为 false）：显示欢迎页。
- **非首次启动**：不显示欢迎页，直接驻留菜单栏，各入口正常工作。
- **菜单项主动触发**：建议在状态栏菜单中新增"欢迎向导"（或复用"关于"）入口，允许用户显式再次打开欢迎页；此路径打开的欢迎页关闭后不改变已完成状态。
- **点击「开始使用」/「跳过设置」后**：写入 `SettingKey.onboardingCompletedAt`（ISO8601 时间戳）+ legacy `onboardingCompleted=true`（`OnboardingViewModel.markCompleted()` 已实现），永久不再自动弹出。

## 5. 验收标准（可测试）
- **AC-01**：全新安装（`onboarding.completedAt` 为空、legacy `onboarding.completed`=false）首次启动时显示欢迎页。
- **AC-02**：完成/跳过引导后，点击菜单栏「打开搜索」打开命令栏搜索浮层，且不再弹出欢迎页。
- **AC-03**：完成/跳过引导后，点击「剪贴板」打开剪贴板历史窗口。
- **AC-04**：完成/跳过引导后，点击「截图」进入区域截图流程（若无屏幕录制权限则走权限提示，而非欢迎页）。
- **AC-05**：完成/跳过引导后，点击「设置…」打开设置窗口（route `.settings`）；点击「关于」打开关于页（route `.about`）。
- **AC-06**：欢迎页底部「开始使用」按钮在默认字体与放大字体下均完整可见且可点击。
- **AC-07**：欢迎页底部「跳过设置」按钮可见可点击，点击弹出二次确认，确认后离开欢迎页。
- **AC-08**：点击「开始使用」（满足 `canStart`）后欢迎页关闭，应用驻留菜单栏，完整体验服务启动（剪贴板监听、清理任务、全局快捷键）。
- **AC-09**：重启应用（非首次，已写完成标记）不自动显示欢迎页，直接驻留菜单栏。
- **AC-10**：欢迎页内容在 720pt 宽窗口内不被横向裁剪；纵向若超高则可滚动或窗口足够高，footer 恒定可达。
- **AC-11**：从菜单主动打开欢迎页并关闭后，不会改变"已完成"状态（重启仍不自动弹出）。
- **AC-12**：屏幕录制未授权且未点"暂不开启截图"时，「开始使用」按钮 `disabled`（`canStart=false`），但「跳过设置」仍可用（回归 v1.1.0 死锁修复）。

## 6. 风险与注意事项
- **权限流程回归（重点）**：v1.1.0 修复过 onboarding 死锁（屏幕录制权限 + 跳过入口）。本次改布局/门禁时不得破坏：`OnboardingViewModel.canStart`、`requestScreenRecording()`、`skipScreenshot()`、`skipOnboarding()` 的既有语义与二次确认必须保留；辅助功能仍为按需申请、不在 onboarding 触发 TCC。
- **UserDefaults/持久化 key 一致性**：完成标记以 Core Data `CDAppSetting` 存储，key 必须继续用 `SettingKey.onboardingCompletedAt`（"onboarding.completedAt"）与 legacy `onboarding.completed`，`AppContainer.loadOnboardingCompletionState()` 的读取路径不变，避免"写了读不到"的新回归。
- **门禁清理**：修复 Bug 1 时确保欢迎窗关闭后 `onboardingWindow` 置 nil、门禁在已完成状态恒放行，避免"关不掉又被拉回"。
- **Sparkle 更新**：更新流程（`UpdateService.setup()`）与欢迎页解耦，本次改动不应触及；仅需确认 onboarding 显示时不阻塞 `updateService.setup()`（当前在 `applicationDidFinishLaunching` 末尾无条件调用，保持即可）。
- **布局适配**：需覆盖系统"字体大小放大"（PRD §9.8 body 到 15pt）与明暗模式，避免仅在默认字号下测试通过。
