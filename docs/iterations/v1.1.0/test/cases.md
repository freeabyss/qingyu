# v1.1.0 测试用例 —— Onboarding 死锁修复：屏幕录制权限申请 + 跳过向导

- **迭代**：v1.1.0（Bug 修复 + 新功能）· Issue #3 · 分支 v1.1.0 · 模式 auto
- **关联文档**：`prd.md`（AC-1~8 / P-1.1~2.5）、`architecture/design.md`（方案 A）、`architecture/review.md`
- **AC 来源**：prd.md 第四节 AC-1 ~ AC-8
- **说明**：本文件为本迭代自包含用例集，仅覆盖本次变更所需场景，不写入 `doc/test/`（全局累积用例待 ⑥ 归档合并）。

## 顶部说明区（架构死角覆盖策略，对齐 review.md §十）

review §十 的 4 条 P2 死角以**手工步骤覆盖**为主，不新增严格自动化：

- **死角1（`CGRequestScreenCaptureAccess` 首次弹窗 vs 已 denied 后不再弹）**：TC-M-001 观察首次弹窗；TC-M-003 备注“若已 denied，再点不弹窗，只能去系统设置手动勾选”。
- **死角2（授权后回 app 无 activation 监听，靠手动 Recheck）**：TC-M-003 隐含验证 —— 授权后回 app 需点 Recheck / Continue 才前进；无 activation 监听是可接受降级。
- **死角4（跳过后 clipboardEnabled=false → 剪贴板监听 pause）**：TC-M-006 顺带观察，不影响其它快捷键。
- **死角5（`startFullExperienceServices()` 幂等）**：由 code review 保证（onComplete 后 window 置 nil 天然单次），无独立用例。

**TC-M-009 known-limitation**：`SettingsViewModel` 权限入口若源码仍走旧 `openSystemSettings`（未补 request），本迭代不强制改造（review §五判定为 P2 遗留），TC-M-009 标记 known-limitation，不阻塞验收。

---

## 用例总览

| 编号 | 标题 | 关联 AC / 需求 | 类型 | 优先级 | 执行者 |
|------|------|------|------|------|------|
| TC-U-001 | 协议扩展未破坏既有 conformer | AC-8 / P-1.1 | unit | P0 | 自动化 |
| TC-U-002 | 进入 .screenRecording 调 request 恰一次 | AC-8 / P-1.1 | unit | P0 | 自动化 |
| TC-U-003 | openPermissionSettings 先 request 后 openSettings | AC-8 / P-1.1 | unit | P0 | 自动化 |
| TC-U-004 | skipOnboarding 写 flag、不强制 clipboard、回调 onComplete | AC-5/6 / P-2.3 | unit | P0 | 自动化 |
| TC-U-005 | skipOnboarding 遍历 7 步参数化均可跳 | AC-4/5 / P-2.1 | unit | P0 | 自动化 |
| TC-U-006 | 跳过时 hotkey 持久化策略 | P-2.3 | unit | P1 | 自动化 |
| TC-U-007 | MockPermissionService spy 计数/返回值可配 | AC-8（基础设施） | unit | P0 | 自动化 |
| TC-M-001 | 首启触发系统授权弹窗 | AC-1 / P-1.1 | manual | P0 | 人工 |
| TC-M-002 | app 出现在系统设置列表 | AC-2 / P-1.1 | manual | P0 | 人工 |
| TC-M-003 | 授权后可继续（含 Recheck 隐含验证） | AC-3 / P-1.3 | manual | P0 | 人工 |
| TC-M-004 | Skip Setup 按钮 7 步全可见 | AC-4 / P-2.1 | manual | P0 | 人工 |
| TC-M-005 | Skip 弹确认 Alert，Cancel 不改变 | AC-4 / P-2.2 | manual | P0 | 人工 |
| TC-M-006 | Skip 确认后进主界面 | AC-5 / P-2.3 | manual | P0 | 人工 |
| TC-R-001 | swift test 全绿 ≥ 133 | AC-8 | regression | P0 | 自动化 |
| TC-R-002 | xcodebuild test 全绿 ≥ 119 | AC-8 | regression | P0 | 自动化 |

> **用例总数：15（自动化 9 + 手工 6）**。原 TC-M-007/008/009（覆盖 AC-6/AC-7）按用户决策本迭代不执行，留待后续迭代验证，详见文末「特别提示」与追溯矩阵。

**执行顺序建议**：先自动化（TC-U-001→007 → TC-R-001 → TC-R-002），再手工（TC-M-001→006）。

---

## 一、单元测试（TC-U-*，自动化，可被 swift test / xcodebuild test 执行）

> 依赖基础设施：所有 TC-U 需先完成 TC-U-007（`MockPermissionService` 补 `requestScreenRecordingPrompt()` spy）与 `StaticPermissionService`（`SettingsSourceTests.swift:187`）补该方法返回固定 `true`，否则协议新增方法致编译失败。

### TC-U-001：协议扩展未破坏既有 conformer

- **编号**：TC-U-001
- **标题**：`PermissionServiceProtocol` 增 `requestScreenRecordingPrompt() -> Bool` 后，全部 conformer 均实现且可调用
- **关联**：AC-8 / P-1.1（接口契约 design §五）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：`PermissionServiceProtocol` 已加新方法；`MockPermissionService`、`StaticPermissionService`、真实 `PermissionService` 均已补实现
- **建议放置**：`SnapVaultTests/PermissionServiceTests.swift`（新建）
- **依赖 mock/spy**：直接实例化 `MockPermissionService`、`StaticPermissionService`；真实 `PermissionService` 只断言编译可实例化，**不真调 CG API**（真调会弹系统 UI）
- **执行步骤**：
  1. 实例化 `MockPermissionService`，设 `requestScreenRecordingResult = true`，调 `requestScreenRecordingPrompt()`
  2. 实例化 `StaticPermissionService`，调 `requestScreenRecordingPrompt()`
- **预期结果**：Mock 返回 `true`；Static 返回固定 `true`；测试目标能编译通过（协议 conformance 完整）
- **通过判定**：`XCTAssertTrue(mock.requestScreenRecordingPrompt())` 通过；`XCTAssertTrue(static.requestScreenRecordingPrompt())` 通过；测试进程未弹任何系统对话框

### TC-U-002：进入 .screenRecording 调 request 恰一次

- **编号**：TC-U-002
- **标题**：`continueToNextStep()` 从 `.clipboardPrivacy` 进入 `.screenRecording` 时调用 `requestScreenRecordingPrompt()` 恰好一次
- **关联**：AC-8 / P-1.1（design §4.2）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：VM 注入 `MockPermissionService`；`clipboardAcknowledged = true`（使 clipboardPrivacy 可前进）
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift` 追加
- **依赖 mock/spy**：`MockPermissionService.requestScreenRecordingCallCount`（spy 计数，见 TC-U-007）
- **执行步骤**：
  1. 构造 VM，`viewModel.step = .clipboardPrivacy`，`viewModel.acknowledgeClipboard()`
  2. 调 `viewModel.continueToNextStep()`；`await viewModel.refreshPermissions()` 等待异步 Task 落定（或直接断言计数）
- **预期结果**：`step == .screenRecording`；request 被调用一次
- **通过判定**：`XCTAssertEqual(permissions.requestScreenRecordingCallCount, 1)` 且 `XCTAssertEqual(viewModel.step, .screenRecording)`

### TC-U-003：openPermissionSettings 先 request 后 openSettings（顺序断言）

- **编号**：TC-U-003
- **标题**：`openPermissionSettings(.screenRecording)` 在调 `openSystemSettings` 前先调 `requestScreenRecordingPrompt`
- **关联**：AC-8 / P-1.1（design §4.2，防绕过 continue 直接点“打开设置”）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：VM 注入 `MockPermissionService`
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift` 追加
- **依赖 mock/spy**：Mock 内维护一条 `callLog: [String]`，`requestScreenRecordingPrompt` 追加 `"request"`，`openSystemSettings` 追加 `"openSettings"`
- **执行步骤**：
  1. 构造 VM，调 `viewModel.openPermissionSettings(.screenRecording)`
- **预期结果**：调用顺序为 `[request, openSettings]`
- **通过判定**：`XCTAssertEqual(permissions.callLog, ["request", "openSettings"])`；且 `permissions.opened == [.screenRecording]`。（补充：`openPermissionSettings(.accessibility)` 不应调 request —— `XCTAssertEqual(permissions.requestScreenRecordingCallCount, 0)`）

### TC-U-004：skipOnboarding 写 flag、不强制 clipboard、回调 onComplete

- **编号**：TC-U-004
- **标题**：`skipOnboarding()` 写 `onboardingCompleted=true`、不强制 `clipboardEnabled=true`、触发 `onComplete` 一次
- **关联**：AC-5、AC-6（持久化侧证）/ P-2.3（design §4.2 差异表）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：VM 注入 `InMemorySettingsService`（现有）；`didComplete = false`
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift` 追加
- **依赖 mock/spy**：现有 `InMemorySettingsService`（其默认取 `AssistantSettingDefaults.values`；**注意：`clipboard.enabled` 默认值为 `"true"`，见 `PersistenceController.swift:307`，并非 PRD/design 假设的 false**）；`onComplete` 闭包置 `didComplete = true`
- **执行步骤**：
  1. 构造 VM（不预设任何权限授权，模拟“权限未授即跳过”）
  2. `await viewModel.skipOnboarding()`
  3. 读回 settings 三个键
- **预期结果**：`onboardingCompleted == true`；`clipboardEnabled == false`；`didComplete == true`。**关键：因 `clipboard.enabled` 代码默认为 `true`，要使跳过后剪贴板不自动启用（PRD P-2.3“保留用户选择权/延后启用”意图），`skipOnboarding()` 必须显式写入 `false`——不能像 design §4.2 差异表所写的“不写（保持默认 false）”那样留空（该表把默认误判为 false）。**
- **通过判定**：`XCTAssertTrue(onboardingCompleted)`、`XCTAssertFalse(clipboardEnabled)`、`XCTAssertTrue(didComplete)` 三者全过。由于 `InMemorySettingsService` 中 `clipboard.enabled` 默认即为 `true`，`XCTAssertFalse` 仅当 `skipOnboarding()` **显式写 false** 时才通过。与 `testCompletingWritesSettingsAndEnablesLaunchAtLogin`（clipboard=true）形成对照。（本项详见 review §三阻塞级发现）

### TC-U-005：skipOnboarding 遍历 7 步参数化均可跳

- **编号**：TC-U-005
- **标题**：在 `.welcome/.searchHotkey/.clipboardPrivacy/.screenRecording/.accessibility/.launchAtLogin/.done` 任意一步调 `skipOnboarding()` 均成功且行为一致
- **关联**：AC-4、AC-5 / P-2.1（footer 与 step 无关，全步可跳）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：不预设权限（确保“未授权步骤也能跳”）
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift` 追加
- **依赖 mock/spy**：`InMemorySettingsService`；for-in 遍历 `OnboardingStep.allCases`，每步用**新构造** VM 避免状态污染
- **执行步骤**：
  1. `for step in OnboardingStep.allCases`：构造新 VM，设 `viewModel.step = step`
  2. `await viewModel.skipOnboarding()`，不应抛错
  3. 每次断言 settings 写入 + onComplete 触发
- **预期结果**：7 步每步均：`onboardingCompleted == true` 且 `didComplete == true`，无异常抛出
- **通过判定**：循环内每步 `XCTAssertTrue(onboardingCompleted, "step=\(step)")` 与 `XCTAssertTrue(didComplete, "step=\(step)")` 均过；`OnboardingStep.allCases.count == 7`

### TC-U-006：跳过时 hotkey 持久化策略

- **编号**：TC-U-006
- **标题**：跳过时若 hotkey 已录入有效则持久化其值；未录入则不写非法值（按 design §4.2 默认 `option+space`）
- **关联**：P-2.3（design §4.2 hotkey 行）
- **类型**：unit ｜ **优先级**：P1
- **前置条件**：VM 注入 `MockHotkeyValidationService`（`persisted = "option+space"`）
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift` 追加
- **依赖 mock/spy**：`MockHotkeyValidationService.persistCurrentShortcutString()` 返回受控字符串；`InMemorySettingsService`
- **执行步骤**：
  1. 设 `hotkeys.persisted = "option+space"`，构造 VM，`await viewModel.skipOnboarding()`
  2. 读回 `settings.stringValue(for: .searchHotkey)`
- **预期结果**：`searchHotkey == "option+space"`（持久化了 `persistCurrentShortcutString()` 的返回值）
- **通过判定**：`XCTAssertEqual(searchHotkey, "option+space")`；若实现选择“未录入不写”，则断言值等于默认键而非空串/非法值（以实际 `skipOnboarding` 策略为准，二者取一，禁止写空串）

### TC-U-007：MockPermissionService spy 计数/返回值可配（测试基础设施）

- **编号**：TC-U-007
- **标题**：`MockPermissionService` 新方法 `requestScreenRecordingPrompt()` 支持 spy 计数与返回值可配置
- **关联**：AC-8（TC-U-002/003 前置基石，design §五 spy 样例）
- **类型**：unit ｜ **优先级**：P0
- **前置条件**：`MockPermissionService` 按 design §五补 `requestScreenRecordingResult` + `requestScreenRecordingCallCount` + `callLog`
- **建议放置**：`SnapVaultTests/OnboardingViewModelTests.swift`（改现有 Mock）
- **依赖 mock/spy**：本用例即“给测试基础设施加断言”
- **执行步骤**：
  1. `mock.requestScreenRecordingResult = false`，调一次 `requestScreenRecordingPrompt()` → 返回 false，计数=1
  2. 设 `= true`，再调一次 → 返回 true，计数=2
- **预期结果**：返回值随配置变化；计数累加
- **通过判定**：`XCTAssertFalse(first)`、`XCTAssertTrue(second)`、`XCTAssertEqual(mock.requestScreenRecordingCallCount, 2)`

---

## 二、手工验收用例（TC-M-*，人工执行）

### TC-M-001：首启触发系统授权弹窗

- **编号**：TC-M-001 ｜ **关联**：AC-1 / P-1.1 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：进入 `.screenRecording` 步骤后 **5 秒**内
- **前置条件**：v1.1.0 修复已应用；执行 `tccutil reset ScreenCapture com.freeabyss.qingyu` 重置权限；Clean 构建（`./build_and_run.sh run`）首启
- **执行步骤**：
  1. 终端执行 `tccutil reset ScreenCapture com.freeabyss.qingyu`
  2. Clean 构建并启动应用，走 onboarding 到 clipboardPrivacy 后点 Continue 进入 screenRecording 步骤（或在该步点主 CTA）
  3. 观察是否弹出系统屏幕录制授权弹窗
- **预期结果**：`CGRequestScreenCaptureAccess()` 触发系统权限弹窗出现
- **通过判定**：5 秒内看到 macOS 系统级“‘Mac Super Assistant’想要录制这台电脑的屏幕”弹窗即通过；无弹窗即失败并截图（备注：若历史已授权则可能不弹，需先 reset）

### TC-M-002：app 出现在系统设置列表

- **编号**：TC-M-002 ｜ **关联**：AC-2 / P-1.1 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：打开设置页后 **即时**
- **前置条件**：TC-M-001 已执行（已触发一次 request，App 注册进 TCC 候选列表）
- **执行步骤**：
  1. 打开“系统设置 → 隐私与安全 → 屏幕录制与系统录音”
  2. 查看列表中是否有本 App（Mac Super Assistant / Assistant）
- **预期结果**：本 App 出现在屏幕录制列表中，可勾选
- **通过判定**：列表中可见本 App 条目即通过；列表中无本 App 即失败（说明 request 未成功注册 TCC）

### TC-M-003：授权后可继续（含 Recheck 隐含验证）

- **编号**：TC-M-003 ｜ **关联**：AC-3 / P-1.3 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：授权后回 app 点 Recheck/Continue 后 **3 秒**内
- **前置条件**：TC-M-002 完成，App 已出现在列表
- **执行步骤**：
  1. 在系统设置列表勾选本 App 授权屏幕录制
  2. 切回 onboarding app（无 activation 自动检测），点 Recheck（重新检查）按钮
  3. 观察 Continue 按钮状态，点 Continue
- **预期结果**：勾选后 `CGPreflightScreenCaptureAccess()` 返回 true，Recheck 后 Continue 变 enabled，可进入下一步（accessibility）
- **通过判定**：点 Recheck 后 Continue 由禁用变可用、点击后进入 accessibility 步骤即通过。**备注（死角1/2）**：若之前已 denied，主 CTA 不再弹系统窗，只能靠系统设置手动勾选 + Recheck；无 activation 监听、需手动 Recheck 是可接受降级

### TC-M-004：Skip Setup 按钮 7 步全可见

- **编号**：TC-M-004 ｜ **关联**：AC-4 / P-2.1 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：每步切换后 **即时**
- **前置条件**：v1.1.0 构建启动，进入 onboarding
- **执行步骤**：
  1. 依次走过 welcome / searchHotkey / clipboardPrivacy / screenRecording / accessibility / launchAtLogin / done 7 步
  2. 每步查看 footer 左下角是否有“Skip Setup / 跳过设置”按钮
- **预期结果**：7 步每一步 footer 左下角均可见 Skip Setup 按钮
- **通过判定**：7 步逐步核对，全部可见即通过；任一步缺失即失败并记录该步

### TC-M-005：Skip 弹确认 Alert，Cancel 不改变

- **编号**：TC-M-005 ｜ **关联**：AC-4 / P-2.2 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：点击后 **即时**
- **前置条件**：onboarding 任意步骤
- **执行步骤**：
  1. 点“Skip Setup”，观察弹出的确认 Alert
  2. 核对标题（Skip onboarding? / 跳过引导?）、内容文案、两个按钮（Skip / Cancel）
  3. 点 Cancel
- **预期结果**：弹出含标题+内容+Skip/Cancel 两按钮的 Alert；点 Cancel 关闭 Alert，停留在原步骤，无任何 settings 变化
- **通过判定**：Alert 三要素齐全且 Cancel 后仍在原步骤、onboarding 未关闭即通过；无 Alert 直接跳过（误触风险）即失败

### TC-M-006：Skip 确认后进主界面

- **编号**：TC-M-006 ｜ **关联**：AC-5 / P-2.3 ｜ **类型**：manual ｜ **优先级**：P0 ｜ **执行者**：人工
- **观察窗口**：点 Skip 后 **3 秒**内
- **前置条件**：TC-M-005 的 Alert 已弹出
- **执行步骤**：
  1. Alert 中点“Skip”
  2. 观察 onboarding 窗口关闭、状态栏图标出现、主功能可用
  3. 顺带观察剪贴板相关快捷键（死角4）
- **预期结果**：onboarding 窗口关闭 → 主界面出现（状态栏图标可见）→ `startFullExperienceServices()` 生效
- **通过判定**：onboarding 关闭且状态栏图标出现、可打开搜索面板即通过。**备注（死角4）**：跳过后 `clipboardEnabled=false`，剪贴板监听 pause，剪贴板快捷键静默不录制但不 crash、不影响其它快捷键

---

## 三、回归（TC-R-*，自动化）

### TC-R-001：swift test 全绿

- **编号**：TC-R-001 ｜ **关联**：AC-8 ｜ **类型**：regression ｜ **优先级**：P0 ｜ **执行者**：自动化
- **前置条件**：v1.1.0 分支，TC-U-001~007 新增用例已合入测试目标
- **执行步骤**：
  1. 项目根目录执行 `swift test`
- **预期结果**：全部通过，无 failure/error；用例总数 ≥ v1.0.1 基线 126，新增 U-001~007 后应 ≥ 133（具体以实际实现条数为准，**用例数不减**为通过条件）
- **通过判定**：退出码 0，输出 `Test Suite ... passed`，无 `failed` 计数；用例总数 ≥ 133（若参数化用例合并计数导致略少，则以“既有 126 全绿 + 新增全绿 + 总数不减”为准）

### TC-R-002：xcodebuild test 全绿

- **编号**：TC-R-002 ｜ **关联**：AC-8 ｜ **类型**：regression ｜ **优先级**：P0 ｜ **执行者**：自动化
- **前置条件**：v1.1.0 分支
- **执行步骤**：
  1. 执行 `xcodebuild test -scheme SnapVault -destination 'platform=macOS'`
- **预期结果**：输出 `** TEST SUCCEEDED **`；失败用例数 0；用例总数 ≥ v1.0.1 基线 119（新增用例是否入 Xcode target 属 P2 遗留：若入 target 则 ≥ 119 + 新增数，未入则保持 119）
- **通过判定**：输出 `TEST SUCCEEDED` 且退出码 0 即通过；出现 `TEST FAILED` 或任何用例 failure 即失败，需附失败用例与日志

---

## 追溯矩阵（AC → 用例）

| AC | 描述 | 覆盖用例 |
|----|------|---------|
| AC-1 | Clean 构建首启触发系统授权弹窗 | TC-M-001 |
| AC-2 | app 出现在系统设置列表 | TC-M-002 |
| AC-3 | 授权后可继续 | TC-M-003 |
| AC-4 | Skip 按钮全 7 步可见 | TC-M-004, TC-M-005, TC-U-005 |
| AC-5 | Skip 后进主界面 | TC-M-006 + TC-U-004/005 |
| AC-6 | 重启不重弹 | —（未验证，留待后续迭代，详见 PR body；代码层持久化 `onboardingCompleted=true` 由 TC-U-004 单测覆盖，端到端重启行为未验） |
| AC-7 | 跳过后按需申请可用 | —（未验证，留待后续迭代；code review 坐实 AppDelegate.ensureScreenRecordingPermission / OnboardingVM 复用同一 requestScreenRecordingPrompt API，但未做端到端验证） |
| AC-8 | 既有测试全绿 + 新增单测覆盖 | TC-R-001, TC-R-002, TC-U-001~007 |

---

## 特别提示

**注**：TC-M-007（重启不重弹）/TC-M-008（按需申请 Alert）/TC-M-009（设置面板入口）原计划覆盖 AC-6/AC-7。本次迭代因用户决策未执行，留待后续迭代验证。code review 确认 AppDelegate.ensureScreenRecordingPermission 已对称补 requestScreenRecordingPrompt（T-003），OnboardingVM/View 逻辑与测试覆盖完整；重启与按需申请的端到端行为待下一迭代补验。
