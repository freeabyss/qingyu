# v1.2.1 XCUITest 架构设计评审记录

> 评审对象：`doc/iterations/v1.2.1/architecture/xcuitest-design.md`
> 评审日期：2026-07-13
> 评审人：架构评审 subagent（独立于设计者，leader 待复核）
> 关联文档：`doc/iterations/v1.2.1/prd.md`（AC-01~12）、`doc/prd.md`（§5/§7/§9）、`doc/iterations/v1.2.1/architecture/design.md`（主体架构）、`Qingyu.xcodeproj/project.pbxproj`、`Package.swift`

---

## 一、评审结论

**APPROVED_WITH_MINOR_FIXES**

方案整体合理、诚实,可测性分析准确标注了菜单栏 app + 全局快捷键 + TCC 权限带来的限制;Target 搭建方案与现有项目结构兼容;"不纳入 SPM"决策正确;22 条用例覆盖了 v1.2.1 全部 12 个 AC;与 159 个 XCTest 分工清晰无重复;与 v1.2.1 主体架构(门禁移除、服务幂等)无冲突。

存在若干改善级发现(0 个阻塞级),需在 ⑤ 开发阶段落实,但不阻塞 Gate 2 进入。

- **阻塞级发现数:0**(可进 Gate 2)
- **改善级发现数:8**
- **建议首期交付边界**:Onboarding 10 条(TC-UI-001~010)优先,菜单分发 + 窗口导航 12 条作为第二批(详见 §五)

---

## 二、关键发现

### 阻塞级(0 条)

无。

### 改善级(8 条)

| # | 发现 | 位置 | 建议 |
|---|------|------|------|
| C-1 | 测试 hook 编译隔离不足:§5.1/§5.2 仅靠 `ProcessInfo.arguments` 检测,未要求 `#if DEBUG` 或 UITest configuration 双重保护。Release build 中 `--uitest-*` 代码路径虽不触发,但代码残留本身是误操作/攻击面。 | §5.1/§5.2 | 建议在 AppDelegate hook 入口加 `#if DEBUG` 包裹,或使用独立的 UITest build configuration(如 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = UITEST`),使 Release build 完全剔除测试 hook 代码。 |
| C-2 | AC-10/AC-06 "放大字体下可见"未被任何用例覆盖。TC-UI-005 只测默认字号下 `hittable`,但 PRD AC-06 明确要求"默认字体与放大字体下均完整可见"。 | §六 TC-UI-005 | 诚实标注此限制:XCUITest 改变系统字号不易(需 `defaults -g AppleMini...` 或 mock 动态字体环境)。建议 TC-UI-005 前置补充 `--uitest-large-text` mock(若实现成本可接受),或在用例备注明确"放大字体覆盖退回手动"。 |
| C-3 | `--uitest-trigger` 绕过路径的行为等价性未说明。§5.5 只说"菜单分发逻辑由代码审查覆盖",未说明在 v1.2.1 门禁移除(design.md §3.2)后,绕过的具体是哪一层、与真实路径的差异。 | §5.5 | 补充说明:v1.2.1 移除门禁后,`--uitest-trigger openSearch` 直接调用 `commandBarController.show()`,与真实菜单路径(`StatusItemController.@objc` -> `show()`)的唯一差异是省略了 `StatusItemController` 的方法分发(已被代码审查覆盖),因此行为等价。这能让评审者/实现者确信绕过不改变被测语义。 |
| C-4 | 数据隔离实现风险低估。§5.4 说"需评估是否加 `init(storeURL:)`",但经核查 `PersistenceController` **已支持**外部 storeURL(`case .persistent(storeURL: URL?)`,`PersistenceController.swift:32/210`);`AssistantFileSystem` 已有 `init(rootDirectory:)`(`AssistantFileSystem.swift:27`)。仅 `DatabaseManager.shared` 的 dbPath 硬编码(`DatabaseManager.swift:53`)需改造。 | §5.4 | 修正 §5.4:PersistenceController 无需改造(已有 storeURL 注入),AssistantFileSystem 已有 rootDirectory 注入,仅需 DatabaseManager 增加可注入 dbPath。实现风险低于文档预估。 |
| C-5 | Accessibility Identifier(§7.5)是 TC-UI-011/016/017/018 的硬依赖,但未列为前置阻塞项。若 ⑤ 开发遗漏,Command Bar(`nonactivatingPanel` + `borderless`)等 panel 无法被 XCUITest 查到。 | §7.5 / §7.1 | 将 §7.5 的 6 个 identifier 列为 ⑤ 开发的**前置阻塞项**(P0),明确"未添加这些 identifier 则 TC-UI-011/016/017/018 无法实现"。 |
| C-6 | §5.4 "独立 Bundle ID"表述混淆。文档说"让 UI test 使用独立 Bundle ID `com.freeabyss.qingyu.uitest` 使系统分配不同容器",但 UITest bundle 的 Bundle ID 与被测 app 的 Bundle ID 是不同概念;改 UITest bundle ID 不影响 app 容器。 | §5.4 | 澄清:此处"独立 Bundle ID"应指"被测 app 以不同 Bundle ID 启动"(即 `XCUIApplication(bundleIdentifier:)` 指向独立构建的 app),而非 UITest bundle 自身的 Bundle ID。结论(不推荐,因影响 TCC)正确,但表述需修正。 |
| C-7 | #22 "全局快捷键(app 激活时)触发 Command Bar"标 B 级偏乐观。`⌥ Space` 是 `KeyboardShortcuts` 库注册的系统级热键,XCUITest 模拟键盘事件时序敏感,即使 app 前台也可能 flaky。 | §二 #22 / §六 TC-UI-022(未单列,含在 22 条内) | 建议降为 C 级或标注"高 flaky 风险,首期可跳过"。实际上 §6.1 用例清单未单列 TC-UI-022(22 条不含全局快捷键),与 §二 #22 的 30 项分析不一致 -- 建议统一表述。 |
| C-8 | §5.3 onboarding 重置时序描述需澄清。文档说"在 `bootstrapDataStack` 之前执行",但 reset 伪代码用 `PersistenceController.shared.viewContext` 删除记录,需 store 已初始化;而 `bootstrapDataStack` 是 store 初始化+迁移。 | §5.3 | 澄清时序:reset 应在 `bootstrapDataStack` 完成(store 就绪)之后、`loadOnboardingCompletionState()`(AppDelegate.swift:32)之前执行。文档"在 bootstrap 之前"与"需访问 store"矛盾。 |

---

## 三、逐项要点核对

### 1. Target 搭建方案可行性

**结论:可行,与现有项目结构兼容。**

核对 `project.pbxproj`:
- 现有 2 个 target:`Qingyu`(`com.apple.product-type.application`)+ `QingyuTests`(`com.apple.product-type.bundle.unit-test`,`TEST_HOST` 指向 `Qingyu.app`)。
- 项目级 `MACOSX_DEPLOYMENT_TARGET = 13.0`,与设计文档"macOS 13.0 对齐"一致。
- `QingyuTests` 用 `BUNDLE_LOADER = "$(TEST_HOST)"` + `TEST_HOST = ...`(unit-test 配置)。
- 设计文档 §3.1 表格的 UI test bundle 配置正确:
  - Product Type `com.apple.product-type.bundle.ui-testing` -- 正确(XCUITest 必需)。
  - `TEST_TARGET_NAME = Qingyu` -- 正确(UI test bundle 用 `TEST_TARGET_NAME` 而非 `BUNDLE_LOADER`/`TEST_HOST`)。
  - "Bundle Loader 不需要" -- **正确**。UI Testing Bundle 不使用 `BUNDLE_LOADER`/`TEST_HOST`,通过 `XCUIApplication` 启动 app。设计文档已补充说明,表述可接受。
  - Bundle ID `com.freeabyss.qingyu.uitests` -- 与现有命名模式一致(app `com.freeabyss.qingyu` + unit-test `com.freeabyss.qingyu.tests`)。
  - `CODE_SIGN_STYLE = Automatic` + ad-hoc 签名 -- 合理,本地开发可行。
- Scheme 文件 `Qingyu.xcodeproj/xcshareddata/xcschemes/Qingyu.xcscheme` 已存在,§3.3 说"勾选 QingyuUITests 的 Test action"可行。

**"不纳入 SPM"理由成立**:
- `Package.swift` 确认现有 SPM 仅有 `Qingyu`(library)+ `QingyuTests`(testTarget)。
- SPM `.testTarget` 只生成 unit-test bundle,无法生成 UI Testing Bundle -- 理由 1 正确。
- `XCUIApplication` 依赖 Xcode test runner 注入 `XCTestUIBootstrap`,SPM `swift test` 不提供 -- 理由 2 正确。
- 决策合理,保持 `Package.swift` 不变。

### 2. 可测性分析准确性

**结论:整体准确,诚实标注了限制,个别表述需修正(见 C-3/C-7/C-8)。**

逐项核对 A/B/C 分级:

| 评审点 | 核对结果 |
|--------|---------|
| **菜单栏 status item 真的不可点击吗?** | 设计文档标 C 级"不稳定,不建议作为自动化入口"-- **合理保守**。公开实践表明 XCUITest 理论上可通过 `app.menuBars` 或坐标点击访问 `NSStatusBarButton`,但跨 macOS 版本行为不一致、menu 弹出同步阻塞导致超时、CI headless 下 status bar 不渲染。应对策略(`--uitest-trigger` 绕过)**正确**。**需真实环境验证**:本地开发机能否稳定点击 status item(若能,可作为可选的 smoke test,但不应作为唯一入口)。 |
| **全局快捷键后台触发是否绝对不可测?** | #23 标 C 级"退回手动"-- **正确**。XCUITest 只能在 app 前台模拟键盘事件;`KeyboardShortcuts` 注册的系统级热键在后台触发需真实键盘事件,辅助功能 API(`AXIsProcessTrusted`)是用于控制其他 app,不能模拟全局快捷键。退回手动**合理**。#22(app 激活时)标 B 级偏乐观(见 C-7)。 |
| **Onboarding 重置 hook 是否污染正式 build?** | §5.1 说"正式 build 不传参则不进入分支"-- **基本安全**,但仅靠 `ProcessInfo` 检测不够(见 C-1)。建议加 `#if DEBUG`。hook 的依赖注入方案(§5.2 优先 `PermissionServiceProtocol` mock)是好的方向。 |
| **`--uitest-trigger` 是否改变被测行为?** | 诚实标注了"菜单分发逻辑由代码审查覆盖"-- **可接受**,但未说明 v1.2.1 门禁移除后的行为等价性(见 C-3)。在 design.md §3.2 移除门禁后,`--uitest-trigger openSearch` 直接调 `commandBarController.show()`,与真实菜单路径唯一差异是省略 `StatusItemController.@objc` 方法分发。`--uitest-trigger openOnboarding` 调用 `showOnboardingWindow()`,与 design.md §3.4 菜单"欢迎向导"入口的闭包路径一致 -- 这条 trigger 实际测的就是真实路径(除菜单点击本身),**等价性好**。 |

### 3. 用例覆盖完整性

**结论:22 条用例覆盖 v1.2.1 全部 12 个 AC,映射完整(§八)。无主流程遗漏。**

AC-01/06/07/10/11(bug 修复关键验收点)核对:
- **AC-01**(首启显示欢迎页)-> TC-UI-001(B,需 `--uitest-reset-onboarding`)✓
- **AC-06**(「开始使用」可见可点)-> TC-UI-002(A)✓ -- 但"放大字体下"未覆盖(C-2)
- **AC-07**(「跳过设置」+ 二次确认)-> TC-UI-003/004(A)✓
- **AC-10**(不横裁/可滚/footer 可达)-> TC-UI-005(B)✓ -- 间接验证,像素级退回手动,可接受;但放大字体未覆盖(C-2)
- **AC-11**(菜单主动打开不改状态)-> TC-UI-009(B)✓

其余 AC(02/03/04/05/08/09/12)均有映射,无遗漏。

**潜在薄弱点**:
- AC-08"完整体验服务启动(剪贴板监听、清理任务、全局快捷键)"-- TC-UI-007/008 只测窗口消失 + status item 存在,未断言服务启动。这是**可接受的边界**(服务启动是内部行为,UI 测试难断言;逻辑已有 XCTest 覆盖),但建议在用例备注诚实标注"服务启动断言退回 XCTest"。

### 4. 与 XCTest 分工

**结论:边界清晰,无重复。**

- §4.1 边界原则表(业务逻辑->XCTest / UI 行为->XCUITest / 端到端->手动)**合理**。
- §4.2 不复盖清单明确列出了 7 类已有 XCTest 覆盖的逻辑,XCUITest 不重复。
- TC-UI-016(Command Bar 搜索交互)只测"结果列表出现或未找到文案",不验证搜索结果正确性(那是 `SearchServiceCoreTests`/`SearchTextMatcherTests` 的事)-- 边界**可接受**。

### 5. 数据隔离与清理

**结论:方案完备,但实现风险被低估(见 C-4)。**

- `--uitest-data-dir` 重定向 Core Data store + 大对象目录 -- 方向正确。
- §5.4 诚实指出了 `PersistenceController.shared` 单例问题,但**经核查 PersistenceController 已支持外部 storeURL**(`.persistent(storeURL: URL?)` case,`PersistenceController.swift:32/210`),`AssistantFileSystem` 已有 `init(rootDirectory:)`(`AssistantFileSystem.swift:27`)。仅 `DatabaseManager.shared` 的 dbPath 硬编码(`DatabaseManager.swift:53`)需改造。
- 独立 Bundle ID 备选方案被否定(影响 TCC)-- 结论正确,但表述混淆(见 C-6)。
- `tearDown` 清理临时目录 -- 正确。

### 6. 风险与 flakiness

**结论:应对策略现实,CI headless 可行性分析合理。**

- §7.1 菜单栏 app 难点(status item / menu 时序 / LSUIElement 激活 / NSPanel 检测)的应对**合理**:
  - `--uitest-trigger` 绕过 status item -- 正确。
  - `app.activate()` + `makeKeyAndOrderFront` + `waitForExistence` -- 正确。
  - `app.descendants(matching:)` + accessibilityIdentifier 查 NSPanel -- 正确,但硬依赖 identifier(见 C-5)。
- §7.2 CI headless:GitHub Actions macOS runner 有 GUI 会话,status item 可能不渲染,对策是用 `--uitest-trigger` 路径 -- **合理**。
- §7.4 flakiness 应对(`waitForExistence`、独立 launch、launchArguments、临时目录清理)-- **标准实践**。
- §7.5 Accessibility Identifier 需求列了 6 个关键控件 -- **必要**,但应列为前置阻塞项(C-5)。

**需真实环境验证**:
- Command Bar `NSPanel`(nonactivatingPanel + borderless)是否能被 `app.descendants(matching:)` 稳定查到(依赖 identifier 添加后)。
- GitHub Actions macOS runner 下 XCUITest 是否能稳定运行(非纯 headless,但屏幕会话配置可能影响)。

### 7. 范围合理性

**结论:22 条作为"首期 MVP 边界"可接受,但建议裁剪到 Onboarding 10 条优先交付(见 §五)。**

- 22 条数量适中,不过多(覆盖全产品主流程)也不过少。
- 但 A 级 9 条无法独立交付(多数依赖 B 级前置:TC-UI-002 需 TC-UI-001 的 `--uitest-reset-onboarding`;TC-UI-016 需 TC-UI-011 的 `--uitest-trigger`)。
- 更合理的裁剪维度是按**功能域**:Onboarding 10 条(TC-UI-001~010)hook 依赖最少,且覆盖 v1.2.1 全部关键 AC;菜单分发 + 窗口导航 12 条依赖 `--uitest-trigger` + accessibilityIdentifier,可作为第二批。

---

## 四、与 v1.2.1 主体架构(design.md)冲突核对

**结论:无冲突。XCUITest hook 与门禁移除等服务幂等改动兼容。**

- design.md §3.2 移除了 5 个 controller 的门禁 guard -> `--uitest-trigger openSearch` 等直接调 `show()` 不再被拦截,与设计预期一致。
- design.md §3.4 新增"欢迎向导"菜单入口(`onShowOnboarding` -> `showOnboardingWindow()`)-> `--uitest-trigger openOnboarding` 调用同一 `showOnboardingWindow()`,路径一致。
- design.md §3.5 服务启动幂等(`hasStartedFullExperience`)-> 不影响 XCUITest(测试不验证重复启动)。
- design.md §3.3 欢迎窗引用清理(`windowWillClose` 置 nil)-> TC-UI-009(菜单主动打开不改状态)可验证此行为。

---

## 五、建议的首期交付边界

**建议:首期裁剪到 Onboarding 10 条(TC-UI-001~010),菜单分发 + 窗口导航 12 条作为第二批。**

理由:
1. **Onboarding 10 条覆盖 v1.2.1 全部关键 AC**(AC-01/06/07/08/09/10/11/12),是本次 bug 修复的核心验收点。
2. Onboarding 用例 hook 依赖最少(仅需 `--uitest-reset-onboarding` / `--uitest-mark-onboarding-completed` / `--uitest-mock-screen-recording-*`),不依赖 `--uitest-trigger` 和 accessibilityIdentifier,实现风险低。
3. 菜单分发(TC-UI-011~015)+ Command Bar/设置/剪贴板窗口导航(TC-UI-016~022)依赖 `--uitest-trigger` hook 和 6 个 accessibilityIdentifier(§7.5),需 ⑤ 开发配合,作为第二批可并行推进。
4. 若 leader 认为 22 条可在单迭代内完成,也可不裁剪 -- 这是工作量决策,非正确性问题。

**不裁剪到 A 级 9 条的原因**:多数 A 级用例依赖 B 级前置(TC-UI-002 依赖 TC-UI-001 的 reset hook;TC-UI-016 依赖 TC-UI-011 的 trigger hook),无法独立交付。

---

## 六、需真实环境验证的点(诚实标注)

以下评审点基于公开知识与代码审查给出判断,但最终需在真实 Xcode/macOS 环境验证:

| # | 验证点 | 当前判断 | 验证方式 |
|---|--------|---------|---------|
| V-1 | `NSStatusBarButton` 是否真的不可点击(§二 #10,C 级) | 合理保守,但非绝对 | ⑤ 开发阶段在本地 macOS 14+ 尝试 `app.menuBars.buttons.firstMatch.click()`,若稳定可降为 B 级 smoke test |
| V-2 | `--uitest-trigger` 路径在门禁移除后与真实菜单路径行为等价(§5.5) | 推断等价(仅省略 StatusItemController 方法分发) | 代码审查 `StatusItemController.@objc` 方法体,确认仅转发无额外逻辑 |
| V-3 | Command Bar `NSPanel`(nonactivatingPanel + borderless)能否被 `app.descendants` 查到(§7.1) | 依赖 accessibilityIdentifier | ⑤ 添加 identifier 后实测 |
| V-4 | GitHub Actions macOS runner 下 status item 是否渲染(§7.2) | 可能不渲染,对策是不依赖 status item | CI 集成时验证 |
| V-5 | `--uitest-reset-onboarding` 的时序(reset 需 store 就绪但早于 loadOnboardingCompletionState)(§5.3,C-8) | 需澄清 | ⑤ 开发时确认 `bootstrapDataStack` 与 store 初始化的关系 |

---

## 七、总结

xcuitest-design.md 是一份**诚实、可行、与现有架构兼容**的 XCUITest 架构设计。其最大优点是诚实标注了菜单栏 app 的 XCUITest 已知限制,并用 `--uitest-trigger` launch argument 绕过策略提供了可落地的工程方案。8 条改善级发现均不阻塞 Gate 2,可在 ⑤ 开发阶段逐项落实。建议首期裁剪到 Onboarding 10 条以聚焦 v1.2.1 bug 修复的核心验收。

**评审结论:APPROVED_WITH_MINOR_FIXES**
