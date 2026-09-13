# Mac Super Assistant（Assistant）v1.0.0 测试用例

> 本文件为 v1.0.0 迭代的测试用例与测试方案定义（测试目标、分层、用例定义：Case ID、前置条件、步骤、期望结果、优先级）。执行结果与统计见同目录 [report.md](report.md)。

## 版本记录

| 版本 | 上线日期 | 说明 |
|------|---------|------|
| v1.0.0 | 2026-07-02 | 首次上线，Mac Super Assistant MVP（22 个用户故事） |
| v1.2.0 | 2026-07-03（用例定稿；开发未开始） | 品牌改名青鸟 Qingniao、文件搜索接入、全屏截图热键、Onboarding 单屏 + 辅助功能按需、关闭 Sandbox + Developer ID 签名公证、DesignToken 层、AppContainer DI、数据目录迁移、死代码清理、健壮性整改。用例见第 11 节。 |

> 命名说明：v1.2.0 起产品正式定名 **青鸟 / Qingniao**（Bundle ID 保留 `com.assistant.app`）。本文标题与第 1–10 节保留历史「Mac Super Assistant / Assistant / SnapVault」命名以体现追溯语境；第 11 节起一律使用青鸟 Qingniao。

## 修订记录

| 日期 | 修改人 | 备注 |
| :--- | :--- | :--- |
| 2026-06-11 | Claude | 重写为当前 Mac Super Assistant / Assistant MVP 测试方案，对齐 `doc/prd.md` |
| 2026-07-02 | Claude | v1.0.1：新增 TC-U-001（常量断言）/TC-U-002（checkNow spy）2 条自动化用例 + TC-M-001/002/003 手工验收记录 |
| 2026-07-03 | Claude | v1.1.0：新增 +7 条自动化用例（协议 conformer / request 触发 / skipOnboarding / 7 步参数化 / hotkey 持久化）+6 条手工用例；+2 条回归基线更新（swift 134 / xcodebuild 125）；3 条端到端用例（TC-M-007/008/009）留待下一迭代。详见第 10 节「Onboarding 与权限（v1.1.0 起）」 |
| 2026-07-03 | Claude | v1.2.0：新增第 11 节「青鸟 Qingniao v1.2 测试用例」，按模块新增 TC（TOK/BRAND/DATA/DI/SEARCH-F/SEARCH-E/SHOT-FS/SHOT-UI/ONB-V2/PERM-OD/CODE/DIST/UPD/SHORTCUT/SETNEW/REG/BUILD/ROBUST/ACC/I18N 前缀）；对第 5 节因 UI 重设计受影响的旧 TC 就地标注「v1.2 修订」并给出新步骤/预期；开发尚未开始，report.md v1.2.0 节仅为计划占位。 |
| 2026-09-13 | Claude | 下一阶段：新增第 12 节「截图会话生命周期回归」——针对反复复发的截图叠层「僵尸暗幕」缺陷（会话 ARC 提前释放 + borderless 窗口不可为 key）建立 SHOT-LIFE 用例组（3 自动化 + 1 手工）；新增 `scripts/verify.sh` 必跑门禁并写入 AGENTS.md「测试门禁」。 |
| 2026-09-13 | Claude | 1.0.0 隐藏截图入口（`FeatureGate.screenshotEnabled = false`：菜单项、搜索命令与空查询快捷操作、全局快捷键 F1、设置页截图插件、欢迎向导屏幕录制段均不暴露，代码保留），相关 TC（五页侧栏、F1、向导屏幕录制等截图入口类用例）暂缓执行，开关恢复后回归。 |

---

## 1. 测试目标

Mac Super Assistant（工程内部代号：Assistant）是 macOS 原生效率工具，MVP 核心能力包括统一搜索入口、应用启动、剪贴板历史、截图与轻量标注、内置命令、计算/单位换算、设置与权限管理。

测试目标：

1. **验证核心用户路径可用**：首次 Onboarding 后，用户可以通过 `⌥ Space` 使用搜索、剪贴板、截图和内置命令。
2. **保护本地数据链路**：剪贴板监听、Core Data 持久化、文件系统大对象、内存索引、去重、清理策略必须稳定。
3. **验证搜索体验**：Provider 聚合、拼音搜索、排序评分、最近使用加权、黑名单过滤必须符合 PRD。
4. **验证权限和隐私边界**：屏幕录制和辅助功能权限必须强制完成；剪贴板默认开启但需用户确认知晓；数据默认仅本地保存。
5. **控制高风险操作**：内置命令只允许白名单；需要确认的命令必须弹确认；不执行任意 shell。
6. **支持发布级体验**：中英文、本地化、关于页、隐私政策、反馈邮件、检查更新、官网/项目主页信息完整。

---

## 2. 测试分层

| 层级 | 范围 | 策略 | 运行方式 |
| :--- | :--- | :--- | :--- |
| 单元测试 | 搜索评分、Provider、拼音、计算器、单位换算、hash、黑名单、使用统计 | 尽量抽离纯 Swift 逻辑测试 | XCTest / Swift Testing |
| 数据集成测试 | Core Data 模型、剪贴板记录、去重、置顶、保留时间、资源路径 | 使用临时 Core Data store 和临时文件目录 | XCTest |
| 服务集成测试 | 剪贴板监听、内存索引同步、Provider 聚合、设置持久化 | 使用 mock pasteboard / mock provider / mock filesystem | XCTest |
| UI 构建验证 | SwiftUI/AppKit 窗口、菜单栏、搜索框、管理中心、Onboarding | 构建验证 + 可测试 ViewModel | Xcode build/test |
| 手动验收 | 权限、真实截图、全局快捷键、菜单栏、系统设置跳转 | 按手动清单逐项验证 | 人工执行 |
| 发布验收 | 关于页、隐私政策、反馈邮件、检查更新、官网/项目主页 | 文档/链接/流程检查 | 人工执行 |

---

## 3. 测试入口与基线命令

### 3.1 必跑自动化命令

| 命令 | 目的 | US-021 基线要求 |
| :--- | :--- | :--- |
| `swift test --skip-update` | SwiftPM 单元/集成测试入口，覆盖纯逻辑、Provider、Core Data 临时 store、文件资源临时目录、Repository 和内存索引 | 必须通过；如失败必须修复或按阻塞流程记录 |
| `xcodebuild -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug build` | macOS App Debug 构建验证，覆盖 SwiftUI/AppKit/Xcode target 集成 | 环境允许时必须运行并通过 |
| `xcodebuild test -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug` | Xcode XCTest 入口，验证 Xcode target 中测试文件和资源配置 | 环境允许时必须运行并通过 |

### 3.2 当前自动化测试目标映射

| 覆盖主题 | 测试文件 | 验证方式 |
| :--- | :--- | :--- |
| SearchSource Provider、触发规则、排序、总上限、执行后关闭 | `SnapVaultTests/SearchServiceCoreTests.swift` | mock sources 聚合测试；验证空输入、分来源 canSearch、`baseScore + matchScore + usageScore` 排序、12 条截断、主动作执行返回关闭搜索框 |
| AppSource 应用索引、拼音、黑名单、使用统计 | `SnapVaultTests/AppSearchSourceTests.swift` | 临时 `.app` bundle 目录；验证 MVP 三目录范围、中文应用拼音/首字母、黑名单隐藏/恢复、启动统计加权 |
| CommandSource 白名单、双语别名、拼音、确认、使用统计 | `QingniaoTests/SystemCommandSourceTests.swift` | 验证 15 个内置命令（含打开剪贴板历史）、危险命令不可搜、确认门禁、中文/英文/拼音/首字母搜索和命令选择加权 |
| SettingsSource 页面入口、拼音和设置源开关 | `SnapVaultTests/SettingsSourceTests.swift` | 验证设置/权限/剪贴板历史/搜索源/快捷键/截图/关于入口，且搜索结果只打开页面不直接切换设置 |
| 拼音工具与文本匹配 | `SnapVaultTests/PinyinHelperTests.swift`、`SnapVaultTests/SearchTextMatcherTests.swift` | 验证中文转拼音、首字母、混合中英文、英文别名和中文别名拼音匹配 |
| CalculatorSource 与单位换算 | `SnapVaultTests/CalculatorSourceTests.swift`、`SnapVaultTests/UnitConverterSourceTests.swift` | 验证四则、括号、小数、非法/除零/范围外输入拒绝；长度、重量、数据大小、温度换算；回车复制动作 |
| contentHash 去重策略 | `SnapVaultTests/AssistantClipboardRepositoryTests.swift` | 验证文本换行规范化、富文本格式参与 hash、图片二进制 hash、文件路径排序、重复复制只更新时间 |
| Core Data 临时 store 与模型 CRUD | `SnapVaultTests/PersistenceControllerTests.swift` | 使用 `.temporary` store；验证 ClipboardRecord/ClipboardResource/SearchBlacklistItem/UsageStat/AppSetting CRUD、唯一约束、级联删除、默认设置 |
| FileResourceStore 临时目录 | `SnapVaultTests/AssistantClipboardRepositoryTests.swift` | 使用临时 `AssistantFileSystem`；验证 Images/Thumbnails/RichText 写读删、UUID 相对路径、存储占用 |
| ClipboardRepository、置顶、保留时间、资源缺失 | `SnapVaultTests/AssistantClipboardRepositoryTests.swift` | 验证 upsert/fetch/history/delete/clearAll/togglePin/cleanupExpired/storageUsage，资源缺失和文件引用缺失 snapshot |
| InMemorySearchIndex 与剪贴板索引链路 | `SnapVaultTests/InMemorySearchIndexTests.swift` | 验证启动重建轻量字段、不加载图片/富文本大对象、upsert/delete/clear/pin 同步、索引命中后按需加载详情 |
| 搜索黑名单 Repository | `SnapVaultTests/SearchBlacklistRepositoryTests.swift` | 验证具体结果 add/list/contains/remove，以及 SearchService 过滤后移除恢复 |
| 设置服务、保留时间、语言、开机启动、截图目录 | `SnapVaultTests/SettingsServiceTests.swift` | 验证默认值、持久化、reset、语言 raw value 和截图保存目录 |
| Onboarding / 权限 / 快捷键 ViewModel | `SnapVaultTests/OnboardingViewModelTests.swift` | 使用 mock Permission/Hotkey/LaunchAtLogin，验证拒绝权限不能完成、重新检测、快捷键冲突和剪贴板知晓确认 |
| 搜索面板与剪贴板页面 ViewModel | `SnapVaultTests/SearchPanelViewModelTests.swift`、`SnapVaultTests/ClipboardListViewModelTests.swift` | 验证键盘选择、ESC/关闭、历史筛选、回车恢复、删除/清空确认等可自动化 ViewModel 行为 |
| 截图标注纯逻辑 | `SnapVaultTests/AnnotationTests.swift` | 验证标注模型、样式预设、撤销/重做等不依赖真实屏幕录制权限的逻辑 |

### 3.3 手动验收归档要求

P0/P1 手动用例执行时，应记录：执行日期、macOS 版本、构建方式、执行人、通过/失败、失败截图或日志、对应 Case ID。US-021 只建立可执行清单和自动化基线；US-022 才执行完整 MVP 集成验收并汇总所有手动结果。

---

## 4. 自动化测试范围

### 4.1 SearchSource / Provider

应覆盖：

- Provider 启用/禁用展示逻辑。
- AppSource 只索引 `/Applications`、`~/Applications`、`/System/Applications` 下的 `.app`。
- CommandSource 只返回内置白名单命令。
- CalculatorSource 只在表达式或单位模式时触发。
- SettingsSource 返回页面级和具体设置区块入口。
- 搜索黑名单过滤具体结果。
- SearchResult 支持 `primaryAction` 和 `secondaryActions`，但 MVP UI 只执行主动作。

### 4.2 搜索排序与触发规则

应覆盖：

- 空输入时不展示任何推荐、最近内容或剪贴板内容。
- 应用、命令、设置输入 1 个字符开始搜索。
- 剪贴板输入不少于 2 个字符开始搜索。
- 计算/换算仅在检测到表达式或单位模式时触发。
- 来源基础优先级：应用 100、命令 90、计算/换算 85、设置 80、剪贴板 70。
- 文本匹配分数参与综合排序。
- 应用和命令的使用次数、最后使用时间参与最近使用加权。
- 总结果上限为 12 条。
- 不显示分组标题，每条结果通过图标和类型标签标识来源。

### 4.3 拼音与中英文别名

应覆盖：

- 应用名称、命令名称、设置项名称支持拼音搜索。
- 应用名称、命令名称、设置项名称支持拼音首字母搜索。
- 剪贴板正文 MVP 不做拼音索引，只做原文搜索。
- 内置命令维护中英文别名。
- 无论当前界面语言，中文和英文关键词都能搜索到对应命令。

### 4.4 CalculatorSource / Unit Converter

应覆盖：

- 基础四则运算。
- 括号。
- 小数。
- 非法表达式不崩溃、不返回错误结果。
- 除零等非有限结果不返回。
- 长度、重量、数据大小、温度换算。
- 不支持货币换算、复杂函数、变量和计算历史。
- 回车主动作复制计算/换算结果到系统剪贴板。
- 计算/换算结果是否进入剪贴板历史遵循统一剪贴板监听与去重逻辑。
- CalculatorSource 表达式求值必须验证未使用 `NSExpression` 等可执行表达式机制；非法表达式、除零、NaN/Infinity、货币、复杂函数、变量、历史、体积/时长等范围外输入均返回空结果。

### 4.5 剪贴板数据模型与持久化

应覆盖：

- Core Data 存储结构化数据。
- 文件系统存储图片原图、缩略图、RTF/HTML 原始格式等大对象。
- 大对象目录至少包含：`Clipboard/Images/`、`Clipboard/Thumbnails/`、`Clipboard/RichText/`。
- 大对象文件名使用 UUID。
- Core Data 保存相对路径/资源标识和 contentHash。
- 文本、富文本、图片、文件引用均可保存。
- 富文本保存纯文本内容和 RTF/HTML 原始格式。
- 展示和搜索使用纯文本。
- 富文本复制回剪贴板时尽量恢复 RTF/HTML，失败则降级为纯文本。
- 文件剪贴板只保存引用/路径，不复制文件内容。
- 文件移动或删除后显示资源不可用提示。

### 4.6 剪贴板去重、置顶和清理

应覆盖：

- 基于 contentHash 去重。
- 重复复制相同文本、图片或文件引用时不新增记录，只更新时间。
- 去重后的记录按更新时间重新排序。
- 已置顶内容重复复制时更新时间但保持置顶。
- 支持置顶/取消置顶。
- 置顶项显示在列表顶部。
- 置顶项不受自动过期清理影响。
- 保留时间预设：7 天、30 天、90 天、永久。
- 默认保留 30 天。
- 只按时间淘汰，不按容量自动清理。
- 显示存储占用，并提供清空历史入口。
- 清空全部历史必须二次确认并提示不可撤销。
- 删除单条历史 MVP 可以不二次确认。

### 4.7 内存搜索索引

应覆盖：

- 启动时从 Core Data 全量加载轻量索引字段。
- 内存索引不加载图片原图、RTF/HTML 原始数据等大对象。
- 索引至少包含 id、纯文本摘要、内容类型、时间、置顶状态、hash、资源引用。
- 新增、更新、删除、置顶变化时同步更新内存索引。
- 剪贴板历史页面和统一搜索优先查询内存索引，再按需加载 Core Data 详情。

### 4.8 搜索黑名单

应覆盖：

- 只支持屏蔽具体搜索结果。
- 可隐藏某个 App、某条内置命令、某个设置入口。
- 不支持按关键词、路径、来源规则批量隐藏。
- MVP 只能通过设置页查看、添加、移除黑名单。
- 黑名单移除后对应结果重新展示。
- MVP 不实现搜索结果右键菜单或完整次级动作入口。

### 4.9 UpdateService（v1.0.1 起）

放置位置：`SnapVaultTests/UpdateServiceTests.swift`（`swift test` 覆盖）。

#### TC-U-001：UpdateService 启动期不主动启动 Sparkle updater

- **类型**：unit / P0
- **意图**：`UpdateService.setup()` 调用后，Sparkle updater 不在启动期主动 `startUpdater`，从代码级消除“无法启动更新程序”弹窗根因。
- **前置条件**：`UpdateService.swift` 采用 `startsUpdaterAutomatically = false` 常量并绑定 `SPUStandardUpdaterController(startingUpdater:)` 入参；测试目标 `@testable import SnapVault`。
- **步骤**：
  1. 读取 `UpdateService.startsUpdaterAutomatically` 常量。
  2. 断言其值为 `false`（该常量即 `SPUStandardUpdaterController(startingUpdater:)` 的唯一实参来源）。
- **预期结果**：启动策略常量为 `false`；测试进程内不弹出任何系统对话框。
- **通过判定**：断言通过，用例在 `swift test` 中 pass。

#### TC-U-002：checkNow() 仍触发 GitHub Releases 跳转

- **类型**：unit / P0
- **意图**：`UpdateService.checkNow()` 通过注入的 `UpdateCheckServiceProtocol` 打开 GitHub Releases 页（MVP“检查更新”跳转策略不被破坏）。
- **前置条件**：`UpdateService.init(updateCheckService:)` 支持注入；在测试文件内自建 spy（不复用其他文件内的 `private` spy 类型）。
- **步骤**：
  1. 构造 spy `UpdateCheckServiceProtocol`（记录 `openDownloadPage()` 调用次数）。
  2. 以注入方式构造 `UpdateService`。
  3. 调用 `checkNow()`。
  4. 断言 spy 记录到恰好一次跳转。
- **预期结果**：`openDownloadPage()` 被调用一次；不触发真实 `NSWorkspace.open`。
- **通过判定**：spy 断言通过（调用次数 == 1），用例在 `swift test` 中 pass。

---

## 5. 手动验收清单

### 5.1 首次 Onboarding

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| ONB-001 | 首次启动显示 Onboarding | 首次运行 App | 依次显示欢迎、搜索入口与快捷键、剪贴板说明、截图权限、辅助功能权限、开机启动、完成 | P0 |
| ONB-002 | 快捷键注册成功 | 默认 `⌥ Space` 未冲突 | Onboarding 尝试注册成功，可继续 | P0 |
| ONB-003 | 快捷键冲突处理 | 模拟默认快捷键注册失败 | 要求用户重新录制快捷键，直到成功后才能完成 | P0 |
| ONB-004 | 剪贴板默认开启确认 | 到剪贴板说明步骤 | 文案说明默认开启、仅本地保存、可暂停/清空；用户点击“我知道了，继续” | P0 |
| ONB-005 | 屏幕录制权限强制 | 拒绝屏幕录制权限 | 停留在权限页，不能完成 Onboarding | P0 |
| ONB-006 | 辅助功能权限强制 | 拒绝辅助功能权限 | 停留在权限页，不能完成 Onboarding，并解释用途边界与未来能力 | P0 |
| ONB-007 | 权限重新检测 | 授权后返回 App 点击重新检测 | 权限状态更新，可继续 | P0 |

> **v1.2 修订（Onboarding 单屏化，见 §7.8 / P-06 / D-116）**：v1.2 Onboarding 由 7 步向导改为**单屏**（720×520）。以下旧 TC 状态更新——
> - **ONB-001「多步依次显示」→ 作废/替换**：不再有多步流。由第 11 节 **ONB-V2-001（单屏布局）** 取代。
> - **ONB-005/ONB-006「拒绝权限停留在权限页且不能完成」→ 部分修订**：屏幕录制仍强制（ONB-005 语义保留，由 **ONB-V2-004** 承接单屏版预期）；**辅助功能不再强制**（ONB-006 作废，由 **ONB-V2-006 / PERM-OD-\*** 取代，辅助功能改为「稍后再说」+ 按需申请）。
> - **ONB-002/003/004/007 仍有效**（快捷键注册/冲突、剪贴板知晓、重新检测），但在单屏语境下执行，新版步骤见 ONB-V2 系列。

### 5.2 菜单栏 App

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| MENU-001 | 菜单栏常驻 | 启动 App | 菜单栏显示单色 template 图标，无 Dock 图标 | P0 |
| MENU-002 | 菜单项完整 | 点击菜单栏图标 | 显示打开搜索、剪贴板、截图、设置、关于、退出 | P0 |
| MENU-003 | 菜单栏截图 | 点击“截图” | 直接进入区域截图 | P0 |
| MENU-004 | 退出 App | 点击“退出” | App 完全退出，快捷键监听和剪贴板记录停止 | P0 |

> **v1.2 修订（品牌改名 + 死代码清理）**：MENU-001「菜单栏图标」预期更新为**青鸟单色 template 图标**（见 BRAND-005）。`MenuBarView` 为 legacy 死代码将被删除（管理中心走独立 NSWindow，非菜单栏下拉承载复杂视图，见 D-114 / CODE-002），但菜单栏 statusItem 菜单项（打开搜索/剪贴板/截图/设置/关于/退出）本身**保留有效**。MENU-001~004 仍执行，图标断言以青鸟图标为准。

### 5.3 统一搜索入口

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| SEARCH-001 | 快捷键打开搜索 | 按 `⌥ Space` 或自定义快捷键 | 居中搜索框出现，输入框聚焦 | P0 |
| SEARCH-002 | 空输入状态 | 打开搜索框但不输入 | 不显示推荐结果、最近内容或剪贴板内容，仅显示输入提示 | P0 |
| SEARCH-003 | 应用搜索 | 输入应用名或拼音 | 返回匹配 `.app`，可回车启动 | P0 |
| SEARCH-004 | 命令搜索 | 输入 `截图`、`screenshot`、`jt` | 返回对应内置命令 | P0 |
| SEARCH-005 | 剪贴板搜索触发 | 输入 1 个字符 | 不触发剪贴板结果 | P0 |
| SEARCH-006 | 剪贴板搜索结果 | 输入不少于 2 个字符且匹配历史 | 返回剪贴板结果 | P0 |
| SEARCH-007 | 计算器结果 | 输入 `1+2*3` | 显示结果 `7`，回车复制到剪贴板 | P0 |
| SEARCH-008 | 单位换算结果 | 输入 `10 cm to inch` | 显示长度换算结果，回车复制 | P1 |
| SEARCH-009 | 搜索关闭 | 点击外部、切换 App、按 ESC、再次按快捷键、执行结果 | 搜索框关闭 | P0 |
| SEARCH-010 | 总结果上限 | 输入广泛关键词 | 最多展示 12 条结果 | P1 |

> **v1.2 修订（命令栏重设计 + 文件搜索接入，见 §9.3/9.4 P-01、D-120/D-121/D-122）**：
> - **SEARCH-002「空输入不展示任何内容」→ 修订**：v1.2 空态改为显示「最近使用（≤5）+ 收藏（≤5）」，不再是纯占位提示（演进关系，见 D-120）。新预期由第 11 节 **SEARCH-E-001** 承接；旧「不显示推荐结果」语义收敛为「不显示搜索推荐结果，但显示最近/收藏入口」。
> - 新增文件搜索来源：广泛关键词场景（SEARCH-010）现可能命中文件结果，来源权重文件=75（高于剪贴板 70），排序断言见 **SEARCH-F-006**。
> - SEARCH-001/003/004/005/006/007/008/009 主流程**保留有效**，但 UI 走 DesignToken 重设计后的命令栏（P-01），选中态/圆角/材质断言见 TOK 系列；新增 ⌘1-6 切源、⌘K 清空、Tab 补全见 **SEARCH-E** 系列。

### 5.4 剪贴板历史页面

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| CLIP-001 | 文本记录 | 复制一段文本 | 历史中出现文本项 | P0 |
| CLIP-002 | 富文本记录 | 从网页/文档复制带格式文本 | 展示纯文本，复制回剪贴板时尽量保留格式 | P0 |
| CLIP-003 | 图片记录 | 复制图片 | 保存原图，生成缩略图，历史中可预览 | P0 |
| CLIP-004 | 文件引用记录 | Finder 中复制文件 | 历史中显示文件名、路径、类型、复制时间，不复制文件内容 | P0 |
| CLIP-005 | 文件丢失容错 | 复制文件后移动/删除原文件 | 历史项显示资源已丢失，恢复时提示失败原因 | P1 |
| CLIP-006 | 类型筛选 | 点击全部/文本/图片/文件 | 列表按类型过滤 | P0 |
| CLIP-007 | 独立搜索框 | 在剪贴板页面输入关键词 | 即时 debounce 搜索，仅搜索剪贴板历史 | P0 |
| CLIP-008 | 回车恢复 | 选择历史项按 Enter | 内容写入系统剪贴板，不自动粘贴到前台应用 | P0 |
| CLIP-009 | 置顶排序 | 置顶某条历史 | 置顶项在列表顶部，搜索时置顶匹配项优先 | P0 |
| CLIP-010 | 重复复制去重 | 重复复制相同内容 | 不新增记录，只更新时间并重新排序 | P0 |
| CLIP-011 | 存储占用 | 打开设置或剪贴板页面 | 显示剪贴板历史存储占用，并提供清空入口 | P1 |
| CLIP-012 | 清空确认 | 点击清空全部 | 显示二次确认，提示不可撤销 | P0 |

> **v1.2 修订（P-02 剪贴板窗口重设计）**：剪贴板历史改为**独立 NSWindow + 两栏 NavigationSplitView**（64px 行、hover 操作、预览 Sheet、swipe action、底部状态栏，见 §9.4 P-02）。CLIP-001~012 功能语义**全部保留有效**，但界面断言（行高、hover 4 按钮、预览 Sheet、swipe 收藏/删除）走新布局；数据链路（去重/置顶/保留/存储占用）不变。数据目录由 `Assistant/` 迁移到 `Qingniao/`，迁移后历史数据必须仍在（见 **DATA** 系列）。

### 5.5 截图与标注

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| SHOT-001 | 区域截图 | 搜索/菜单触发区域截图 | 可选择区域，完成后进入预览工具栏 | P0 |
| SHOT-002 | 全屏截图 | 搜索触发全屏截图 | 完成截图并进入预览工具栏 | P0 |
| SHOT-003 | 窗口截图 | 搜索触发窗口截图 | 可选择窗口并截图，进入预览工具栏 | P0 |
| SHOT-004 | 标注工具 | 使用矩形框、箭头、文字、马赛克/模糊 | 标注显示正确，可撤销/重做 | P0 |
| SHOT-005 | 标注样式预设 | 切换颜色、线宽、文字大小 | 预设生效：红/黄/蓝/绿/白/黑，细/中/粗，小/中/大 | P1 |
| SHOT-006 | 复制截图 | 点击复制 | 截图写入系统剪贴板，并进入剪贴板历史 | P0 |
| SHOT-007 | 保存截图 | 点击保存 | 保存为 PNG 到 `~/Pictures/Screenshots`，文件名为 `Screenshot yyyy-MM-dd HH.mm.ss.png`，显示轻提示 | P0 |
| SHOT-008 | 保存不进剪贴板 | 点击保存但不复制 | 不额外写入剪贴板历史 | P1 |
| SHOT-009 | ESC 取消 | 区域/窗口选择、预览、标注中按 ESC | 始终取消当前截图流程；预览阶段丢弃并关闭 | P0 |
| SHOT-010 | 副屏区域截图 | 将鼠标移到右侧、左侧或下方副屏并触发区域截图，框选可辨识内容 | 叠层只覆盖鼠标所在显示器，结果来自该显示器对应选区，不混入主屏内容；Retina 缩放下尺寸正确 | P0 |
| SHOT-011 | 区域选区原位锁定 | 完成有效框选后尝试再次拖动，并观察操作区 | 选区边框与遮罩保持原位且不可再次修改；选区下方显示复制、保存、标注、取消四按钮工具栏，不出现居中大图预览 | P0 |
| SHOT-012 | 区域工具栏边缘避让与关闭 | 分别在屏幕底边、左右边缘框选，并执行复制、保存、取消、ESC、标注 | 底边空间不足时工具栏移到选区上方，左右不越屏；前四种完成后选区和工具栏关闭，标注前也先关闭选区 | P0 |

> **v1.2 修订（全屏热键 + 悬浮 pill 标注 UI，见 §9.4 P-04/P-05、FR-SHOT-FULLSCREEN）**：
> - **SHOT-002「全屏截图」→ 修订**：v1.2 全屏截图新增独立全局热键 `⌃⌥⌘3`，不再只能走命令面板。新预期见 **SHOT-FS** 系列。
> - **SHOT-004「标注工具」→ 修订**：标注工具改为**顶部/底部悬浮 pill**；**blur 灰禁用**并 tooltip「v1.3 支持」，mosaic 保留（`CIPixellate` scale 10）。新预期见 **SHOT-UI** 系列。
> - SHOT-001/003/005/006/007/008/009 **保留有效**；保存默认目录 P-05 描述为「上次目录，默认 `~/Desktop`」，与 FR-SHOT-10「`~/Pictures/Screenshots`」存在文档差异，见评审 review.md 冲突记录（不阻塞，测试以 PRD FR-SHOT-10 为准，SHOT-007 保持 `~/Pictures/Screenshots`）。

### 5.6 内置命令

当前内置命令权威清单以 [architecture/api.md](../architecture/api.md) 为准，共 15 个命令（含“打开剪贴板历史”）。

| Case ID | 场景 | 覆盖 CommandID | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| CMD-001 | 打开系统设置 | `openSystemSettings` | 搜索并执行 | 打开系统设置 | P0 |
| CMD-002 | 打开本应用设置 | `openAppSettings` | 搜索并执行 | 打开管理中心设置页 | P0 |
| CMD-003 | 打开目录 | `openDownloads` / `openApplications` / `openDesktop` | 分别搜索下载、应用程序、桌面目录命令 | Finder 打开对应目录 | P1 |
| CMD-004 | 截图命令 | `captureRegion` / `captureFullScreen` / `captureWindow` | 分别搜索区域/全屏/窗口截图 | 进入对应截图流程 | P0 |
| CMD-005 | 清空剪贴板历史确认 | `clearClipboardHistory` | 搜索并执行清空历史 | 弹确认，取消不清空，确认后清空 | P0 |
| CMD-006 | 暂停/恢复剪贴板记录 | `toggleClipboardRecording` | 搜索并执行 | 剪贴板记录状态切换 | P0 |
| CMD-007 | 检查权限状态 | `checkPermissions` | 搜索并执行 | 打开权限页或显示权限状态 | P1 |
| CMD-008 | 重启 Finder/Dock 确认 | `restartFinder` / `restartDock` | 分别搜索并执行重启 Finder、重启 Dock | 弹确认，取消不执行；真实执行仅限人工安全环境 | P0 |
| CMD-009 | 切换深浅色模式 | `toggleAppearance` | 搜索并执行 | 不弹确认，系统外观切换 | P1 |
| CMD-010 | 禁止高风险命令和任意 shell | 禁止项 | 输入疑似 shell、sudo、关机、重启系统、注销、删除文件、杀进程命令 | 不执行，不返回可直接执行的危险结果 | P0 |

> **v1.2 修订（关闭 Sandbox 后 AppleEvents 命令可靠执行，见 §7.9 / D-103）**：CMD-008（重启 Finder/Dock）、CMD-009（切换外观）等 AppleEvents 类命令在 v1.2 关闭 App Sandbox 后应**真实可执行、不再静默失败**；首次控制其他 App 可能触发 Automation 授权。新增真实执行验收见 **DIST** / **REG** 系列（AC-CMD-SANDBOX）。当前命令白名单为 15 条（含“打开剪贴板历史”），确认门禁不变，CMD-001~010 全部保留有效。

### 5.7 设置、关于与发布信息

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| SET-001 | 搜索源开关 | 设置中关闭某搜索源展示 | 该来源结果不再出现在统一搜索中 | P0 |
| SET-002 | 剪贴板功能开关 | 关闭剪贴板记录 | 停止记录新剪贴板；重新开启后恢复 | P0 |
| SET-003 | 黑名单管理 | 设置页添加/移除具体结果 | 加入后不展示，移除后重新展示 | P1 |
| SET-004 | 开机启动 | 完成 Onboarding 后检查登录项 | 默认启用；设置中可关闭 | P1 |
| SET-005 | 语言切换 | 设置为中文/English/跟随系统 | 文案切换或提示重启后生效 | P1 |
| ABOUT-001 | 关于页信息 | 打开关于页 | 显示应用名称、版本号、构建号、官网/项目主页、隐私政策、检查更新、反馈入口、第三方许可、版权信息 | P0 |
| ABOUT-002 | 检查更新 | 点击检查更新 | 打开官网下载页或 GitHub Release 页面 | P1 |
| ABOUT-003 | 邮件反馈 | 点击反馈问题 | 打开邮件客户端，预填应用版本、macOS 版本、错误摘要和用户补充说明 | P1 |
| PRIV-001 | 隐私政策入口 | 关于页点击隐私政策 | 打开隐私政策，说明本地保存、不上传、不同步、不训练、关闭记录和清空方式 | P0 |

> **v1.2 修订（品牌/版本号/设置新页/更新策略）**：
> - **ABOUT-001「关于页信息」→ 修订**：应用名称改为**青鸟 Qingniao**，版本号显示 **1.2.0**（三源一致，见 BRAND-006 / BRAND-007）。
> - **ABOUT-002「检查更新」→ 修订**：彻底移除 Sparkle，检查更新直接跳 GitHub Releases（见 UPD 系列）。
> - **ABOUT-003「邮件反馈」→ 修订**：反馈邮箱改为 **feedback@qingniao.app**（上线前校验，见 BRAND-004）。
> - **SET-001~005 保留有效**，新增「外观」「数据」页与快捷键冲突检测见 **SETNEW** 系列。
> - PRIV-001 保留，隐私政策数据目录路径更新为 `~/Library/Application Support/Qingniao/`（见 DATA-005）。

### 5.8 本地化

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| L10N-001 | 系统中文 | macOS 语言为中文 | App 默认显示简体中文 | P0 |
| L10N-002 | 系统英文 | macOS 语言为英文 | App 默认显示 English | P0 |
| L10N-003 | 手动切换语言 | 设置中选择语言 | 核心 UI、Onboarding、权限说明、隐私说明、错误提示、关于页语言一致 | P0 |
| L10N-004 | 双语命令搜索 | 中文界面输入英文命令，英文界面输入中文命令 | 均能搜索到对应内置命令 | P1 |

### 5.9 更新检查（v1.0.1 起）

| Case ID | 场景 | 步骤 | 预期结果 | 优先级 |
| :--- | :--- | :--- | :--- | :--- |
| TC-M-001 | Debug 启动无 Sparkle 弹窗 | Debug 构建启动后观察 3 秒 | 不出现“无法启动更新程序”系统对话框 | P0 |
| TC-M-002 | Release 启动无 Sparkle 弹窗 | Release 构建启动后观察 3 秒 | 不出现“无法启动更新程序”系统对话框 | P0 |
| TC-M-003 | 检查更新跳转浏览器 | 点击“检查更新” | 默认浏览器打开 `https://github.com/abyss/assistant/releases`，不出现 Sparkle 更新 UI 或错误弹窗 | P0 |

> v1.0.1（2026-07-02）·TC-M-001/002/003 由 @user 亲自执行通过（Debug + Release + 检查更新跳转），详见 `iterations/v1.0.1/test/report.md`。

---

## 6. P0/P1 验证方式总表

| 能力域 | P0/P1 Case ID | 自动化验证 | 手动验证 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| Onboarding 与权限 | ONB-001 ~ ONB-007 | `OnboardingViewModelTests` 覆盖步骤流、权限拒绝/重新检测、快捷键冲突、剪贴板知晓确认 | 必须手动验证真实系统权限页、授权/拒绝后的系统状态变化 | 真实屏幕录制/辅助功能授权依赖 macOS 隐私数据库，不能只靠自动化替代 |
| 菜单栏 App | MENU-001 ~ MENU-004 | Xcode build 验证 App target、`LSUIElement`、菜单代码可编译 | 必须手动验证菜单栏图标、无 Dock 图标、菜单项和退出后后台服务停止 | 菜单栏与 Dock 状态属于系统 UI 行为 |
| 统一搜索入口 | SEARCH-001 ~ SEARCH-010 | `SearchServiceCoreTests`、`SearchPanelViewModelTests`、`AppSearchSourceTests`、`SystemCommandSourceTests`、`CalculatorSourceTests`、`UnitConverterSourceTests` | 必须手动验证全局快捷键唤起、失焦/切 App 关闭、真实 App 启动 | 核心排序/触发/上限自动化，系统快捷键和窗口行为人工验收 |
| 剪贴板历史 | CLIP-001 ~ CLIP-012 | `AssistantClipboardRepositoryTests`、`ClipboardMonitorTests`、`InMemorySearchIndexTests`、`ClipboardListViewModelTests` | 必须手动验证真实 NSPasteboard 文本/富文本/图片/Finder 文件复制恢复 | 数据层和 ViewModel 自动化，真实 pasteboard 格式兼容人工验收 |
| 截图与标注 | SHOT-001 ~ SHOT-012 | `AnnotationTests` 覆盖标注模型/样式/撤销重做，以及多屏裁剪和区域工具栏定位几何；Xcode build 覆盖截图 target 集成 | 必须手动验证区域/全屏/窗口截图、副屏真实内容、选区锁定、复制/保存 PNG、ESC | 真实截图依赖屏幕录制权限和多显示器环境 |
| 内置命令 | CMD-001 ~ CMD-010 | `SystemCommandSourceTests` 覆盖 15 个白名单（含打开剪贴板历史）、确认门禁、危险命令拒绝、双语/拼音和使用统计 | 必须手动验证打开目录/系统设置/截图命令；重启 Finder/Dock 仅安全环境确认 | 自动化不得真实执行中风险系统操作 |
| 设置、黑名单、关于与发布信息 | SET-001 ~ SET-005、ABOUT-001 ~ ABOUT-003、PRIV-001 | `SettingsServiceTests`、`SettingsSourceTests`、`SearchBlacklistRepositoryTests`、`ReleaseInfoServiceTests` | 必须手动验证真实关于页、隐私政策链接、邮件客户端、检查更新 URL | US-020 官网素材与链接最终准备不属于 US-021 |
| 本地化 | L10N-001 ~ L10N-004 | `SettingsSourceTests`、`SettingsServiceTests`、`SystemCommandSourceTests` 覆盖语言设置 raw value 和双语搜索 | 必须手动验证中文/英文 UI 文案完整 | 自动化覆盖设置/搜索，完整文案需人工走查 |
| 性能 | 冷启动、搜索响应、CPU、内存、剪贴板响应 | SearchService elapsed 和索引单测可作为回归信号 | 必须用 Activity Monitor/Instruments 和人工计时验收 | US-021 建立验收方式；US-022 执行完整性能记录 |

---

## 7. 性能验收

| 指标 | 目标 | 验收方式 |
| :--- | :--- | :--- |
| 冷启动 | ≤ 1 秒 | 本地多次启动取平均，排除首次系统缓存异常 |
| 搜索响应 | ≤ 100ms | 输入关键词到结果刷新，覆盖应用/命令/剪贴板/计算器 |
| 后台空闲 CPU | ≤ 1% | Activity Monitor 或 Instruments 观察常驻空闲状态 |
| 后台常驻内存 | ≤ 150MB，理想 ≤ 100MB | 常驻 30 分钟后观察内存占用 |
| 剪贴板监听响应 | 复制后 1 秒内进入历史 | 文本、图片、文件分别验证 |
| 截图交互 | 区域选择/预览/复制/保存无明显卡顿 | 手动验证 |

---

## 8. 明确不测 / 不自动执行范围

MVP 自动化测试不得执行：

- 关机、重启系统、注销、删除文件、杀进程、sudo、任意 shell。
- 真实重启 Finder / Dock，除非在人工安全环境下确认。
- 未经用户确认的崩溃日志或诊断信息上传。
- 静默访问网络反馈接口。

MVP 暂不覆盖：

- OCR。
- 录屏。
- 长截图。
- 截图历史页。
- 插件系统。
- 账号系统。
- 支付/授权/订阅。
- Mac App Store 审核流程。
- Developer ID 签名和 Apple Notarization 公证流程。

---

## 9. 后续测试改进

1. 为 SearchSource、剪贴板索引、Core Data repository、文件资源管理建立依赖注入接口，降低测试对真实系统状态的依赖。
2. 将截图坐标转换、标注图层模型、搜索评分、单位换算、拼音匹配等逻辑抽成纯函数，提升单元测试覆盖率。
3. 增加 UI 自动化测试，覆盖 Onboarding、管理中心和搜索框基础交互。
4. 后续引入签名/公证后，增加发布包安装、Gatekeeper、更新检查的端到端验收。
5. 后续引入右键菜单、Action Panel、快捷数字键后，补充对应交互测试。

---

## 10. Onboarding 与权限（v1.1.0 起）

> 本节用例来自 v1.1.0 迭代（Onboarding 死锁修复：屏幕录制权限申请 + 跳过向导，Issue #3、PR #4）。用例 ID 在本节内命名，与第 4/5 节 v1.0.1 的同号用例不冲突。追溯详见 `iterations/v1.1.0/test/cases.md`。

### 10.1 自动化用例

| 编号 | 标题 | 关联 AC / 需求 | 类型 | 优先级 |
|------|------|------|------|------|
| TC-U-001 | 协议扩展未破坏既有 conformer | AC-8 | unit | P0 |
| TC-U-002 | 进入 .screenRecording 调 request 恰一次 | AC-8 | unit | P0 |
| TC-U-003 | openPermissionSettings 先 request 后 openSettings | AC-8 | unit | P0 |
| TC-U-004 | skipOnboarding 写 flag、显式 clipboard=false、回调 onComplete | AC-5/6 | unit | P0 |
| TC-U-005 | skipOnboarding 遍历 7 步参数化均可跳 | AC-4/5 | unit | P0 |
| TC-U-006 | 跳过时 hotkey 持久化策略 | P-2.3 | unit | P1 |
| TC-U-007 | MockPermissionService spy 计数/返回值可配 | AC-8（基础设施） | unit | P0 |

- **TC-U-001**：`PermissionServiceProtocol` 新增 `requestScreenRecordingPrompt() -> Bool` 后，全部 conformer（真实 `PermissionService`、`MockPermissionService`、`StaticPermissionService`）均实现且可调用。判定：Mock 返回可配置 `true`、Static 返回固定 `true`、测试目标编译通过且不弹任何系统对话框。
- **TC-U-002**：`continueToNextStep()` 从 `.clipboardPrivacy` 进入 `.screenRecording` 时调用 `requestScreenRecordingPrompt()` 恰好一次。判定：`requestScreenRecordingCallCount == 1` 且 `step == .screenRecording`。
- **TC-U-003**：`openPermissionSettings(.screenRecording)` 在调 `openSystemSettings` 前先调 `requestScreenRecordingPrompt`。判定：`callLog == ["request", "openSettings"]` 且 `opened == [.screenRecording]`；`openPermissionSettings(.accessibility)` 不应调 request（`requestScreenRecordingCallCount == 0`）。
- **TC-U-004**：`skipOnboarding()` 写 `onboardingCompleted=true`、**显式**写 `clipboardEnabled=false`（`clipboard.enabled` 代码默认为 `"true"`，见 `PersistenceController.swift:307`，因此必须显式写 false 而非留空）、触发 `onComplete` 一次。判定：`XCTAssertTrue(onboardingCompleted)`、`XCTAssertFalse(clipboardEnabled)`、`XCTAssertTrue(didComplete)`。
- **TC-U-005**：在 `OnboardingStep.allCases`（7 步）任意一步调 `skipOnboarding()` 均成功且行为一致。判定：每步 `onboardingCompleted == true` 且 `didComplete == true`，`allCases.count == 7`。
- **TC-U-006**：跳过时若 hotkey 已录入有效值则持久化其值，否则用默认 `option+space`，禁止写空串/非法值。判定：`searchHotkey == "option+space"`（或实现选择的默认键）。
- **TC-U-007**：`MockPermissionService.requestScreenRecordingPrompt()` 支持 spy 计数（`requestScreenRecordingCallCount`）与返回值可配（`requestScreenRecordingResult`）+ `callLog`。判定：返回值随配置变化、计数累加。

### 10.2 手工验收用例

| 编号 | 标题 | 关联 AC / 需求 | 优先级 | 结果 |
|------|------|------|------|------|
| TC-M-001 | 首启触发系统授权弹窗 | AC-1 | P0 | 通过 |
| TC-M-002 | app 出现在系统设置列表 | AC-2 | P0 | 通过 |
| TC-M-003 | 授权后可继续（含 Recheck 隐含验证） | AC-3 | P0 | 通过 |
| TC-M-004 | Skip Setup 按钮 7 步全可见 | AC-4 | P0 | 通过 |
| TC-M-005 | Skip 弹确认 Alert，Cancel 不改变 | P-2.2 | P0 | 通过 |
| TC-M-006 | Skip 确认后进主界面 | AC-5 | P0 | 通过 |

- **TC-M-001**：`tccutil reset ScreenCapture com.assistant.app` 后 Clean 构建首启，进入 `.screenRecording` 步骤 5 秒内出现 macOS 系统屏幕录制授权弹窗。
- **TC-M-002**：TC-M-001 触发 request 后，「系统设置 → 隐私与安全 → 屏幕录制与系统录音」列表中出现本 App（Mac Super Assistant / Assistant）。
- **TC-M-003**：系统设置勾选授权后切回 app 点 Recheck，Continue 由禁用变可用、进入 accessibility 步骤（无 activation 自动检测、需手动 Recheck 是可接受降级）。
- **TC-M-004**：welcome/searchHotkey/clipboardPrivacy/screenRecording/accessibility/launchAtLogin/done 7 步 footer 左下角均可见 Skip Setup 按钮。
- **TC-M-005**：点 Skip Setup 弹含标题+内容+Skip/Cancel 两按钮的确认 Alert；点 Cancel 停留原步骤、无 settings 变化。
- **TC-M-006**：Alert 中点 Skip 后 onboarding 窗口关闭、状态栏图标出现、可打开搜索面板（跳过后 clipboardEnabled=false，剪贴板监听 pause 不 crash、不影响其它快捷键）。

- **待验证（v1.1.1+）**：TC-M-007 重启不重弹 / TC-M-008 hotkey 按需申请 Alert / TC-M-009 设置面板权限入口。代码层对称补齐（AppDelegate.ensureScreenRecordingPermission 补 request、`onboardingCompleted=true` 持久化由 TC-U-004 单测覆盖），端到端待下一迭代补验。详见 `iterations/v1.1.0/test/report.md`。

### 10.3 回归基线（v1.1.0 起）

| 编号 | 标题 | 基线 | 结果 |
|------|------|------|------|
| TC-R-001 | swift test 全绿 | ≥ 134（v1.0.1 基线 126 → 134） | 134/134 全绿 |
| TC-R-002 | xcodebuild test 全绿 | ≥ 125（v1.0.1 基线 119 → 125） | 125/125 TEST SUCCEEDED |

### 10.4 追溯矩阵（v1.1.0 AC → 用例）

| AC | 描述 | 覆盖用例 |
|----|------|---------|
| AC-1 | Clean 构建首启触发系统授权弹窗 | TC-M-001 |
| AC-2 | app 出现在系统设置列表 | TC-M-002 |
| AC-3 | 授权后可继续 | TC-M-003 |
| AC-4 | Skip 按钮全 7 步可见 | TC-M-004, TC-M-005, TC-U-005 |
| AC-5 | Skip 后进主界面 | TC-M-006 + TC-U-004/005 |
| AC-6 | 重启不重弹 | 待验证（TC-M-007 延期；代码层 TC-U-004 覆盖持久化，端到端未验） |
| AC-7 | 跳过后按需申请可用 | 待验证（TC-M-008/009 延期；code review 坐实复用同一 request API，端到端未验） |
| AC-8 | 既有测试全绿 + 新增单测覆盖 | TC-R-001, TC-R-002, TC-U-001~007 |

---

## 11. 青鸟 Qingniao v1.2 测试用例

> 本节为 v1.2.0 迭代新增用例，累积式追加，不覆盖第 1–10 节历史。用例 ID 采用模块前缀（TOK/BRAND/DATA/DI/SEARCH-F/SEARCH-E/SHOT-FS/SHOT-UI/ONB-V2/PERM-OD/CODE/DIST/UPD/SHORTCUT/SETNEW/REG/BUILD/ROBUST/ACC/I18N），与第 1–10 节的 TC-U/TC-M/TC-R 及 ONB/SEARCH/CLIP 等前缀不冲突。追溯依据：`doc/prd.md`（青鸟 v1.2）、`doc/architecture/design.md` v17、`api.md` v3、`db.md` v3、`doc/iterations/v1.2.0/architecture/review.md`（评审 6 个改善级问题 M-1~M-6）。
>
> **开发状态**：本用例集定稿时 v1.2 开发尚未开始（见 review.md §八 T-A~T-O 任务拆解）。用例只描述**外部可观察行为**，不锁定内部代码结构（死代码清理 CODE 系列、强制解包 ROBUST 系列除外，属明确要求的工程健康度校验）。
>
> **字段说明**：每条 TC 含 关联 FR/AC、前置条件、步骤、预期结果、优先级（P0/P1/P2）、自动化类型（swift = `swift test`；xcodebuild = `xcodebuild test`；手工 = 人工验收；E2E UI = 端到端 UI 走查）、对应测试文件（或「待建」）。测试模块随改名由 `SnapVaultTests` → `QingniaoTests`，本节测试文件路径统一以 `QingniaoTests/` 记（现物理目录 `SnapVaultTests/`，改名任务 T-A 落地后一致）。

### 11.1 覆盖模块与前缀索引

| 前缀 | 模块 | 关联 FR / 决策 | 主要类型 |
|------|------|----------------|----------|
| TOK | Design Token 层 | FR-UI-DESIGN-TOKENS / §9.2 / D-118 | swift + 手工 |
| BRAND | 品牌改名一致性 | §2.0 / D-101/D-102 / FR-UI-8/30 | swift + 手工 |
| DATA | 数据目录迁移 | FR-DATA-EXPORT-BACKUP / db §8.4 / D-111 | swift + 手工 |
| DI | AppContainer 依赖注入 | design §2.5/§16 / api §17 / M-1 | swift + 手工 |
| SEARCH-F | 文件搜索接入 | FR-SEARCH-FILE / US-012 / D-105 / M-3 | swift + 手工 |
| SEARCH-E | 命令栏空态与增强 | §9.3 / D-120/D-122 / FR-SEARCH-14/25 | swift + 手工 |
| SHOT-FS | 全屏截图热键 | FR-SHOT-FULLSCREEN / US-013 / D-107 | swift + 手工 |
| SHOT-UI | 截图标注 UI | §9.4 P-05 / FR-SHOT-7 / D-117 | 手工 + swift |
| ONB-V2 | Onboarding 单屏 | FR-UI-ONBOARDING / P-06 / D-116 | swift + 手工 |
| PERM-OD | 权限按需申请 | FR-ONBOARD-ACCESSIBILITY-ONDEMAND / D-104 / AC-7 | swift + 手工 |
| CODE | 死代码清理 | §10.7 / D-106 / api §21 | swift/静态 |
| DIST | 分发签名 | FR-PERM-APPLE-EVENTS / §11.4 / D-103 / M-5 | 手工 + 脚本 |
| UPD | 更新（移除 Sparkle） | FR-UI-9~17 / §10.5 | swift + 手工 |
| SHORTCUT | 快捷键与冲突检测 | FR-UI-HOTKEYS / §9.6 / FR-ONBOARD-16 | swift + 手工 |
| SETNEW | 设置新页 | FR-UI-SETTINGS-WINDOW / P-03 | swift + 手工 |
| REG | 回归 | §12.1 / 全 MVP FR | swift + 手工 |
| BUILD | 构建脚本 | §10.7 | 脚本 + 手工 |
| ROBUST | 健壮性整改 | review M-6 / 强制解包点 | swift/静态 |
| ACC | 无障碍 | FR-UI-A11Y / §9.8 / §7.14 | 手工 |
| I18N | 中英双语 | FR-UI-I18N / §9.9 | swift + 手工 |

### 11.2 TOK —— Design Token 层

#### TOK-001：JadeColor 明暗双模式取值
- **关联**：FR-UI-DESIGN-TOKENS、§9.2.1、D-113 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：待建 `QingniaoTests/DesignTokenTests.swift`
- **前置条件**：DesignToken 层已建立，`JadeColor` 暴露 Light/Dark 取值。
- **步骤**：1) 读取 `JadeColor.jade500` 在 light/dark 下的解析值；2) 断言 light ≈ `#0A9488`、dark ≈ `#2DD4BF`；3) 对 jade600/jade50 同理。
- **预期结果**：品牌主色明暗取值与 §9.2.1 表一致；语义色走系统色（`systemGreen` 等），不自定义。

#### TOK-002：JadeRadius 圆角档位统一
- **关联**：§9.2.3 ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：待建 `DesignTokenTests.swift`
- **步骤**：断言 `JadeRadius` sm=6/md=8/lg=12/xl=16/2xl=20，且圆角风格为 `.continuous`。
- **预期结果**：五档圆角值与规范一致，使用连续曲率。

#### TOK-003：JadeSpace 间距 4px 基准
- **关联**：§9.2.4 ｜ **优先级**：P2 ｜ **类型**：swift ｜ **文件**：待建
- **步骤**：断言 space 档位 1/2/3/4/6/8 = 4/8/12/16/24/32。
- **预期结果**：间距档位与规范一致。

#### TOK-004：JadeFont 字号档位
- **关联**：§9.2.5 ｜ **优先级**：P2 ｜ **类型**：swift ｜ **文件**：待建
- **步骤**：断言 display=40/title1=28/title2=22/title3=17/body=13/callout=12/subhead=11/caption=10/commandBarInput=20（pt）。
- **预期结果**：字号档位与规范一致；正文可跟随系统字体大小缩放（ACC-005 覆盖动态类型）。

#### TOK-005：JadeShadow / JadeMaterial 定义存在且被引用
- **关联**：§9.2.6/9.2.7、FR-UI-COMMAND-BAR ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：待建
- **步骤**：1) 断言 shadow sm/md/lg/xl 与 material（command bar=ultraThinMaterial、sheet=thinMaterial、遮罩 opacity 0.4）定义存在；2) 手工走查命令栏/工具条使用 `.ultraThinMaterial`。
- **预期结果**：阴影/材质 token 存在并在命令栏、pill、Sheet、遮罩正确应用。

#### TOK-006：UI 无散落硬编码颜色/圆角/间距/字号（走查）
- **关联**：FR-UI-DESIGN-TOKENS、D-118、review M-2 ｜ **优先级**：P1 ｜ **类型**：手工/静态走查 ｜ **文件**：code review 清单
- **前置条件**：核心页（命令栏/剪贴板/设置）Token 迁移完成。
- **步骤**：审查核心页 View 源码，检查是否仍存在 `Color(hex:)` 字面量、`cornerRadius(数字字面量)`、魔法 padding 数字、`.font(.system(size:数字))` 未走 token。
- **预期结果**：核心页颜色/圆角/间距/字号统一走 Jade* token；残留硬编码在 code review 记录并列入 v1.x 收尾（M-2 允许非核心页分批）。

### 11.3 BRAND —— 品牌改名一致性

#### BRAND-001：Bundle ID 保持 com.assistant.app 不变
- **关联**：§2.0、D-102 ｜ **优先级**：P0 ｜ **类型**：swift/脚本 ｜ **文件**：待建 `QingniaoTests/BrandingConsistencyTests.swift`
- **前置条件**：改名任务 T-A 完成。
- **步骤**：读取运行时 `Bundle.main.bundleIdentifier`（或解析 Info.plist `CFBundleIdentifier`）。
- **预期结果**：等于 `com.assistant.app`（TCC/Keychain/数据目录绑定键不变，绝不能改）。

#### BRAND-002：CFBundleName / 显示名为 Qingniao
- **关联**：§2.0、FR-UI-30 ｜ **优先级**：P0 ｜ **类型**：swift/脚本 ｜ **文件**：`BrandingConsistencyTests.swift`
- **步骤**：断言 Info.plist `CFBundleName`（或 display name）为 `Qingniao`；产物为 `Qingniao.app`。
- **预期结果**：显示名/产物名改为青鸟 Qingniao。

#### BRAND-003：无残留旧品牌串（SnapVault / Mac Super Assistant / Assistant 显示名）
- **关联**：§2.0、D-101 ｜ **优先级**：P1 ｜ **类型**：脚本/静态 ｜ **文件**：grep 检查（可入 CI）
- **步骤**：grep 用户可见文案（Localizable.xcstrings、关于页、Onboarding、隐私政策、菜单项）是否含 `SnapVault`/`Mac Super Assistant`/单独作为品牌名的 `Assistant`。
- **预期结果**：用户可见文案无旧品牌串；内部类型名 `Assistant*`→`Qingniao*`（api §2.1，领域名 Clipboard*/Search* 保留）；GitHub 仓库路径 `freeabyss/assistant` 保留不算残留。

#### BRAND-004：反馈邮箱为 feedback@qingniao.app【上线前校验】
- **关联**：FR-UI-25、D-053 ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`BrandingConsistencyTests.swift` + 手工
- **步骤**：1) 断言反馈邮件 mailto 目标为 `feedback@qingniao.app`；2)【上线前校验】确认该邮箱真实可收件。
- **预期结果**：反馈入口指向 feedback@qingniao.app；**邮箱可用性上线前人工确认**。

#### BRAND-005：菜单栏图标为青鸟单色 template
- **关联**：FR-UI-30b、§9.2.9 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：深/浅色模式下观察菜单栏 statusItem 图标。
- **预期结果**：单色 template 青鸟 glyph，深浅色自适应，无 Dock 图标。

#### BRAND-006：关于页应用名与版本号一致（1.2.0）
- **关联**：FR-UI-8、FR-UI-ABOUT-VERSION、AC-VERSION、D-108 ｜ **优先级**：P0 ｜ **类型**：手工 + swift ｜ **文件**：手工 + `BrandingConsistencyTests.swift`
- **步骤**：1) 打开关于页；2) 断言名称=青鸟 Qingniao、版本号=1.2.0；3) 与 `Bundle.main` 的 `CFBundleShortVersionString` 比对一致。
- **预期结果**：关于页显示 1.2.0，与工程版本源一致。

#### BRAND-007：版本号三源一致（MARKETING_VERSION / Info.plist / CHANGELOG）
- **关联**：FR-UI-36、AC-VERSION、D-108 ｜ **优先级**：P0 ｜ **类型**：脚本 ｜ **文件**：待建脚本（可入 CI）
- **步骤**：解析 pbxproj `MARKETING_VERSION`、Info.plist `CFBundleShortVersionString`、`CHANGELOG.md` 顶部版本；三者比对。
- **预期结果**：三源均为 `1.2.0`；CHANGELOG 补全 v1.0.0/v1.0.1/v1.1.0/v1.2.0 条目；任一不一致视为发布阻塞。

### 11.4 DATA —— 数据目录迁移

#### DATA-001：Assistant/ → Qingniao/ move 迁移成功
- **关联**：db §8.4、FR-DATA-EXPORT-BACKUP-2、D-111 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：待建 `QingniaoTests/DataMigrationTests.swift`
- **前置条件**：临时 Application Support 目录下预置旧 `Assistant/`（含 store + `Clipboard/Images|Thumbnails|RichText`）。
- **步骤**：1) 触发迁移逻辑；2) 断言 `Qingniao/` 存在且含原数据；3) store 重命名正确、可打开。
- **预期结果**：旧目录内容 move 到 `Qingniao/`，历史剪贴板数据不丢失，store 可加载。

#### DATA-002：迁移失败 fallback 备份旧库 + 新建空库不阻塞启动
- **关联**：db §8.4、review 第二节 #4 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`DataMigrationTests.swift`
- **前置条件**：模拟 move/migration 失败（如目标已存在损坏文件或 IO 错误）。
- **步骤**：1) 触发迁移；2) 断言旧库被备份（保留副本）、新建空库、启动流程继续不崩溃。
- **预期结果**：迁移失败时降级为「备份旧库 + 新建空库」，App 仍能启动，不阻塞。

#### DATA-003：Core Data lightweight migration 跨版本保留数据
- **关联**：FR-DATA-EXPORT-BACKUP-2、db §3.3、FR-CLIP-45~59 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`DataMigrationTests.swift`
- **前置条件**：预置旧模型版本 store（含 ClipboardRecord 记录，含已删除的 ocrText 列场景）。
- **步骤**：1) 用新模型打开 store 触发 lightweight migration；2) 断言历史记录仍可读、ocrText 列移除不导致失败。
- **预期结果**：lightweight migration 成功，历史数据保留，删列不破坏迁移。

#### DATA-004：清空所有数据（设置数据页）
- **关联**：FR-UNINSTALL-2、db §11.5、FR-UI-SETTINGS-WINDOW ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`DataMigrationTests.swift` + 手工
- **前置条件**：存在剪贴板历史、使用统计、黑名单、大对象文件。
- **步骤**：1) 设置→数据→「清空所有数据」；2) 二次确认（不可撤销）；3) 断言 Core Data 记录、UsageStat、黑名单、`Clipboard/*` 大对象全部清除。
- **预期结果**：一键清空全部数据，二次确认拦截，清除后目录无残留大对象。

#### DATA-005：数据目录路径为 Qingniao/ 且 Time Machine 兼容
- **关联**：FR-DATA-EXPORT-BACKUP-1/3、§11.5、D-111 ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`DataMigrationTests.swift`
- **步骤**：1) 断言数据根目录解析为 `~/Library/Application Support/Qingniao/`；2) 断言未设置 Time Machine 排除标志（`isExcludedFromBackup=false`）。
- **预期结果**：数据存于 Qingniao/，随系统备份；隐私政策/FAQ 文案路径同步更新。

### 11.5 DI —— AppContainer 依赖注入

#### DI-001：AppContainer 组装根提供各服务依赖
- **关联**：design §2.5、api §17、M-1 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：待建 `QingniaoTests/AppContainerTests.swift`
- **前置条件**：AppContainer 已建立为 DI 根。
- **步骤**：1) 构造 AppContainer（可注入 mock）；2) 断言其暴露的服务（Permission/Settings/Search/Clipboard/Hotkey 等）非空且类型正确；3) 单例服务同实例复用。
- **预期结果**：AppContainer 正确组装依赖，可注入替身用于测试。

#### DI-002：AppDelegate 瘦身（职责剥离到控制器）
- **关联**：design §2.5/§16、M-1 ｜ **优先级**：P1 ｜ **类型**：静态/走查 ｜ **文件**：code review 清单
- **前置条件**：拆分后（原 955 行）。
- **步骤**：审查 AppDelegate 是否将窗口/状态栏/快捷键逻辑迁至 StatusItemController + 窗口控制器群 + GlobalShortcutManager；AppDelegate 仅保留生命周期装配。
- **预期结果**：AppDelegate 显著瘦身，窗口/状态栏/快捷键职责归位；行为回归全套测试通过（REG 系列）。

#### DI-003：窗口控制器生命周期正确
- **关联**：design §16、api §17 ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`AppContainerTests.swift` + 手工
- **步骤**：1) 打开/关闭命令栏、剪贴板窗口、设置窗口、截图叠层；2) 断言重复打开不产生多实例泄漏、关闭正确释放；3) 手工验证多次开关无残留窗口。
- **预期结果**：各窗口控制器单实例复用、生命周期正确、无泄漏。

### 11.6 SEARCH-F —— 文件搜索接入

#### SEARCH-F-001：FileSearchSource 启动时实例化并注册
- **关联**：FR-SEARCH-FILE-1、US-012、D-105 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`QingniaoTests/FileSearchSourceTests.swift`（现存文件转接线回归）
- **前置条件**：AppContainer 注册 FileSearchSource（修复此前 522 行从未实例化的问题）。
- **步骤**：1) 从 SearchService 获取已注册 source 列表；2) 断言包含 FileSearchSource 且启用。
- **预期结果**：文件搜索源被注册进搜索服务，`⌥ Space` 可返回文件结果。

#### SEARCH-F-002：默认索引三目录
- **关联**：FR-SEARCH-FILE-2/3、US-012 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`FileSearchSourceTests.swift`
- **前置条件**：注入临时目录替身覆盖 Desktop/Documents/Downloads。
- **步骤**：1) 断言默认索引范围为 `~/Desktop`、`~/Documents`、`~/Downloads`；2) 断言排除隐藏文件/目录、`~/Library`、系统缓存、`.app` 包内部。
- **预期结果**：只索引三目录，排除规则生效。

#### SEARCH-F-003：文件名/路径匹配（原名 + 拼音/首字母见备注）
- **关联**：FR-SEARCH-FILE-4、FR-SEARCH-13 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`FileSearchSourceTests.swift`
- **前置条件**：临时目录放置若干文件（含中文名文件）。
- **步骤**：1) 输入原文文件名片段，断言命中；2) 验证只做文件名/路径匹配，不做文件内容全文检索。
- **预期结果**：原文匹配命中。**备注（PRD 冲突，见 review）**：FR-SEARCH-13 明确「文件名暂不做拼音索引」，而任务指令提到「拼音/首字母匹配」——本 TC 以 PRD FR-SEARCH-13 为准：文件搜索**只做原文匹配**，拼音/首字母不作为 v1.2 断言项（如实现选择支持，另补 P2 用例，不作为 P0 门禁）。

#### SEARCH-F-004：输入 2 字符触发、异步不阻塞
- **关联**：FR-SEARCH-FILE-7、FR-SEARCH-17、§11.1 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`FileSearchSourceTests.swift`
- **步骤**：1) 输入 1 字符断言不触发文件搜索；2) 输入 ≥2 字符断言触发；3) 断言执行为异步（不阻塞其他来源结果返回）。
- **预期结果**：≥2 字符触发，异步执行。

#### SEARCH-F-005：文件结果展示与主/次动作
- **关联**：FR-SEARCH-FILE-5/6、§9.4 P-01 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`FileSearchSourceTests.swift` + 手工
- **步骤**：1) 断言 FileSearchResult 含文件名、路径、类型图标（P-01 另含大小/修改时间）；2) 主动作=打开文件（openFile）、次动作=在 Finder 中显示（revealInFinder）；3) 手工回车打开、次动作定位 Finder。
- **预期结果**：结果字段完整；主动作打开、次动作 Finder 定位（手工验收 AC-FILE）。

#### SEARCH-F-006：文件来源权重 75（高于剪贴板 70）
- **关联**：FR-SEARCH-11、D-121、design §7.4 ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：`QingniaoTests/SearchServiceCoreTests.swift`
- **步骤**：构造同等文本匹配分的文件结果与剪贴板结果，断言文件排前（基础优先级 75 > 70）。
- **预期结果**：文件权重 75 生效，排序高于剪贴板。**备注**：架构已按 75 落地并标注与 FR-SEARCH-11 原 60 的差异（review 冲突 #1），测试以 75 为准。

#### SEARCH-F-007：无结果态
- **关联**：FR-SEARCH-FILE、§9.7 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：输入不存在的文件名。
- **预期结果**：显示「未找到匹配项」空态（magnifyingglass 图标），不崩溃、不阻塞其他来源。

#### SEARCH-F-008：大目录索引性能 ≤300ms 首批
- **关联**：§11.1、M-3 ｜ **优先级**：P1 ｜ **类型**：swift（性能信号）+ 手工 ｜ **文件**：`FileSearchSourceTests.swift` + Instruments
- **前置条件**：临时目录含大量文件（如数千项）。
- **步骤**：测量输入到首批文件结果返回耗时。
- **预期结果**：常用目录下 ≤300ms 返回首批，UI 不阻塞；选型（Spotlight/MDQuery 优先 + FileManager 降级，M-3）在开发前定案。

#### SEARCH-F-009：文件结果受搜索源开关和黑名单约束
- **关联**：FR-SEARCH-FILE-9、FR-SEARCH-8c ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：`FileSearchSourceTests.swift`
- **步骤**：1) 关闭文件搜索源开关，断言不返回文件结果；2) 将某文件结果加黑名单，断言不展示，移除后恢复。
- **预期结果**：开关与黑名单对文件结果生效。

### 11.7 SEARCH-E —— 命令栏空态与增强

#### SEARCH-E-001：空输入显示最近使用（≤5）+ 收藏（≤5）
- **关联**：FR-SEARCH-14、§9.3、D-120 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/SearchPanelViewModelTests.swift`
- **前置条件**：存在最近使用记录与收藏项。
- **步骤**：1) 打开命令栏不输入；2) 断言展示最近使用最多 5 条 + 收藏最多 5 条；3) 断言不展示通用搜索推荐结果。
- **预期结果**：空态显示最近/收藏入口（演进语义，D-120），不是搜索推荐结果。

#### SEARCH-E-002：⌘1-6 切换搜索源
- **关联**：FR-SEARCH-25、§9.6、D-122 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`SearchPanelViewModelTests.swift`
- **步骤**：分别触发 ⌘1/2/3/4/5/6，断言搜索范围切换为 所有/应用/命令/剪贴板/文件/设置。
- **预期结果**：⌘1-6 正确切源；数字键用于切源、不直接执行结果（FR-SEARCH-26 保留扩展空间）。

#### SEARCH-E-003：⌘K 清空输入
- **关联**：§9.6 ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：`SearchPanelViewModelTests.swift`
- **步骤**：输入文本后触发 ⌘K，断言输入框清空、回到空态。
- **预期结果**：⌘K 清空输入。

#### SEARCH-E-004：计算器/换算命中时答案固定首行
- **关联**：§9.4 P-01、FR-PROVIDER-9 ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：`QingniaoTests/CalculatorSourceTests.swift` + `SearchServiceCoreTests.swift`
- **步骤**：输入 `1+2*3`，断言结果列表第一行为答案 `7`，回车复制到剪贴板。
- **预期结果**：答案固定首行，回车复制。

#### SEARCH-E-005：Tab 补全（唯一匹配时）
- **关联**：§9.6 ｜ **优先级**：P2 ｜ **类型**：swift + 手工 ｜ **文件**：`SearchPanelViewModelTests.swift`
- **步骤**：输入前缀命中唯一文件/应用名，按 Tab，断言补全为完整名。
- **预期结果**：匹配唯一时 Tab 补全；多匹配不误补。

### 11.8 SHOT-FS —— 全屏截图热键

#### SHOT-FS-001：默认全屏截图热键 ⌃⌥⌘3
- **关联**：FR-SHOT-FULLSCREEN、US-013、D-107、§9.6 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：待建 `QingniaoTests/GlobalShortcutTests.swift`
- **前置条件**：GlobalShortcutManager 提供 registerFullscreenCapture。
- **步骤**：断言全屏截图默认热键为 `⌃⌥⌘3`（与系统 `⇧⌘3` 错开）。
- **预期结果**：默认热键 ⌃⌥⌘3 注册。

#### SHOT-FS-002：全屏热键触发全屏截图流程（E2E）
- **关联**：FR-SHOT-2、FR-SHOT-FULLSCREEN、AC-FULLSCREEN ｜ **优先级**：P0 ｜ **类型**：手工 E2E ｜ **文件**：手工
- **前置条件**：已授予屏幕录制权限。
- **步骤**：按 `⌃⌥⌘3`。
- **预期结果**：直接进入全屏截图并进入预览工具栏（不需先开命令栏）。

#### SHOT-FS-003：全屏热键可重绑
- **关联**：FR-SHOT-FULLSCREEN、FR-UI-HOTKEYS ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`GlobalShortcutTests.swift` + 手工
- **步骤**：设置→快捷键→重绑全屏截图热键，断言新键持久化并生效。
- **预期结果**：重绑成功、重启后保持（与 SHORTCUT-004 联动）。

#### SHOT-FS-004：全屏热键冲突提示
- **关联**：FR-SHOT-FULLSCREEN、FR-ONBOARD-16、§7.12 ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`GlobalShortcutTests.swift`
- **步骤**：将全屏热键绑到已占用组合，断言冲突检测提示并要求重录。
- **预期结果**：冲突时行内提示 + 一键替换（见 SHORTCUT-001）。

### 11.9 SHOT-UI —— 截图标注 UI

#### SHOT-UI-001：顶/底悬浮 pill 工具条
- **关联**：§9.4 P-05、FR-UI-SCREENSHOT-ANNOTATE ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：进入截图预览标注。
- **预期结果**：顶部工具 pill（rect/arrow/text/mosaic/blur禁用）+ 底部 pill（撤销/重做、六色 swatch、三档线宽、取消/复制/保存），居中悬浮、ultraThinMaterial。

#### SHOT-UI-002：mosaic 保留可用
- **关联**：FR-SHOT-7、§9.4 P-05、D-117 ｜ **优先级**：P0 ｜ **类型**：手工 + swift ｜ **文件**：手工 + `QingniaoTests/AnnotationTests.swift`
- **步骤**：选 mosaic 工具在画布涂抹。
- **预期结果**：马赛克生效（`CIPixellate` scale 10），撤销/重做可用。

#### SHOT-UI-003：blur 灰禁用 + tooltip「v1.3 支持」
- **关联**：FR-ANNOTATE-BLUR、D-117、§9.4 P-05 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：hover blur 工具项。
- **预期结果**：blur 呈禁用态、不可选，tooltip 显示「v1.3 支持」；不声明「模糊」能力。

#### SHOT-UI-004：六色 swatch + 三档线宽
- **关联**：FR-SHOT-16~19、§9.4 P-05 ｜ **优先级**：P1 ｜ **类型**：手工 + swift ｜ **文件**：`AnnotationTests.swift`
- **步骤**：切换颜色（red/yellow/jade/green/white/black）与线宽（细2/中4/粗8）。
- **预期结果**：颜色/线宽预设生效并应用到后续标注。

#### SHOT-UI-005：标注编辑器快捷键（⌘Z/⇧⌘Z/⌘C/⌘S/⎋/1-4）
- **关联**：§9.6 标注编辑器表 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：逐一验证撤销/重做/复制/保存/取消/切工具数字键。
- **预期结果**：各快捷键行为符合总表；1-4 切换 矩形/箭头/文字/马赛克。

### 11.10 ONB-V2 —— Onboarding 单屏

#### ONB-V2-001：单屏布局（720×520）
- **关联**：FR-UI-ONBOARDING、§9.4 P-06、D-116 ｜ **优先级**：P0 ｜ **类型**：手工 ｜ **文件**：手工
- **前置条件**：清除 onboarding 完成标记后首启。
- **步骤**：观察 Onboarding 窗口。
- **预期结果**：单屏 720×520、24px 圆角、大图标 + 欢迎语 + slogan + 3 配置卡（热键/剪贴板/开机启动）+ 权限段 + 底部按钮，不再是多步向导。

#### ONB-V2-002：⌥ Space 默认热键录制
- **关联**：FR-ONBOARD-15、P-06 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/OnboardingViewModelTests.swift`
- **步骤**：断言默认展示 `⌥ Space` 热键；可在卡内重录。
- **预期结果**：默认 ⌥ Space，成功注册后方可完成（FR-ONBOARD-17）。

#### ONB-V2-003：屏幕录制主按钮触发 TCC
- **关联**：FR-ONBOARD-3/10、P-06、AC-1 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`OnboardingViewModelTests.swift`（request 计数）+ 手工
- **步骤**：1) 单测断言点击「授予屏幕录制权限」调用 requestScreenRecordingPrompt 一次；2) 手工 `tccutil reset ScreenCapture com.assistant.app` 后首启点击，5s 内弹系统授权。
- **预期结果**：主按钮触发 TCC 注册弹窗（复用 v1.1 request API）。

#### ONB-V2-004：屏幕录制未授权时「开始使用」禁用
- **关联**：FR-ONBOARD-11、P-06 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`OnboardingViewModelTests.swift`
- **步骤**：屏幕录制未授权时，断言「开始使用」按钮 disabled；授权后 enabled。
- **预期结果**：未授予屏幕录制不能完成（截图能力依赖）。

#### ONB-V2-005：辅助功能「稍后再说」不阻塞完成
- **关联**：FR-ONBOARD-ACCESSIBILITY-ONDEMAND、AC-ONBOARD-ACCESSIBILITY、D-104 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`OnboardingViewModelTests.swift`
- **步骤**：不授予辅助功能，点「稍后再说」，断言仍可完成 Onboarding（屏幕录制已授权前提下）。
- **预期结果**：辅助功能非强制；跳过它仍可完成。

#### ONB-V2-006：跳过设置入口 + 二次确认
- **关联**：FR-ONBOARD-18、P-06 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`OnboardingViewModelTests.swift`
- **步骤**：点左下「跳过设置」，断言弹确认 Alert，Cancel 不改变、Skip 进主界面并显式写 clipboardEnabled=false（承接 v1.1 TC-U-004）。
- **预期结果**：跳过带二次确认，行为与 v1.1 一致。

#### ONB-V2-007：隐私政策链接
- **关联**：FR-UI-20、P-06 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：点右下「隐私政策」link。
- **预期结果**：打开隐私政策，说明本地保存/不上传/清空方式，路径含 Qingniao/。

#### ONB-V2-008：完成/跳过后重启不重弹（AC-6）
- **关联**：FR-ONBOARD-19、AC-6、db §8.3（onboarding.completedAt 迁移）｜ **优先级**：P0 ｜ **类型**：swift + 手工 E2E ｜ **文件**：`OnboardingViewModelTests.swift`（持久化）+ 手工
- **步骤**：1) 单测断言完成/跳过写入 `onboarding.completedAt`（Date?，取代旧 Bool，旧 true→写非空时间戳）；2) 手工完成后重启 App，断言不再弹 Onboarding。
- **预期结果**：重启不重弹（v1.1 遗留 TC-M-007 在 v1.2 端到端闭环）。

### 11.11 PERM-OD —— 权限按需申请

#### PERM-OD-001：Onboarding 不主动弹辅助功能 TCC
- **关联**：FR-ONBOARD-ACCESSIBILITY-ONDEMAND、D-104 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`OnboardingViewModelTests.swift`
- **步骤**：走完 Onboarding，断言全程未调用辅助功能 request（仅屏幕录制会请求）。
- **预期结果**：Onboarding 不主动申请辅助功能。

#### PERM-OD-002：首次触发相关能力时才弹说明 Alert（AC-7）
- **关联**：FR-ONBOARD-20、AC-7、api §13 onDemandAccessibilityCheck ｜ **优先级**：P0 ｜ **类型**：swift + 手工 E2E ｜ **文件**：待建 `QingniaoTests/OnDemandPermissionTests.swift` + 手工
- **步骤**：1) 单测断言首次触发需辅助功能能力时调用 onDemandAccessibilityCheck 弹说明 Alert、可打开系统设置；2) 手工端到端验证 Alert 弹出。
- **预期结果**：按需申请正确弹出并可跳系统设置（v1.1 遗留 TC-M-008 闭环）。

#### PERM-OD-003：onDemandAccessibilityCheck 两 conformer 补齐
- **关联**：review 第二节 #1、api §13、承接 v1.1 TC-U-001 教训 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`QingniaoTests/PermissionServiceProtocolConformanceTests.swift`
- **步骤**：断言 `PermissionServiceProtocol.onDemandAccessibilityCheck()` 在真实 PermissionService、MockPermissionService、StaticPermissionService 三 conformer 均实现且可调用。
- **预期结果**：三 conformer 均实现（否则编译失败），Mock 可配返回/计数。

### 11.12 CODE —— 死代码清理

#### CODE-001：无 UnifiedSearch* 残留
- **关联**：FR-PROVIDER-15、§10.7、D-106、api §21 ｜ **优先级**：P1 ｜ **类型**：静态/脚本 ｜ **文件**：grep 检查（可入 CI）
- **步骤**：grep 源码树无 `UnifiedSearchService`/`UnifiedSearchViewModel`/`UnifiedResultRow`/`ResultGroupView`/`UnifiedResultList`/`UnifiedSearchTypes` 定义或引用。
- **预期结果**：legacy 双搜索体系已删除，仅保留 SearchService + SearchPanelViewModel。

#### CODE-002：无 MenuBarView 残留
- **关联**：§10.7、D-106 ｜ **优先级**：P1 ｜ **类型**：静态/脚本 ｜ **文件**：grep 检查
- **步骤**：grep 无 `MenuBarView` 定义/引用。
- **预期结果**：MenuBarView 删除（管理中心走独立窗口）。

#### CODE-003：无 UnitConverterSource 残留（能力并入 CalculatorSource）
- **关联**：FR-PROVIDER-15、§10.7、D-106 ｜ **优先级**：P1 ｜ **类型**：静态 + swift ｜ **文件**：grep + `CalculatorSourceTests.swift`
- **步骤**：1) grep 无 `UnitConverterSource`；2) 断言单位换算（长度/重量/数据/温度）仍由 CalculatorSource 提供且回归通过。
- **预期结果**：独立换算源删除，换算能力并入 CalculatorSource 不丢失；`UnitConverterSourceTests.swift` 一并删除。

#### CODE-004：无 OCRService/ContentStore 接线点
- **关联**：§10.7、D-106/D-110、db 删 ocrText ｜ **优先级**：P1 ｜ **类型**：静态/脚本 ｜ **文件**：grep 检查
- **步骤**：grep 无 `OCRService`/`ContentStore`/`ContentRepository` 及 GRDB `ClipboardRepository`（GRDB 版）实例化/接线；确认 ClipboardRecord 无 `ocrText`。
- **预期结果**：OCR/内容仓库死代码删除，ocrText 字段与相关 UI 筛选移除（MVP 不含 OCR）。

#### CODE-005：统一 JadeToast（三套 Toast 收敛为一）
- **关联**：D-119、§9.5、design §3.7 ｜ **优先级**：P1 ｜ **类型**：静态 + 手工 ｜ **文件**：grep + 手工
- **步骤**：1) grep 确认仅存在单套 `JadeToast`，旧三套 Toast 类型删除；2) 手工验证保存截图/复制等场景 Toast 表现一致（jade/red 两态、底部居中 3s）。
- **预期结果**：Toast 收敛为单套 JadeToast，行为统一。

### 11.13 DIST —— 分发签名

#### DIST-001：关闭 App Sandbox
- **关联**：FR-PERM-APPLE-EVENTS-1、§11.4、D-103 ｜ **优先级**：P0 ｜ **类型**：脚本/静态 ｜ **文件**：entitlements 检查（可入 CI）
- **步骤**：解析 `.entitlements`，断言 `com.apple.security.app-sandbox` 移除或为 false。
- **预期结果**：App Sandbox 关闭。

#### DIST-002：apple-events entitlement 存在
- **关联**：FR-PERM-APPLE-EVENTS-1/4、api §15 ｜ **优先级**：P0 ｜ **类型**：脚本/静态 ｜ **文件**：entitlements 检查
- **步骤**：断言含 `com.apple.security.automation.apple-events`（或对应 AppleEvents 授权 entitlement），保留 Hardened Runtime。
- **预期结果**：AppleEvents entitlement 存在，Hardened Runtime 启用。

#### DIST-003：AppleEvents 命令真实可执行（AC-CMD-SANDBOX）
- **关联**：US-010、FR-PERM-APPLE-EVENTS、§8 命令 12-14 ｜ **优先级**：P0 ｜ **类型**：手工（安全环境）｜ **文件**：手工
- **前置条件**：安全人工环境。
- **步骤**：执行重启 Finder / 重启 Dock（确认后）/ 切换深浅色。
- **预期结果**：命令真实生效、不静默失败；首次控制其他 App 触发 Automation 授权并有说明文案。

#### DIST-004：Developer ID 签名可验证（spctl）
- **关联**：FR-UI-16、§11.4、D-103、AC-SIGN ｜ **优先级**：P0 ｜ **类型**：脚本/手工 ｜ **文件**：手工/脚本
- **步骤**：对候选产物运行 `codesign --verify --deep --strict` 与 `spctl --assess --type execute`。
- **预期结果**：Developer ID 签名有效，spctl 评估通过。

#### DIST-005：Notarization 公证 + staple 票钉
- **关联**：FR-UI-17、§11.4、D-103、AC-SIGN ｜ **优先级**：P0 ｜ **类型**：脚本/手工 ｜ **文件**：手工/脚本
- **步骤**：`notarytool` 提交公证后 `stapler validate`，并在 Gatekeeper 首次打开验证。
- **预期结果**：公证通过、票据 staple 成功、Gatekeeper 校验通过。

#### DIST-006：检查更新跳 GitHub Releases（无 Sparkle）
- **关联**：FR-UI-15、§10.5 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/UpdateServiceTests.swift`（承接 TC-U-002）+ 手工
- **步骤**：点关于/更新页「检查更新」。
- **预期结果**：浏览器打开 `github.com/freeabyss/assistant/releases`，无 Sparkle UI/错误弹窗（见 UPD 系列）。

### 11.14 UPD —— 更新（移除 Sparkle）

#### UPD-001：无 Sparkle 配置残留（SUPublicEDKey/SUFeedURL）
- **关联**：§10.5、design §3.8、api §21 ｜ **优先级**：P0 ｜ **类型**：脚本/静态 ｜ **文件**：Info.plist + 源码 grep（可入 CI）
- **步骤**：grep Info.plist 无 `SUFeedURL`/`SUPublicEDKey`/`SUEnableAutomaticChecks`；源码/依赖无 Sparkle framework、无 appcast.xml。
- **预期结果**：Sparkle 彻底移除，无配置/资源残留。

#### UPD-002：启动无「无法启动更新程序」弹窗
- **关联**：承接 v1.0.1 TC-M-001/002、§10.5 ｜ **优先级**：P0 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：Debug/Release 启动后观察 3s。
- **预期结果**：无 Sparkle 相关系统对话框。

#### UPD-003：检查更新按钮打开 Releases 页
- **关联**：FR-UI-15、承接 TC-M-003 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`UpdateServiceTests.swift` + 手工
- **步骤**：单测断言 checkNow 触发打开下载页一次；手工点击验证跳转。
- **预期结果**：跳 GitHub Releases 页，不触发自动更新流程。

### 11.15 SHORTCUT —— 快捷键与冲突检测

#### SHORTCUT-001：冲突检测（注册失败提示 + 一键替换）
- **关联**：FR-UI-HOTKEYS、FR-ONBOARD-16、§9.4 P-03 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：待建 `QingniaoTests/HotkeyConflictDetectorTests.swift`
- **步骤**：将某全局热键绑到已占用组合，断言 HotkeyConflictDetector 报冲突、行内红色警告 + 一键替换按钮。
- **预期结果**：冲突可检测并提示重录/替换。

#### SHORTCUT-002：所有默认全局热键工作
- **关联**：§9.6 全局表、FR-SEARCH-2、FR-SHOT-FULLSCREEN ｜ **优先级**：P0 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：验证 ⌥Space（命令栏）、⇧⌃⌘4（区域）、⇧⌃⌘5（窗口）、⌃⌥⌘3（全屏）、⌥⌘C（剪贴板）、⌥⌘,（设置）。
- **预期结果**：各默认全局热键触发对应功能。**备注**：区域/窗口默认键 §9.6 表为 `⇧⌃⌘4/5`，而 §7.11/PRD 示例为 `⌃⌥⌘4/5`（review 冲突记录，不阻塞，以设置页展示为准）；本 TC 以 §9.6 总表值为断言基线。

#### SHORTCUT-003：热键可重绑
- **关联**：FR-SEARCH-3、§7.11 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：设置→快捷键页重绑各全局热键。
- **预期结果**：重绑生效。

#### SHORTCUT-004：重绑后持久化（重启保持）
- **关联**：FR-UI-HOTKEYS ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/SettingsServiceTests.swift` + 手工
- **步骤**：重绑热键后重启 App，断言仍为新键。
- **预期结果**：重绑值持久化。

### 11.16 SETNEW —— 设置新页

#### SETNEW-001：外观页（跟随系统/浅/深）
- **关联**：FR-UI-SETTINGS-WINDOW、§9.1、§9.4 P-03、D-115 ｜ **优先级**：P1 ｜ **类型**：swift + 手工 ｜ **文件**：`SettingsServiceTests.swift` + 手工
- **步骤**：外观页切换 跟随系统/浅色/深色，断言 appearance.mode 持久化并即时生效。
- **预期结果**：外观切换生效并持久化，明暗 token 一一对应。

#### SETNEW-002：数据页 - 打开数据目录
- **关联**：§9.4 P-03、FR-UNINSTALL-3 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：数据页点「打开数据目录」。
- **预期结果**：Finder 打开 `~/Library/Application Support/Qingniao/`。

#### SETNEW-003：数据页 - 清空所有数据
- **关联**：FR-UNINSTALL-2、db §11.5 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`DataMigrationTests.swift`（同 DATA-004）+ 手工
- **步骤**：数据页「清空所有数据」→ 二次确认。
- **预期结果**：见 DATA-004；确认后清空、不可撤销。

#### SETNEW-004：数据页 - 导出灰禁用（v1.3）
- **关联**：FR-DATA-EXPORT-BACKUP-4、§9.4 P-03 ｜ **优先级**：P2 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：观察数据页「导出数据」项。
- **预期结果**：导出禁用/标注后续版本；v1.2 不提供导出本体（避免误以为已支持）。

#### SETNEW-005：设置侧栏分组完整
- **关联**：§9.4 P-03、FR-UI-SETTINGS-WINDOW ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：打开设置窗口。
- **预期结果**：侧栏含 概览/剪贴板/快捷键/截图/搜索源/外观/权限/数据/更新/关于/反馈；概览页含版本 + stat cards（含截图数，M-4 需数据层落点）。

### 11.17 REG —— 回归（既有核心功能在 v1.2 UI 下）

#### REG-001：剪贴板 4 类型记录与恢复
- **关联**：FR-CLIP-2~5、CLIP-001~004 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/AssistantClipboardRepositoryTests.swift`（改名后 Clipboard*Tests）+ 手工
- **步骤**：复制文本/富文本/图片/文件，验证记录与回车恢复。
- **预期结果**：四类型在 P-02 新窗口下记录/恢复正常，去重/置顶/保留不变。

#### REG-002：应用启动
- **关联**：FR-APP-1~5、SEARCH-003 ｜ **优先级**：P0 ｜ **类型**：swift + 手工 ｜ **文件**：`QingniaoTests/AppSearchSourceTests.swift`
- **步骤**：搜索并启动三目录下的 .app。
- **预期结果**：应用索引与启动正常。

#### REG-003：命令白名单 15 条 + 确认门禁
- **关联**：FR-CMD-1~10、CMD-001~010、§8 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`QingniaoTests/SystemCommandSourceTests.swift`
- **步骤**：断言 15 条命令（含“打开剪贴板历史”）、确认门禁、危险命令拒绝、双语/拼音搜索、使用统计。
- **预期结果**：命令白名单回归通过。

#### REG-004：计算器/换算
- **关联**：FR-PROVIDER-6~10、SEARCH-007/008 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：`CalculatorSourceTests.swift`
- **步骤**：四则/括号/小数/长度/重量/数据/温度换算、非法输入拒绝。
- **预期结果**：计算/换算回归通过（换算能力已并入 CalculatorSource，见 CODE-003）。

#### REG-005：截图 region/window
- **关联**：FR-SHOT-1/3、SHOT-001/003 ｜ **优先级**：P0 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：区域/窗口截图 + 标注 + 复制/保存。
- **预期结果**：区域/窗口截图在 P-04/P-05 新 UI 下正常（全屏见 SHOT-FS）。

#### REG-006：权限设置页
- **关联**：FR-UI-11、§9.4 P-03 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：权限页查看状态/重新检测/打开系统设置。
- **预期结果**：权限页功能正常（屏幕录制状态 + 辅助功能按需说明）。

#### REG-007：swift test / xcodebuild test 全绿（基线更新）
- **关联**：US-021 基线、TC-R-001/002 ｜ **优先级**：P0 ｜ **类型**：swift + xcodebuild ｜ **文件**：全套
- **步骤**：`swift test --skip-update` 与 `xcodebuild test`。
- **预期结果**：全绿；基线在 v1.1（swift 134 / xcodebuild 125）基础上，删 UnitConverter/OCR 相关用例、增 v1.2 新用例后重新核定（开发完成时在 report.md 记录实际数）。

### 11.18 BUILD —— 构建脚本

#### BUILD-001：build_and_run.sh pgrep -x Qingniao
- **关联**：§10.7、D-106 ｜ **优先级**：P1 ｜ **类型**：脚本/静态 ｜ **文件**：`build_and_run.sh` 检查
- **步骤**：检查脚本 `pgrep -x` 目标为 `Qingniao`（原 `SnapVault`），`APP_PATH` 指向 `Qingniao.app`。
- **预期结果**：脚本进程名/产物名改为 Qingniao。

#### BUILD-002：scheme / target 名 Qingniao
- **关联**：§10.7、api §2.1、T-A ｜ **优先级**：P1 ｜ **类型**：脚本/手工 ｜ **文件**：pbxproj/scheme 检查
- **步骤**：断言 Xcode target/scheme、PRODUCT_NAME、module 名为 Qingniao；测试 target QingniaoTests。
- **预期结果**：工程命名改为 Qingniao（Bundle ID 仍 com.assistant.app，见 BRAND-001）。

### 11.19 ROBUST —— 健壮性整改

#### ROBUST-001：无 try! / as! / 强解 !（Apple 样板除外）
- **关联**：review M-6、design §22 ｜ **优先级**：P1 ｜ **类型**：静态/脚本 ｜ **文件**：源码 grep（可入 CI）
- **步骤**：grep 源码强制解包点：`try!`、`as!`、结尾 `!` 强解（`URL(string:)!`、`localEventMonitor!` 等），排除 IB/Storyboard 生成与 Apple 样板允许项。
- **预期结果**：CalculatorSource `try! NSRegularExpression`→预编译常量/`try?`；PreviewPanel `as!`→`as?`+guard；AppDelegate `localEventMonitor!`→可选绑定；ReleaseInfoService `URL(string:)!`→静态合法 URL。无新增强解。

#### ROBUST-002：整改后行为不回归
- **关联**：review M-6 ｜ **优先级**：P0 ｜ **类型**：swift ｜ **文件**：相关既有测试
- **步骤**：整改强制解包后运行相关单测（Calculator regex、ReleaseInfo URL、预览面板逻辑可测部分）。
- **预期结果**：改安全写法后功能行为不变，测试全绿。

### 11.20 ACC —— 无障碍

#### ACC-001：核心控件有 accessibilityLabel
- **关联**：FR-A11Y-1、FR-UI-A11Y、§9.8 ｜ **优先级**：P1 ｜ **类型**：手工（Accessibility Inspector）｜ **文件**：手工
- **步骤**：用 Accessibility Inspector 检查搜索框/结果项/按钮/开关/列表项。
- **预期结果**：均有可读 label；装饰性 SF Symbol `.accessibilityHidden(true)`。

#### ACC-002：VoiceOver 可读完核心流程
- **关联**：FR-A11Y-1/2、§9.8 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：开 VoiceOver 走搜索→选择→执行→关闭、剪贴板复制回、设置切换。
- **预期结果**：VoiceOver 朗读角色/状态/结果类型，流程可完成。

#### ACC-003：键盘遍历（Tab）
- **关联**：FR-A11Y-2、§9.8 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：仅用键盘 Tab 遍历各窗口交互元素。
- **预期结果**：核心操作可全键盘完成。

#### ACC-004：对比度 WCAG AA
- **关联**：§9.8、TOK-001 ｜ **优先级**：P2 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：明暗模式下检查文本/背景对比度。
- **预期结果**：满足 WCAG AA；尊重「增强对比度」「降低透明度」。

#### ACC-005：减弱动态效果 + 动态字体
- **关联**：§9.2.8、§9.8 ｜ **优先级**：P2 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：开启系统「减弱动态效果」与调大字体。
- **预期结果**：动画降级为无位移淡入淡出；body 字号跟随系统缩放（到 15pt）不截断。

### 11.21 I18N —— 中英双语

#### I18N-001：所有新字符串走 Localizable.xcstrings
- **关联**：FR-UI-I18N、§9.9 ｜ **优先级**：P1 ｜ **类型**：静态 + swift ｜ **文件**：xcstrings 检查 + 走查
- **步骤**：检查 v1.2 新增 UI 文案（命令栏 placeholder、设置新页、Onboarding 单屏、tooltip「v1.3 支持」等）均有中英条目，无硬编码。
- **预期结果**：新字符串本地化齐备，简中 + 英文。

#### I18N-002：长英文不截断
- **关联**：§9.9 ｜ **优先级**：P1 ｜ **类型**：手工 ｜ **文件**：手工
- **步骤**：切英文，观察设置/Onboarding/关于/权限页布局。
- **预期结果**：长英文（约中文 1.5–2×）不截断、不溢出。

#### I18N-003：日期/数字本地化
- **关联**：§9.9 ｜ **优先级**：P2 ｜ **类型**：swift + 手工 ｜ **文件**：走查
- **步骤**：检查剪贴板时间、存储占用、统计数字用 DateFormatter/NumberFormatter 走 locale。
- **预期结果**：日期/数字按 locale 格式化。

#### I18N-004：双语命令搜索回归
- **关联**：FR-CMD-9、L10N-004 ｜ **优先级**：P1 ｜ **类型**：swift ｜ **文件**：`SystemCommandSourceTests.swift`
- **步骤**：中文界面输入英文命令、英文界面输入中文命令。
- **预期结果**：均命中对应内置命令（回归保持）。

### 11.22 v1.2 追溯矩阵（P0 FR / AC → TC）

| FR / AC | 描述 | 覆盖 TC |
|---------|------|---------|
| FR-SEARCH-FILE-1~9 / US-012 / AC-FILE | 文件搜索接入 | SEARCH-F-001~009 |
| FR-SHOT-FULLSCREEN / US-013 / AC-FULLSCREEN | 全屏截图热键 | SHOT-FS-001~004 |
| FR-UI-ONBOARDING / P-06 / D-116 | Onboarding 单屏 | ONB-V2-001~008 |
| FR-ONBOARD-ACCESSIBILITY-ONDEMAND / AC-7 / D-104 | 辅助功能按需 | ONB-V2-005, PERM-OD-001~003 |
| FR-ONBOARD-19 / AC-6 | 重启不重弹 | ONB-V2-008 |
| FR-UI-DESIGN-TOKENS / D-118 | Design Token | TOK-001~006 |
| FR-UI-COMMAND-BAR / D-120/D-122 | 命令栏空态/切源 | SEARCH-E-001~005 |
| FR-UI-ABOUT-VERSION / FR-UI-36 / AC-VERSION / D-108 | 版本号一致 | BRAND-006, BRAND-007 |
| §2.0 / D-101/D-102 | 品牌改名 / Bundle ID | BRAND-001~007 |
| FR-DATA-EXPORT-BACKUP / db §8.4 / D-111 | 数据迁移 | DATA-001~005 |
| FR-PERM-APPLE-EVENTS / D-103 / AC-CMD-SANDBOX / AC-SIGN | 关 Sandbox + 签名公证 | DIST-001~006 |
| §10.5（移除 Sparkle） | 更新策略 | UPD-001~003 |
| §10.7 / D-106（死代码） | 死代码清理 | CODE-001~005 |
| design §2.5/§16 / M-1 | AppContainer DI | DI-001~003 |
| FR-UI-HOTKEYS / FR-ONBOARD-16 | 快捷键冲突检测 | SHORTCUT-001~004 |
| FR-UI-SETTINGS-WINDOW / P-03 | 设置新页 | SETNEW-001~005 |
| review M-6（强制解包） | 健壮性整改 | ROBUST-001~002 |
| FR-UI-A11Y / §9.8 / §7.14 | 无障碍 | ACC-001~005 |
| FR-UI-I18N / §9.9 | 国际化 | I18N-001~004 |
| §12.1 全 MVP 回归 | 回归 | REG-001~007 |
| review M-2（Token 迁移残留） | 硬编码看护 | TOK-006 |
| review M-3（文件搜索选型/性能） | 性能看护 | SEARCH-F-008 |
| review M-4（截图数统计落点） | 概览统计 | SETNEW-005 |
| review M-5（关 Sandbox 安全） | entitlements 最小化 | DIST-001, DIST-002 |

### 11.23 v1.2 P0 用例统计

| 指标 | 数值 |
|------|------|
| v1.2 新增 TC 总数 | 98 |
| 其中 P0 | 49 |
| 其中 P1 | 42 |
| 其中 P2 | 7 |
| P0 中含 swift 自动化成分（纯 swift 或 swift+手工/脚本混合） | 37 |
| P0 中脚本/静态可自动化（entitlements/版本三源/grep 等，多可入 CI） | 6 |
| P0 中纯手工 / E2E（系统权限/签名公证/真机截图等） | 6 |

> 注：多数 TC 为「swift + 手工」混合（swift 覆盖逻辑层，手工覆盖系统交互），上表按是否含 swift 自动化成分归类，故三类之和大于「纯手工」列。确切通过数在开发完成后于 report.md v1.2.0 节记录。各模块 TC 数：TOK6 / BRAND7 / DATA5 / DI3 / SEARCH-F9 / SEARCH-E5 / SHOT-FS4 / SHOT-UI5 / ONB-V2 8 / PERM-OD3 / CODE5 / DIST6 / UPD3 / SHORTCUT4 / SETNEW5 / REG7 / BUILD2 / ROBUST2 / ACC5 / I18N4 = 98。

---

## 12. 截图会话生命周期回归（下一阶段起）

> **背景**：截图统一会话上线后多次出现同一缺陷：进入截图状态后屏幕压暗，但点击、拖拽、Esc 全部无效，会话永不退出且反复触发会叠层。根因有二——`CaptureSessionController` 作为调用方局部变量且全部回调为 `weak`，函数返回即被 ARC 释放，叠层窗口被 `NSApp.windows` 持有而事件闭包的 self 已为 nil（"僵尸暗幕"）；叠加 borderless 窗口默认 `canBecomeKey == false`，Esc/⌘A 键盘事件不可达。修复见提交 `7e02195`。本节用例防止该类缺陷复发；自动化部分已纳入 `scripts/verify.sh` 必跑门禁。

### 12.1 自动化用例（提交前必跑：`./scripts/verify.sh`）

#### SHOT-LIFE-001：会话激活期自持有，结束即释放
- **关联**：Task 005/006 会话生命周期 ｜ **优先级**：P0 ｜ **类型**：XCTest ｜ **文件**：`QingniaoTests/CaptureSessionControllerTests.swift`（`testSessionStaysAliveWhileActiveAndReleasesOnFinish` / `testSessionStaysAliveWhileActiveAndReleasesOnCancel`）
- **步骤**：创建会话 → `start()` → 释放全部外部引用 → 断言会话仍存活 → `finish()`（及对称的 `cancel()`）→ 断言会话释放。
- **预期结果**：激活期间会话自持有存活，调用方是否持有不影响生命周期；finish/cancel 严格配对解除自持有。

#### SHOT-LIFE-002：调用方释放引用后叠层事件仍驱动会话（僵尸复现）
- **关联**：生产 bug 复现场景 ｜ **优先级**：P0 ｜ **类型**：XCTest ｜ **文件**：同上（`testOverlayEventsStillDriveSessionAfterCallerDropsReference`）
- **步骤**：`start()` 后丢弃调用方全部强引用，从叠层窗口的 `onEvent` 上抛 mouseDown/mouseDragged/mouseUp。
- **预期结果**：会话仍收到事件并锁定区域目标（`onLocked` 触发）；事件链不得因会话提前释放而中断。

#### SHOT-LIFE-003：borderless 叠层窗口可成为 key/main 窗口
- **关联**：键盘事件可达性 ｜ **优先级**：P0 ｜ **类型**：XCTest ｜ **文件**：同上（`testOverlayWindowCanBecomeKeyAndMain`）
- **预期结果**：`CaptureOverlayNSWindow.canBecomeKey` / `canBecomeMain` 均为 true，保证 Esc/⌘A 可达叠层视图。

### 12.2 手工验收用例（真实屏幕录制环境）

#### SHOT-LIFE-004：真实交互冒烟
- **优先级**：P0 ｜ **类型**：手工
- **时机**：发版前，以及任何截图链路（叠层、会话、完成协调器）改动之后。
- **步骤**：F1 或菜单「截图」进入截图状态，依次验证：屏幕压暗；悬停窗口出现高亮框；单击截取窗口；拖拽圈选自动截取区域；`⌘A` 截当前屏；悬停菜单栏/桌面空白出现整屏提示框且单击截全屏；`Esc` 随时退出；连续多次触发后取消不残留暗幕。
- **预期结果**：以上全部可用；任何一步无响应即为本节回归缺陷复发。

### 12.3 必跑门禁

- 每次代码修改完毕、提交之前运行 `./scripts/verify.sh`（全量单元测试 + `git diff --check`），失败必须修复后提交；该要求已写入根目录 `AGENTS.md`「测试门禁」。

---
