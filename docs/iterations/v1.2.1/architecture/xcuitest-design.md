# v1.2.1 架构设计补充：XCUITest 自动化测试

> 关联 PRD：`doc/iterations/v1.2.1/prd.md`（AC-01~AC-12）　全局 PRD：`doc/prd.md`（§5 MVP 功能集、§7 功能需求、§9 设计语言）
> 基线：v1.2.1（d55c439）　Issue：#7
> 范围：为清羽 Qingyu 补充 XCUITest UI 自动化测试能力，覆盖全产品主流程。发布版本号届时 bump 到 v1.2.2。
> 本设计只输出架构方案与用例边界（编号 + 可测性等级 + 前置 + 断言），不写完整用例步骤（那是 ⑤ 用例生成阶段的事）。

---

## 一、现状与目标

### 1.1 现有测试基线

| 维度 | 现状 |
|------|------|
| 单元/集成测试 | 159 个 XCTest 用例，在 `QingyuTests/` target（`com.apple.product-type.bundle.unit-test`），经 SPM `swift test` 运行 |
| UI 测试 | **无**。无 XCUITest target，无 UI 自动化覆盖 |
| 测试 target 结构 | Xcode 项目内 2 个 target：`Qingyu`（app）+ `QingyuTests`（unit-test bundle，`TEST_HOST` 指向 `Qingyu.app`） |
| SPM | `Package.swift` 有 `Qingyu`（library）+ `QingyuTests`（testTarget）两个 target |
| 已覆盖逻辑 | 搜索排序/拼音/去重、OnboardingViewModel（canStart/start/skip）、权限服务逻辑、剪贴板监听、数据库迁移、热键冲突检测等 |

### 1.2 目标

- 新增 `QingyuUITests` XCUITest target，在 Xcode 项目内搭建 UI Testing Bundle。
- 首期覆盖"全产品主流程"的 UI 行为验证：Onboarding 呈现与完成/跳过、菜单栏各入口分发、命令栏搜索基本交互、设置/剪贴板窗口基本导航。
- 诚实标注可测性边界：菜单栏 app（`LSUIElement=true`）+ 全局快捷键 + TCC 权限带来的限制，明确哪些可自动化、哪些需辅助手段、哪些退回手动。

### 1.3 非目标

- 不复盖已在 XCTest 覆盖的业务逻辑（搜索排序算法、拼音匹配、去重、权限服务状态机等）。
- 不做截图标注工具的像素级 UI 测试。
- 不做真实 TCC 权限授予流程的端到端自动化（需手动或 CI 预配置）。
- 不做全局快捷键在 app 未激活时触发的自动化（XCUITest 限制，见 §二）。

---

## 二、可测性分析（关键，诚实标注）

### 2.1 产品形态对 XCUITest 的影响

清羽是 **菜单栏 app**（`Info.plist` `LSUIElement=true`），无 Dock 图标、无主窗口。启动后仅驻留 `NSStatusItem`，窗口按需创建（Onboarding 窗口、Command Bar 浮层、剪贴板窗口、设置窗口、截图预览）。这意味着：

1. **无标准主窗口**：`XCUIApplication().windows.firstMatch` 不保证指向业务窗口。
2. **`NSStatusItem` 点击**：XCUITest 对系统菜单栏的 `NSStatusBarButton` 访问能力有限且 flaky（macOS 已知问题），不能作为稳定测试入口。
3. **全局快捷键**：`KeyboardShortcuts` 库注册的系统级热键在 app 未激活时也生效，但 XCUITest 只能在 app 前台时模拟键盘事件，无法测试"app 在后台时热键触发"。
4. **TCC 权限**：屏幕录制（`CGPreflightScreenCaptureAccess`）和辅助功能（`AXIsProcessTrusted`）由系统 TCC 管控，CI/headless 环境无法自动授权。

### 2.2 逐项可测性等级

等级定义：
- **A - 可直接测**：XCUITest 可直接驱动，断言可靠，无需 app 内测试 hook。
- **B - 需辅助**：需 app 内测试 hook（launch argument / environment 注入）或 XCUITest 特殊技巧才能测；测的是"受控条件下的 UI 行为"而非真实系统交互。
- **C - 不建议 UI 测**：XCUITest 基本不可行或极不稳定；退回手动验证或已有 XCTest 单元/集成测试覆盖。

| # | 主流程 / 功能 | 可测性 | 原因与说明 |
|---|-------------|--------|-----------|
| 1 | Onboarding 窗口首启呈现（AC-01） | **B** | 需 `--uitest-reset-onboarding` launch argument 重置完成标记，否则非首启不弹。窗口本身是标准 `NSWindow` + SwiftUI，XCUITest 可查 button/text。 |
| 2 | Onboarding「开始使用」按钮可见可点（AC-06） | **A** | 窗口呈现后，XCUITest 可查 `button["开始使用"]` 的 `exists` / `hittable` / `isEnabled`。 |
| 3 | Onboarding「跳过设置」按钮可见可点 + 二次确认（AC-07） | **A** | 同上；二次确认 Alert/Sheet 可查。 |
| 4 | Onboarding footer 恒定可见、内容不横裁（AC-10） | **B** | 按钮可见性可查（A 级）；但"放大字体下不裁剪"需设置系统字号或 mock 动态字体环境，实际通过 `exists && hittable` 间接验证，不做像素级 frame 断言（flaky）。 |
| 5 | Onboarding「开始使用」disabled 条件（AC-12） | **B** | 需 `--uitest-mock-screen-recording-denied` 模拟未授权状态；否则真实环境可能已授权。 |
| 6 | Onboarding 完成后关窗 + 驻留菜单栏（AC-08） | **A** | 点「开始使用」后断言 onboarding 窗口消失、菜单栏 status item 存在。 |
| 7 | Onboarding 跳过后关窗 + 驻留（AC-08 skip 路径） | **A** | 同上。 |
| 8 | 重启不自动弹 Onboarding（AC-09） | **B** | 需两步：先完成/跳过 onboarding 并终止 app，再重新 launch 并断言 onboarding 窗口不存在。需 launch argument 控制首启状态。 |
| 9 | 菜单「欢迎向导」主动打开 + 关闭不改完成态（AC-11） | **B** | 需先完成 onboarding（launch argument 标记已完成），再通过菜单或 launch argument 触发 `showOnboardingWindow()`，关闭后断言状态不变。菜单点击本身见 #14。 |
| 10 | 菜单栏 status item 点击 -> 菜单弹出 | **C** | `NSStatusBarButton` 的 XCUITest 访问不稳定，menu 弹出时序 flaky。**不建议作为自动化入口**；改用 launch argument 直接触发对应 controller（见 §五）。手动验证菜单弹出。 |
| 11 | 菜单项「打开搜索」分发 -> Command Bar 呈现（AC-02） | **B** | 菜单点击不可靠（#10），改用 `--uitest-trigger openSearch` launch argument 直接调用 `commandBarController.show()`，断言 Command Bar panel 可见。菜单分发逻辑本身由代码审查 + 手动覆盖。 |
| 12 | 菜单项「剪贴板」分发 -> 剪贴板窗口呈现（AC-03） | **B** | 同 #11，用 `--uitest-trigger openClipboard`。 |
| 13 | 菜单项「截图」分发 -> 截图流程/权限提示（AC-04） | **C** | 截图依赖屏幕录制 TCC。未授权时走 `NSAlert` 权限提示（可测 Alert 呈现），但真实截图捕获在 CI 不可行。**仅测权限提示 Alert 的呈现**，真实截图退回手动。 |
| 14 | 菜单项「设置/关于」分发 -> 设置窗口呈现（AC-05） | **B** | 同 #11，用 `--uitest-trigger openSettings` / `openAbout`。 |
| 15 | Command Bar 搜索基本交互（输入 -> 结果 -> 回车 -> 关闭） | **A** | Command Bar 是 `NSPanel` + SwiftUI `CommandBarView`。launch argument 触发 `show()` 后，XCUITest 可输入文本、查结果列表、回车、断言 panel 消失。搜索结果内容依赖索引状态，需等待异步加载。 |
| 16 | Command Bar ESC 关闭 | **A** | 同 #15，panel 可见时按 ESC，断言消失。 |
| 17 | Command Bar 空态显示最近使用/收藏 | **B** | 需 app 内有预设使用记录（launch argument 注入 mock usage data），否则空态为初始占位。首期可只测"空输入时 panel 不消失"。 |
| 18 | 设置窗口基本导航（侧栏切换） | **A** | 设置窗口是标准 `NSWindow` + SwiftUI `NavigationSplitView`。launch argument 触发 `show(route: .settings)` 后，XCUITest 可点侧栏项、断言主区域切换。 |
| 19 | 设置窗口 route .about 导航 | **A** | 同 #18，`--uitest-trigger openAbout`，断言关于页内容可见。 |
| 20 | 剪贴板窗口基本导航（空态呈现） | **A** | 剪贴板窗口是标准 `NSWindow` + SwiftUI。launch argument 触发 `show()` 后，断言空态文案可见。 |
| 21 | 剪贴板窗口搜索框 | **B** | 需 mock 剪贴板数据或验证空态搜索行为。首期只测搜索框可见可聚焦。 |
| 22 | 全局快捷键（app 激活时）触发 Command Bar | **B** | XCUITest 可模拟 `⌥ Space`，但需 app 已注册快捷键且在前台。需 `--uitest-skip-shortcuts` 不跳过注册（或专门不传此 arg）。时序敏感，可能 flaky。 |
| 23 | 全局快捷键（app 未激活时）触发 | **C** | XCUITest 无法在 app 未激活时模拟系统级热键。**退回手动验证**。 |
| 24 | 真实屏幕录制 TCC 授权流程 | **C** | CI/headless 无法授权。**退回手动验证**；`PermissionService` 逻辑已有 XCTest 覆盖。 |
| 25 | 真实辅助功能 TCC 授权流程 | **C** | 同 #24。**退回手动验证**。 |
| 26 | 截图区域选择 + 标注编辑器 | **C** | 截图 overlay 是全屏 `NSWindow`，依赖屏幕录制权限；标注编辑器依赖截图结果。**退回手动验证**；标注逻辑（`AnnotationShape` / `AnnotationCanvas`）已有 XCTest。 |
| 27 | 截图像素正确性 | **C** | 像素级断言不可行。**不做**。 |
| 28 | 开机启动注册 | **C** | `LaunchAtLoginService` 依赖 `SMAppService`，系统级行为。**退回手动**；逻辑已有间接覆盖。 |
| 29 | Sparkle/更新检查 | **C** | `UpdateService` 跳转 GitHub Releases，网络依赖。**退回手动**；逻辑已有 XCTest。 |
| 30 | 版本号三源一致 | **C** | 非纯 UI 行为。**退回脚本/构建检查**。 |

### 2.3 可测性分析结论

**可自动化（A + B 级，共 18 项）**：Onboarding 呈现与按钮交互、Command Bar 搜索交互、设置窗口导航、剪贴板窗口导航、Onboarding 完成后窗口关闭与驻留、重启不重弹。

**需辅助手段（B 级）**：首启状态重置、权限状态 mock、菜单分发绕过（launch argument 直接触发 controller）、剪贴板/使用记录 mock。

**退回手动或已有测试（C 级，共 12 项）**：菜单栏 status item 点击交互、全局快捷键后台触发、真实 TCC 权限流程、截图捕获与标注 UI、截图像素、开机启动、更新检查、版本号一致性。

---

## 三、UITest Target 搭建方案

### 3.1 Target 新增

在 `Qingyu.xcodeproj` 新增 `QingyuUITests` target：

| 属性 | 值 |
|------|-----|
| Product Type | `com.apple.product-type.bundle.ui-testing`（UI Testing Bundle） |
| Product Name | `QingyuUITests` |
| Bundle ID | `com.freeabyss.qingyu.uitests` |
| Deployment Target | macOS 13.0（与 app target 对齐，`MACOSX_DEPLOYMENT_TARGET = 13.0`） |
| Test Target Name | `Qingyu`（`TEST_TARGET_NAME = Qingyu`） |
| Bundle Loader | 不需要（UI test bundle 不使用 `BUNDLE_LOADER` / `TEST_HOST`，它通过 `XCUIApplication` 启动 app） |
| 代码签名 | `CODE_SIGN_STYLE = Automatic`；UI test bundle 通常 ad-hoc 签名即可，无需 Developer ID |
| 源码目录 | `QingyuUITests/`（项目根下新建，与 `QingyuTests/` 平级） |

### 3.2 为什么不纳入 SPM（Package.swift）

**不纳入**。理由：

1. **SPM 不支持 UI test target**：`PackageDescription` 的 `TestTarget`（`.testTarget`）生成的是 unit-test bundle（`com.apple.product-type.bundle.unit-test`），无法生成 UI Testing Bundle（`.ui-testing`）。XCUITest 需要 `XCTestCase` + `XCUIApplication`，这些在 SPM 纯命令行环境下不可用。
2. **`XCUIApplication` 依赖 Xcode 运行时**：UI test 需要 Xcode 的 test runner 注入 `XCTestUIBootstrap`，SPM `swift test` 不提供此环境。
3. **现有 SPM 结构不变**：`Package.swift` 继续托管 `Qingyu`（library）+ `QingyuTests`（unit-test），`swift test` 继续跑 159 个单元/集成测试。XCUITest 只在 `xcodebuild` 下运行。

### 3.3 构建与运行命令

```bash
# 构建 app + UITest bundle
xcodebuild -project Qingyu.xcodeproj \
  -scheme Qingyu \
  -configuration Debug \
  -destination 'platform=macOS' \
  build-for-testing

# 运行 UITest
xcodebuild -project Qingyu.xcodeproj \
  -scheme Qingyu \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:QingyuUITests \
  test-without-building
```

> Scheme 需在 `Qingyu.xcodeproj/xcshareddata/xcschemes/` 中勾选 `QingyuUITests` 的 Test action。

### 3.4 Target 依赖与签名

- `QingyuUITests` 依赖 `Qingyu` target（作为 `TEST_TARGET_NAME`）。
- App target 的 entitlements（`Qingyu.entitlements`）不变：Sandbox 关闭、Hardened Runtime、AppleEvents、Screen Capture。
- UITest bundle 不需要独立 entitlements 文件；macOS UI test bundle 在本地开发机以 ad-hoc 签名运行。
- CI 环境（如 GitHub Actions macOS runner）需确保 `xcodebuild` 有 GUI 会话（`xvfb` 或 `--destination platform=macOS,arch=arm64`）；headless 模式下 XCUITest 可能受限（见 §六风险）。

### 3.5 目录结构

```
QingyuUITests/
├── OnboardingUITests.swift          // Onboarding 呈现与完成/跳过
├── CommandBarUITests.swift           // 命令栏搜索基本交互
├── SettingsWindowUITests.swift       // 设置窗口导航
├── ClipboardWindowUITests.swift      // 剪贴板窗口导航
├── MenuDispatchUITests.swift         // 菜单分发（launch argument 触发）
├── RestartBehaviorUITests.swift      // 重启不重弹 Onboarding
├── ScreenshotEntryUITests.swift      // 截图入口（仅权限提示 Alert）
└── Helpers/
    ├── UITestLaunchArguments.swift   // launch argument 常量定义
    └── UITestHelpers.swift           // 公共工具（waitForWindow、resetState 等）
```

---

## 四、与现有 XCTest 的分工

### 4.1 边界原则

| 层次 | 测试类型 | 职责 | 工具 |
|------|---------|------|------|
| 业务逻辑 | XCTest（已有 159 个） | 搜索排序/拼音/去重算法、ViewModel 状态机、权限服务逻辑、数据库 CRUD、剪贴板监听、热键冲突检测 | SPM `swift test` |
| UI 行为 | XCUITest（新增） | 窗口呈现、按钮可见可点、导航流转、菜单分发、搜索框输入->结果->执行->关闭 | `xcodebuild test` |
| 端到端手动 | 手动验证清单 | 真实 TCC 权限、截图捕获、全局快捷键后台触发、菜单栏物理点击 | 人工 |

### 4.2 不复盖清单（XCUITest 不做的事）

以下已被 XCTest 覆盖，XCUITest **不重复**：

- `OnboardingViewModel.canStart` 规则、`start()`/`skipOnboarding()` 写入逻辑 -> `OnboardingViewModelTests`（14 个用例）
- 搜索结果排序、拼音/首字母匹配、黑名单过滤 -> `SearchServiceCoreTests` / `SearchTextMatcherTests` / `SearchBlacklistRepositoryTests`
- 剪贴板 hash 去重、富文本恢复 -> `AssistantClipboardRepositoryTests`
- 权限服务状态查询与系统设置跳转 -> `PermissionServiceProtocolConformanceTests`
- 热键冲突检测 -> `HotkeyConflictDetectorTests`
- 数据库迁移 -> `DataDirectoryMigratorTests`
- 截图标注 shape 逻辑 -> `AnnotationTests`

### 4.3 XCUITest 只验证

1. **窗口存在性与可见性**：某操作后，期望的 `NSWindow`/`NSPanel` 出现或消失。
2. **控件可见性与可用性**：按钮/toggle/textField 的 `exists`、`hittable`、`isEnabled`。
3. **导航流转**：点击侧栏项后主区域内容切换。
4. **输入->结果->执行链路**：输入文本后结果列表出现，回车后 panel 消失。
5. **菜单分发（受限）**：通过 launch argument 模拟菜单项点击，验证对应窗口弹出。

---

## 五、测试辅助设施

### 5.1 测试 Hook 设计（launch arguments）

在 `AppDelegate.applicationDidFinishLaunching` 开头读取 `ProcessInfo.processInfo.arguments`，仅在检测到 UI test 参数时激活对应行为。**正式 build（无参数）完全不受影响**。

| Launch Argument | 作用 | 生效条件 |
|----------------|------|---------|
| `--uitest-reset-onboarding` | 启动时清除 `onboarding.completedAt` 和 `onboarding.completed` 标记，使 app 进入首启状态 | 仅当参数存在时 |
| `--uitest-mark-onboarding-completed` | 启动时写入完成标记，使 app 跳过 onboarding 直接驻留菜单栏 | 仅当参数存在时 |
| `--uitest-mock-screen-recording-denied` | Mock `PermissionService.status(.screenRecording)` 返回 `.denied`，用于测 AC-12 disabled 状态 | 仅当参数存在时 |
| `--uitest-mock-screen-recording-authorized` | Mock `PermissionService.status(.screenRecording)` 返回 `.authorized`，用于 CI 环境测 onboarding 完成 | 仅当参数存在时 |
| `--uitest-skip-shortcuts` | 跳过 `GlobalShortcutManager.setupShortcuts()` 注册，避免测试环境热键冲突 | 仅当参数存在时 |
| `--uitest-trigger <action>` | 启动完成后直接触发指定 action（绕过菜单栏点击），取值：`openSearch` / `openClipboard` / `openSettings` / `openAbout` / `openOnboarding` / `startScreenshot` | 仅当参数存在时 |
| `--uitest-data-dir <path>` | 覆盖 Application Support 数据目录到指定临时路径，隔离测试数据 | 仅当参数存在时 |
| `--uitest-skip-screenshot-capture` | 截图入口走 `ensureScreenRecordingPermission()` 检查但跳过实际 `ScreenshotService.capture*()`，仅验证权限提示或跳过逻辑 | 仅当参数存在时 |

### 5.2 实现方式（设计层面，不写代码）

```swift
// AppDelegate.applicationDidFinishLaunching 开头：
let args = ProcessInfo.processInfo.arguments
let isUITest = args.contains("--uitest-reset-onboarding") 
    || args.contains("--uitest-mark-onboarding-completed")
    // ... 或检测任何 --uitest-* 前缀

if isUITest {
    // 1. 重置/标记 onboarding 状态
    if args.contains("--uitest-reset-onboarding") { resetOnboardingState() }
    if args.contains("--uitest-mark-onboarding-completed") { markOnboardingCompleted() }
    
    // 2. Mock 权限（通过依赖注入替换 PermissionService 或设置全局 flag）
    if args.contains("--uitest-mock-screen-recording-denied") { ... }
    
    // 3. 数据目录隔离
    if let dirIndex = args.firstIndex(of: "--uitest-data-dir"), dirIndex + 1 < args.count {
        let dir = args[dirIndex + 1]
        // 覆盖 AssistantFileSystem.directoryName 或 PersistenceController 的 store URL
    }
}
```

**关键约束**：
- 所有 `--uitest-*` 分支必须以 `ProcessInfo` 参数检测为前提，正式 build 不传参则完全不进入这些分支。
- Mock 权限的实现优先通过**依赖注入**（`PermissionService` 已有 `PermissionServiceProtocol`），在 `AppDelegate` 或 `AppContainer` 初始化时根据参数替换为 mock 实现，而非在生产代码中散布 `#if DEBUG` 或全局 flag。
- `--uitest-data-dir` 的实现需要 `PersistenceController` / `DatabaseManager` / `AssistantFileSystem` 支持外部指定目录路径。当前 `AssistantFileSystem.directoryName` 是常量，需改为可注入参数（设计层面建议，实现阶段再定）。

### 5.3 Onboarding 状态重置（测 AC-01 首启）

**方案**：`--uitest-reset-onboarding` 在 `applicationDidFinishLaunching` 执行 `bootstrapDataStack` 之前，删除 Core Data store 中 `key == "onboarding.completedAt"` 和 `key == "onboarding.completed"` 的 `CDAppSetting` 记录。

```swift
// 伪代码：
func resetOnboardingState() {
    let context = PersistenceController.shared.viewContext
    context.performAndWait {
        for key in [SettingKey.onboardingCompletedAt.rawValue, SettingKey.onboardingCompleted.rawValue] {
            let request = CDAppSetting.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            if let records = try? context.fetch(request) {
                records.forEach { context.delete($0) }
            }
        }
        try? context.save()
    }
}
```

> 注意：此重置必须在 `loadOnboardingCompletionState()` 调用之前执行，否则读到旧状态。

### 5.4 数据隔离（避免污染真实用户数据）

**方案**：`--uitest-data-dir <path>` 将 Core Data store 和大对象目录重定向到临时路径（如 `NSTemporaryDirectory()` + `QingyuUITest/`）。

- `PersistenceController` 的 `NSPersistentContainer` 的 store URL 需支持外部注入。
- `DatabaseManager`（GRDB）的 dbPath 需支持外部注入。
- `AssistantFileSystem` 的 directoryName 或 baseDirectory 需支持外部注入。
- 测试 teardown 时清理临时目录。

> 当前实现中 `PersistenceController.shared` 是单例，store URL 硬编码到 Application Support。实现阶段需评估是否加一个 `init(storeURL:)` 或 static 配置入口。若改动过大，备选方案是让 UI test 使用独立 Bundle ID（`com.freeabyss.qingyu.uitest`）使系统分配不同的 Application Support 容器 -- 但这会影响 TCC 权限绑定，不推荐。优先选 `--uitest-data-dir` 方案。

### 5.5 菜单分发绕过（解决 status item 不可点击）

`StatusItemController` 的 6 个 `@objc` 方法各自调用对应 controller 的 `show()` / action。XCUITest 无法可靠点击 `NSStatusBarButton`，因此用 `--uitest-trigger <action>` 在 `applicationDidFinishLaunching` 末尾（或 `dispatchAsync` 延迟后）直接调用对应方法：

| `--uitest-trigger` 值 | 等效菜单项 | 调用 |
|----------------------|-----------|------|
| `openSearch` | 打开搜索 | `container.commandBarController.show()` |
| `openClipboard` | 剪贴板 | `container.clipboardHistoryWindowController.show()` |
| `openSettings` | 设置 | `container.settingsWindowController.show(route: .settings)` |
| `openAbout` | 关于 | `container.settingsWindowController.show(route: .about)` |
| `openOnboarding` | 欢迎向导 | `showOnboardingWindow()` |
| `startScreenshot` | 截图 | `container.screenshotWindowController.captureRegion()`（配合 `--uitest-skip-screenshot-capture`） |

> **菜单分发逻辑本身**（`StatusItemController.makeMenu()` 的 6 个 `@objc` 方法是否正确 mapping 到 controller）由代码审查 + 手动验证覆盖。XCUITest 只验证"controller.show() 被调用后窗口正确呈现"。

---

## 六、用例范围（首期 MVP 边界）

### 6.1 用例清单

以下为首期 XCUITest 用例编号与边界。完整步骤由 ⑤ 用例生成阶段（`/test` subagent）写入 `doc/iterations/v1.2.1/test/cases.md`，本设计只列编号、覆盖目标、可测性等级、前置条件、关键断言。

#### Onboarding（AC-01/06/07/08/10/11/12）

| 编号 | 覆盖 AC | 可测性 | 前置条件 | 关键断言 |
|------|---------|--------|---------|---------|
| TC-UI-001 | AC-01 | B | `--uitest-reset-onboarding` | onboarding 窗口存在；标题文案"欢迎使用清羽"可见 |
| TC-UI-002 | AC-06 | A | TC-UI-001 前置 | 「开始使用」button `exists && hittable` |
| TC-UI-003 | AC-07 | A | TC-UI-001 前置 | 「跳过设置」button `exists && hittable` |
| TC-UI-004 | AC-07 | A | TC-UI-001 前置 | 点「跳过设置」-> 二次确认 dialog 出现；点确认 -> onboarding 窗口消失 |
| TC-UI-005 | AC-10 | B | TC-UI-001 前置 | 「开始使用」和「跳过设置」同时 `hittable`（footer 恒定可见）；不验证 frame 像素 |
| TC-UI-006 | AC-12 | B | `--uitest-reset-onboarding` + `--uitest-mock-screen-recording-denied` | 「开始使用」`isEnabled == false`；「跳过设置」`isEnabled == true` |
| TC-UI-007 | AC-08 | A | TC-UI-001 前置 + `--uitest-mock-screen-recording-authorized` | 点「开始使用」-> onboarding 窗口消失；status item 存在（`app.menuBars` 非空） |
| TC-UI-008 | AC-08 | A | TC-UI-001 前置 | 点「跳过设置」-> 确认 -> onboarding 窗口消失；status item 存在 |
| TC-UI-009 | AC-11 | B | `--uitest-mark-onboarding-completed` + `--uitest-trigger openOnboarding` | onboarding 窗口出现；关闭后 app 仍驻留（status item 存在）；不验证持久化层（已有 XCTest） |
| TC-UI-010 | AC-09 | B | 步骤 1: `--uitest-mark-onboarding-completed` 启动并终止；步骤 2: 无参数重启 | 步骤 2 中 onboarding 窗口 `exists == false` |

#### 菜单栏入口分发（AC-02/03/04/05）

| 编号 | 覆盖 AC | 可测性 | 前置条件 | 关键断言 |
|------|---------|--------|---------|---------|
| TC-UI-011 | AC-02 | B | `--uitest-mark-onboarding-completed` + `--uitest-trigger openSearch` | Command Bar panel 可见（查 textField 或已知 accessibility identifier） |
| TC-UI-012 | AC-03 | B | `--uitest-mark-onboarding-completed` + `--uitest-trigger openClipboard` | 剪贴板窗口可见；空态文案可见或窗口 title 匹配 |
| TC-UI-013 | AC-04 | C/B | `--uitest-mark-onboarding-completed` + `--uitest-mock-screen-recording-denied` + `--uitest-trigger startScreenshot` | 权限提示 NSAlert 出现（查 alert button）；不测真实截图 |
| TC-UI-014 | AC-05 | B | `--uitest-mark-onboarding-completed` + `--uitest-trigger openSettings` | 设置窗口可见；侧栏可见 |
| TC-UI-015 | AC-05 | B | `--uitest-mark-onboarding-completed` + `--uitest-trigger openAbout` | 设置窗口可见；关于页内容（版本号/图标）可见 |

#### Command Bar 搜索交互

| 编号 | 覆盖 | 可测性 | 前置条件 | 关键断言 |
|------|------|--------|---------|---------|
| TC-UI-016 | FR-SEARCH-4/6/7 | A | TC-UI-011 前置 | 输入文本 -> 结果列表出现（`cells.count > 0` 或"未找到"文案）；ESC -> panel 消失 |
| TC-UI-017 | FR-SEARCH-27/29 | A | TC-UI-011 前置 | 输入文本 -> 回车执行 -> panel 消失 |
| TC-UI-018 | FR-SEARCH-14 | B | TC-UI-011 前置，不输入 | 空输入时 panel 不消失（空态或占位可见） |

#### 设置窗口导航

| 编号 | 覆盖 | 可测性 | 前置条件 | 关键断言 |
|------|------|--------|---------|---------|
| TC-UI-019 | FR-UI-5/8 | A | TC-UI-014 前置 | 点侧栏"剪贴板" -> 主区域切换；点"快捷键" -> 主区域切换；点"关于" -> 关于页可见 |
| TC-UI-020 | FR-UI-8 | A | TC-UI-015 前置 | 关于页版本号可见（`staticTexts` 含 "1.2.x"）；不验证三源一致（退回脚本） |

#### 剪贴板窗口导航

| 编号 | 覆盖 | 可测性 | 前置条件 | 关键断言 |
|------|------|--------|---------|---------|
| TC-UI-021 | FR-CLIP-18/19 | A | TC-UI-012 前置 | 空态文案可见；类型筛选 tabs/buttons 可见；搜索框可见可聚焦 |
| TC-UI-022 | FR-CLIP-19b | B | TC-UI-012 前置 + mock 剪贴板数据（可选首期跳过） | 搜索框输入 -> 列表过滤（首期无 mock 数据时只测搜索框不报错） |

### 6.2 用例统计

| 分类 | 数量 | 可测性分布 |
|------|------|-----------|
| Onboarding | 10 | A: 4, B: 6 |
| 菜单分发 | 5 | B: 4, C/B: 1 |
| Command Bar | 3 | A: 2, B: 1 |
| 设置窗口 | 2 | A: 2 |
| 剪贴板窗口 | 2 | A: 1, B: 1 |
| **合计** | **22** | **A: 9, B: 12, C/B: 1** |

### 6.3 不纳入首期的项（标注手动或后续）

| 功能 | 原因 | 处理方式 |
|------|------|---------|
| 菜单栏 status item 物理点击 | XCUITest 对 `NSStatusBarButton` 不稳定 | 手动验证 |
| 全局快捷键后台触发 | XCUITest 无法模拟 | 手动验证 |
| 真实屏幕录制 TCC | CI 无法授权 | 手动验证 |
| 截图捕获 + 标注编辑器 UI | 依赖 TCC + 全屏 overlay | 手动验证；标注逻辑已有 XCTest |
| 截图像素正确性 | 像素断言不可行 | 不做 |
| 开机启动注册 | 系统级行为 | 手动验证 |
| 更新检查跳转 | 网络依赖 | 手动验证；已有 XCTest |
| 版本号三源一致 | 非纯 UI | 脚本/构建检查 |
| 辅助功能 TCC 按需申请 | CI 无法授权 | 手动验证 |
| 命令栏 ⌘1-6 切换搜索源 | 需 mock 各源数据 | 后续迭代 |
| 剪贴板窗口 swipe action / 预览 Sheet | 需 mock 数据 | 后续迭代 |

---

## 七、风险与约束

### 7.1 菜单栏 app 的 XCUITest 已知难点

| 难点 | 影响 | 应对 |
|------|------|------|
| `NSStatusBarButton` 不可靠点击 | 无法通过"点菜单栏图标 -> 点菜单项"路径自动化 | 用 `--uitest-trigger` launch argument 绕过，直接调用 controller；菜单分发逻辑由代码审查 + 手动覆盖 |
| `NSMenu` 弹出时序 | menu `performClick` 是同步阻塞，XCUITest 等待 menu 消失超时 | 不测菜单弹出时序；绕过菜单直接测窗口 |
| `LSUIElement=true` app 激活 | `XCUIApplication.activate()` 可能不使 app 获得焦点 | 测试中显式 `app.activate()`；对 Command Bar 等 `NSPanel` 用 `makeKeyAndOrderFront` 后等待 `app.windows` 包含目标 panel |
| Command Bar `NSPanel` 检测 | `nonactivatingPanel` + `borderless` 的 panel 可能不在 `app.windows` 中 | 使用 `app.windows.containing` 或 `app.descendants(matching:)` 查 accessibility identifier；为 Command Bar 的输入框加 `accessibilityIdentifier("commandBar.searchField")` |

### 7.2 CI 环境（headless）可行性

- **GitHub Actions macOS runner**：提供 GUI 会话（非纯 headless），XCUITest 理论可运行。但菜单栏 app 的 status item 可能不渲染（取决于 runner 的屏幕会话配置）。
- **对策**：CI 中只用 `--uitest-trigger` 路径（不依赖 status item），验证窗口呈现与交互。status item 物理交互在 CI 中跳过或标记 `XCTSkip`。
- **本地开发机**：完整运行所有用例。

### 7.3 macOS 版本兼容

- Deployment Target macOS 13.0。XCUITest API 在 macOS 13+ 稳定。
- `NSApp.activate()` 在 macOS 14+ 用 `NSApp.activate()`，13 用 `NSApp.activate(ignoringOtherApps:)`（app 代码已处理）。UI test 中同样处理。
- `XCUIElement` 的 `exists` / `hittable` / `waitForExistence(timeout:)` 在 macOS 13+ 可用。

### 7.4 测试稳定性（flakiness）应对

| 风险 | 策略 |
|------|------|
| 异步加载（搜索结果、剪贴板索引） | 使用 `waitForExistence(timeout:)` 而非固定 sleep；超时设 5-10s |
| 窗口创建延迟 | `waitForExistence` 等待目标窗口/控件 |
| 动画干扰（Command Bar resize 动画 0.12s） | 测试中 `waitForExistence` 等待稳定状态；不断言动画中间帧 |
| 每个测试独立 | 每个 `testXxx()` 方法 `setUp()` 中 `app.launch()` 重新启动 app；`tearDown()` 中 `app.terminate()` |
| Launch argument 传递 | `app.launchArguments = ["--uitest-reset-onboarding", ...]`；在 `launch()` 前设置 |
| 测试数据污染 | `--uitest-data-dir` 指向 `NSTemporaryDirectory()`；`tearDown` 清理 |

### 7.5 Accessibility Identifier 需求

当前源码中 SwiftUI 视图大量使用 `L10n.localized()` 文本作为按钮标题，XCUITest 可按文本查询（如 `app.buttons["开始使用"]`）。但本地化环境下文本可能变化。建议为首期用例涉及的关键控件补加 `accessibilityIdentifier`：

| 控件 | 建议 identifier | 所在文件 |
|------|----------------|---------|
| Onboarding「开始使用」按钮 | `onboarding.startButton` | `OnboardingView.swift` |
| Onboarding「跳过设置」按钮 | `onboarding.skipButton` | `OnboardingView.swift` |
| Command Bar 搜索输入框 | `commandBar.searchField` | `CommandBarView.swift` |
| Command Bar 结果列表 | `commandBar.resultList` | `CommandBarView.swift` |
| 设置窗口侧栏 | `settings.sidebar` | `SettingsView.swift` |
| 剪贴板窗口搜索框 | `clipboard.searchField` | `ClipboardHistoryView.swift` |

> 加 `accessibilityIdentifier` 是源码改动，属于实现阶段（⑤），不改变功能行为。本设计只标注需求。

---

## 八、验收标准映射

| AC | XCUITest 用例 | 可测性 | 备注 |
|----|-------------|--------|------|
| AC-01 首启显示欢迎页 | TC-UI-001 | B | 需 `--uitest-reset-onboarding` |
| AC-02 完成后搜索可用 | TC-UI-011 | B | 需 `--uitest-trigger openSearch` |
| AC-03 完成后剪贴板可用 | TC-UI-012 | B | 需 `--uitest-trigger openClipboard` |
| AC-04 完成后截图走权限提示 | TC-UI-013 | C/B | 仅测权限 Alert，真实截图手动 |
| AC-05 完成后设置/关于可用 | TC-UI-014, TC-UI-015 | B | 需 `--uitest-trigger` |
| AC-06 「开始使用」可见可点 | TC-UI-002 | A | |
| AC-07 「跳过设置」可见可点 + 确认 | TC-UI-003, TC-UI-004 | A | |
| AC-08 完成后关窗 + 驻留 | TC-UI-007, TC-UI-008 | A | |
| AC-09 重启不自动弹 | TC-UI-010 | B | 需两步 launch |
| AC-10 不横裁 / 可滚 / footer 可达 | TC-UI-005 | B | 间接验证（hittable），不做像素 |
| AC-11 菜单主动打开不改状态 | TC-UI-009 | B | 需 `--uitest-trigger openOnboarding` |
| AC-12 未授权时开始禁用、跳过可用 | TC-UI-006 | B | 需 mock 权限 |

---

## 九、不做的事

1. **不修改 `Package.swift`**：SPM 不支持 UI test target，保持不变。
2. **不修改 `doc/` 根下业务文件**：不碰 `doc/prd.md`、`doc/architecture/`、`doc/test/`。
3. **不写完整用例步骤**：只列编号与边界，步骤由 ⑤ `/test` subagent 写入 `test/cases.md`。
4. **不做截图标注 UI 的自动化**：退回手动 + 已有 XCTest。
5. **不做真实 TCC 权限端到端自动化**：退回手动。
6. **不做全局快捷键后台触发自动化**：退回手动。
7. **不改变现有 159 个 XCTest**：XCUITest 是新增层，不影响现有测试。
8. **不在本阶段实现**：本设计是架构文档，不写代码、不改 Xcode 项目文件、不改源码。

---

## 十、后续实现路线

| 步骤 | 内容 | 负责阶段 |
|------|------|---------|
| 1 | Gate 2 审阅本设计 | leader |
| 2 | 在 Xcode 项目新增 `QingyuUITests` target | ⑤ 开发 |
| 3 | 在 `AppDelegate` / `AppContainer` 加 launch argument 测试 hook | ⑤ 开发 |
| 4 | 为关键控件补 `accessibilityIdentifier` | ⑤ 开发 |
| 5 | 实现 22 个 UI test 用例 | ⑤ 开发 |
| 6 | 本地 `xcodebuild test` 验证全绿 | ⑤ 测试 |
| 7 | CI 集成（GitHub Actions macOS job） | ⑤ 测试 |
| 8 | 写入 `doc/iterations/v1.2.1/test/cases.md` 完整步骤 | ⑤ /test subagent |
| 9 | 版本号 bump 到 v1.2.2 | ⑥ 上线 |
