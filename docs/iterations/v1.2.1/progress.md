# v1.2.1 开发进度

> Issue：#7　分支：v1.2.1　基线：v1.2.0（8821b92）

## 任务完成情况

| # | 任务 | 文件 | 状态 |
|---|------|------|------|
| T-001 | Bug 2 布局修复：ScrollView 包裹中部 + footer 吸底 | `Qingyu/Views/Onboarding/OnboardingView.swift` | ✅ |
| T-002 | Bug 1 门禁移除：删除 6 处 `ensureOnboardingReady` guard | `CommandBarController` / `ClipboardHistoryWindowController` / `SettingsWindowController` / `ScreenshotWindowController` / `GlobalShortcutManager` | ✅ |
| T-003 | 死接口清理：删除 `onboardingGate` / `ensureOnboardingReady()` | `Qingyu/App/Controllers/AppContainer.swift` | ✅ |
| T-004 | AppDelegate 门禁移除 + `windowWillClose` 引用清理 + 服务幂等 | `Qingyu/App/AppDelegate.swift` | ✅ |
| T-005 | 菜单「欢迎向导」入口（AC-11） | `StatusItemController.swift` + `Localizable.xcstrings`（`menubar.onboarding`） | ✅ |

## 编译与测试记录

- `swift build`：Build complete，0 errors。
- `swift test`：159/159 passed，0 failures（v1.2.0 基线 159，无回归）。
- `xcodebuild ... -configuration Debug clean build`：**BUILD SUCCEEDED**，0 errors。
- 烟雾测试：app 启动稳定，未崩溃。

### 编译 warning 修复（顺带清理 pre-existing Swift 6 mode warning）

编译无 error。`xcodebuild clean build` 后顺带清理了一批 pre-existing warning（工程健康度改进，非 v1.2.1 功能改动）：

| 修复 | 文件 |
|------|------|
| `ScreenshotService` 标 `@unchecked Sendable`（self capture ×2） | `ScreenshotService.swift` |
| MenuBarIcon 移除 mac 不支持的 3x 条目（unassigned child ×5） | `MenuBarIcon.imageset/Contents.json` + 删 `menubar_54.png` |
| `migrator` var→let | `DatabaseManager.swift` |
| `SearchBlacklistRepository` / `UsageStatRepository` 标 `@unchecked Sendable`（self capture ×4） | `SearchBlacklistRepository.swift` / `AppSearchSource.swift` |
| `AppSearchSource` / `FileSearchSource` NSLock→`OSAllocatedUnfairLock`（lock in async ×4） | `AppSearchSource.swift` / `FileSearchSource.swift` |
| `MainActor.run { NSWorkspace.shared.open(url) }` 返回值未使用 ×2 | `SearchCore.swift` / `SearchPanelViewModel.swift` |
| `SettingsServiceProtocol` 加 `T: Sendable` + 3 enum 加 `Sendable`（T.Type non-Sendable ×1） | `AppSetting.swift` + 4 测试 conformer |

### 剩余 warning（保留，pre-existing 高风险）

- `HotkeyConflictDetector.swift:60/77/78`（3 条，Swift 6 mode）：`@MainActor` 类遵循 nonisolated 协议 + `nonisolated init` 赋值 main-actor 属性。修复需重构 `@MainActor` + `nonisolated init` + 默认参数的并发模型（尝试 `@MainActor` 协议会引入默认参数 nonisolated 调用 error），风险高，保留作为独立技术债，建议升级 Swift 6 时统一处理。

## AC 核对（详见 architecture/review.md）

- 代码层满足：AC-01 ~ AC-12 全部。
- 自动化覆盖：AC-12（`OnboardingViewModelTests` 既有用例）。
- 待手动端到端验证：AC-01（首启显示）、AC-06/07/10（布局可见性，默认 + 放大字号 + 明暗模式）。

## 遗留

- ⑥ 上线部署：Release + Developer ID 签名 + notarytool 公证 + staple + GitHub Releases（需用户在真实环境执行 `start.sh release` 并提供签名/公证凭证）。
- 手动 AC 端到端验证（同上）。

---

## T-UI-001:搭建 QingyuUITests target（XCUITest ⑤ 扩展）

- **passes: false** —— target 搭建完成且正确；`xcodebuild test` 运行阻塞于环境授权（非 target 缺陷）

### 产出
- pbxproj 编辑策略：ruby `xcodeproj` gem 1.28.1（`gem install --user-install`，不需 sudo）
- 新增 `QingyuUITests` target：productType `com.apple.product-type.bundle.ui-testing`，`TEST_TARGET_NAME=Qingyu`（不设 `TEST_HOST`/`BUNDLE_LOADER`，符合设计文档 §3.1）；build settings 对齐 QingyuTests（macOS 13、Swift 5、`CODE_SIGN_STYLE=Automatic`/ad-hoc）
- UUID 24 位 hex 大写，不与现有冲突（target UUID `C66729BECCA77395DD91EF6F`）
- 新建 `QingyuUITests/{Info.plist, QingyuUITests.swift}`（bundle id `com.freeabyss.qingyu.uitests`，占位 `testPlaceholder`）
- `Qingyu.xcscheme` Test action 加入 QingyuUITests TestableReference
- `Package.swift` 未动；`Qingyu/` 源码未动

### 验证
- `xcodebuild build-for-testing`：** TEST BUILD SUCCEEDED **（target 编译通过，`QingyuUITests-Runner.app` + xctest 生成，ad-hoc 签名 OK）
- 现有 Qingyu/QingyuTests 编译：不受影响（build-for-testing 一并通过）
- `swift test`：159/159（无回归）
- `xcodebuild test -only-testing:QingyuTests`：** TEST EXECUTE SUCCEEDED **（148 passed，证明 xcodebuild test 环境正常）

### 阻塞（`xcodebuild test -only-testing:QingyuUITests`）
- 失败现象：runner 报 `Timed out while enabling automation mode.`（60s 超时），`testPlaceholder` 未执行
- 根因：macOS UI automation 首次需用户在 GUI 授权 testmanagerd/Xcode 的 UI automation（`com.apple.dt.AutomationModeUI` 服务需显示授权 UI）；CLI agent 环境无法处理 GUI 授权弹窗（`osascript` 调 System Events 同样卡住超时）
- 无法自动授权：TCC.db 受 SIP 保护（CLI 读写均拒）；`tccutil` 只能 reset 不能 grant；`sudo` 需密码不可用
- **非 target 缺陷**：build-for-testing SUCCEEDED + unit test via xcodebuild test 通过，证明 target 配置与 xcodebuild test 环境均正常，阻塞纯在 UI automation 首次 GUI 授权

### 解决方案（需用户在 GUI 执行一次）
1. Xcode GUI 打开 `Qingyu.xcodeproj` > Product > Test 运行 QingyuUITests，处理首次 automation 授权弹窗；或
2. System Settings > Privacy & Security > Accessibility 启用 Xcode Helper / testmanagerd；或
3. System Settings > Privacy & Security > Developer Tools 启用 Xcode

授权后 CLI `xcodebuild test -only-testing:QingyuUITests` 即可通过（target 无需改动）。后续任务 T-UI-002~008 可基于此 target 开发（target 已就绪）。

---

## T-UI-002:实现测试 hook（launch arguments，#if DEBUG 隔离）

- **passes: true** -- 8 个 hook 全部 `#if DEBUG` 包裹；Release build 无 hook 符号；swift test 178/178（159+19）无回归

### 产出
- 新建 `Qingyu/App/UITestSupport.swift`：launch argument 常量 + `UITestSupport` 解析结构体 + `UITestTriggerAction` 枚举 + `UITestMockPermissionService`（mock `PermissionServiceProtocol`），整个文件 `#if DEBUG` 包裹
- `AppDelegate.swift`：`applicationDidFinishLaunching` 消费 8 个 hook（data-dir 在 bootstrapDataStack 之前；reset/mark 在 bootstrapDataStack 之后、loadOnboardingCompletionState 之前--评审 C-8；trigger 延迟到下一 run-loop；skip-shortcuts 在 startFullExperienceServices 内跳过；mock-screen-recording 在 showOnboardingWindow 注入 mock permission service）；所有 hook 代码 `#if DEBUG` 包裹
- `AppContainer.swift`：新增 `resetOnboardingState()` / `markOnboardingCompletedForUITest()`（`#if DEBUG`），操作 Core Data `CDAppSetting`
- `PersistenceController.swift`：`static let shared` 改为 `static var shared` + `_defaultShared` 懒加载单例 + `setDebugShared(_:)` DEBUG override（`--uitest-data-dir` 数据隔离，评审 C-4 确认已有 storeURL 注入能力）
- `DatabaseManager.swift`：`databaseURL()` 检查 `setDebugDatabaseURL(_:)` DEBUG override（GRDB 数据库也重定向到临时目录）
- `Package.swift` 未动（UITestSupport 是 app 源码，在 Qingyu target 内）

### 支持的 hook
| Launch Argument | 作用 |
|----------------|------|
| `--uitest-reset-onboarding` | 清空 onboardingCompletedAt + legacy onboardingCompleted（首启状态） |
| `--uitest-mark-onboarding-completed` | 写入完成标记（跳过 onboarding 直接驻留） |
| `--uitest-data-dir <path>` | 重定向 PersistenceController + DatabaseManager 到临时路径（数据隔离） |
| `--uitest-mock-screen-recording-denied` | 注入 OnboardingViewModel 假权限（denied） |
| `--uitest-mock-screen-recording-authorized` | 注入 OnboardingViewModel 假权限（authorized） |
| `--uitest-trigger <action>` | action ∈ {openSearch, openClipboard, openSettings, openAbout, openOnboarding}，直接调用对应 controller（绕过 status item 点击） |
| `--uitest-large-text` | 模拟放大字号（测 AC-10；flag 已解析，视图侧应用待 T-UI-003+） |
| `--uitest-skip-shortcuts` | 跳过 globalShortcutManager.setupShortcuts（避免热键注册干扰） |

### Release 隔离
- UITestSupport.swift 整个文件 `#if DEBUG` 包裹；AppDelegate/AppContainer/PersistenceController/DatabaseManager 中所有 hook 代码均在 `#if DEBUG` 块内
- `swift build -c release`：Build complete，0 errors；Release 二进制无 UITest 符号（`nm` 验证）
- 无 launch arguments 时 `isUITest == false`，现有 applicationDidFinishLaunching 流程完全不变

### 新增单元测试
- `QingyuTests/UITestSupportTests.swift`：19 个用例覆盖空参数、8 个单独 flag、trigger 合法/非法/缺值/flag-as-value、data-dir 缺值/空串、多参数组合、完整 launch 场景、Equatable

### 验证
- `swift test`：178/178 passed（159 原有 + 19 新增），0 failures
- `swift build -c release`：Build complete，0 errors（hook 代码在 Release 不编译）

---

## T-UI-003:补 accessibilityIdentifier（Onboarding / 菜单 / 窗口关键控件）

- **passes: true** -- §0.5 硬依赖 6 控件 + 命名约定补充 13 控件全部补齐；swift test 159/159 无回归

### 产出
- Onboarding（`OnboardingView.swift`）：`onboarding.startButton` / `onboarding.skipButton` / `onboarding.screenRecording.grant` / `onboarding.screenRecording.skip` / `onboarding.hotkeyRecorder` / `onboarding.clipboardToggle` / `onboarding.launchAtLoginToggle`（7 控件，SwiftUI `.accessibilityIdentifier` modifier）
- 菜单（`StatusItemController.swift`）：`menubar.openSearch` / `menubar.clipboard` / `menubar.screenshot` / `menubar.settings` / `menubar.about` / `menubar.onboarding` / `menubar.quit`（7 NSMenuItem，`setAccessibilityIdentifier(_:)` 方法--Swift 中 `accessibilityIdentifier` 桥接为 getter 方法非可赋值属性，初次赋值写法编译报错已修正）
- Command Bar（`CommandBarView.swift`）：`commandBar.searchField`（TextField）/ `commandBar.resultList`（LazyVStack）
- 剪贴板窗口（`ClipboardHistoryView.swift`）：`clipboard.searchField`（JadeTextField）/ `clipboard.sidebar`（List）
- 设置窗口（`SettingsView.swift`）：`settings.sidebar`（VStack）

### cases.md §0.5 回写
- 新增 §0.5.1 补充标识符清单（13 控件）+ NSMenuItem 方案说明
- §0.5 原 6 个硬依赖表保留不变

### 验证
- `swift build`：Build complete，0 errors
- `swift test`：159/159 passed，0 failures（无回归）
- 标识符不影响正式 build UI 呈现（accessibilityIdentifier 对用户不可见；VoiceOver label 未改动，Onboarding 按钮等仍由 L10n 文本提供 label）

---

## T-UI-006:实现第二批 P1 用例代码（TC-UI-011~022，菜单分发 + Command Bar + 设置 + 剪贴板）

- **passes: true** -- 12 条用例（TC-UI-011~022）分布到 4 个文件编译通过；`xcodebuild build-for-testing` **TEST BUILD SUCCEEDED**

### 产出
- `QingyuUITests/MenuDispatchUITests.swift`：TC-UI-011~015（5 条）。用 `--uitest-trigger openSearch/openClipboard/openSettings/openAbout/openOnboarding` 绕过 status item 点击；TC-UI-013 用 `--uitest-trigger startScreenshot` + `--uitest-mock-screen-recording-denied` + `--uitest-skip-screenshot-capture`（注：后 2 个 hook 未在 UITestSupport.swift 中实现，trigger startScreenshot 也未列入 UITestTriggerAction 枚举——TC-UI-013 代码逻辑照 cases.md 实现，运行时 hook 待 T-UI-002 补齐后才能验证，本任务只要求编译通过）。
- `QingyuUITests/CommandBarUITests.swift`：TC-UI-016~018（3 条）。TC-UI-016 输入->结果->ESC 关闭；TC-UI-017 回车执行->自动关闭；TC-UI-018 空输入不消失。用 `commandBar.searchField` / `commandBar.resultList` 查询；ESC 用 `typeText("\u{1B}")`，Enter 用 `typeText("\r")`；消失用 NSPredicate + expectation 轮询。
- `QingyuUITests/SettingsWindowUITests.swift`：TC-UI-019~020（2 条）。TC-UI-019 侧栏导航"剪贴板历史"->"快捷键"->"关于"（主区域切换信号：保留时间/打开搜索/清羽）；TC-UI-020 版本号可见（`label MATCHES ".*1\\.2\\..*"`，等价 CONTAINS "1.2."，适配实际 L10n "版本 1.2.x (xxx)"）。
- `QingyuUITests/ClipboardWindowUITests.swift`：TC-UI-021~022（2 条）。TC-UI-021 空态+类型筛选（全部/文本/图片/文件）+搜索框可见可聚焦；TC-UI-022 搜索框输入不崩溃（`app.state != .notRunning`，XCUIApplication.State 无 .running case）。

### 对照 cases.md 偏差（文案以实际 L10n 为准）
| 用例 | cases.md 字面 | 实际 L10n（zh-Hans） | 处理 |
|------|--------------|---------------------|------|
| TC-UI-012/021 空态 | "剪贴板历史为空" | "暂无剪贴板记录"（clipboard.empty.title） | 用实际 L10n，代码注释说明 |
| TC-UI-019 侧栏项 | "剪贴板" | "剪贴板历史"（management.page.clipboard） | 用实际 L10n |
| TC-UI-016/017 未找到 | "未找到" | "未找到匹配项"（commandBar.noResults.title） | CONTAINS "未找到" 兜底 |
| TC-UI-020 版本号 | `MATCHES "1\\.2\\..*"` | label 形如 "版本 1.2.1 (123)" | `MATCHES ".*1\\.2\\..*"`（前后加 .*，等价 CONTAINS） |
| TC-UI-019 主区域信号 | "保留时间"/"呼出统一搜索" | "保留时间"/"打开搜索"（management.shortcuts.search） | 用实际 L10n |
| TC-UI-022 State 断言 | `app.state == .running` | XCUIApplication.State 无 .running case | 改用 `app.state != .notRunning` |
| TC-UI-013 hook | `startScreenshot` + `--uitest-skip-screenshot-capture` | UITestSupport.swift 未实现这 2 个 hook | 代码照 cases.md 写，运行时待 T-UI-002 补齐 |

### 附带修复（T-UI-001/T-UI-002 遗留，本任务编译依赖）
1. **重建 QingyuUITests target**：开发过程中 `git checkout` 误回滚 pbxproj 到 v1.2.0（T-UI-001 的 pbxproj 改动未提交，丢失）。用 ruby `xcodeproj` gem 重建 target（productType `com.apple.product-type.bundle.ui-testing`，TEST_TARGET_NAME=Qingyu，build settings 对齐 QingyuTests + PRODUCT_NAME=$(TARGET_NAME)），加入 6 个 swift 文件（QingyuUITests.swift + OnboardingUITests.swift[T-UI-004 产物] + 本任务 4 文件）+ Info.plist。
2. **UITestSupport.swift 加入 Qingyu target**：T-UI-002 创建了 `Qingyu/App/UITestSupport.swift` 但未加入 pbxproj 的 Qingyu target Sources phase（T-UI-002 只验证了 SPM `swift build/test`，未验证 xcodebuild）。本任务把 UITestSupport.swift 加入 App group + Qingyu target Sources phase，修复 AppDelegate.swift `#if DEBUG` 引用 `UITestSupport`/`UITestTriggerAction` 找不到类型的编译错误。

### 验证
- `xcodebuild build-for-testing -project Qingyu.xcodeproj -scheme Qingyu -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile`：**TEST BUILD SUCCEEDED**
- 不要求跑通（已知环境阻塞：macOS UI automation GUI 授权，见 T-UI-001 blocked_reason），跑通留待 T-UI-007
- 12 条用例代码逻辑对照 cases.md 无遗漏；OnboardingUITests.swift（T-UI-004）顺带加入 target，编译通过

---

## T-UI-004:实现第一批 P0 用例代码（TC-UI-001~010，Onboarding）

- **passes: true** -- 10 条用例（TC-UI-001~010）实现完毕，`xcodebuild build-for-testing` **TEST BUILD SUCCEEDED**

### 产出
- `QingyuUITests/OnboardingUITests.swift`：10 条用例，严格对照 cases.md TC-UI-001~010 实现
  - TC-UI-001 首启显示欢迎页（`--uitest-reset-onboarding`，断言 onboarding 窗口 + 标题文案含"清羽"）
  - TC-UI-002「开始使用」可见可点（断言 exists + isHittable，不断言 isEnabled）
  - TC-UI-003「跳过设置」可见可点 + isEnabled（不依赖 canStart）
  - TC-UI-004 跳过 + 二次确认 sheet + 关窗（`app.sheets.firstMatch`，确认按钮文案"跳过"=L10n onboarding.skip.confirm.action）
  - TC-UI-005 footer 恒定可见（5a 默认字号 + 5b `--uitest-large-text` 放大字号，两子场景单方法内两步 launch）
  - TC-UI-006 未授权时开始禁用跳过可用（`--uitest-mock-screen-recording-denied`，断言 startButton.isEnabled==false + skipButton.isEnabled==true）
  - TC-UI-007 authorized 路径点开始关窗驻留（`--uitest-mock-screen-recording-authorized`）
  - TC-UI-008 skip 路径点跳过确认关窗驻留
  - TC-UI-009 菜单主动打开欢迎页关闭不改完成态（`--uitest-mark-onboarding-completed` + `--uitest-trigger openOnboarding`，关闭用 `XCUIIdentifierCloseWindow` / 备选 ⌘W）
  - TC-UI-010 重启不重弹（单方法内两步 launch，复用同一 tmpDir，断言 onboarding 不出现）
- 通用约定（§0）：每用例 `--uitest-data-dir <tmp>` + `--uitest-skip-shortcuts`；按用例名隔离临时目录，tearDown 清理；accessibilityIdentifier 查询（onboarding.startButton / onboarding.skipButton）；menuBars 驻留断言带降级（§0.7，menuBars 优先，降级 `app.state != .notRunning`）

### 附带修复（pbxproj 回滚导致 T-UI-001/T-UI-006 target 配置丢失）
1. **重建 QingyuUITests target**：发现 pbxproj 被回滚到 v1.2.0（T-UI-001/T-UI-006 的 target 配置未提交、丢失，scheme 引用 C66729BECCA77395DD91EF6F 但 pbxproj 无此 target）。用 python 脚本重建完整 target（productType `com.apple.product-type.bundle.ui-testing`，TEST_TARGET_NAME=Qingyu，build settings 对齐 QingyuTests），含全部 6 个 swift 文件 + Info.plist。
2. **UITestSupport.swift 加入 Qingyu target Sources phase**：T-UI-002 创建了文件 + AppDelegate 引用，但 fileReference 的 buildFile 未加入 Qingyu Sources phase（T-UI-002 只验证 SPM `swift test`，未验证 xcodebuild）。修复后 AppDelegate `#if DEBUG` 引用 UITestSupport/UITestTriggerAction 编译通过。
3. **修复 T-UI-006 CommandBarUITests.swift:79 编译错误**：`wait(for:timeout:)` 返回 Void 非 Bool，改用 `wait(for:)` + `XCTAssertFalse(element.exists, message)`。

### 对照 cases.md 偏差
- 编号映射以 cases.md 为准（cases.md TC-UI-006=未授权禁用 / TC-UI-009=菜单主动打开 / TC-UI-010=重启不重弹；tasks.json T-UI-004 steps 描述的编号映射有错位，以 cases.md 为权威）
- 标题文案用 CONTAINS "清羽" 兜底（实际 L10n = "欢迎使用 清羽 Qingyu"，含空格）
- 确认按钮文案"跳过"（L10n onboarding.skip.confirm.action，非"确认跳过"）
- `app.state == .Running`（cases.md §0.7 旧 API）改为 `app.state != .notRunning`（XCUIApplicationState 无 .running case）

### 验证
- `xcodebuild build-for-testing -project Qingyu.xcodeproj -scheme Qingyu -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile`：**TEST BUILD SUCCEEDED**（含全部 6 个 UITest 文件 + app target）
- 不要求跑通（已知环境阻塞：macOS UI automation GUI 授权，见 T-UI-001 blocked_reason），跑通留待 T-UI-005
- 10 条用例代码逻辑对照 cases.md 无遗漏、无 TODO、无注释掉的断言

---

## T-UI-002 补遗漏：TC-UI-013 依赖 hook（startScreenshot trigger + skip-screenshot-capture）

- **passes: true** -- 补 T-UI-002 遗漏的两个 hook，`swift test` 181/181（178+3）无回归，build-for-testing TEST BUILD SUCCEEDED，Release build 不受影响

### 产出
- `Qingyu/App/UITestSupport.swift`：`UITestLaunchArg.skipScreenshotCapture` 常量；`UITestTriggerAction.startScreenshot` case；`UITestSupport.skipScreenshotCapture` 字段 + `isUITest` + `parse`；`Notification.Name.uitestScreenshotTriggered`（全 `#if DEBUG`）
- `Qingyu/App/AppDelegate.swift`：`handleUITestTrigger` 加 `case .startScreenshot` -> `container.screenshotWindowController.captureRegion()`（与 `onStartScreenshot` 闭包同方法，cases.md §0.4）
- `Qingyu/App/Controllers/ScreenshotWindowController.swift`：`performCapture` 权限检查后、隐藏 command bar 前加 `#if DEBUG` skip 拦截——发 `.uitestScreenshotTriggered` 通知 + return（不弹 overlay、不真实捕获）
- `QingyuTests/UITestSupportTests.swift`：+3 测试（skipScreenshotCapture 解析、startScreenshot trigger、TC-UI-013 完整 launchArgs 组合）

### skip-screenshot-capture 行为选择
- 位置：`performCapture` 中 `ensureScreenRecordingPermission()` **之后**。保留权限提示路径（TC-UI-013 mock-denied 的 Alert 断言），同时兜底防止授权时真实捕获/弹全屏 overlay。
- 行为：发 `.uitestScreenshotTriggered` 通知 + `return`（走取消路径，不进 `Task`、不调 `capture()`、不弹 overlay）。提供稳定可断言标记（"截图入口可达"），不依赖屏幕录制权限。
- 无 flag 时行为完全不变（现有截图功能不受影响）。

### 验证
- `swift test`：181/181 passed（178 + 3 新测试，无回归）
- `xcodebuild build-for-testing -onlyUsePackageVersionsFromResolvedFile`：**TEST BUILD SUCCEEDED**（app + QingyuTests + QingyuUITests 全编译）
- `xcodebuild build -configuration Release`：**BUILD SUCCEEDED**（hook 全 `#if DEBUG`，Release 无 hook 符号）
