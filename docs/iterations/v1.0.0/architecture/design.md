# Mac Super Assistant（Assistant）架构设计

## 修订记录

| 日期 | 修改人 | 备注 |
| :--- | :--- | :--- |
| 2026-06-05 | Claude | 初始版本：SnapVault 剪贴板工具架构 |
| 2026-06-05 | Claude | v2：增加应用搜索、文件搜索，重构为 Spotlight 类启动器 |
| 2026-06-07 | Claude | v3-v12：陆续补充系统命令、计算器、单位换算、拼音、最近内容、截图工具栏、标注编辑器等设计 |
| 2026-06-09 | Claude | v13-v14：补充 XCTest / SwiftPM 测试入口相关架构记录 |
| 2026-06-11 | Claude | v15：按当前 PRD 重写为 Mac Super Assistant / Assistant MVP 架构，核心方案改为 SwiftUI + AppKit、Core Data + 文件系统、SearchSource Provider、轻量内存索引 |

> 说明：本文件以 `doc/prd.md` 当前 Mac Super Assistant MVP 决策为准。旧 SnapVault / GRDB / FTS5 / OCR / 文件搜索等内容已作为历史修订背景保留在修订记录中，不再作为 MVP 实现依据。

---

## 1. 系统概述

Mac Super Assistant（产品暂定名，工程内部代号：Assistant）是一款 macOS 原生效率工具，定位为 **增强版 Spotlight + 常用效率工具集成中心**。

MVP 以统一搜索入口为主，集成以下能力：

- 应用启动。
- 剪贴板历史。
- 区域 / 全屏 / 窗口截图。
- 轻量截图标注。
- 内置白名单命令。
- 基础计算器与常用单位换算。
- 设置、权限、关于、隐私、反馈等发布级基础能力。

产品形态为菜单栏 App，无 Dock 图标，通过 `⌥ Space` 呼出统一搜索框。复杂或低频操作由管理中心承载。

---

## 2. 架构目标

### 2.1 功能目标

- 所有核心能力都能通过统一搜索框触发。
- 管理中心承载剪贴板历史、设置、权限和概览。
- 剪贴板历史默认开启，支持文本、富文本、图片、文件引用。
- 截图完成后进入预览工具栏，支持复制、保存、标注、取消。
- 内置命令严格白名单，不支持任意 shell。

### 2.2 非功能目标

- 冷启动目标 ≤ 1 秒。
- 搜索响应目标 ≤ 100ms。
- 后台空闲 CPU ≤ 1%。
- 后台常驻内存目标 ≤ 150MB，理想 ≤ 100MB。
- 数据默认仅本地保存，不上传、不同步、不训练。
- MVP 最低支持 macOS 13 Ventura。

### 2.3 设计约束

- 技术栈限定为 SwiftUI + AppKit + 原生 macOS API。
- 数据存储采用 Core Data + 文件系统，不采用 SQLite/GRDB 作为主存储。
- 剪贴板搜索采用 Core Data 持久化 + 轻量内存搜索索引，不使用 SQLite FTS5。
- MVP 不实现 OCR、文件搜索、插件系统、账号系统、云同步、自动安装更新、签名公证。

### 2.4 MVP Scope Guard

以下能力明确不进入当前 MVP 实现、测试验收或默认任务范围：

- GRDB / FTS5 作为业务数据层。
- OCR。
- 文件搜索 / 文件索引。
- 货币换算。
- 通用收藏 / 标签分类。
- 最近内容中心。
- 任意 shell、sudo、关机、重启系统、注销、删除文件、杀进程。
- 账号系统、支付、授权码、订阅。
- 自动下载/安装更新。
- Mac App Store 分发。

---

## 3. 总体架构

系统采用 **SwiftUI/AppKit Shell + MVVM + Service + Provider + Local Data** 分层架构。

```text
┌─────────────────────────────────────────────────────────────┐
│                       App Shell                              │
│  AssistantApp / AppDelegate / MenuBarController / Hotkey     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    Presentation Layer                        │
│ SearchPanel / ClipboardHistory / ScreenshotOverlay           │
│ ManagementCenter / Onboarding / Settings / About             │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ViewModel Layer                           │
│ SearchViewModel / ClipboardViewModel / SettingsViewModel     │
│ OnboardingViewModel / ScreenshotViewModel                    │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                     Service Layer                            │
│ SearchService / ClipboardService / ScreenshotService         │
│ PermissionService / SettingsService / FeedbackService        │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Provider Layer                             │
│ AppSource / ClipboardSource / CommandSource                  │
│ CalculatorSource / SettingsSource                            │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                      Data Layer                              │
│ Core Data / FileResourceStore / InMemorySearchIndex          │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    macOS Platform APIs                       │
│ NSWorkspace / NSPasteboard / ScreenCaptureKit or CG APIs     │
│ Accessibility / Screen Recording / ServiceManagement         │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. 模块划分

| 模块 | 职责 | 关键对象 |
| :--- | :--- | :--- |
| App Shell | 应用生命周期、菜单栏、无 Dock 图标、全局快捷键、开机启动 | `AssistantApp`, `AppDelegate`, `MenuBarController`, `HotkeyManager` |
| Onboarding | 首次启动流程、快捷键注册、权限强制引导、剪贴板默认开启确认 | `OnboardingView`, `OnboardingViewModel`, `PermissionService` |
| Search | 统一搜索框、Provider 聚合、排序、黑名单、最近使用加权 | `SearchPanel`, `SearchService`, `SearchSource`, `SearchResult` |
| App Source | 扫描常规 App 目录并启动 `.app` | `AppSource`, `ApplicationIndex` |
| Clipboard | 剪贴板监听、历史保存、去重、置顶、搜索、恢复到剪贴板 | `ClipboardMonitor`, `ClipboardService`, `ClipboardRepository` |
| Screenshot | 区域/全屏/窗口截图、预览工具栏、标注、复制、保存 | `ScreenshotService`, `ScreenshotOverlay`, `AnnotationCanvas` |
| Command | 内置白名单命令、中英文别名、确认弹窗 | `CommandSource`, `SystemCommandExecutor` |
| Calculator | 四则运算、单位换算、复制结果 | `CalculatorSource`, `UnitConverter` |
| Settings | 搜索源展示开关、剪贴板功能开关、黑名单、语言、保存路径 | `SettingsView`, `SettingsService` |
| Management Center | 首页/概览、剪贴板历史、设置、权限 | `ManagementCenterView` |
| Privacy / Feedback / Update | 隐私政策、邮件反馈、检查更新打开网页 | `AboutView`, `FeedbackService`, `UpdateCheckService` |
| Data | Core Data、文件资源、大对象路径、内存索引 | `PersistenceController`, `FileResourceStore`, `InMemorySearchIndex` |

---

## 5. App Shell 架构

### 5.1 运行形态

- App 为菜单栏常驻应用。
- 默认不显示 Dock 图标。
- 菜单栏使用单色 template 图标，适配深浅色模式。
- 菜单栏菜单只包含：打开搜索、剪贴板、截图、设置、关于、退出。
- 菜单栏“截图”为直接动作，执行区域截图。

### 5.2 快捷键

- 默认全局快捷键为 `⌥ Space`。
- Onboarding 中尝试注册默认快捷键。
- 如果注册失败或冲突，要求用户重新录制快捷键。
- 用户必须设置一个可成功注册的快捷键后才能完成 Onboarding。
- 设置页允许修改快捷键。

建议实现：

- 使用原生 Carbon Event Hot Key 或成熟快捷键封装。
- `HotkeyManager` 负责注册、注销、冲突检测结果表达和持久化同步。

### 5.3 开机启动

- 完成 Onboarding 后默认启用开机启动。
- 设置页允许关闭。
- 建议使用 `SMAppService`（macOS 13+）实现登录项。

---

## 6. Onboarding 与权限架构

### 6.1 流程顺序

Onboarding 按功能逐项引导：

1. 欢迎。
2. 搜索入口与快捷键。
3. 剪贴板历史与本地隐私说明。
4. 截图与屏幕录制权限。
5. 系统控制 / 辅助功能权限。
6. 开机启动。
7. 完成。

### 6.2 强制权限

MVP 强制完成：

- 屏幕录制权限：用于截图。
- 辅助功能权限：为后续自动粘贴、窗口控制、模拟快捷键、控制其他 App 等能力预留。

用户拒绝必要权限时：

- 停留在权限引导页。
- 不进入完整产品体验。
- 提供打开系统设置、重新检测、退出应用。

### 6.3 剪贴板确认

剪贴板历史默认开启，但 Onboarding 必须让用户显式确认已知晓：

- 默认开启。
- 数据仅本地保存。
- 可随时暂停记录或清空历史。
- 不提供复杂配置开关，以保持开箱即用。

---

## 7. 搜索架构

### 7.1 SearchSource 协议

Provider 是内置搜索源，不等同于第三方插件。MVP 不支持插件市场、热加载或外部扩展。

```swift
protocol SearchSource {
    var id: String { get }
    var displayName: LocalizedStringKey { get }
    var isEnabledInSearch: Bool { get }
    func canSearch(query: String) -> Bool
    func search(query: String) async -> [SearchResult]
}

struct SearchResult: Identifiable {
    let id: SearchResultID
    let sourceID: String
    let title: String
    let subtitle: String
    let icon: SearchResultIcon
    let typeLabel: String
    let baseScore: Double
    let matchScore: Double
    let usageScore: Double
    let primaryAction: SearchAction
    let secondaryActions: [SearchAction]
}

enum SearchAction {
    case openApplication(URL)
    case copyToClipboard(ClipboardPayload)
    case runCommand(CommandID)
    case openSettings(SettingsRoute)
    case startScreenshot(ScreenshotMode)
}
```

MVP UI 只执行 `primaryAction`，但模型保留 `secondaryActions`，为后续 Action Panel / 右键菜单预留。

### 7.2 MVP Provider

| Provider | 触发规则 | 主要动作 |
| :--- | :--- | :--- |
| AppSource | 输入 1 个字符开始 | 启动 App |
| CommandSource | 输入 1 个字符开始 | 执行内置命令 |
| SettingsSource | 输入 1 个字符开始 | 打开设置/权限/关于等页面 |
| ClipboardSource | 输入不少于 2 个字符开始 | 复制历史项到系统剪贴板 |
| CalculatorSource | 检测到表达式或单位模式 | 复制计算/换算结果 |

### 7.3 空输入状态

- 搜索框空输入时不显示任何推荐结果、最近内容或剪贴板内容。
- 仅保留输入提示。
- 行为参考 Alfred 的空状态体验。

### 7.4 搜索排序

统一搜索结果采用综合评分：

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
| 剪贴板 | 70 |

MVP 实现最近使用加权：

- 应用启动次数。
- 应用最后启动时间。
- 命令执行次数。
- 命令最后执行时间。

行为数据仅本地保存。

### 7.5 结果展示

- 所有来源结果合并排序后按总上限截断。
- 总上限为 12 条。
- 不按来源单独限制数量。
- 不显示分组标题。
- 每条结果通过图标和类型标签标识来源。
- MVP 不实现 `⌘1` 到 `⌘9` 快捷数字键，但模型和 UI 布局预留。

### 7.6 关闭策略

搜索框采用失焦自动关闭：

- 点击外部关闭。
- 切换到其他 App 关闭。
- 按 ESC 关闭。
- 再次按全局快捷键关闭。
- 执行结果主动作后关闭。

### 7.7 搜索黑名单

- MVP 支持屏蔽具体搜索结果。
- 可隐藏某个 App、某条内置命令、某个设置入口。
- 不支持按关键词、路径、来源规则批量隐藏。
- MVP 不实现搜索结果右键菜单或完整次级动作入口。
- 黑名单只能通过设置页查看、添加、移除。
- 移除后结果重新展示。

---

## 8. AppSource 架构

### 8.1 MVP 搜索范围

MVP 只索引以下目录中的 `.app` bundle：

- `/Applications`
- `~/Applications`
- `/System/Applications`

长期目标支持更广泛应用索引，包括所有 `.app`、系统设置项、命令行工具、浏览器 PWA、Xcode 模拟器 App 等。

### 8.2 索引字段

`ApplicationIndexItem` 建议包含：

- app id / bundle identifier。
- display name。
- localized name。
- path。
- icon resource。
- pinyin。
- pinyin initials。
- lastLaunchAt。
- launchCount。
- hidden / blacklist 状态。

### 8.3 匹配策略

优先级建议：

1. 精确匹配。
2. 前缀匹配。
3. 拼音前缀匹配。
4. 拼音首字母匹配。
5. 包含匹配。
6. 模糊匹配。

---

## 9. Clipboard 架构

### 9.1 监听策略

剪贴板监听基于 `NSPasteboard.general.changeCount` 轮询。

自适应轮询策略：

- 默认/活跃状态：500ms。
- 长时间无变化后：2s。
- 检测到变化后：恢复 500ms。
- 后台常驻监听，不能只在 App 激活时监听。

### 9.2 支持类型

MVP 支持：

- 文本。
- 富文本：纯文本 + RTF/HTML 原始格式。
- 图片：原图 + 缩略图。
- 文件引用：文件名、路径、类型、复制时间等元信息，不复制文件内容。

### 9.3 默认行为

- 剪贴板历史默认开启。
- 只按时间淘汰。
- 默认保留 30 天。
- 设置预设：7 天、30 天、90 天、永久。
- 不做敏感内容过滤，因为数据仅本地保存。
- 不自动粘贴到前台应用。
- 历史项点击或回车后，只复制到系统剪贴板。

### 9.4 去重与置顶

- 基于 contentHash 去重。
- 重复复制相同文本、图片或文件引用时，不新增记录，只更新时间。
- 记录按更新后的复制时间重新排序。
- 已置顶内容重复复制时更新时间但保持置顶。
- 置顶项显示在列表顶部。
- 置顶项不受自动过期清理影响。
- 不做收藏分类和标签系统。

### 9.5 剪贴板历史页面

- 提供独立搜索框，只搜索剪贴板历史。
- 输入时即时搜索，使用 debounce 避免频繁查询。
- 类型筛选：全部、文本、图片、文件。
- 默认无搜索时：置顶项在最上，其余按复制时间倒序。
- 搜索时：置顶匹配项优先，其余按匹配度和时间综合排序。
- MVP 暂不实现右键菜单。
- 用户通过键盘选择历史项并按回车，将内容放回系统剪贴板。

### 9.6 存储占用

- MVP 显示剪贴板历史存储占用。
- 不按容量自动清理。
- 显示占用的位置提供清空历史入口。
- 清空全部历史必须二次确认，并提示不可撤销。
- 删除单条历史 MVP 可不做二次确认。

---

## 10. 数据存储架构

### 10.1 技术选型

MVP 使用：

- Core Data。
- 文件系统。
- 轻量内存搜索索引。

不使用：

- SQLite/GRDB 作为主存储。
- SQLite FTS5。
- 纯 JSON 文件存储。
- Spotlight/系统索引作为剪贴板搜索主路径。

### 10.2 Core Data 职责

Core Data 存储结构化数据：

- 剪贴板历史元数据。
- 文本内容。
- 富文本索引信息。
- 资源路径或资源标识。
- contentHash。
- 置顶状态。
- 创建/更新时间。
- 设置项。
- 搜索源展示开关。
- 剪贴板功能开关。
- 搜索黑名单。
- 应用/命令使用统计。
- 语言、保留时间、截图保存目录等配置。

### 10.3 建议实体

| Entity | 说明 |
| :--- | :--- |
| `ClipboardRecord` | 剪贴板历史主表 |
| `ClipboardResource` | 图片、缩略图、RTF/HTML 等文件资源引用 |
| `SearchBlacklistItem` | 搜索黑名单具体结果 |
| `UsageStat` | 应用/命令使用次数和最后使用时间 |
| `AppSetting` | 设置键值 |

`ClipboardRecord` 建议字段：

- `id: UUID`
- `type: String`（text / richText / image / file）
- `plainText: String?`
- `summary: String?`
- `contentHash: String`
- `createdAt: Date`
- `updatedAt: Date`
- `isPinned: Bool`
- `filePath: String?`
- `resourceIDs: [UUID]` 或 Core Data relationship

### 10.4 文件系统职责

大对象不直接塞入 Core Data，放入 Application Support 下的文件系统目录。

MVP 目录结构：

```text
~/Library/Application Support/Assistant/
  Clipboard/
    Images/
    Thumbnails/
    RichText/
  Logs/
```

说明：MVP 截图保存到用户可见的 `~/Pictures/Screenshots`，不在 Application Support 中建立截图历史目录；如后续需要截图临时缓存或截图历史，应另行设计。

剪贴板大对象目录至少包含：

- `Clipboard/Images/`
- `Clipboard/Thumbnails/`
- `Clipboard/RichText/`

文件名使用 UUID，Core Data 保存相对路径或资源标识。

去重依赖 Core Data 中的 contentHash，不依赖文件名。

### 10.5 缺失资源容错

MVP 只做容错，不做主动修复：

- Core Data 记录存在但资源文件缺失时，历史项显示“资源已丢失”或等价提示。
- 复制/恢复时提示失败原因。
- 不在启动时主动清理孤儿文件。
- 不执行数据库/文件一致性修复。

---

## 11. 内存搜索索引架构

### 11.1 目标

统一搜索和剪贴板历史页面必须快速响应。Core Data 负责持久化，内存索引负责快速查询和排序。

### 11.2 加载策略

- App 启动时从 Core Data 全量加载必要轻量索引字段。
- 不加载图片原图、RTF/HTML 原始数据等大对象。
- 剪贴板新增、更新、删除、置顶变化时同步更新索引。
- 搜索命中后再按需加载 Core Data 详情和文件系统大对象。

### 11.3 索引字段

内存索引至少包含：

- id。
- source type。
- title / text summary。
- plain text。
- content type。
- pinyin / aliases。
- updatedAt。
- isPinned。
- hash。
- resource reference。
- usage stats。

### 11.4 一致性原则

- Core Data 是事实来源。
- 内存索引可重建。
- 数据变更时先持久化，再更新索引。
- 索引更新失败时，应允许通过重建索引恢复。

---

## 12. Screenshot 架构

### 12.1 截图模式

MVP 支持：

- 区域截图。
- 全屏截图。
- 窗口截图。

截图依赖屏幕录制权限。

### 12.2 截图流程

```text
用户触发截图
  ├─ 区域 / 全屏 / 窗口捕获
  ├─ 生成截图预览
  ├─ 显示浮动工具栏
  │   ├─ 复制
  │   ├─ 保存
  │   ├─ 标注工具
  │   └─ 取消
  └─ 用户选择具体动作
```

工具栏不提供抽象“完成”按钮。

### 12.3 标注能力

MVP 标注工具：

- 矩形框。
- 箭头。
- 文字。
- 马赛克/模糊。
- 撤销/重做。

样式预设：

- 颜色：红、黄、蓝、绿、白、黑。
- 线宽：细、中、粗。
- 文字大小：小、中、大。

不提供完整颜色选择器、字体选择器和透明度设置。

### 12.4 复制与保存

复制：

- 将当前截图及标注结果写入系统剪贴板。
- 进入剪贴板历史，遵循普通图片剪贴板记录逻辑。

保存：

- 保存为 PNG。
- 默认目录：`~/Pictures/Screenshots`。
- 首次保存时自动创建目录。
- 文件名：`Screenshot yyyy-MM-dd HH.mm.ss.png`。
- 保存后显示轻提示，可包含保存目录信息。
- 保存不额外写入剪贴板历史。
- MVP 不实现截图历史页。

### 12.5 ESC 行为

截图流程中 ESC 始终取消当前截图流程：

- 区域选择中取消截图。
- 窗口选择中取消截图。
- 预览阶段丢弃截图并关闭。
- 标注中退出当前标注/截图流程。

---

## 13. CommandSource 架构

### 13.1 安全边界

MVP 只支持内置白名单命令：

1. 打开系统设置。
2. 打开本应用设置。
3. 打开下载目录。
4. 打开应用程序目录。
5. 打开桌面目录。
6. 区域截图。
7. 全屏截图。
8. 窗口截图。
9. 清空剪贴板历史。
10. 暂停 / 恢复剪贴板记录。
11. 检查权限状态。
12. 重启 Finder。
13. 重启 Dock。
14. 切换深色 / 浅色模式。

明确不支持：

- 关机。
- 重启系统。
- 注销。
- 删除文件。
- 杀进程。
- sudo。
- 任意 shell。
- 搜索框直接执行用户输入命令。

### 13.2 确认策略

需要确认：

- 清空剪贴板历史。
- 重启 Finder。
- 重启 Dock。

不需要确认：

- 切换深色 / 浅色模式。

### 13.3 别名和拼音

每个内置命令维护：

- 中文名称。
- 英文名称。
- 中文别名。
- 英文别名。
- 拼音。
- 拼音首字母。

无论当前界面语言，中文或英文关键词都能搜到对应命令。

---

## 14. CalculatorSource 架构

MVP 支持：

- 基础四则运算。
- 括号。
- 小数。
- 常用单位换算：长度、重量、数据大小、温度。

不支持：

- 货币换算。
- 复杂函数。
- 变量。
- 计算历史。

执行动作：

- 回车复制计算/换算结果到系统剪贴板。
- 是否进入剪贴板历史，遵循统一剪贴板监听与去重逻辑。

---

## 15. SettingsSource 与管理中心架构

### 15.1 SettingsSource

MVP 返回页面级和具体设置区块入口：

- 打开设置。
- 打开权限。
- 打开剪贴板历史。
- 打开搜索源设置。
- 打开快捷键设置。
- 打开截图设置。
- 打开关于。

MVP 不支持在搜索结果中直接切换设置开关。长期目标是全量设置项索引和安全直接操作。

### 15.2 管理中心

MVP 管理中心包含：

1. 首页 / 概览。
2. 剪贴板历史。
3. 设置。
4. 权限。

设置页包含：

- 快捷键。
- 搜索源展示开关。
- 剪贴板功能开关。
- 搜索黑名单。
- 剪贴板保留时间。
- 剪贴板存储占用。
- 截图保存位置。
- 开机启动。
- 语言切换。

语言选项：

- 跟随系统（默认）。
- 简体中文。
- English。

如果运行时切换复杂，MVP 可提示重启后生效。

---

## 16. 隐私、反馈与发布架构

### 16.1 本地优先

- 剪贴板数据仅本地保存。
- 截图仅本地处理。
- 不上传。
- 不同步。
- 不训练。
- 不做敏感内容过滤。

### 16.2 隐私政策

MVP 必须提供隐私政策文档或页面，并从关于页进入。内容说明：

- 剪贴板数据如何保存。
- 截图如何处理。
- 不上传、不同步、不训练。
- 如何关闭剪贴板记录。
- 如何清空数据。
- 错误/崩溃反馈的数据范围和用户控制方式。

### 16.3 错误/崩溃反馈

- 支持用户主动触发错误/崩溃反馈。
- 必须由用户点击按钮并确认后才可上报。
- 不允许静默自动上传。
- 上报前展示数据范围并允许取消。
- 渠道优先使用邮件反馈。
- 邮件可预填应用版本、macOS 版本、错误摘要和用户补充说明。

### 16.4 检查更新与分发

MVP：

- 提供检查更新能力。
- 发现新版本后打开官网下载页或 GitHub Release 页面。
- 不做完整自动下载、安装和重启更新流程。
- 发布渠道为 GitHub Release + 简单官网/项目主页。
- 不优先进入 Mac App Store。
- MVP 阶段暂不强制 Developer ID 签名和 Apple Notarization 公证。
- MVP 后、公开扩大分发前补齐签名和公证。

官网/项目主页包含：

- 产品名称。
- Slogan。
- 核心功能介绍。
- 截图或演示动图。
- 下载按钮。
- 版本记录。
- 隐私政策。
- 反馈邮箱。
- FAQ。
- 必要权限用途说明。

---

## 17. 测试策略

测试方案详见 [test.md](test.md)。

架构层面要求：

- Provider、搜索评分、拼音、计算器、单位换算、hash 去重必须可单元测试。
- Core Data 与文件系统资源管理必须支持临时目录/临时 store 集成测试。
- 剪贴板监听应可通过抽象 Pasteboard 接口进行 mock。
- 截图坐标、标注图层、截图导出应尽量抽成纯逻辑或可测模型。
- 权限、截图、全局快捷键等系统交互进入手动验收清单。

---

## 18. 详细方案索引

| 领域 | 文档 | 状态 |
| :--- | :--- | :--- |
| 产品需求 | [prd.md](prd.md) | 当前有效 |
| 测试方案 | [test.md](test.md) | 当前有效 |
| 数据库设计 | [architecture_db.md](architecture_db.md) | 当前有效：Core Data + 文件系统数据模型详细方案 |
| 接口设计 | [architecture_api.md](architecture_api.md) | 当前有效：Assistant MVP 内部接口设计 |

---

## 19. 当前架构风险

| 风险 | 影响 | 缓解 |
| :--- | :--- | :--- |
| Core Data + 内存索引一致性 | 搜索结果可能与持久化不一致 | Core Data 作为事实来源；索引可重建；数据变更后同步索引 |
| 图片/富文本大对象存储增长 | 占用磁盘空间 | 显示存储占用；按保留时间清理；提供清空入口 |
| 强制辅助功能权限信任成本 | 普通用户可能疑惑 | Onboarding 和官网解释当前用途边界与未来能力 |
| 截图权限和 macOS 版本差异 | 截图功能可能不可用 | 最低 macOS 13；提供权限页、重新检测和降级提示 |
| 富文本恢复兼容性 | 不同 App 对 RTF/HTML 支持不同 | 优先恢复原格式，失败降级纯文本 |
| MVP 不签名公证 | 早期安装体验受 Gatekeeper 影响 | MVP 后、公开扩大分发前补齐签名和公证 |

---

## 20. 变更记录

| 日期 | 变更内容 |
| :--- | :--- |
| 2026-06-11 | v15：重写总体架构，按 `doc/prd.md` 当前 MVP 决策对齐 SwiftUI + AppKit、菜单栏 App、强制 Onboarding、SearchSource Provider、多动作模型、Core Data + 文件系统、轻量内存搜索索引、剪贴板自适应轮询、截图预览/标注、内置白名单命令、发布与隐私策略。 |
| 2026-06-12 | US-001：实现 Assistant 基础 App Shell 对齐。工程运行产物改为 `Assistant.app`，Info.plist 使用 `Assistant` / `Mac Super Assistant` 与 `com.freeabyss.qingyu`；保留现有 Xcode target/module 以兼容测试。菜单栏图标改为 template `sparkles`，菜单补齐打开搜索、剪贴板、截图、设置、关于、退出；默认同步 `SMAppService` 开机启动并在设置中保存/关闭；Application Support 与 OSLog 子系统统一到 Assistant 命名空间。 |
