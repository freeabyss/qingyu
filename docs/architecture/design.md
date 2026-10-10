# 清羽 Qingyu 架构设计

> 版本：**v17** · 关联 PRD：`doc/prd.md`（清羽 Qingyu v1.2）· 关联文档：`doc/architecture/api.md`（v3）、`doc/architecture/db.md`（v3）、`doc/iterations/v1.2.0/architecture/review.md`

## 版本记录

| 版本 | 上线日期 | 说明 |
|------|---------|------|
| v1.0.0 | 2026-07-02 | 首次上线，MVP（22 个用户故事），当时暂定名 Mac Super Assistant |
| v1.0.1 | 2026-07-02 | Bug 修复：关闭启动期 Sparkle updater 自动启动 |
| v1.1.0 | 2026-07-03 | Onboarding 死锁修复 + 跳过设置入口 |
| v1.2.0 | 2026-07-03 | 品牌改名清羽 Qingyu；文件搜索接入；全屏截图热键；关闭 Sandbox 改 Developer ID 分发；AppContainer/DI + 窗口控制器拆分；DesignToken 层；死代码清理；版本号三源统一 1.2.0 |

## 修订记录

| 日期 | 修改人 | 备注 |
| :--- | :--- | :--- |
| 2026-06-05 → 2026-06-11 | Claude | v1–v15：SnapVault 剪贴板工具 → Spotlight 类启动器 → Mac Super Assistant MVP（SwiftUI+AppKit、Core Data+文件系统、SearchSource Provider、轻量内存索引） |
| 2026-07-03 | Claude | v16：v1.1.0 Onboarding 修复设计 |
| 2026-07-03 | arch subagent | **v17：按 v1.2 PRD 全面修订。品牌改名清羽 Qingyu；明确 6 层职责边界；AppDelegate 拆分为 AppContainer(DI 根)+窗口控制器+StatusItemController；Onboarding 单屏 + 辅助功能按需申请；FileSearchSource 接入 SearchService；删除 UnifiedSearch*/UnitConverterSource/OCR 整套死代码；剪贴板收敛到 AssistantClipboardRepository 单仓；截图补全屏热键 + 悬浮 pill 工具栏；新增 UI/Design System 模块（JadeToken + 统一组件）；移除 Sparkle 仅保留跳 GitHub Releases；新增窗口管理/改名迁移/分发签名/无障碍章节；双数据栈标注为技术债；风险表与变更记录更新。** |
| 2026-09-06 | Claude | Task 001：新增 §23 插件内核架构（第一方插件模型，ADR-001），`PluginRegistry`/`QingyuPlugin` 落地，AppContainer 建空注册表。 |

> 说明：本文件以 `doc/prd.md`（清羽 Qingyu v1.2）当前决策为准。架构层只定义模块契约、边界、数据流与风险，不落具体 `.swift` 实现行。旧 SnapVault / GRDB 主存储 / FTS5 / OCR 等内容作为历史背景保留在修订记录中，不再作为实现依据。

---

## 1. 系统概述

清羽（Qingyu，英文名 Qingyu，中文名清羽；Bundle ID 保留 `com.freeabyss.qingyu`）是一款 macOS 原生效率工具，定位为 **增强版 Spotlight + 常用效率工具集成中心**。

MVP 以统一搜索入口（Command Bar，默认 `⌥ Space`）为主，集成以下能力：

- 应用启动。
- 剪贴板历史。
- **文件搜索（v1.2 接入）**。
- 区域 / 全屏 / 窗口截图（v1.2 补全屏全局热键）。
- 轻量截图标注。
- 内置白名单命令。
- 基础计算器与常用单位换算。
- 设置、权限、关于、隐私、反馈等发布级基础能力。

产品形态为菜单栏 App，无 Dock 图标（`LSUIElement=true`）。复杂或低频操作由独立管理窗口（剪贴板历史 / 设置）承载。

> 命名策略见 PRD §2.0 / D-101 / D-102：显示名、工程 target、源码目录、对外文案全面改为清羽 / Qingyu；Bundle ID 保持 `com.freeabyss.qingyu` 不变（TCC 权限、Keychain、数据目录、开机启动项的绑定键）。改名迁移策略见本文 §17。

---

## 2. 架构总览

### 2.1 功能目标

- 所有核心能力都能通过统一搜索框触发（应用、剪贴板、文件、命令、计算/换算、设置）。
- 独立管理窗口承载剪贴板历史、设置、权限和概览。
- 剪贴板历史默认开启，支持文本、富文本、图片、文件引用。
- 截图完成后进入预览工具栏，支持复制、保存、标注、取消；全屏截图支持全局热键。
- 内置命令严格白名单，不支持任意 shell；关闭 Sandbox 后 AppleEvents 命令可靠执行。

### 2.2 非功能目标

- 冷启动 ≤ 1 秒；本地来源搜索响应 ≤ 100ms；文件搜索首批结果 ≤ 300ms（异步不阻塞其他来源）。
- 后台空闲 CPU ≤ 1%；后台常驻内存 ≤ 150MB（理想 ≤ 100MB）。
- 数据默认仅本地保存，不上传、不同步、不训练。
- 最低支持 macOS 12 Monterey（通用二进制，Apple 芯片 + Intel）。

### 2.3 设计约束

- 技术栈限定 SwiftUI + AppKit + 原生 macOS API。
- **活动持久化栈为 Core Data + 文件系统**；剪贴板搜索采用 Core Data 持久化 + 轻量内存搜索索引。GRDB 作为历史遗留双栈（技术债，见 §4、§18），v1.2 不重构、不再写入。
- v1.2 关闭 App Sandbox（保留 Hardened Runtime + apple-events entitlement）。
- MVP 不实现插件系统、账号系统、云同步、自动安装更新、OCR、文件内容全文检索。

### 2.4 分层架构（6 层，职责边界明确）

系统采用 **App Shell → Presentation → ViewModel → Service → Provider → Data → macOS Platform APIs** 分层。相邻层单向依赖，禁止跨层反向依赖；UI 不得直接依赖 Core Data / 文件系统 / macOS 底层 API。

```text
┌─────────────────────────────────────────────────────────────┐
│  App Shell                                                    │
│  QingyuApp / AppDelegate(仅生命周期) / AppContainer(DI 根)   │
│  StatusItemController / 窗口控制器群 / GlobalShortcutManager   │
├───────────────────────────────────────────────────────────── │
│  Presentation Layer（SwiftUI View + 通用组件 + DesignTokens）  │
│  CommandBar / ClipboardHistory / ScreenshotOverlay+Annotation │
│  Settings / Onboarding / About                                │
├───────────────────────────────────────────────────────────── │
│  ViewModel Layer（@MainActor，状态与意图，无系统 API）          │
│  SearchPanelViewModel / ClipboardHistoryViewModel             │
│  OnboardingViewModel / SettingsViewModel / ScreenshotViewModel│
├───────────────────────────────────────────────────────────── │
│  Service Layer（业务编排，async/await）                        │
│  SearchService / ClipboardService / ScreenshotService         │
│  PermissionService / SettingsService / FeedbackService        │
│  ReleaseInfoService / LaunchAtLoginService                    │
├───────────────────────────────────────────────────────────── │
│  Provider Layer（SearchSource 聚合）                           │
│  AppSource / ClipboardSource / CommandSource                  │
│  CalculatorSource / SettingsSource / FileSearchSource(v1.2)   │
├───────────────────────────────────────────────────────────── │
│  Data Layer                                                   │
│  Core Data(PersistenceController,活动栈) / FileResourceStore  │
│  InMemorySearchIndex ／ (GRDB DatabaseManager: 历史遗留,只读)  │
├───────────────────────────────────────────────────────────── │
│  macOS Platform APIs                                          │
│  NSWorkspace / NSPasteboard / CG*/ScreenCaptureKit            │
│  Accessibility / ScreenRecording / SMAppService / AppleEvents │
└─────────────────────────────────────────────────────────────┘
```

**各层职责边界：**

| 层 | 职责 | 禁止 |
| :--- | :--- | :--- |
| App Shell | App 生命周期、依赖组装（AppContainer）、菜单栏、窗口生命周期、全局热键注册 | 不含业务逻辑；不直接持有持久化细节 |
| Presentation | SwiftUI 视图、通用组件、DesignToken 引用、布局 | 不硬编码颜色/圆角/字号；不直接调系统 API 或 Core Data |
| ViewModel | `@MainActor` 状态、用户意图转 Service 调用 | 不引用 AppKit 窗口、不直接访问持久化 |
| Service | 业务编排、跨 Provider/Repository 协作、错误归一 | 不感知具体 View |
| Provider | 单一搜索源的检索与结果构造 | 不感知 UI 布局 |
| Data | 持久化、文件资源、内存索引 | 不向上暴露 `NSManagedObject` |

### 2.5 AppContainer —— 依赖注入根（v1.2 核心变更）

**问题背景**：现状 `AppDelegate.swift` 955 行，为 god object——手工组装全部依赖，同时管理窗口、状态栏、命令栏面板、截图、剪贴板、快捷键、更新检查等，无 DI 容器，难测试、难演进。

**v1.2 拆分方案**：

- **AppDelegate**：仅保留 App 生命周期回调（`applicationDidFinishLaunching` / `applicationWillTerminate` 等），将组装工作委托给 AppContainer。
- **AppContainer**：依赖注入根。集中构造并持有 Service / Provider / Repository / Data 层单例（或作用域实例），向窗口控制器与 ViewModel 提供依赖。替代原 955 行手工组装。是唯一知道"如何拼装整个对象图"的地方。
- **StatusItemController**：菜单栏 `NSStatusItem`、菜单构建（打开搜索/剪贴板/截图/设置/关于/退出）、双态模板图标。
- **窗口控制器群**（见 §16 窗口管理）：
  - `CommandBarController`（命令栏 `NSPanel` 浮层）
  - `ClipboardHistoryWindowController`（剪贴板历史 `NSWindow`）
  - `SettingsWindowController`（设置 `NSWindow`）
  - `AnnotationWindowController`（截图预览 + 标注 `NSPanel`）
  - `ScreenshotOverlayController`（区域/窗口选择全屏叠层）
- **GlobalShortcutManager**：全局热键注册/注销/冲突表达（搜索、区域/窗口/全屏截图、打开剪贴板/设置）。

> 拆分是"职责归位"，不改变分层数量（仍 6 层）；AppContainer 属 App Shell 层。拆分范围与回归风险见 §19 风险表"改名+拆分回归风险"。

---

## 3. 模块设计

| 模块 | 职责 | 关键对象 |
| :--- | :--- | :--- |
| App Shell | 生命周期、DI 组装、菜单栏、窗口、全局热键、开机启动 | `QingyuApp`, `AppDelegate`, `AppContainer`, `StatusItemController`, `GlobalShortcutManager`, `LaunchAtLoginService` |
| Onboarding | 单屏首次引导、快捷键注册、屏幕录制授权、辅助功能按需说明 | `OnboardingView`, `OnboardingViewModel`, `PermissionService` |
| Search | 统一搜索、Provider 聚合、排序、黑名单、最近使用加权、空态首页 | `CommandBar`, `SearchPanelViewModel`, `SearchService`, `SearchSource`, `SearchResult` |
| App Source | 扫描常规 App 目录并启动 `.app` | `AppSource`, `ApplicationIndex` |
| File Search | 文件名/路径搜索（v1.2 接入），主目录常用位置 | `FileSearchSource`, `FileSearchResult` |
| Clipboard | 监听、历史保存、去重、置顶、搜索、恢复；独立窗口 | `ClipboardMonitor`, `ClipboardService`, `AssistantClipboardRepository`, `ClipboardHistoryWindowController` |
| Screenshot | 区域/全屏/窗口截图（全屏含全局热键）、预览工具栏、标注、复制、保存 | `ScreenshotService`, `ScreenshotOverlayController`, `AnnotationWindowController`, `AnnotationCanvas` |
| Command | 内置白名单命令、别名/拼音、确认弹窗 | `CommandSource`, `SystemCommandExecutor` |
| Calculator | 四则运算、单位换算（含原 UnitConverterSource 能力）、复制结果 | `CalculatorSource`, `UnitConverter` |
| Settings | 概览/剪贴板/快捷键/截图/搜索源/外观/权限/数据/更新/关于/反馈 | `SettingsWindowController`, `SettingsView`, `SettingsService` |
| UI / Design System | Design Token 层、统一组件库 | `JadeColor/JadeRadius/JadeSpace/JadeFont/JadeShadow/JadeMaterial`, `JadeButton`, `JadeTextField`, `HotkeyRecorder`, `JadeToast` … |
| Update / About / Feedback | 检查更新跳 GitHub Releases、关于页、邮件反馈 | `AboutView`, `ReleaseInfoService`, `FeedbackService` |
| Data | Core Data(活动栈)、文件资源、内存索引 | `PersistenceController`, `FileResourceStore`, `InMemorySearchIndex` |

### 3.1 Onboarding 模块（单屏 + 辅助功能按需）

**流程改为单屏**（PRD P-06，取代原 7 步向导）：

- 单页 720×520，含：欢迎 + slogan；3 个配置项卡片（`⌥ Space` 热键录制、剪贴板默认开关、开机启动开关）；屏幕录制权限段（主按钮触发 TCC）；辅助功能段（说明用途 + "稍后再说"，不强制）；底部"开始使用"（屏幕录制授权后或用户点"暂不开启"才可用）+ "跳过设置" + "隐私政策"。
- `OnboardingViewModel` 由 7 步状态机（`OnboardingStep` 枚举）改为单屏模型：以离散布尔/权限状态字段驱动（hotkey 已注册、屏幕录制状态、剪贴板确认、开机启动选择），不再线性推进。保留 `skipOnboarding()`（v1.1 已交付）。
- **首次启动判定**：以 `AppSetting.onboardingCompletedAt`（`Date?`）非空判定已完成/跳过；重启后不重弹（PRD AC-6）。取代旧 `onboarding.completed` 布尔的多步语义（迁移见 db.md §8.3）。

**辅助功能按需申请**（PRD FR-ONBOARD-ACCESSIBILITY-ONDEMAND / D-104）：

- Onboarding 不再阻断在辅助功能授权上。
- `PermissionService` 保留，新增 `onDemandAccessibilityCheck()`：在首次真正触发需要辅助功能的能力时才检查/提示 TCC，并可打开系统设置（PRD AC-7）。
- MVP 全局热键由 KeyboardShortcuts 库实现，不依赖辅助功能；辅助功能仅为未来能力（自动粘贴、模拟快捷键、控制其他 App、窗口控制）预留。

> 屏幕录制仍是强制项（截图依赖），复用 v1.1 已交付的 `requestScreenRecordingPrompt()`。

### 3.2 Search 模块

**唯一入口 SearchService**（PRD FR-PROVIDER-15 / D-106）：

- **删除 legacy 双搜索体系**：`UnifiedSearchService` / `UnifiedSearchViewModel` / `UnifiedResultRow` / `ResultGroupView` / `UnifiedResultList` / `UnifiedSearchTypes` 及仅存活于 `#Preview` 的 `MenuBarView` 整块删除。活动路径统一为 `SearchService` + `SearchPanelViewModel` + `CommandBar`。
- Provider 聚合：AppSource / ClipboardSource / CommandSource / CalculatorSource / SettingsSource / **FileSearchSource**。

**FileSearchSource 接入**（PRD US-012 / FR-SEARCH-FILE / D-105，本次核心补齐）：

- 现状 `FileSearchSource.swift`（522 行）从未被实例化。v1.2 在 AppContainer 中实例化并注册到 SearchService。
- 默认索引范围：`~/Desktop`、`~/Documents`、`~/Downloads`。默认排除隐藏文件/目录、`~/Library`、系统缓存目录、`.app` 包内部内容。
- 检索实现建议：优先 Spotlight metadata（`NSMetadataQuery` / `MDQuery`，随系统索引、性能好）；在 Spotlight 不可用/被禁时降级为 `FileManager` enumerator 受限遍历（限定深度 + 排除规则），异步执行。
- 触发：输入 ≥ 2 字符；异步执行不阻塞其他来源。
- 结果类型：`FileSearchResult`（`SearchResult` 之上携带路径、大小、修改时间、UTI），显示文件名 + 路径 + 类型图标。
- 动作：主动作"打开文件"（系统默认应用）；次级动作"在 Finder 中显示"。
- 评分：来源基础优先级**文件 = 75**（PRD §9.3 建议权重 75；PRD FR-SEARCH-11 表列 60 为旧值，本文按 §9.3 采用 75，差异在 §19 风险与 review 中标注，供 PRD 校准）。

**UnitConverterSource 删除**（PRD FR-PROVIDER-15 / D-106）：

- 独立 `UnitConverterSource` 与 `CalculatorSource` 内的 `UnitConverter` 重复，删除独立源，单位换算统一由 CalculatorSource 承载（长度/重量/数据大小/温度）。

**搜索空态**：

- 空查询不展示内容区，命令栏只有输入框；输入字符后才展示结果区。

### 3.3 Clipboard 模块

**唯一仓库 AssistantClipboardRepository**（PRD §10.6 / D-109）：

- 活动路径为 `AssistantClipboardRepository`（Core Data，739 行）。
- **废弃死路径**：`ClipboardRepository`（GRDB，386 行）、`ContentRepository`（GRDB，541 行）及其 UI 依赖（`RecentContentView` 中依赖 `ContentRepository` 的方法拔除）。相关 GRDB 表在 v1.2 保持存在但不再写入（兼容旧数据），V1.x 彻底移除。
- 剪贴板历史窗口为独立 `ClipboardHistoryWindowController`（`NSWindow`，复用命令栏的单列搜索与结果列表，见 PRD P-02、本文 §16）。
- 监听/去重/置顶/保留时间/资源缺失容错等沿用 v1.0 已交付实现，本次不变更。

### 3.4 Screenshot 模块

- **新增全屏截图全局热键**（PRD US-013 / FR-SHOT-FULLSCREEN / D-107）：默认 `⌃⌥⌘3`（与系统 `⇧⌘3` 错开），可重绑；`GlobalShortcutManager.registerFullscreenCapture()` 补一条注册。区域/窗口热键沿用现状。
- 截图入口前统一经屏幕录制权限守卫，权限缺失弹提示不崩溃。
- 预览 + 标注为独立 `AnnotationWindowController`（居中 `NSPanel`，无边框、20px 圆角、`.ultraThinMaterial`）。
- **ScreenshotToolbar 改悬浮 pill 样式**（`.ultraThinMaterial`），顶部工具 pill + 底部操作 pill（PRD P-05）。
- 标注工具：矩形、箭头、文字、马赛克（`CIPixellate` scale 10）、撤销/重做。**blur 独立模糊工具延后 v1.3**（禁用 + tooltip 标注），v1.2 只保留 mosaic（D-117）。

### 3.5 Command 模块

- 内置白名单 15 条（新增“打开剪贴板历史”，见 §13）。执行走 `NSWorkspace` / `NSAppleScript`（AppleEvents），**不引入任何 shell 执行**（现状即如此，保持）。
- **Sandbox 关闭后**（§18 分发），重启 Finder/Dock、切换深浅色等 AppleEvents 命令畅通、不再静默失败；首次控制其他 App 触发 Automation 授权，产品有说明文案。

### 3.6 Settings 模块

设置窗口（`SettingsWindowController`，独立 `NSWindow`，200px 侧栏）分组（PRD P-03）：概览 / 剪贴板 / 快捷键 / 截图 / 搜索源 / **外观** / 权限 / **数据** / 更新 / 关于 / 反馈。

- **新增"外观"页**：明暗模式切换（`.system/.light/.dark`）；accent 颜色预留、材质切换列 v1.3。
- **新增"数据"页**："打开数据目录"（Finder 打开 `~/Library/Application Support/Qingyu/`）、"清空所有数据"（二次确认，见 db.md §11）、"导出数据"（占位，本体 V1.x）。
- **快捷键冲突检测（基础版）**：`HotkeyConflictDetector` —— 向 KeyboardShortcuts/Carbon 注册热键返回失败时，回调 UI 行内红色提示并要求重录/一键替换（PRD FR-UI-HOTKEYS）。

### 3.7 UI / Design System 模块（v1.2 新增）

集中沉淀设计契约与组件，禁止散落硬编码（PRD 第 9 章 / FR-UI-DESIGN-TOKENS / D-118）。

**DesignTokens**（Light/Dark 双取值，静态常量/枚举）：

- `JadeColor`：低饱和蓝灰强调色与中性表面（Jade 名称保留为 API 兼容；当前视觉值见 `docs/prd/02-ui-spec.md`「视觉语言」）；中性色优先绑定系统动态色（`labelColor` / `windowBackgroundColor` …）。语义色直接走系统色（`systemGreen/Red/Orange/…`）。
- `JadeRadius`：sm 6 / md 8 / lg 10 / xl 12 / 2xl 16（统一 `.continuous`）。
- `JadeSpace`：4px 基准（1/2/3/4/6/8）。
- `JadeFont`：display / title-1~3 / body / callout / subhead / caption / command-bar-input（SF Pro，随系统字体大小动态缩放）。
- `JadeShadow`：sm/md/lg/xl（command bar 用 xl）。
- `JadeMaterial`：命令栏使用不透明中性表面以稳定文字对比；工具条 `.ultraThinMaterial`、Sheet `.thinMaterial`、管理窗口 `windowBackground`。

**统一组件**（Presentation 层复用 View）：`JadeButton`（primary/secondary/destructive/ghost(link)）、`JadeTextField`、`HotkeyRecorder`、`StatCard`、`ListRow`（44/64px）、`Pill Badge`、`Tooltip`、`JadeToast`、`ConfirmationDialog`、`PermissionGate`。

**组件去重**（PRD D-119）：

- 双行组件收敛为单一 `ListRow`。
- 双搜索结果体系收敛（随 UnifiedSearch* 删除）。
- **三套 Toast 统一为 JadeToast**：删除/收敛 `ToastView`+modifier、`RecentContentView` 手写 overlay、`ScreenshotToolbar` 内联 `Text`，统一为一套 `JadeToast`（底部/居中，3s 自动消失，jade/red）。

> 约束落地方式：架构规定"View 禁止硬编码颜色/圆角/字号，必须走 token"，由 code review 把关（无静态 lint 强约束）。

### 3.8 Update 模块（移除 Sparkle）

- **彻底移除 Sparkle**（PRD §10.5）：删除 Sparkle 依赖与配置残留（Info.plist 的 `SUFeedURL` / `SUPublicEDKey` 占位、`appcast.xml`、UpdateService/AppDelegate/Logger 中的 Sparkle 相关代码）。
- 保留 `ReleaseInfoService`：仅提供"检查更新"按钮，跳转 GitHub Releases 页面由用户手动下载安装，不做自动下载/安装/重启。

---

## 4. 数据架构（双栈技术债标注）

- **活动栈**：Core Data（`PersistenceController`）+ 文件系统 + 轻量内存索引。剪贴板写入、历史、设置、黑名单、使用统计均走 Core Data。详见 `db.md`。
- **历史遗留栈（技术债）**：GRDB（`DatabaseManager` 178 行）曾用于全文搜索/导出/清理，与 Core Data 双栈并存、无同步机制。**v1.2 决策：不重构**（风险高、收益不确定），保持现状交付；GRDB 相关表在 v1.2 保持兼容但不再写入。
- **v1.2 一致性保护**：写入剪贴板时若命中 GRDB 遗留表路径，做容错（try/catch，失败降级不崩溃），保证以 Core Data 展示为准、同一记录展示一致。资源文件缺失容错展示。
- **V1.x 方向**：统一到单一栈——SwiftData 或单 Core Data 栈，消除双栈一致性风险（迁移时机/验收标准见 PRD 第 16 章待解决问题 #6）。

数据目录、实体、迁移、清理详见 `db.md`（v3）。核心变更：数据目录 `~/Library/Application Support/Assistant/` → `~/Library/Application Support/Qingyu/`（启动时旧目录存在则 move）；删除 OCR 字段；AppSetting 默认值更新。

---

## 5. App Shell 架构

### 5.1 运行形态

- 菜单栏常驻，默认无 Dock 图标（`LSUIElement=true`）。
- 菜单栏单色 template 图标（双态：普通 / 新剪贴提示），适配深浅色。
- 菜单：打开搜索、剪贴板、截图（直接执行区域截图）、设置、关于、退出。
- 组装由 AppContainer 完成，菜单由 StatusItemController 构建。

### 5.2 全局快捷键

由 `GlobalShortcutManager` 统一管理（基于 KeyboardShortcuts 库，不依赖辅助功能）：

| 功能 | 默认 | 可重绑 |
| :--- | :--- | :--- |
| 打开命令栏 | `⌥ Space` | 是 |
| 区域截图 | `⇧⌃⌘4` | 是 |
| 窗口截图 | `⇧⌃⌘5` | 是 |
| 全屏截图（v1.2 新增） | `⌃⌥⌘3` | 是 |
| 打开剪贴板历史 | `⌥⌘C` | 是 |
| 打开设置 | `⌥⌘,` | 是 |

- 注册失败/冲突：`HotkeyConflictDetector` 回调，设置页行内提示并要求重录（一键替换）。

### 5.3 开机启动

- 完成/跳过 Onboarding 后默认启用；设置可关。使用 `SMAppService`（macOS 13+）。

---

## 6. Onboarding 与权限架构

见 §3.1。核心：单屏流程；屏幕录制强制、辅助功能按需；首次启动以 `onboardingCompletedAt` 判定，重启不重弹。

---

## 7. 搜索架构

### 7.1 SearchSource 协议

Provider 为内置搜索源，非第三方插件。MVP 不支持插件市场/热加载。协议契约见 `api.md` §3。

### 7.2 MVP Provider（v1.2）

| Provider | 触发规则 | 主要动作 |
| :--- | :--- | :--- |
| AppSource | 1 字符起 | 启动 App |
| CommandSource | 1 字符起 | 执行内置命令 |
| SettingsSource | 1 字符起 | 打开设置/权限/关于等 |
| ClipboardSource | ≥ 2 字符 | 复制历史项到系统剪贴板 |
| **FileSearchSource** | ≥ 2 字符 | 打开文件 / 在 Finder 中显示 |
| CalculatorSource | 检测到表达式或单位模式 | 复制计算/换算结果 |

### 7.3 空输入状态

命令栏空态只有输入框，不展示内容区。

### 7.4 搜索排序

```text
finalScore = sourceBasePriority + textMatchScore + usageBoost
```

默认来源基础优先级：

| 来源 | 基础优先级 |
| :--- | :--- |
| 应用 | 100 |
| 命令 | 90 |
| 计算/换算 | 85 |
| 设置 | 80 |
| **文件** | **75**（按 PRD §9.3；FR-SEARCH-11 表旧值 60，取 75，见 §19） |
| 剪贴板 | 70 |

最近使用加权：应用启动次数/时间、命令执行次数/时间，仅本地保存。

### 7.5 结果展示

- 合并排序后总上限 12 条，不分组，图标+类型标签标识来源。
- `⌘1`–`⌘6` 切换搜索源；`⌘K` 清空输入；`Tab` 唯一匹配补全（PRD §9.6）。数字快捷键 `⌘1`~`⌘9` 执行仍为 V1.x 预留。

### 7.6 关闭策略

失焦/点击外部/切 App/ESC/再次热键/执行主动作后关闭。

### 7.7 搜索黑名单

沿用现状：只屏蔽具体结果（App/命令/设置入口/文件结果），设置页管理，移除后重现。文件结果同受搜索源开关与黑名单约束。

---

## 8. AppSource 架构

沿用现状：索引 `/Applications`、`~/Applications`、`/System/Applications` 下 `.app`；字段含 bundle id / 名称 / 拼音 / 首字母 / 启动次数与时间；匹配优先级精确→前缀→拼音前缀→拼音首字母→包含→模糊。

---

## 9. FileSearch 架构（v1.2 新增）

见 §3.2。关键：AppContainer 实例化并注册；默认三目录；Spotlight metadata 优先、FileManager enumerator 降级；异步；`FileSearchResult` 携带路径/大小/时间；主动作打开、次级 Finder 显示；权重 75；受开关与黑名单约束。首次索引进行中显示"正在索引你的文件…"，不阻塞其他来源（PRD §9.7）。

---

## 10. Clipboard 架构

监听（`NSPasteboard.changeCount` 自适应轮询 500ms/2s）、类型（文本/富文本/图片/文件引用）、默认行为（默认开启、30 天时间淘汰、不自动粘贴）、去重置顶（contentHash）、历史页（独立搜索/类型筛选/存储占用）、资源缺失容错等沿用 v1.0 已交付实现。唯一仓库为 `AssistantClipboardRepository`（见 §3.3）。

---

## 11. 内存搜索索引架构

沿用现状：启动时从 Core Data 全量加载轻量字段（不含大对象）；变更时同步；Core Data 为事实来源，索引可重建；命中后按需回源。

---

## 12. Screenshot 架构

见 §3.4。模式区域/全屏/窗口，全屏含全局热键；预览独立 `AnnotationWindowController`；悬浮 pill 工具栏；标注 mosaic（blur 延后 v1.3）；复制进剪贴板历史、保存不进历史（保存到上次目录，默认 `~/Desktop`，`⌥`+保存弹 NSSavePanel）；ESC 始终取消。

---

## 13. CommandSource 架构

内置白名单 15 条（打开系统设置/本应用设置/下载/应用程序/桌面目录、区域/全屏/窗口截图、打开剪贴板历史、清空剪贴板历史*、暂停恢复记录、检查权限、重启 Finder*、重启 Dock*、切换深浅色；* 需确认）。禁止关机/重启系统/注销/删除文件/杀进程/sudo/任意 shell。执行走 NSWorkspace/AppleScript（AppleEvents），Sandbox 关闭后畅通（见 §3.5、§18）。别名/拼音沿用现状。

---

## 14. CalculatorSource 架构

四则/括号/小数 + 长度/重量/数据大小/温度换算（**含原 UnitConverterSource 能力，独立源已删除**）。白名单递归下降 parser，不用 `NSExpression`；非法/除零/NaN 静默返回空。回车复制结果，遵循统一剪贴板去重。

> 现状 `CalculatorSource.swift:351` 的 `try! NSRegularExpression` 属强制解包风险点，v1.2 改安全写法（见 §19 / api.md 删改说明）。

---

## 15. Settings 与管理中心架构

见 §3.6。设置窗口分组含外观/数据两新页；快捷键冲突基础检测；关于页版本号必须与 `MARKETING_VERSION` 一致（1.2.0）。语言：跟随系统/简体中文/English。

---

## 16. 窗口管理（新增章节）

v1.2 明确 4 类窗口 + 1 类叠层的形态、层级与生命周期，全部由对应窗口控制器管理、AppContainer 组装：

| 窗口/叠层 | 类型 | 控制器 | 层级/形态 | 生命周期 |
| :--- | :--- | :--- | :--- | :--- |
| Command Bar | `NSPanel`（nonactivating、floating） | `CommandBarController` | 屏幕居中浮层，`.ultraThinMaterial`，失焦/ESC 关闭 | 常驻控制器，按需 show/hide；不销毁重建 |
| 剪贴板历史 | `NSWindow`（标准可缩放） | `ClipboardHistoryWindowController` | 独立窗口，命令栏同款搜索—结果—状态栏，最小 680×460 | 首次打开创建，关闭隐藏/释放二选一（建议隐藏复用） |
| 设置 | `NSWindow`（标准） | `SettingsWindowController` | 独立窗口，200px 侧栏，最小 920×640 | 同上，`⌘,` 或命令栏打开 |
| 截图预览+标注 | `NSPanel`（无边框浮层） | `AnnotationWindowController` | 屏幕中央，20px 圆角，`.ultraThinMaterial`，最大 1100×820 | 截图完成时创建，复制/保存/取消后释放 |
| 截图区域/窗口选择 | 全屏 overlay window（覆盖各屏） | `ScreenshotOverlayController` | 全屏遮罩 0.4，十字准星/窗口高亮，ESC 取消 | 触发时创建覆盖所有屏，选完/取消后释放 |

- 层级：Command Bar 与截图叠层为浮层（floating），高于普通窗口；截图叠层在捕获期间最高。
- 焦点：Command Bar 使用 nonactivating panel，避免抢占前台 App 激活态影响失焦关闭语义。
- 多屏：截图叠层需覆盖所有屏幕；Command Bar 显示在主屏或鼠标所在屏（实现细节留开发）。

---

## 17. 改名迁移（新增章节）

**改名范围**（PRD §2.0 / D-101 / D-102）：

| 对象 | 旧 | 新 | 说明 |
| :--- | :--- | :--- | :--- |
| 显示名 / 产品名 | Assistant / Mac Super Assistant / SnapVault | 清羽 / Qingyu | 全面替换（历史语境除外） |
| Xcode 工程 / target / scheme | SnapVault | Qingyu | `PROJECT_NAME` / `SCHEME_NAME` |
| Swift module 名 | (SnapVault) | Qingyu | 测试模块 `QingyuTests` |
| 源码目录 | `SnapVault/` `SnapVaultTests/` | `Qingyu/` `QingyuTests/` | 目录改名 |
| 产物 | `Assistant.app` | `Qingyu.app` | `PRODUCT_NAME=Qingyu` |
| Application Support 目录 | `.../Assistant/` | `.../Qingyu/` | 启动时旧目录存在则 move（见 db.md §8.3） |
| **Bundle ID** | `com.freeabyss.qingyu` | **`com.freeabyss.qingyu`（保留）** | TCC/Keychain/数据目录/登录项绑定键，不改 |
| build_and_run.sh | `pgrep -x SnapVault` / `PROJECT_NAME=SnapVault` | `Qingyu` | 见 PRD §10.7 |
| GitHub repo | github.com/freeabyss/qingyu | 保留 | 不改 repo 名，避免链接失效 |

**版本号三源统一**（PRD FR-UI-36 / D-108）：`MARKETING_VERSION=1.2.0`、`CFBundleShortVersionString=1.2.0`、`CURRENT_PROJECT_VERSION` 按提交号；CHANGELOG 补全 v1.0.0/v1.0.1/v1.1.0/v1.2.0；关于页显示一致。现状三源均为 `0.1.0`、`PRODUCT_NAME=Assistant`，须一并修正。

> Bundle ID 保留是关键：因数据目录仍绑定 `com.freeabyss.qingyu` 容器语义，Application Support 目录名可自由改为 `Qingyu`（目录名与 Bundle ID 无强绑定），迁移见 db.md。

---

## 18. 分发与签名（新增章节）

**分发模式**（PRD §10.5 / §11.4 / D-103 / FR-PERM-APPLE-EVENTS）：

- **签名**：Developer ID Application 证书。
- **公证**：Apple `notarytool` 提交公证。
- **装订**：`stapler` staple 票据到 `.app` / `.dmg`。
- **渠道**：GitHub Releases（github.com/freeabyss/qingyu/releases）；不上 Mac App Store。
- **检查更新**：`ReleaseInfoService` 仅跳 GitHub Releases，用户手动下载安装；无 Sparkle、无自动下载/安装。

**entitlements 清单（v1.2）**：

| entitlement | v1.1（旧） | v1.2（新） | 原因 |
| :--- | :--- | :--- | :--- |
| `com.apple.security.app-sandbox` | `true` | **移除 / false** | 关闭 Sandbox，使 AppleEvents 命令可靠执行 |
| Hardened Runtime | — | **启用** | 公证要求 |
| `com.apple.security.automation.apple-events` | 缺失 | **新增** | restartFinder/Dock、控制其他 App 的 AppleEvents |
| `com.apple.security.files.user-selected.read-write` | `true` | 保留 | 截图保存目录 / 数据目录选择（安全书签） |
| `com.apple.security.screencapture` | `true` | 保留（非 sandbox 下由 TCC 管控） | 截图 |

- 关闭 Sandbox 后，文件搜索访问主目录常用位置、AppleEvents 控制系统均不受沙盒限制；屏幕录制/辅助功能仍由 TCC 管控。
- 首次控制其他 App 触发 Automation 授权，产品有说明文案。

---

## 19. 无障碍支持（新增章节）

对应 PRD §7.14 / §9.8 / FR-A11Y / FR-UI-A11Y。技术实现要点：

- **VoiceOver**：核心控件（搜索框、结果项、按钮、开关、列表项、菜单项）设 `accessibilityLabel` / role / value；结果项朗读类型（应用/命令/文件/剪贴板…）与状态；装饰性 SF Symbol 设 `.accessibilityHidden(true)`。
- **全键盘可达**：搜索/选择/执行/关闭/剪贴板复制回/设置切换均可仅键盘完成；控件支持 `Tab` 遍历。
- **Dynamic Type**：`JadeFont` 正文字号跟随系统"字体大小"设置动态缩放（body 支持到 15pt）；布局避免固定高度截断。
- **Reduce Motion**：动画尊重 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`，开启时降级为无位移淡入淡出（`JadeMotion` 内部分支）。
- **Increase Contrast / Reduce Transparency**：中性色优先绑定系统动态色（`labelColor` 等），材质在"降低透明度"下降级为不透明背景；对比度满足 WCAG AA。
- 深度屏幕阅读器优化（动态朗读顺序、复杂控件描述）列 V1.x；v1.2 保证基础可用。

---

## 20. 测试策略

测试方案详见 `doc/test/cases.md`、`doc/test/report.md`。架构层要求：

- Provider（含 FileSearchSource）、搜索评分、拼音、计算器、单位换算、hash 去重可单元测试。
- FileSearchSource 接入 SearchService 的集成路径可测（`FileSearchSourceTests` 保留并作为接线回归；`UnitConverterSourceTests` 随源删除移除；OCR 相关测试删除）。
- Core Data 与文件资源可用临时目录/临时 store 集成测试。
- 剪贴板监听可 mock（抽象 Pasteboard 接口）。
- 截图坐标/标注图层/导出抽为纯逻辑可测。
- AppContainer 应可注入 mock 依赖构造对象图（拆分后的可测性收益）。
- 权限、截图、全局快捷键、AppleEvents、签名公证进入手动验收清单（PRD §12.1 AC-*）。

---

## 21. 详细方案索引

| 领域 | 文档 | 状态 |
| :--- | :--- | :--- |
| 产品需求 | `doc/prd.md` | 当前有效（清羽 v1.2） |
| 测试方案 | `doc/test/cases.md`、`doc/test/report.md` | 当前有效 |
| 数据库设计 | `doc/architecture/db.md` | 当前有效（v3：Core Data 活动栈 + 文件系统；GRDB 技术债标注） |
| 接口设计 | `doc/architecture/api.md` | 当前有效（v3：Qingyu 内部接口） |
| 迭代评审 | `doc/iterations/v1.2.0/architecture/review.md` | 本迭代评审记录 |

---

## 22. 当前架构风险

| 风险 | 影响 | 缓解 |
| :--- | :--- | :--- |
| **双数据栈一致性（Core Data + GRDB）** | 同一记录在写入路径与遗留 GRDB 路径可能不一致 | Core Data 为事实来源；写入命中 GRDB 遗留表做容错不崩溃；v1.2 不再写 GRDB；V1.x 统一单栈 |
| **文件搜索性能** | 大目录遍历可能阻塞/耗时 | 优先 Spotlight metadata；FileManager 降级限深+排除规则；异步执行；索引中提示不阻塞其他来源；性能目标 ≤300ms 首批 |
| **DesignToken 改造范围** | 全量 View 迁移到 token 面广，易遗漏硬编码 | 集中定义 Token + 统一组件；code review 把关；分批迁移（先命令栏/剪贴板/设置核心页） |
| **改名 + AppDelegate 拆分回归** | 改 target/目录/module + 拆 955 行 god object 面广，易引入回归 | Bundle ID 保留降低权限/数据风险；拆分按控制器职责切分、AppContainer 单点组装；保留全套测试回归；数据目录 move 迁移加 fallback |
| Core Data + 内存索引一致性 | 搜索结果与持久化不一致 | Core Data 事实来源；索引可重建；变更后同步 |
| 图片/富文本大对象增长 | 磁盘占用 | 显示存储占用；按保留时间清理；清空入口 |
| 截图权限与 macOS 版本差异 | 截图不可用 | 最低 macOS 13；权限页/重检/降级提示；截图底层实现选型见 PRD 待解决 #7 |
| 富文本恢复兼容性 | 不同 App 对 RTF/HTML 支持不同 | 优先原格式，失败降级纯文本 |
| 关闭 Sandbox 的安全审视 | 失去沙盒隔离 | 保留 Hardened Runtime + 最小 entitlements；命令严格白名单；本地优先不联网 |
| 强制解包崩溃点（PreviewPanel/AppDelegate localEventMonitor/CalculatorSource try!/ReleaseInfoService URL(string:)!） | 运行时崩溃 | v1.2 改安全写法（`guard let`/`as?`/预编译常量 regex/静态合法 URL） |

> **已移除（v1.2 已解决）**：原"强制辅助功能权限信任成本"（改按需申请）、原"MVP 不签名公证 Gatekeeper 影响"（v1.2 完成签名公证）、v1.1 的 Onboarding 死锁（已修）。

---

## 23. 插件内核架构（v0.2 阶段，Task 001）

> 决策依据：`docs/decisions/ADR-001-first-party-plugin-model.md`。接口细节见 `api.md` §Plugin 接口。

清羽的三大功能（快速启动、剪贴板、截图）以**编译期第一方插件模块**组织，由 `PluginRegistry`（`Qingyu/Plugins/Core/`）统一聚合：

- **模型**：插件实现 `QingyuPlugin`（`@MainActor`），经 `manifest` 声明搜索源、动作（稳定 `PluginActionID`）、设置页、菜单项、全局快捷键与 `requiredPermissions`。不扫描磁盘、不加载外部 Bundle、无 SDK/市场（YAGNI 基线，见计划"执行前决策"）。
- **生命周期**：`startAll()` 逐个启动已启用插件，单个失败记录并隔离（状态 `failed`，贡献隐藏，不阻断其他插件）；`setEnabled(_:for:)` 持久化到 UserDefaults（`plugin.<plugin-id>.enabled`）并同步启停；停用调用 `stop()` 后贡献不可见。
- **可见性**：贡献可见 ⇔ 已注册 && 已启用 && 非 `failed` && 非 `stopped`；跨模块调用一律走 `PluginRegistry.execute(_:)` 按动作 ID 路由，不用通知字符串作插件 API。
- **消费方**：SearchService（搜索源聚合）、设置侧栏（设置页聚合）、状态栏菜单、GlobalShortcutManager（快捷键聚合）在 Task 002–009 逐步迁移到注册表；Task 001 仅在 `AppContainer` 创建空注册表，既有接线保持不变。

---

## 24. 变更记录

| 日期 | 变更内容 |
| :--- | :--- |
| 2026-06-11 | v15：重写总体架构，对齐 Mac Super Assistant MVP。 |
| 2026-07-02 · v1.0.1 | UpdateService 关闭启动期 Sparkle updater 自动启动。 |
| 2026-07-03 · v1.1.0 | Onboarding 死锁修复（方案 A）：PermissionService 新增 `requestScreenRecordingPrompt()`；OnboardingViewModel 触发 request + `skipOnboarding()`；footer Skip 按钮 + 确认 Alert；xcstrings 5 键。 |
| 2026-07-03 · **v1.2.0（v17）** | 按 v1.2 PRD 全面修订：① 品牌改名清羽 Qingyu（Bundle ID 保留 `com.freeabyss.qingyu`）；② 明确 6 层职责边界；③ **AppDelegate(955 行 god object) 拆分为 AppDelegate(仅生命周期) + AppContainer(DI 根) + StatusItemController + 5 类窗口控制器 + GlobalShortcutManager**；④ Onboarding 改单屏、辅助功能按需申请（`onDemandAccessibilityCheck()`）、首次启动以 `onboardingCompletedAt` 判定；⑤ **删除 UnifiedSearch* 系列 + MenuBarView**，SearchService 为唯一入口；⑥ **FileSearchSource 接入**（AppContainer 实例化注册，默认三目录，Spotlight/FileManager，权重 75，`FileSearchResult`）；⑦ **删除 UnitConverterSource**，单位换算并入 CalculatorSource；⑧ 剪贴板收敛到 `AssistantClipboardRepository` 单仓，废弃 GRDB `ClipboardRepository`/`ContentRepository` 及其 UI 依赖；⑨ 截图补全屏全局热键 `⌃⌥⌘3`、悬浮 pill 工具栏、blur 延后 v1.3；⑩ 新增 UI/Design System 模块（JadeToken + 统一组件 + 三套 Toast 收敛为 JadeToast）；⑪ 移除 Sparkle，仅保留 ReleaseInfoService 跳 GitHub Releases；⑫ 新增窗口管理/改名迁移/分发签名/无障碍章节；⑬ 双数据栈标注为技术债（不重构，加一致性容错）；⑭ 风险表更新（新增双栈/文件搜索性能/DesignToken/改名拆分回归/关闭 Sandbox/强制解包；移除已解决项）；⑮ 版本号三源统一 1.2.0。 |
| 2026-09-06 · Task 001 | 新增 §23 插件内核架构：编译期第一方插件模型（ADR-001），`PluginRegistry` 聚合搜索源/动作/设置页/菜单/快捷键/权限声明，启停持久化与失败隔离；AppContainer 创建空注册表，既有硬编码接线暂不变。 |
