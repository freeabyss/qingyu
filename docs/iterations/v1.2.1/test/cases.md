# v1.2.1 XCUITest 完整用例

> 关联设计：`doc/iterations/v1.2.1/architecture/xcuitest-design.md`（用例边界 TC-UI-001~022、可测性分级、测试 hook 设计）
> 评审记录：`doc/iterations/v1.2.1/architecture/xcuitest-review.md`（8 个改善级发现，本文落实）
> 迭代 PRD：`doc/iterations/v1.2.1/prd.md`（AC-01~AC-12）
> 全局 PRD：`doc/prd.md`（§5 MVP 功能集、§7 功能需求、§9 设计语言 P-01~P-06）
> 主体架构：`doc/iterations/v1.2.1/architecture/design.md`（门禁移除、菜单"欢迎向导"入口、onboardingWindow 引用清理、服务幂等）
> 范围：把 22 条用例编号（TC-UI-001~022）展开为开发 subagent 可直接照着写 XCUITest 代码的完整用例。本文件只写用例，不写代码。

---

## 〇、通用约定

以下约定适用于全部 22 条用例，单条用例的"前置条件"与"清理步骤"只写与通用约定不同的部分。

### 0.1 通用 Launch Arguments

每个 `testXxx()` 方法在 `setUp` / 方法开头设置 `app.launchArguments`，**必须**包含以下两项（数据隔离 + 避免热键冲突）：

```
--uitest-data-dir <临时目录绝对路径>
--uitest-skip-shortcuts
```

- `<临时目录绝对路径>`：`NSTemporaryDirectory() + "QingyuUITest/<testMethodName>"`，每个用例独立子目录。
- 临时目录在 `setUp` 创建，`tearDown` 删除，避免污染真实用户数据与跨用例残留。
- 评审 C-4 已确认：`PersistenceController` 已支持外部 storeURL（`.persistent(storeURL: URL?)`），`AssistantFileSystem` 已有 `init(rootDirectory:)`，仅 `DatabaseManager.shared` 的 dbPath 硬编码需 ⑤ 改造为可注入。`--uitest-data-dir` 的实现风险低于设计文档原估。

### 0.2 通用 setUp / tearDown 模式

```
setUp:
  1. 构造临时目录路径（按用例名隔离）
  2. app = XCUIApplication()
  3. app.launchArguments = [<通用参数> + <用例特定参数>]
  4. app.launch()
  5. app.activate()   // LSUIElement app 显式激活，避免 panel 不获焦

tearDown:
  1. app.terminate()
  2. 删除临时目录（FileManager）
```

每个 `testXxx()` 独立运行，不依赖其他用例的残留状态。TC-UI-010（重启不重弹）在单个 test 方法内完成两次 launch/terminate，不跨方法。

### 0.3 Onboarding 状态重置时序（落实评审 C-8）

`--uitest-reset-onboarding` 与 `--uitest-mark-onboarding-completed` 是 **launch argument**，在 `applicationDidFinishLaunching` 时由 `ProcessInfo.processInfo.arguments` 消费。关键时序约束：

1. 重置/标记操作发生在 **app launch 时**（即 `applicationDidFinishLaunching` 内），而非 XCUITest 侧 launch 之前——XCUITest 只负责传参。
2. 在 app 内部，重置/标记必须在 **`bootstrapDataStack` 完成（Core Data store 就绪）之后**、**`loadOnboardingCompletionState()`（`AppDelegate.swift:32`）之前**执行。设计文档原文"在 bootstrap 之前"与"需访问 store"矛盾，以本时序为准（评审 C-8 已澄清）。
3. 因此 XCUITest 侧 `app.launch()` 后，app 启动时已消费参数并完成重置/标记，随后正常进入首启/非首启分支。

### 0.4 `--uitest-trigger` 绕过等价性（落实评审 C-3）

v1.2.1 移除门禁（`design.md` §3.2）后，`--uitest-trigger <action>` 在 `applicationDidFinishLaunching` 末尾直接调用对应 controller 的 `show()` / action，与真实菜单路径（`StatusItemController.@objc` 方法 -> controller `show()`）的**唯一差异是省略了 `StatusItemController` 的方法分发**（该方法分发仅转发无额外逻辑，由代码审查 + 评审 V-2 覆盖）。

| `--uitest-trigger` 值 | 等效菜单项 | 直接调用 | 等价性说明 |
|----------------------|-----------|---------|-----------|
| `openSearch` | 打开搜索 | `container.commandBarController.show()` | 门禁已移除，与菜单路径等价 |
| `openClipboard` | 剪贴板 | `container.clipboardHistoryWindowController.show()` | 同上 |
| `openSettings` | 设置… | `container.settingsWindowController.show(route: .settings)` | 同上 |
| `openAbout` | 关于 | `container.settingsWindowController.show(route: .about)` | 同上 |
| `openOnboarding` | 欢迎向导 | `showOnboardingWindow()`（与 `design.md` §3.4 菜单入口 `onShowOnboarding` 闭包调用同一方法） | **测的就是真实路径**（除菜单点击本身） |
| `startScreenshot` | 截图 | `container.screenshotWindowController.captureRegion()`（配合 `--uitest-skip-screenshot-capture`） | 同上，仅测权限提示 |

因此使用 trigger 的用例（TC-UI-009、TC-UI-011~015）验证的是"controller.show() 被调用后窗口正确呈现"，菜单分发 mapping 本身退回代码审查 + 手动。

### 0.5 Accessibility Identifier 硬依赖（落实评审 C-5）

以下 6 个 identifier 是 TC-UI-011/016/017/018/019/021/022 的**硬依赖**，⑤ 开发必须补加（P0 前置阻塞项）。未添加则这些用例无法实现（Command Bar `nonactivatingPanel` + `borderless` 无法被 `app.windows` 稳定查到，需经 `app.descendants(matching:)` + identifier）。

| 控件 | identifier | 所在文件 | 依赖用例 |
|------|-----------|---------|---------|
| Onboarding「开始使用」按钮 | `onboarding.startButton` | `OnboardingView.swift` | TC-UI-002/005/006/007（按文本查询可兜底，但建议补 identifier） |
| Onboarding「跳过设置」按钮 | `onboarding.skipButton` | `OnboardingView.swift` | TC-UI-003/004/005/006/008 |
| Command Bar 搜索输入框 | `commandBar.searchField` | `CommandBarView.swift` | TC-UI-011/016/017/018 |
| Command Bar 结果列表 | `commandBar.resultList` | `CommandBarView.swift` | TC-UI-016/017 |
| 设置窗口侧栏 | `settings.sidebar` | `SettingsView.swift` | TC-UI-014/019 |
| 剪贴板窗口搜索框 | `clipboard.searchField` | `ClipboardHistoryView.swift` | TC-UI-012/021/022 |

Onboarding 按钮按本地化文本（`app.buttons["开始使用"]` / `["跳过设置"]`）查询在当前中文环境下可行，但本地化环境下文本可能变化，建议一并补 identifier。Command Bar / 剪贴板搜索框 / 设置侧栏**必须**用 identifier（panel 查询需要）。

#### 0.5.1 补充标识符（T-UI-003 落实，命名约定 `<区域>.<控件>`）

以下标识符为 T-UI-003 按 §0.5 命名约定补全，非用例硬依赖（Onboarding 额外控件按文本可兜底；菜单项 XCUITest 经 `--uitest-trigger` 绕过，标识符供手动验证与可访问性审计）：

| 控件 | identifier | 所在文件 | 说明 |
|------|-----------|---------|------|
| Onboarding 热键录制器 | `onboarding.hotkeyRecorder` | `OnboardingView.swift` | KeyboardShortcuts.HotkeyRecorder |
| Onboarding 剪贴板开关 | `onboarding.clipboardToggle` | `OnboardingView.swift` | 配置卡片 Toggle |
| Onboarding 开机启动开关 | `onboarding.launchAtLoginToggle` | `OnboardingView.swift` | 配置卡片 Toggle |
| Onboarding「授予屏幕录制权限」按钮 | `onboarding.screenRecording.grant` | `OnboardingView.swift` | 权限段主按钮 |
| Onboarding「暂不开启截图」按钮 | `onboarding.screenRecording.skip` | `OnboardingView.swift` | 权限段次按钮 |
| 剪贴板窗口侧栏 | `clipboard.sidebar` | `ClipboardHistoryView.swift` | NavigationSplitView sidebar List |
| 菜单「打开搜索」 | `menubar.openSearch` | `StatusItemController.swift` | NSMenuItem accessibilityIdentifier |
| 菜单「剪贴板」 | `menubar.clipboard` | `StatusItemController.swift` | NSMenuItem |
| 菜单「截图」 | `menubar.screenshot` | `StatusItemController.swift` | NSMenuItem |
| 菜单「设置」 | `menubar.settings` | `StatusItemController.swift` | NSMenuItem |
| 菜单「关于」 | `menubar.about` | `StatusItemController.swift` | NSMenuItem |
| 菜单「欢迎向导」 | `menubar.onboarding` | `StatusItemController.swift` | NSMenuItem |
| 菜单「退出」 | `menubar.quit` | `StatusItemController.swift` | NSMenuItem |

> NSMenuItem 方案说明：T-UI-003 采用 `setAccessibilityIdentifier(_:)` 方法（NSMenuItem 经 NSObject/NSAccessibility 非正式协议响应；Swift 中 `accessibilityIdentifier` 桥接为 getter 方法而非可赋值属性，故用 setter 方法形式赋值）。菜单项 XCUITest 查询本身不稳定（设计 §2.2 #10 标 C 级），用例经 `--uitest-trigger` 绕过菜单点击，故菜单项 identifier 为补充性质（手动验证 + 可访问性审计），非用例硬依赖。若后续 XCUITest 需稳定查菜单项，可补 `tag` 整数兜底。

### 0.6 等待与超时

- 窗口/控件出现：`waitForExistence(timeout: 10)`（异步加载、动画 0.12s 留余量）。
- 窗口/控件消失：`NSPredicate` + `expectation(for:evaluator:)` 或轮询 `!element.exists`，超时 5s。
- 不使用固定 `sleep`，除明确标注的 debounce 等待（剪贴板搜索 debounce）。
- `XCUIElement.exists` / `hittable` / `isEnabled` 在 macOS 13+ 可用。

### 0.7 status item 驻留断言说明

Onboarding 完成/跳过后断言"app 驻留菜单栏"，设计文档用 `app.menuBars` 非空。**已知风险**：`app.menuBars` 查询在 CI headless 下可能不稳定（评审 V-4）。应对：

- 优先断言 `app.menuBars.firstMatch.exists`（超时 3s）。
- 若 flaky，降级断言"app 仍在运行"（`app.state == .running`）+ onboarding 窗口已消失。
- 不依赖 status item 物理点击（C 级，评审 §二 #10）。

### 0.8 测试 hook 编译隔离（落实评审 C-1）

设计文档 §5.1 的 hook 仅靠 `ProcessInfo` 检测。建议 ⑤ 开发在 `AppDelegate` hook 入口加 `#if DEBUG` 包裹，或使用独立 UITest build configuration（`SWIFT_ACTIVE_COMPILATION_CONDITIONS = UITEST`），使 Release build 完全剔除测试 hook 代码。本文用例不直接断言此项，但所有 `--uitest-*` 参数仅在 DEBUG/UITest configuration 下生效。

---

## 一、第一批 P0：Onboarding（TC-UI-001~010）

覆盖 v1.2.1 全部关键 AC（AC-01/06/07/08/09/10/11/12）。hook 依赖最少（仅需 onboarding reset/mark + 权限 mock），不依赖 `--uitest-trigger` 和 accessibilityIdentifier（Onboarding 按钮可按文本查询兜底），实现风险低。

### TC-UI-001　首启显示欢迎页

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-01；US-001；FR-ONBOARD-1；全局 PRD §9.4 P-06 |
| 可测性 | B |
| 优先级 | P0 |

**前置条件**
- `--uitest-reset-onboarding`（重置 `onboarding.completedAt` 与 legacy `onboarding.completed`，使 app 进入首启状态）
- `--uitest-data-dir <tmp>`、`--uitest-skip-shortcuts`（通用）
- 时序见 §0.3：reset 在 app launch 时消费，`bootstrapDataStack` 之后、`loadOnboardingCompletionState()` 之前。

**步骤**
1. `app.launchArguments = ["--uitest-reset-onboarding", "--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]`
2. `app.launch()`；`app.activate()`
3. `waitForExistence(timeout: 10)`：查 onboarding 窗口（`app.windows` 含标题或 `app.staticTexts["欢迎使用清羽"]`）
4. 查标题文案：`app.staticTexts["欢迎使用清羽"]` 或 `app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "清羽")).firstMatch`

**关键断言**
- onboarding 窗口 `exists == true`
- 标题文案"欢迎使用清羽"（或 slogan"你的本地 Mac 效率中心"）`exists == true`

**依赖 hook**：`--uitest-reset-onboarding`、`--uitest-data-dir`

**清理**：`app.terminate()`；删除 tmpDir

---

### TC-UI-002　「开始使用」按钮可见可点（默认字号）

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-06（默认字体部分）；US-001；FR-UI-ONBOARDING；全局 PRD §9.4 P-06 |
| 可测性 | A |
| 优先级 | P0 |

**前置条件**：同 TC-UI-001（`--uitest-reset-onboarding` + 通用）

**步骤**
1. launch（同 TC-UI-001 前置）
2. `waitForExistence(timeout: 10)`：onboarding 窗口
3. 查「开始使用」按钮：`app.buttons["开始使用"]`（或 `app.buttons["onboarding.startButton"]` 若 identifier 已补）
4. 断言 `exists`、`hittable`、`isEnabled`

**关键断言**
- 「开始使用」button `exists == true && hittable == true`
- `isEnabled` 状态取决于权限 mock：本用例未传权限 mock，默认环境若已授权则 `isEnabled == true`，若未授权则 `false`——**本用例只断言可见可点（exists+hittable），不断言 isEnabled**（isEnabled 由 TC-UI-006/007 分别验证）

**依赖 hook**：`--uitest-reset-onboarding`

**清理**：同 TC-UI-001

**备注**：默认字号下可见；放大字号下可见由 TC-UI-005 子场景 5b 覆盖（落实评审 C-2）。

---

### TC-UI-003　「跳过设置」按钮可见可点

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-07（可见可点部分）；US-001；FR-ONBOARD-18；v1.1.0 skip 入口回归 |
| 可测性 | A |
| 优先级 | P0 |

**前置条件**：同 TC-UI-001

**步骤**
1. launch（同 TC-UI-001 前置）
2. `waitForExistence`：onboarding 窗口
3. 查「跳过设置」按钮：`app.buttons["跳过设置"]`（或 identifier `onboarding.skipButton`）
4. 断言 `exists`、`hittable`、`isEnabled`

**关键断言**
- 「跳过设置」button `exists == true && hittable == true && isEnabled == true`（跳过按钮不依赖 `canStart`，始终可用——v1.1.0 死锁修复回归点）

**依赖 hook**：`--uitest-reset-onboarding`

**清理**：同 TC-UI-001

---

### TC-UI-004　「跳过设置」+ 二次确认 + 关窗

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-07（二次确认部分）；US-001；FR-ONBOARD-18；v1.1.0 确认 Alert 回归 |
| 可测性 | A |
| 优先级 | P0 |

**前置条件**：同 TC-UI-001

**步骤**
1. launch（同 TC-UI-001 前置）
2. `waitForExistence`：onboarding 窗口
3. 点击 `app.buttons["跳过设置"]`
4. `waitForExistence(timeout: 5)`：二次确认 dialog（查 `app.sheets.firstMatch` 或 `app.alerts.firstMatch` 或确认按钮文案，L10n key `onboarding.skip.confirm.*`）
5. 点击确认按钮（`app.buttons["确认跳过"]` 或 sheet 的确认 action；具体文案以 `Localizable.xcstrings` 为准）
6. 等待 onboarding 窗口消失：轮询 `!onboardingWindow.exists`，超时 5s

**关键断言**
- 点击「跳过设置」后，二次确认 dialog `exists == true`
- 点击确认后，onboarding 窗口 `exists == false`

**依赖 hook**：`--uitest-reset-onboarding`

**清理**：同 TC-UI-001

---

### TC-UI-005　footer 恒定可见（含放大字号变体）

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-10（不横裁 / footer 可达）；AC-06（放大字体下可见，落实评审 C-2）；US-001；FR-UI-ONBOARDING；全局 PRD §9.8 动态字体 |
| 可测性 | B |
| 优先级 | P0 |

**前置条件**
- 子场景 5a（默认字号）：同 TC-UI-001
- 子场景 5b（放大字号）：`--uitest-reset-onboarding` + `--uitest-large-text`（**需 ⑤ 开发实现此 mock hook**，模拟 `UIAccessibility.isBoldTextEnabled` 或动态字号放大到 body 15pt；见评审 C-2）+ 通用

**步骤（5a 默认字号）**
1. launch（reset + 通用，不带 large-text）
2. `waitForExistence`：onboarding 窗口
3. 同时查「开始使用」与「跳过设置」两个 button
4. 断言两者 `exists == true && hittable == true`（footer 恒定可见，两按钮同时可达）

**步骤（5b 放大字号）**
5. `app.terminate()`
6. `app.launchArguments = ["--uitest-reset-onboarding", "--uitest-large-text", "--uitest-data-dir", tmpDir2, "--uitest-skip-shortcuts"]`
7. `app.launch()`；`app.activate()`
8. `waitForExistence`：onboarding 窗口
9. 同时查「开始使用」与「跳过设置」两个 button
10. 断言两者 `exists == true && hittable == true`（放大字号下 footer 仍可见可点——AC-06/AC-10 放大字体覆盖）

**关键断言**
- 5a：默认字号下两 button 同时 `hittable`
- 5b：放大字号下两 button 同时 `hittable`（**不验证 frame 像素**，只验证可点击性；横向不裁剪由 `maxWidth: .infinity` 保证，纵向超高可滚由 `ScrollView` 保证，退回代码审查 + 手动验证滚动交互）

**依赖 hook**：`--uitest-reset-onboarding`；5b 额外依赖 `--uitest-large-text`

**清理**：删除两个 tmpDir

**备注（落实评审 C-2）**：若 ⑤ 开发评估 `--uitest-large-text` 实现成本过高未实现，5b 退回手动验证（在系统偏好设置放大字号后人工确认 footer 可见），并在本用例标注 `XCTSkipUnless` 或手动验证清单。AC-06"放大字体下可见"的自动化覆盖以 5b 为准。

---

### TC-UI-006　未授权时「开始使用」禁用、「跳过设置」可用

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-12；US-001；FR-ONBOARD-11；v1.1.0 死锁修复回归（未授权时跳过仍可用） |
| 可测性 | B |
| 优先级 | P0 |

**前置条件**
- `--uitest-reset-onboarding`
- `--uitest-mock-screen-recording-denied`（mock `PermissionService.status(.screenRecording)` 返回 `.denied`，使 `canStart == false`）
- 通用（`--uitest-data-dir`、`--uitest-skip-shortcuts`）

**步骤**
1. launch（reset + mock-denied + 通用）
2. `waitForExistence`：onboarding 窗口
3. 查「开始使用」button：`app.buttons["开始使用"]`
4. 查「跳过设置」button：`app.buttons["跳过设置"]`
5. 断言两者 `isEnabled` 状态

**关键断言**
- 「开始使用」`isEnabled == false`（`canStart == false`：屏幕录制未授权且未点"暂不开启截图"）
- 「跳过设置」`isEnabled == true`（跳过不依赖 `canStart`——v1.1.0 死锁修复回归：未授权时用户不会被锁死，仍可跳过）
- 两者 `exists == true`（按钮可见，只是禁用状态不同）

**依赖 hook**：`--uitest-reset-onboarding`、`--uitest-mock-screen-recording-denied`

**清理**：同 TC-UI-001

---

### TC-UI-007　点「开始使用」后关窗 + 驻留（authorized 路径）

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-08（完成路径）；US-001；US-002；FR-ONBOARD-19 |
| 可测性 | A |
| 优先级 | P0 |

**前置条件**
- `--uitest-reset-onboarding`
- `--uitest-mock-screen-recording-authorized`（mock 权限已授权，使 `canStart == true`，「开始使用」可点）
- 通用

**步骤**
1. launch（reset + mock-authorized + 通用）
2. `waitForExistence`：onboarding 窗口
3. 断言「开始使用」`isEnabled == true`（确认 mock 生效，canStart 通过）
4. 点击 `app.buttons["开始使用"]`
5. 等待 onboarding 窗口消失：轮询 `!onboardingWindow.exists`，超时 5s
6. 断言 app 驻留菜单栏：`waitForExistence(timeout: 3)` `app.menuBars.firstMatch`（降级见 §0.7）

**关键断言**
- 点击「开始使用」前，button `isEnabled == true`
- 点击后，onboarding 窗口 `exists == false`
- `app.menuBars.firstMatch.exists == true`（或降级 `app.state == .Running`）

**依赖 hook**：`--uitest-reset-onboarding`、`--uitest-mock-screen-recording-authorized`

**清理**：同 TC-UI-001

**备注**：AC-08"完整体验服务启动（剪贴板监听、清理任务、全局快捷键）"是内部行为，UI 测试难断言；服务启动逻辑退回 XCTest 覆盖（评审 §三已标注）。`hasStartedFullExperience` 幂等（`design.md` §3.5）不在本用例验证范围。

---

### TC-UI-008　点「跳过设置」+ 确认后关窗 + 驻留（skip 路径）

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-08（skip 路径）；US-001 |
| 可测性 | A |
| 优先级 | P0 |

**前置条件**：同 TC-UI-001（reset，无需 mock 权限，skip 不依赖 `canStart`）

**步骤**
1. launch（reset + 通用）
2. `waitForExistence`：onboarding 窗口
3. 点击 `app.buttons["跳过设置"]`
4. `waitForExistence(timeout: 5)`：二次确认 dialog
5. 点击确认按钮
6. 等待 onboarding 窗口消失：轮询 `!onboardingWindow.exists`，超时 5s
7. 断言 `app.menuBars.firstMatch.exists == true`（降级见 §0.7）

**关键断言**
- 确认后 onboarding 窗口 `exists == false`
- `app.menuBars.firstMatch.exists == true`（skip 后同样驻留 + 启动服务，`onComplete` 闭包统一处理，`design.md` §3.5）

**依赖 hook**：`--uitest-reset-onboarding`

**清理**：同 TC-UI-001

---

### TC-UI-009　菜单主动打开欢迎页 + 关闭不改完成态

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-11；US-001；`design.md` §3.4 菜单"欢迎向导"入口、§3.3 `windowWillClose` 引用清理 |
| 可测性 | B |
| 优先级 | P0 |

**前置条件**
- `--uitest-mark-onboarding-completed`（标记已完成，app 跳过 onboarding 直接驻留）
- `--uitest-trigger openOnboarding`（启动后主动调用 `showOnboardingWindow()`）
- 通用

**trigger 等价性（落实评审 C-3，见 §0.4）**：`--uitest-trigger openOnboarding` 调用 `showOnboardingWindow()`，与 `design.md` §3.4 菜单"欢迎向导"入口（`onShowOnboarding` 闭包 -> `showOnboardingWindow()`）调用**同一方法**，唯一差异是省略 `StatusItemController.@objc openOnboardingFromMenu()` 方法分发（仅转发无额外逻辑）。因此本用例测的就是真实路径（除菜单点击本身），等价性好。

**步骤**
1. launch（mark-completed + trigger openOnboarding + 通用）
2. `waitForExistence(timeout: 10)`：onboarding 窗口出现（主动打开）
3. 断言 onboarding 窗口 `exists == true`
4. 关闭 onboarding 窗口：
   - 方式 A：点击窗口标题栏红色关闭按钮（查 `app.windows` 的关闭按钮，或 `app.buttons` 含 close 图标）
   - 方式 B（备选）：若关闭按钮难查，按 `⌘W`（窗口快捷键关闭）
5. 等待 onboarding 窗口消失：轮询 `!onboardingWindow.exists`，超时 5s
6. 断言 app 仍驻留：`app.menuBars.firstMatch.exists == true`（降级见 §0.7）

**关键断言**
- 主动打开后 onboarding 窗口 `exists == true`
- 关闭后 onboarding 窗口 `exists == false`
- app 仍驻留（`menuBars` 非空 或 `app.state == .Running`）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openOnboarding`

**清理**：同 TC-UI-001

**备注**：
- 不验证持久化层（`isOnboardingCompleted` 不因关闭而改变）——已有 XCTest 覆盖 `OnboardingViewModel.markCompleted()` 语义。
- 验证 `design.md` §3.3 `windowWillClose` 引用清理：关闭后 `onboardingWindow = nil`，再次主动打开走全新创建路径（不拉回僵尸窗口）。本用例验证"关闭后 app 仍驻留"即间接验证引用未泄漏导致 crash。
- AC-11"重启仍不自动弹出"的持久化验证由 TC-UI-010 覆盖。

---

### TC-UI-010　重启不自动弹欢迎页

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-09；US-001；FR-ONBOARD-19 |
| 可测性 | B |
| 优先级 | P0 |

**前置条件**（两步 launch，单个 test 方法内完成）
- 步骤 1 launch：`--uitest-mark-onboarding-completed` + `--uitest-data-dir <tmp>`（**复用同一 tmpDir**）+ `--uitest-skip-shortcuts`
- 步骤 2 launch：`--uitest-data-dir <tmp>`（**同一 tmpDir，保留完成标记**）+ `--uitest-skip-shortcuts`；**不传** mark/reset

**步骤**
1. 构造 tmpDir（单个，两步复用）
2. 步骤 1：
   - `app.launchArguments = ["--uitest-mark-onboarding-completed", "--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]`
   - `app.launch()`；`app.activate()`
   - `waitForExistence(timeout: 3)`：`app.menuBars.firstMatch`（驻留）
   - 断言 onboarding 窗口 `exists == false`（已完成，首启不弹）
3. `app.terminate()`
4. 步骤 2：
   - `app.launchArguments = ["--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]`（复用 tmpDir，不传 mark/reset）
   - `app.launch()`；`app.activate()`
   - 等待 app 启动完成：`waitForExistence(timeout: 5)` `app.menuBars.firstMatch` 或固定等待 2s
5. 断言 onboarding 窗口 `exists == false`（重启不自动弹）
6. 断言 `app.menuBars.firstMatch.exists == true`（直接驻留）

**关键断言**
- 步骤 1 后 onboarding 窗口不出现
- 步骤 2（重启）后 onboarding 窗口 `exists == false`
- 步骤 2 后 app 驻留（`menuBars` 非空）

**依赖 hook**：`--uitest-mark-onboarding-completed`（步骤1）、`--uitest-data-dir`（两步复用）

**清理**：`app.terminate()`；删除 tmpDir

**备注**：关键点是 tmpDir **必须复用**——步骤 1 写入的 `onboarding.completedAt` 持久化到 tmpDir 的 Core Data store，步骤 2 读取同一 store 的 `loadOnboardingCompletionState()` 应返回已完成。若 tmpDir 不复用（步骤 2 用新目录），则步骤 2 等效首启，onboarding 会弹出，用例失败。

---

## 二、第二批 P1：菜单分发 + Command Bar + 设置 + 剪贴板（TC-UI-011~022）

依赖 `--uitest-trigger` hook 和 §0.5 的 accessibilityIdentifier，需 ⑤ 开发配合。trigger 等价性说明见 §0.4。

### TC-UI-011　菜单分发 -> Command Bar 呈现

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-02；US-002；US-003；FR-UI-3；FR-SEARCH-1；全局 PRD §9.4 P-01 |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**
- `--uitest-mark-onboarding-completed`
- `--uitest-trigger openSearch`
- 通用
- **硬依赖**（§0.5）：Command Bar 搜索框 `accessibilityIdentifier("commandBar.searchField")`

**trigger 等价性（§0.4）**：`openSearch` 直接调 `commandBarController.show()`，门禁已移除，与菜单路径等价。

**步骤**
1. launch（mark-completed + trigger openSearch + 通用）
2. `waitForExistence(timeout: 5)`：搜索框 `app.descendants(matching: .textField)["commandBar.searchField"]`（或 `app.textFields["commandBar.searchField"]`）
3. 断言搜索框 `exists == true && hittable == true`

**关键断言**
- Command Bar 搜索框 `exists == true`（panel 呈现）
- 搜索框 `hittable == true`（可聚焦输入）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSearch`

**清理**：`app.terminate()`；删除 tmpDir

---

### TC-UI-012　菜单分发 -> 剪贴板窗口呈现

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-03；US-002；US-008；FR-UI-3；全局 PRD §9.4 P-02 |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**
- `--uitest-mark-onboarding-completed`
- `--uitest-trigger openClipboard`
- 通用
- **硬依赖**（§0.5）：剪贴板搜索框 `accessibilityIdentifier("clipboard.searchField")`

**trigger 等价性（§0.4）**：`openClipboard` 直接调 `clipboardHistoryWindowController.show()`。

**步骤**
1. launch（mark-completed + trigger openClipboard + 通用）
2. `waitForExistence(timeout: 5)`：剪贴板窗口（查 `app.textFields["clipboard.searchField"]` 或空态文案 `app.staticTexts["剪贴板历史为空"]`，全局 PRD §9.7）
3. 断言窗口可见

**关键断言**
- 剪贴板搜索框 `exists == true`，或空态文案"剪贴板历史为空"`exists == true`（隔离数据目录下剪贴板为空，走空态）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openClipboard`

**清理**：同 TC-UI-011

---

### TC-UI-013　截图入口 -> 权限提示（未授权）

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-04；US-002；US-009；FR-UI-4；FR-SHOT-1 |
| 可测性 | C/B（设计文档标 C/B，仅测权限提示 Alert，真实截图退回手动） |
| 优先级 | P1 |

**前置条件**
- `--uitest-mark-onboarding-completed`
- `--uitest-mock-screen-recording-denied`（mock 未授权）
- `--uitest-trigger startScreenshot`
- `--uitest-skip-screenshot-capture`（跳过真实 `ScreenshotService.capture*()`，仅验证权限提示路径）
- 通用

**trigger 等价性（§0.4）**：`startScreenshot` 调 `screenshotWindowController.captureRegion()`（配合 skip-capture），门禁已移除，走 `ensureScreenRecordingPermission()` 检查。

**步骤**
1. launch（mark-completed + mock-denied + trigger startScreenshot + skip-capture + 通用）
2. `waitForExistence(timeout: 5)`：权限提示 NSAlert（查 `app.alerts.firstMatch` 或 alert button 文案，如"打开系统设置"）
3. 断言 alert `exists == true`

**关键断言**
- 权限提示 Alert `exists == true`（未授权时走提示，而非欢迎页——AC-04 修复点）
- **不测**真实截图捕获（C 级，退回手动）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-mock-screen-recording-denied`、`--uitest-trigger startScreenshot`、`--uitest-skip-screenshot-capture`

**清理**：同 TC-UI-011；若有 alert 残留，点击取消关闭

**备注**：本用例验证 v1.2.1 修复点——截图入口不再被 onboarding 门禁劫持到欢迎页，而是走自身权限提示逻辑（`design.md` §3.2 门禁移除）。

---

### TC-UI-014　菜单分发 -> 设置窗口呈现

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-05；US-002；US-011；FR-UI-3；FR-UI-5；全局 PRD §9.4 P-03 |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**
- `--uitest-mark-onboarding-completed`
- `--uitest-trigger openSettings`
- 通用
- **硬依赖**（§0.5）：设置侧栏 `accessibilityIdentifier("settings.sidebar")`（或按侧栏项文本查询兜底）

**trigger 等价性（§0.4）**：`openSettings` 调 `settingsWindowController.show(route: .settings)`。

**步骤**
1. launch（mark-completed + trigger openSettings + 通用）
2. `waitForExistence(timeout: 5)`：设置窗口（查 `app.groups["settings.sidebar"]` 或侧栏项 staticText，全局 PRD §9.4 P-03 分组：概览/剪贴板/快捷键/截图/搜索源/外观/权限/数据/更新/关于/反馈）
3. 断言设置窗口可见；侧栏可见

**关键断言**
- 设置窗口 `exists == true`
- 侧栏至少一项可见（如"概览"或"剪贴板"staticText `exists == true`）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSettings`

**清理**：同 TC-UI-011

---

### TC-UI-015　菜单分发 -> 关于页呈现

| 字段 | 内容 |
|------|------|
| 覆盖 | AC-05；US-002；US-011；FR-UI-8；FR-UI-ABOUT-VERSION |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**
- `--uitest-mark-onboarding-completed`
- `--uitest-trigger openAbout`
- 通用

**trigger 等价性（§0.4）**：`openAbout` 调 `settingsWindowController.show(route: .about)`。

**步骤**
1. launch（mark-completed + trigger openAbout + 通用）
2. `waitForExistence(timeout: 5)`：关于页内容（查 `app.staticTexts` 含"清羽"或"Qingyu"，全局 PRD §9.4 P-03 关于页：图标 96×96 + 版本号 + 版权 + 反馈入口）
3. 断言关于页可见

**关键断言**
- 关于页内容 `exists == true`（"清羽"/"Qingyu" staticText 可见）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openAbout`

**清理**：同 TC-UI-011

**备注**：版本号三源一致（FR-UI-36）退回脚本/构建检查，不在本用例验证（TC-UI-020 只验证版本号可见）。

---

### TC-UI-016　Command Bar 搜索基本交互（输入 -> 结果 -> ESC 关闭）

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-SEARCH-4/6/7；US-003；全局 PRD §9.4 P-01、§9.3 |
| 可测性 | A |
| 优先级 | P1 |

**前置条件**：同 TC-UI-011（mark-completed + trigger openSearch）
- **硬依赖**（§0.5）：`commandBar.searchField`、`commandBar.resultList`

**步骤**
1. launch（mark-completed + trigger openSearch + 通用）
2. `waitForExistence`：搜索框 `commandBar.searchField`
3. 点击搜索框聚焦：`searchField.click()`
4. 输入文本：`searchField.typeText("设置")`（或 "screenshot"、"计算" 等高频词，确保有结果）
5. `waitForExistence(timeout: 5)`：结果列表 `app.groups["commandBar.resultList"]` 的 cells，或"未找到匹配项"staticText（全局 PRD §9.7）
6. 断言结果列表出现：`resultList.cells.count > 0` 或未找到文案 `exists`
7. 按 ESC：`app.keyboards.keys["\u{1B}"].tap()`（或 `typeText("\u{1B}")`，ESC = 0x1B）
8. 等待 Command Bar 消失：轮询 `!searchField.exists`，超时 3s

**关键断言**
- 输入后结果列表 `exists == true`（cells.count > 0 或未找到文案）
- ESC 后搜索框/panel `exists == false`（FR-SEARCH-7：ESC 关闭搜索框）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSearch`

**清理**：同 TC-UI-011

**备注**：不验证搜索结果正确性（那是 `SearchServiceCoreTests` / `SearchTextMatcherTests` 的事，评审 §三已标注边界）。结果列表内容依赖索引状态，用 `waitForExistence` 等待异步加载。

---

### TC-UI-017　Command Bar 回车执行 + 自动关闭

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-SEARCH-27/29；US-003 |
| 可测性 | A |
| 优先级 | P1 |

**前置条件**：同 TC-UI-011

**步骤**
1. launch（mark-completed + trigger openSearch + 通用）
2. `waitForExistence`：搜索框
3. `searchField.click()`；`searchField.typeText("设置")`（选一个有结果的词）
4. `waitForExistence`：结果列表
5. 按 Enter：`searchField.typeText("\r")`（或 `app.keyboards.keys["\r"].tap()`）
6. 等待 Command Bar 消失：轮询 `!searchField.exists`，超时 3s

**关键断言**
- 回车后 Command Bar panel `exists == false`（FR-SEARCH-29：执行主动作后搜索框自动关闭）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSearch`

**清理**：同 TC-UI-011

**备注**：不验证主动作执行结果（如是否真打开设置窗口），只验证 panel 自动关闭行为（FR-SEARCH-29）。主动作正确性退回各 Provider 的 XCTest。

---

### TC-UI-018　Command Bar 空输入不消失（空态）

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-SEARCH-14；US-003；全局 PRD §9.3 空态展示最近使用+收藏 |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**：同 TC-UI-011

**步骤**
1. launch（mark-completed + trigger openSearch + 通用）
2. `waitForExistence`：搜索框
3. **不输入任何文本**
4. 固定等待 2s（确保非瞬时关闭）
5. 断言搜索框/panel 仍 `exists == true`

**关键断言**
- 空输入时 Command Bar panel `exists == true`（不消失）
- 搜索框 `exists == true`

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSearch`

**清理**：同 TC-UI-011

**备注**：FR-SEARCH-14 空态展示"最近使用+收藏"需 app 内有预设使用记录。隔离数据目录下无使用记录，空态为初始占位。首期只测"空输入时 panel 不消失"，"最近使用+收藏"列表内容验证需 mock 使用记录（`--uitest-mock-usage-data`，后续迭代补），不在此用例验证。

---

### TC-UI-019　设置窗口侧栏导航切换

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-UI-5/8；US-011；全局 PRD §9.4 P-03 |
| 可测性 | A |
| 优先级 | P1 |

**前置条件**：同 TC-UI-014（mark-completed + trigger openSettings）
- **硬依赖**（§0.5）：`settings.sidebar`（或按侧栏项文本查询）

**步骤**
1. launch（mark-completed + trigger openSettings + 通用）
2. `waitForExistence`：设置窗口 + 侧栏
3. 点击侧栏"剪贴板"项：`app.staticTexts["剪贴板"].click()`（或 `app.buttons["剪贴板"]`）
4. `waitForExistence(timeout: 3)`：主区域切换（查剪贴板设置内容，如"保留时间"staticText 或相关控件）
5. 点击侧栏"快捷键"项：`app.staticTexts["快捷键"].click()`
6. `waitForExistence`：主区域切换（查快捷键录制器 HotkeyRecorder 或"呼出统一搜索"staticText）
7. 点击侧栏"关于"项：`app.staticTexts["关于"].click()`
8. `waitForExistence`：关于页内容（"清羽"/"Qingyu" staticText）

**关键断言**
- 每次点击侧栏项后，主区域内容切换（前一页内容消失、新页内容出现）
- "剪贴板" -> 主区域含剪贴板设置控件
- "快捷键" -> 主区域含快捷键录制器
- "关于" -> 主区域含关于页内容

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openSettings`

**清理**：同 TC-UI-011

---

### TC-UI-020　关于页版本号可见

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-UI-8；FR-UI-ABOUT-VERSION；US-011；全局 PRD §9.4 P-03 |
| 可测性 | A |
| 优先级 | P1 |

**前置条件**：同 TC-UI-015（mark-completed + trigger openAbout）

**步骤**
1. launch（mark-completed + trigger openAbout + 通用）
2. `waitForExistence`：关于页
3. 查版本号 staticText：`app.staticTexts.containing(NSPredicate(format: "label MATCHES %@", "1\\.2\\..*")).firstMatch`（匹配 `1.2.x` 格式）

**关键断言**
- 版本号 staticText `exists == true`（label 匹配 `1.2.*`）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openAbout`

**清理**：同 TC-UI-011

**备注**：不验证版本号三源一致（Xcode `MARKETING_VERSION` / `Info.plist` / `CHANGELOG`），退回脚本/构建检查（FR-UI-36）。本用例只验证关于页**显示**了版本号。

---

### TC-UI-021　剪贴板窗口空态 + 类型筛选 + 搜索框可见可聚焦

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-CLIP-18/19；US-008；全局 PRD §9.4 P-02、§9.7 |
| 可测性 | A |
| 优先级 | P1 |

**前置条件**：同 TC-UI-012（mark-completed + trigger openClipboard）
- **硬依赖**（§0.5）：`clipboard.searchField`

**步骤**
1. launch（mark-completed + trigger openClipboard + 通用）
2. `waitForExistence`：剪贴板窗口（搜索框或空态文案）
3. 查空态文案：`app.staticTexts["剪贴板历史为空"]`（全局 PRD §9.7，隔离数据目录下为空）
4. 查类型筛选 tabs/buttons：FR-CLIP-18 要求"全部/文本/图片/文件"（查 `app.staticTexts["全部"]`、`["文本"]`、`["图片"]`、`["文件"]` 或 segmented control）
5. 查搜索框：`app.textFields["clipboard.searchField"]`
6. 点击搜索框：`searchField.click()`
7. 断言搜索框聚焦（`searchField.value` 非空 placeholder 消失，或 `searchField.hasFocus`，或通过键盘输入验证可输入）

**关键断言**
- 空态文案"剪贴板历史为空"`exists == true`
- 类型筛选 tabs（全部/文本/图片/文件）`exists == true`
- 搜索框 `exists == true && hittable == true`
- 搜索框可聚焦（点击后可输入）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openClipboard`

**清理**：同 TC-UI-011

---

### TC-UI-022　剪贴板窗口搜索框输入（空数据过滤）

| 字段 | 内容 |
|------|------|
| 覆盖 | FR-CLIP-19b（搜索框只搜剪贴板历史）；US-008 |
| 可测性 | B |
| 优先级 | P1 |

**前置条件**：同 TC-UI-012（mark-completed + trigger openClipboard）
- **硬依赖**（§0.5）：`clipboard.searchField`

**步骤**
1. launch（mark-completed + trigger openClipboard + 通用）
2. `waitForExistence`：剪贴板窗口 + 搜索框
3. 点击搜索框：`searchField.click()`
4. 输入文本：`searchField.typeText("test")`
5. 固定等待 1s（FR-CLIP-19d debounce）
6. 断言 app 不崩溃（`app.state == .Running`）
7. 断言列表区域不报错：空数据下显示空态或"未找到"，无异常

**关键断言**
- 输入后 `app.state == .Running`（不崩溃）
- 搜索框 `exists == true`（输入后仍可用）
- 空数据下列表过滤无异常（空态文案保持或变为"未找到"）

**依赖 hook**：`--uitest-mark-onboarding-completed`、`--uitest-trigger openClipboard`

**清理**：同 TC-UI-011

**备注**：验证真实过滤行为需 mock 剪贴板数据（`--uitest-mock-clipboard-data`，后续迭代补）。首期无 mock 数据时只测"搜索框输入不报错、空数据过滤无异常"，落实设计文档 §6.1 "首期无 mock 数据时只测搜索框不报错"。

---

## 三、评审改善级发现落实映射

本文档逐条落实 `xcuitest-review.md` 的 8 个改善级发现：

| 评审 # | 发现 | 落实位置 |
|--------|------|---------|
| C-1 | 测试 hook 编译隔离不足 | §0.8：建议 ⑤ 开发加 `#if DEBUG` 或 UITest configuration；用例不直接断言 |
| C-2 | AC-10/AC-06 放大字体未覆盖 | TC-UI-005 子场景 5b：`--uitest-large-text` 放大字号变体（需 ⑤ 实现，否则退回手动） |
| C-3 | trigger 绕过等价性未说明 | §0.4 统一说明 + TC-UI-009/011~015 各自注明等价性 |
| C-4 | 数据隔离实现风险低估 | §0.1：确认 PersistenceController / AssistantFileSystem 已支持注入，仅 DatabaseManager 需改造 |
| C-5 | Accessibility Identifier 硬依赖 | §0.5 列为 ⑤ 开发 P0 前置阻塞项，TC-UI-011/016/017/018/019/021/022 标注硬依赖 |
| C-6 | 独立 Bundle ID 表述混淆 | 不影响用例（结论"不推荐"不变），§0.1 用 `--uitest-data-dir` 方案 |
| C-7 | #22 全局快捷键 B 级偏乐观 | 22 条用例不含全局快捷键（TC-UI-022 是剪贴板搜索框，FR-CLIP-19b）；全局快捷键列入待定区 |
| C-8 | onboarding reset 时序矛盾 | §0.3 澄清：reset 在 `bootstrapDataStack` 之后、`loadOnboardingCompletionState` 之前 |

---

## 四、AC 覆盖矩阵

| AC | 用例 | 可测性 | 备注 |
|----|------|--------|------|
| AC-01 首启显示欢迎页 | TC-UI-001 | B | 需 `--uitest-reset-onboarding` |
| AC-02 完成后搜索可用 | TC-UI-011 | B | 需 `--uitest-trigger openSearch` |
| AC-03 完成后剪贴板可用 | TC-UI-012 | B | 需 `--uitest-trigger openClipboard` |
| AC-04 完成后截图走权限提示 | TC-UI-013 | C/B | 仅测权限 Alert，真实截图手动 |
| AC-05 完成后设置/关于可用 | TC-UI-014, TC-UI-015 | B | 需 `--uitest-trigger` |
| AC-06 「开始使用」可见可点 | TC-UI-002, TC-UI-005(5b) | A/B | 默认字号 A，放大字号 B（C-2） |
| AC-07 「跳过设置」+ 确认 | TC-UI-003, TC-UI-004 | A | |
| AC-08 完成后关窗 + 驻留 | TC-UI-007, TC-UI-008 | A | 服务启动退回 XCTest |
| AC-09 重启不自动弹 | TC-UI-010 | B | 两步 launch，tmpDir 复用 |
| AC-10 不横裁/可滚/footer 可达 | TC-UI-005 | B | 间接验证 hittable，像素退回手动 |
| AC-11 菜单主动打开不改状态 | TC-UI-009 | B | 需 `--uitest-trigger openOnboarding` |
| AC-12 未授权时开始禁用、跳过可用 | TC-UI-006 | B | 需 mock 权限；v1.1.0 死锁修复回归 |

**用例统计**：

| 批次 | 范围 | 数量 | 可测性分布 | 优先级 |
|------|------|------|-----------|--------|
| 第一批 | Onboarding（TC-UI-001~010） | 10 | A: 4, B: 6 | P0 |
| 第二批 | 菜单分发 5 + Command Bar 3 + 设置 2 + 剪贴板 2（TC-UI-011~022） | 12 | A: 5, B: 6, C/B: 1 | P1 |
| **合计** | | **22** | **A: 9, B: 12, C/B: 1** | |

---

## 五、待定项（不新增编号，记录已知边界）

以下项在设计文档 §6.3 已标注"不纳入首期"或评审 C-7 指出，本阶段不新增用例编号，记录待后续迭代评估：

| 待定项 | 原因 | 后续处理 |
|--------|------|---------|
| 全局快捷键（app 激活时）触发 Command Bar | 评审 C-7：`⌥ Space` 时序敏感 flaky；22 条不含此项 | ⑤ 本地实测稳定性后决定是否降为 B 级 smoke test 或维持手动 |
| 全局快捷键（app 未激活时）触发 | XCUITest 无法模拟系统级热键（C 级） | 退回手动验证 |
| 菜单栏 status item 物理点击 | `NSStatusBarButton` XCUITest 访问不稳定（C 级） | 退回手动；评审 V-1 建议本地实测后决定 |
| 真实屏幕录制 TCC 授权流程 | CI/headless 无法授权（C 级） | 退回手动；`PermissionService` 逻辑已有 XCTest |
| 截图捕获 + 标注编辑器 UI | 依赖 TCC + 全屏 overlay（C 级） | 退回手动；标注逻辑已有 XCTest |
| 开机启动注册 | `SMAppService` 系统级行为（C 级） | 退回手动 |
| 更新检查跳转 | 网络依赖（C 级） | 退回手动；已有 XCTest |
| 版本号三源一致 | 非纯 UI 行为 | 脚本/构建检查（TC-UI-020 只验证可见） |
| `--uitest-large-text` mock hook 实现 | 评审 C-2 建议；若 ⑤ 不实现，TC-UI-005 的 5b 退回手动 | ⑤ 开发评估实现成本 |
| `--uitest-mock-usage-data` / `--uitest-mock-clipboard-data` | TC-UI-018/022 的真实数据验证需 mock | 后续迭代补 hook |
| 命令栏 ⌘1-6 切换搜索源 | 需 mock 各源数据 | 后续迭代 |
| 剪贴板窗口 swipe action / 预览 Sheet | 需 mock 数据 | 后续迭代 |
