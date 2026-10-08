# v1.1.0 PRD —— Onboarding 死锁修复：屏幕录制权限申请 + 跳过向导

> 本迭代同时含 **Bug 修复**（TCC 屏幕录制权限申请断点）与 **新功能**（跳过 onboarding）。
> 目标输出仅覆盖本迭代新增/变更部分，`doc/prd.md`（全局累积版）仅作背景参考，不在此写入。
> 关联 Issue：#3 · 分支：v1.1.0 · 模式：auto

---

## 一、背景与问题定义

Onboarding 流程存在两个互相叠加、最终形成**死锁**的问题，导致部分用户**完全无法进入应用**：

### 现象
1. **Bug（阻塞级）**：走到"屏幕录制"步骤，点"打开系统偏好设置"，进入系统"隐私与安全 → 屏幕录制与系统录音"页，**本 App 未出现在列表中**，无法勾选授权。
2. **无跳过入口**：Onboarding 是 7 步硬串行流程，权限未授时硬 `guard return`，无任何跳过分支。

### 诊断根因（硬证据）
- `PermissionService.swift:40`：屏幕录制状态检测仅用只读预检 `CGPreflightScreenCaptureAccess()`，onboarding 打开系统设置 URL（`openSystemSettings`，`PermissionService.swift:46-54`）前**从未调用任何会触发 TCC 注册的 API**。macOS TCC 机制要求 App **至少调用一次需要该权限的真实 API**，系统才会把它加入设置候选列表。
- 对比：Accessibility 在 `PermissionService.swift:60-63` 已用 `AXIsProcessTrustedWithOptions(prompt=true)` 正确触发注册，屏幕录制缺了对称的 request 调用。
- `OnboardingViewModel.swift:73-74`：`.screenRecording` 步骤 `guard permissionStatuses[.screenRecording]?.isAuthorized == true else { return }`，权限拿不到就前进不了。
- `OnboardingView.swift:100-111`：footer 仅有 `Quit` / `Continue` 两个按钮，全仓 grep `skip|Skip` = 0 处，无跳过入口。
- 次要放大因素：`build_and_run.sh` 默认清 DerivedData 重建 + adhoc 签名，CDHash 每次变化，历史 TCC 授权会 stale。

### 死锁链条
用户拿不到屏幕录制权限 → 卡在 `.screenRecording` 步骤（`canContinueCurrentStep` 恒 false）→ 无跳过入口 → 完全无法进入主界面。

---

## 二、用户故事

- **US-1（Bug 修复）**：作为**首次启动应用的用户**，我希望在 onboarding 屏幕录制步骤能**看到系统权限弹窗、并能在系统设置中找到本应用**，以便正常授权后继续 onboarding。
- **US-2（新功能）**：作为**不愿授予全部权限或想稍后配置的用户**，我希望在 onboarding **任意步骤**都能**点"跳过设置"直接进入主界面**，被跳过的权限延后到我真正使用相关功能时再申请。

---

## 三、产品需求

### Bug 修复部分（对应 US-1）
- **P-1.1**：进入 `.screenRecording` 步骤或点击"打开系统偏好设置"按钮时，主动调用 `CGRequestScreenCaptureAccess()` 触发一次真实 TCC 请求；这会促使系统首次注册本 App 到 TCC 数据库并加入设置候选列表。抽象为 `PermissionService.requestScreenRecordingPrompt()`。
- **P-1.2**：若 `CGRequestScreenCaptureAccess()` 直接返回 `true`（用户之前已授权），onboarding 应能识别并允许前进。
- **P-1.3**：若返回 `false`，系统弹窗要求授权；用户去系统设置授权后回到 onboarding，`CGPreflightScreenCaptureAccess()` 返回 `true`，Continue 按钮 enabled 允许继续。

### 新功能部分（对应 US-2）
- **P-2.1**：Onboarding footer 增加**全局可见**的"跳过设置"（Skip Setup）按钮，7 步任意步骤都可点。
- **P-2.2**：点击后弹**确认对话框**（Alert）避免误触，确认后才执行跳过。
- **P-2.3**：确认后调用 `skipOnboarding()`：
  - Core Data 写入 `SettingKey.onboardingCompleted = true`（复用现有键，不新增字段）。
  - **不**强制启用 `clipboardEnabled` —— **决策：默认 false**，保留用户选择权，延后由主界面首次剪贴板操作或设置面板启用。（注意与正常完成流程 `completeIfPossible` 中 `clipboardEnabled=true` 的差异，见 `OnboardingViewModel.swift:122`）
  - hotkey：若用户已录入有效快捷键则持久化其值，否则用**默认快捷键 `⌥Space`**（`option+space`，见 `KeyboardShortcuts+Names.swift:10`、`PersistenceController.swift:305`）。
  - 调用 `onComplete()` 关闭向导，触发 `AppDelegate.startFullExperienceServices()`（见 `AppDelegate.swift:202-208`）。
- **P-2.4**：跳过后主界面运行时，若用户使用需要屏幕录制/辅助功能权限的功能（截图、快捷键触发）而权限未授，给出**明确的按需申请提示**（模态弹窗），不闪退不静默失败。
- **P-2.5**：跳过后重启应用不再显示 onboarding（`onboardingCompleted=true` 已持久化，`loadOnboardingCompletionState` 读取，见 `AppDelegate.swift:225-236`）。

---

## 四、验收标准（对齐 issue #3 AC-1~AC-8）

- **AC-1**（P-1.1）：Clean 构建首启（`tccutil reset ScreenCapture com.freeabyss.qingyu` 后），进入屏幕录制步骤能触发系统授权弹窗。
- **AC-2**（P-1.1）：打开系统设置"隐私与安全 → 屏幕录制"页，本 App 出现在列表中。
- **AC-3**（P-1.3）：授权后 `CGPreflightScreenCaptureAccess()` 返回 true，屏幕录制步骤 Continue 按钮 enabled，可继续。
- **AC-4**（P-2.1）：Onboarding footer 在 welcome / searchHotkey / clipboardPrivacy / screenRecording / accessibility / launchAtLogin / done 7 步中每一步都有"跳过设置"按钮。
- **AC-5**（P-2.3）：点击跳过 → 确认 → `onboardingCompleted=true`（Core Data）、window 关闭、`startFullExperienceServices()` 被调用、进入主界面。
- **AC-6**（P-2.5）：跳过后重启应用不再弹 onboarding。
- **AC-7**（P-2.4）：跳过后主界面首次触发需屏幕录制/辅助功能权限的操作时，用户能通过入口（弹窗/菜单栏/设置面板）重新申请权限，且申请路径与 onboarding 一致（**复用同一 request 逻辑**）。
- **AC-8**（回归）：既有测试全绿（`swift test` ≥ 126、`xcodebuild test` ≥ 119）；新增单元测试覆盖 `requestScreenRecordingPrompt` 与 `skipOnboarding` 主逻辑。

---

## 五、交互设计

### 跳过按钮
- **位置**：footer 左下角（远离主行动 Continue，避免误触）。当前 footer 左侧为 `Quit` 按钮（`OnboardingView.swift:101`），"跳过设置"与其并列或分组放置于左侧区。
- **文案**：`Skip Setup` / 中文 `跳过设置`。

### 跳过确认 Alert
- 标题：`Skip onboarding?` / `跳过引导？`
- 内容：`You can configure permissions and preferences later in the app settings. Some features may require additional permissions before they work.` / `你可以稍后在应用设置中配置权限和偏好。部分功能可能需要在使用前授予额外权限。`
- 按钮：`Skip`（destructive-ish）/ `Cancel`

### 屏幕录制步骤按钮语义微调
- 主 CTA 保留 `Open System Settings`，点击时**先**调用 `CGRequestScreenCaptureAccess()`，再打开系统设置 URL（`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`，已存在于 `PermissionService.swift:73`）。
- 附加提示文案（可选，若空间允许）：`If the app doesn't appear in the list, quit and relaunch the app.` / `如列表中未出现本应用，请退出并重新启动应用后再试。`

### 跳过后主界面的按需申请入口（P-2.4 实现方式）
- 首次触发需权限功能时（如按 hotkey 截图），弹模态提示：`Screen recording permission required to take a screenshot. Grant now?` → 按钮 `Grant` / `Later`。
- `Grant`：触发与 onboarding 相同的 request + open settings 流程。
- `Later`：静默返回，功能本次不执行（不闪退）。

---

## 六、非功能需求
- 复用/扩展现有 `PermissionServiceProtocol`（`PermissionService.swift:22-26`），新增 `requestScreenRecordingPrompt()` 抽象，让 View/VM 不直接调 CG* API。
- 权限申请代码必须可测：DI 支持 spy 实现用于单元测试（现有 VM 已通过构造注入 `permissionService`，见 `OnboardingViewModel.swift:19-31`）。
- 跳过逻辑不引入新持久化字段，复用 `SettingKey.onboardingCompleted`。记录"哪些权限被延后"为可选优化，非本迭代硬需求。

---

## 七、已知遗留与不做项（本迭代不处理）

| 编号 | 遗留项 | 建议版本 |
|------|--------|---------|
| L-1 | `CFBundleShortVersionString=0.1.0` 与实际 tag 脱节 | 下个 release 号统一 |
| L-2 | `build_and_run.sh` 用 `pgrep -x SnapVault` 检测但可执行文件是 `Assistant` | 顺手改 patch |
| L-3 | entitlements `com.apple.security.screencapture` 键可能非官方 | 启用真自动更新迭代一起核实 |
| L-4 | v1.0.1 P2：`UpdateServiceTests.swift` 未入 Xcode target | 下个 patch 顺手加 |
| L-5 | Sparkle 相关 v1.0.1 已归档遗留（entitlements/appcast/SUPublicEDKey） | 启用真自动更新的独立迭代 |

---

## 关键决策点

- **跳过后 `clipboardEnabled` 默认 false**：保留用户选择权，与正常完成流程强制开启不同，延后启用。
- **跳过后主界面首次触权时弹按需申请 Alert**：复用 `PermissionService` 的 request + open settings 流程，与 onboarding 路径一致。
