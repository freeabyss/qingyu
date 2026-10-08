# v1.1.0 测试用例评审记录

- **评审时间**：2026-07-02
- **评审对象**：doc/iterations/v1.1.0/test/cases.md（18 条：TC-U 7 + TC-M 9 + TC-R 2）
- **评审人**：test-review subagent
- **评审结论**：APPROVED_WITH_MINOR_FIXES

## 一、AC 覆盖完整性

追溯矩阵核对（逐条比对 cases.md 尾部矩阵与实际用例正文）：

| AC | 覆盖用例（矩阵声明） | 核对结论 |
|----|------|------|
| AC-1 | TC-M-001 | 一致，覆盖 |
| AC-2 | TC-M-002 | 一致，覆盖 |
| AC-3 | TC-M-003 | 一致，覆盖 |
| AC-4 | TC-M-004, TC-M-005, TC-U-005 | 一致；TC-U-005 是 VM 层"任意步可跳"代理，按钮可见性由 TC-M-004 手工保证，组合合理 |
| AC-5 | TC-M-006 + TC-U-004/005 | 一致，覆盖 |
| AC-6 | TC-M-007 + TC-U-004（持久化侧证） | 一致，覆盖 |
| AC-7 | TC-M-008, TC-M-009 | 覆盖，但见下方"擦边球"判定 |
| AC-8 | TC-R-001, TC-R-002, TC-U-001~007 | 一致，覆盖 |

**结论：AC-1~AC-8 全部被至少一条 TC 覆盖，矩阵与正文一致，无笔误。**

**AC-7 "擦边球"判定**：AC-7 的核心断言是"申请路径与 onboarding 一致（复用同一 request 逻辑）"。TC-M-008 只验证"弹 Alert + 点打开设置能跳系统设置"，**未强制验证 `ensureScreenRecordingPermission()` 打开设置前确有 `requestScreenRecordingPrompt()` 调用**（即 design §4.4 要求补的对称 request）。而该路径 `AppDelegate.ensureScreenRecordingPermission()` 是内部 `new PermissionService()`（`AppDelegate.swift:768`），无 DI，无法单测——只能靠手工/code review。**判定：现状可接受**（review §五已将其列为手工验收 + code review 保证），但建议 TC-M-008 通过判定补一句"code review 确认 openSystemSettings 前有 requestScreenRecordingPrompt 调用"，见 §三非阻塞建议。

## 二、按用例逐条评审

### TC-U-001（协议扩展未破坏既有 conformer）
- 结论：通过
- 意见：3 处 conformer 已核实——真实 `PermissionService`（`PermissionService.swift:29`）、`MockPermissionService`（`OnboardingViewModelTests.swift:114`）、`StaticPermissionService`（`SettingsSourceTests.swift:187`）。已确认 **`PermissionServiceProtocol` 无任何 protocol extension 默认实现**（grep `extension PermissionServiceProtocol` = 0 处），故新增方法后缺任一 conformer 实现即编译失败，编译期即可捕获——用例设计的编译期兜底成立。三个实现在测试中均可实例化（Mock/Static 无副作用，真实 `PermissionService` 仅断言可实例化不调 CG API）。用例正确。

### TC-U-002（进入 .screenRecording 调 request 恰一次）
- 结论：通过
- 意见：判定明确（`requestScreenRecordingCallCount == 1` + `step == .screenRecording`）。依赖 TC-U-007 提供 spy 计数，顺序合理（cases.md 顶部已声明 TC-U-007 为前置）。注意执行步骤中 `continueToNextStep()` 内是 `Task { await refreshPermissions() }`（`OnboardingViewModel.swift:72`），request 调用应发生在同步路径（进入 step 时）而非异步 Task 内，否则计数断言时序不稳；用例已给"或直接断言计数"的兜底，可接受。

### TC-U-003（openPermissionSettings 先 request 后 openSettings）
- 结论：通过
- 意见：`callLog` 顺序断言 + accessibility 分支不调 request 的反向断言，设计严谨。现状 `openPermissionSettings`（`OnboardingViewModel.swift:95-97`）直接转调 `openSystemSettings`，本迭代需按 design §4.2 加 `.screenRecording` 分支的 request——用例正确锁定该行为。

### TC-U-004（skipOnboarding 写 flag、不强制 clipboard、回调 onComplete）
- 结论：修订（已改，见 §四）
- 意见：**发现阻塞级事实错误**——原用例"依赖 mock"称"默认 `clipboardEnabled` 取 `AssistantSettingDefaults`，预期为 false"。实测 `AssistantSettingDefaults.values["clipboard.enabled"] = "true"`（`PersistenceController.swift:307`），默认是 **true**。同时 design §4.2 差异表把 skip 的 clipboardEnabled 写为"不写（保持默认 false）"——**这个默认判断也是错的**。若 `skipOnboarding()` 真的"不写" clipboardEnabled，则读回为 true，`XCTAssertFalse(clipboardEnabled)` 必然失败，且违背 PRD P-2.3"跳过后 clipboard 默认 false / 保留用户选择权"的产品意图。**结论：`skipOnboarding()` 必须显式写 `clipboardEnabled = false`。** 已修订 TC-U-004 明确此点并标注 design 文档缺陷。

### TC-U-005（skipOnboarding 遍历 7 步参数化均可跳）
- 结论：通过
- 意见：每步新构造 VM 防污染（cases 已说明），`OnboardingStep.allCases.count == 7` 已核实（`OnboardingViewModel.swift:133-141` 恰 7 例）。断言 message 带 `step=` 便于定位。设计合理。

### TC-U-006（跳过时 hotkey 持久化策略）
- 结论：通过
- 意见：`MockHotkeyValidationService.persisted = "option+space"`（`OnboardingViewModelTests.swift:133`）已存在，无需新建 mock。用例给了"已录入持久化 / 未录入不写非法值"二选一判定并禁止写空串，与 design §4.2 hotkey 行一致。合理。

### TC-U-007（MockPermissionService spy 计数/返回值可配）
- 结论：通过
- 意见：作为 TC-U-002/003 的基础设施，需给现有 `MockPermissionService` 补 `requestScreenRecordingResult` + `requestScreenRecordingCallCount` + `callLog`。与 design §五 spy 样例一致；`callLog` 供 TC-U-003 顺序断言。合理。**注：现有 Mock 的 `openSystemSettings` 已 append 到 `opened`（line 122-124），补 `callLog` 时需在同方法内一并 append `"openSettings"`。** 用例已隐含，实现时勿漏。

### TC-M-001（首启触发系统授权弹窗）
- 结论：通过
- 意见：`tccutil reset ScreenCapture com.freeabyss.qingyu` 命令完整，bundle id **已核实与项目一致**（`project.pbxproj` `PRODUCT_BUNDLE_IDENTIFIER = com.freeabyss.qingyu`）。弹窗文案"'Mac Super Assistant'想要录制…"中的 app 名 **已核实**（`Info.plist` `CFBundleDisplayName = Mac Super Assistant`）。判定明确（5 秒窗口 + 截图留证）。

### TC-M-002（app 出现在系统设置列表）
- 结论：通过
- 意见：判定明确（列表可见 = 通过）。依赖 TC-M-001 先触发 request，顺序正确。app 名匹配已核实（可能显示 Assistant 或 Mac Super Assistant，用例已两者并列，稳妥）。

### TC-M-003（授权后可继续，含 Recheck 隐含验证）
- 结论：通过
- 意见：Recheck 按钮 **已核实存在且贴合实际**——`OnboardingView.swift:140` `Button(L10n.localized("onboarding.permission.recheck")) { Task { await viewModel.refreshPermissions() } }`，用例"点 Recheck（重新检查）"表述与源码一致。覆盖 review §十死角 1（已 denied 不再弹）/死角 2（无 activation 监听、手动 Recheck）。合理。

### TC-M-004（Skip Setup 按钮 7 步全可见）
- 结论：通过
- 意见：7 步逐步核对，判定明确（任一步缺失即失败并记录）。footer 与 step 无关，天然满足 AC-4。**成本评审（针对评审要点 4）**：TC-M-004 是"每步看一眼 footer 是否有按钮"，非"每步真跑一遍完整 skip"，7 步全测成本低（仅切换步骤观察），**无需削减为抽 3 步**——真正高成本的是 skip 后进主界面/重启（TC-M-006/007），而那两条本就只跑一次。结论：7 步全测合理，保留。

### TC-M-005（Skip 弹确认 Alert，Cancel 不改变）
- 结论：通过
- 意见：Alert 三要素 + Cancel 后停留原步骤 + 无 settings 变化，判定明确。防误触语义（AC-4/P-2.2）覆盖到位。

### TC-M-006（Skip 确认后进主界面）
- 结论：通过
- 意见：判定明确（onboarding 关闭 + 状态栏图标 + 可开搜索面板）。顺带覆盖 review §十死角 4（clipboardEnabled=false → 剪贴板 pause 不 crash）。合理。

### TC-M-007（跳过后重启不重弹）
- 结论：通过
- 意见：判定明确。依赖 TC-M-006 成功，顺序正确。覆盖 AC-6。

### TC-M-008（跳过后按 hotkey 截图弹按需申请 Alert）
- 结论：修订（已改，见 §四）
- 意见：路径可复现——`ensureScreenRecordingPermission()`（`AppDelegate.swift:767`）守在 `performRegionCapture/Window/Screen`（640/682/738）前，快捷键框架 skip 后经 `startFullExperienceServices → registerGlobalShortcuts` 仍激活（跳过只影响 clipboardEnabled，不影响 hotkey 注册），用户能复现。覆盖 review §十死角 3。**修订点**：补 code review 项以坐实 AC-7"复用同一 request 逻辑"（现有源码 `AppDelegate.swift:778` 打开设置前**尚未**调 request，本迭代必须补）。

### TC-M-009（设置面板按需申请入口存在，known-limitation）
- 结论：通过
- 意见：标 known-limitation 可接受——review §五已判定 `SettingsViewModel` 走旧 `openSystemSettings`（未补 request）为 P2 遗留、不阻塞。P1 优先级 + 明确降级说明，合理。

### TC-R-001（swift test 全绿 ≥ 133）
- 结论：通过
- 意见：下限清晰——v1.0.1 基线 126 + 新增 7（TC-U-001~007）= ≥ 133，且给了"参数化合并计数则以'126 全绿 + 新增全绿 + 总数不减'为准"的兜底。基线 126 与 v1.0.1 review 一致。合理。

### TC-R-002（xcodebuild test 全绿 ≥ 119）
- 结论：通过
- 意见：下限 119 清晰；新增用例入 Xcode target 属 P2、"入则 ≥119+新增、未入则保持 119"标注明确。与 v1.0.1 review（119/119 基线）一致。合理。

## 三、发现的问题

### 阻塞级（必须修订）
1. **TC-U-004 clipboardEnabled 默认值事实错误（已修订）**：`AssistantSettingDefaults.values["clipboard.enabled"]` 实为 `"true"`（`PersistenceController.swift:307`），非 cases/design 假设的 false。连带影响：`skipOnboarding()` 若按 design §4.2"不写 clipboardEnabled"实现，则读回 true，TC-U-004 `XCTAssertFalse` 必失败，且违背 PRD P-2.3 意图。**开发实现约束：`skipOnboarding()` 必须显式 `set(false, for: .clipboardEnabled)`。** 已改 TC-U-004（§四）。

### 非阻塞级（建议）
1. **design.md §4.2 差异表缺陷（不阻塞用例评审，指出待后续修）**：差异表将 skip 的 clipboardEnabled 标为"不写（保持默认 false）"，默认值判断错误。本 review 已在 TC-U-004 修订中给出正确约束（显式写 false），开发以 cases.md TC-U-004 为准即可；design.md 文档本身建议在开发环节顺手订正，但不阻塞用例进入 Gate 3。
2. **TC-M-008 建议补 code review 项**：AC-7 核心是"复用同一 request 逻辑"，而 `AppDelegate.ensureScreenRecordingPermission()` 无 DI 不可单测。建议在 TC-M-008 通过判定追加"code review 确认 `openSystemSettings(for:.screenRecording)` 前有 `requestScreenRecordingPrompt()` 调用"，使 AC-7 的"复用"断言不仅靠手工观感。已在 §四追加。
3. **TC-U-002 时序提示（已含兜底，无需改）**：request 应在 `continueToNextStep` 同步进入 step 时调用，而非放进 `Task { await refreshPermissions() }` 异步块，否则计数断言时序不稳。用例已给"直接断言计数"兜底，实现时注意即可。

## 四、修订记录（直接改了 cases.md）

1. **TC-U-004**：
   - "依赖 mock/spy"：把"默认 clipboardEnabled 预期为 false"更正为"`clipboard.enabled` 默认值为 `"true"`（`PersistenceController.swift:307`），并非 PRD/design 假设的 false"。
   - "预期结果"：新增关键说明——`skipOnboarding()` 必须**显式写 false**，不能按 design §4.2"不写（保持默认 false）"留空（该表把默认误判为 false）。
   - "通过判定"：补充"`XCTAssertFalse` 仅当显式写 false 时才通过"，并指向 review §三阻塞级发现。
2. **TC-M-008**：通过判定追加 code review 项（确认打开设置前调用 requestScreenRecordingPrompt），坐实 AC-7"复用同一 request 逻辑"。

## 五、最终结论

- **状态：APPROVED_WITH_MINOR_FIXES**
- 阻塞级问题：1 条（TC-U-004 clipboardEnabled 默认值错误）——已直接修订 cases.md，下一环输入自洽。
- AC 覆盖：完整（AC-1~AC-8 全覆盖，矩阵与正文一致）。
- 遗漏检查：review §十死角 1/2/3/4/5 均有 TC 追溯或 code review 兜底；P-2.4（TC-M-008）、StaticPermissionService 编译失败风险（TC-U-001）均覆盖。无遗漏。
- 冗余检查：TC-U-002（进入 step 调 request）与 TC-U-003（openPermissionSettings 顺序）验证不同触发路径，**不重叠**，均保留；无可删用例。
- **是否可进入 Gate 3 任务拆解：是**（阻塞项已修订，剩余 2 条为非阻塞建议 + 1 条 design 文档订正提示）。
</content>
</invoke>
