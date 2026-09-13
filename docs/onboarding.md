# 青鸟 Qingniao 工程上手指南（New Engineer Onboarding）

> 面向新加入的工程师，帮助你在 1 小时内理解项目全貌、跑起来、并知道去哪里改代码。
> 关联文档：`doc/prd.md`（需求）、`doc/architecture/design.md`（架构总设计 v17）、`doc/architecture/api.md`（接口契约 v3）、`doc/architecture/db.md`（数据模型 v3）、`BUILD_README.md`（构建细节）。
>
> **阅读顺序建议**：本文 → `design.md` §2 分层架构 → 挑一个你要改的模块看 `api.md` 对应章节。

---

## 1. 这是什么项目

青鸟（Qingniao，中文名青鸟 / 英文名 Qingniao）是一款 **macOS 原生菜单栏效率工具**，定位为「增强版 Spotlight + 常用效率工具集成中心」。核心是一个统一搜索框（Command Bar，默认 `⌥ Space`），聚合：应用启动、剪贴板历史、文件搜索、截图标注、白名单命令、计算器/单位换算、设置。

- 形态：菜单栏常驻 App，无 Dock 图标（`LSUIElement=true`）。
- 数据：**默认仅本地**，不上传、不同步、不训练。
- 最低系统：macOS 13 Ventura；语言 Swift 5.9；UI 用 SwiftUI + AppKit 混合。
- 分发：Developer ID 签名 + 公证，走 GitHub Releases（`github.com/freeabyss/qingniao`），不上架 Mac App Store，v1.2 起**关闭 App Sandbox**。

当前迭代 **v1.2.0**（分支 `v1.2.0`），主题是品牌改名 + 产品全面审视。历史版本见 `doc/architecture/design.md` §版本记录。

---

## 2. 5 分钟跑起来

前置：macOS 13+、Xcode 15+、Swift 5.9+。

```bash
# 方式 A：一键脚本（推荐，Debug 构建 + 启动）
cd /path/to/assistant
chmod +x build_and_run.sh      # 首次
./build_and_run.sh             # 默认 = clean+build+run；也支持 build / run / release / help

# 方式 B：Xcode
open Qingniao.xcodeproj         # 选 Qingniao scheme，Cmd+R

# 方式 C：命令行 xcodebuild
xcodebuild -project Qingniao.xcodeproj -scheme Qingniao -configuration Debug build
```

Debug 产物：`DerivedData/Build/Products/Debug/Qingniao.app`。

**跑测试**（两种，日常用 SPM 快）：

```bash
swift test                                                   # SPM 测试目标 QingniaoTests，最快
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao # Xcode 测试计划
```

> 注意：`build_and_run.sh` **没有** test 子命令，测试用上面两条命令。当前测试基线 **159 个测试全绿 / 25 个测试文件**。

**常见排障**（详见 `BUILD_README.md`）：

```bash
sudo xcodebuild -license accept                 # 首次许可
rm -rf .build .swiftpm                           # 清 SPM 缓存
rm -rf ~/Library/Application\ Support/Qingniao/  # 重置本地数据
defaults delete com.assistant.app               # 重置偏好（注意 Bundle ID 仍是 com.assistant.app）
log stream --process Qingniao --level debug      # 实时日志
```

---

## 3. 双构建系统 & 依赖

项目**同时**有 SwiftPM 与 Xcode 工程，这是新人最容易踩的坑：

| | `Package.swift`（SPM） | `Qingniao.xcodeproj`（Xcode） |
| :--- | :--- | :--- |
| 用途 | 跑单元测试（`swift test`），CI 友好 | 构建可运行的 `.app`、调试、发布 |
| 构建内容 | library target `Qingniao` | 完整 App（含 `@main`、资源、entitlements） |
| 关键排除 | **排除** `App/QingniaoApp.swift`、`Info.plist`、`Qingniao.entitlements`、`Resources/Assets.xcassets`、`Resources/Localizable.xcstrings` | 全部纳入 |

含义：SwiftUI `@main` 入口和 App 资源只在 Xcode 构建里生效；SPM 只编译库代码 + 测试。**加了新文件要同时确认两个系统都能编到**。

**第三方依赖**（仅 2 个）：
- `GRDB.swift` `~> 7.0`（SQLite 封装）——**历史遗留/技术债**，v1.2 不再写入，见 §7。
- `KeyboardShortcuts` `~> 2.4`（sindresorhus）——全局热键，不依赖辅助功能权限。

---

## 4. 目录地图（去哪里改代码）

源码根 `Qingniao/`，按层组织。绝对定位建议直接搜类型名。

```
Qingniao/
├── App/                     App Shell 层：入口、生命周期、DI、窗口
│   ├── QingniaoApp.swift        SwiftUI @main（⚠ 类型名仍是 AssistantApp，见 §8）
│   ├── AppDelegate.swift        仅生命周期回调（136 行，已从旧 955 行 god object 瘦身）
│   ├── AppState.swift
│   └── Controllers/
│       ├── AppContainer.swift            ★ 依赖注入根 / 组合根（361 行，从这里读起）
│       ├── StatusItemController.swift    菜单栏 NSStatusItem
│       ├── CommandBarController.swift     命令栏浮层（NSPanel）
│       ├── ClipboardHistoryWindowController.swift
│       ├── SettingsWindowController.swift
│       └── ScreenshotWindowController.swift
├── Services/                Service + Provider 层：业务编排 & 搜索源
│   ├── SearchEngine/
│   │   ├── SearchCore.swift          ★ SearchSource 协议 + SearchService 都在这（不是独立文件!）
│   │   ├── AppSearchSource.swift     应用搜索源
│   │   ├── AssistantClipboardSource.swift  剪贴板搜索源
│   │   ├── SystemCommandSource.swift 白名单命令源
│   │   ├── CalculatorSource.swift    计算/单位换算源
│   │   ├── SettingsSource.swift      设置入口源
│   │   ├── FileSearchSource.swift    文件搜索源（v1.2 才真正接线）
│   │   ├── CommandBarHomeProvider.swift  空态「最近使用+收藏」首页
│   │   └── InMemorySearchIndex.swift 轻量内存搜索索引
│   ├── ClipboardMonitor/ClipboardMonitor.swift  ★ 内含 ClipboardService（不是独立文件!）
│   ├── ScreenshotService/ScreenshotService.swift
│   ├── Permissions/PermissionService.swift
│   ├── Hotkey/                GlobalShortcutManager / HotkeyConflictDetector / HotkeyValidationService
│   ├── LaunchAtLogin/LaunchAtLoginService.swift
│   ├── DataCleanup/ · DataManagement/
│   └── UpdateService/         ReleaseInfoService（跳 GitHub Releases）/ UpdateService
├── Database/                Data 层
│   ├── PersistenceController.swift   Core Data 活动栈
│   ├── AssistantFileSystem.swift     文件资源目录
│   ├── DataDirectoryMigrator.swift   Assistant/ → Qingniao/ 目录迁移
│   ├── DatabaseManager.swift         GRDB（历史遗留/技术债）
│   └── Repositories/
│       ├── AssistantClipboardRepository.swift  ★ 唯一活动剪贴板仓库（文件名未改，见 §8）
│       └── SearchBlacklistRepository.swift
├── ViewModels/              @MainActor：SearchPanel / ClipboardList / Onboarding / Settings
├── Views/                   Presentation 层
│   ├── Design/              ★ Design Token：JadeColor/Font/Material/Radius/Shadow/Space
│   ├── Components/          通用组件：JadeButton/JadeTextField/HotkeyRecorder/ListRow/Toast…
│   ├── SearchPanel/CommandBarView · ClipboardList/ · Settings/ · Onboarding/ · Annotation/ · Preview/
├── Models/                  AppSetting / ClipboardItem / Tag / SnapVaultError
├── Utilities/               PinyinHelper / CryptoHelper / L10n / Logger / KeyboardShortcuts+Names
└── Resources/               Assets.xcassets / Localizable.xcstrings / Info.plist / entitlements
```

---

## 5. 架构分层（一页版）

系统是 **6 层单向依赖**：`App Shell → Presentation → ViewModel → Service → Provider → Data → macOS API`。铁律：**相邻层单向依赖，UI 不得直接碰 Core Data / 文件系统 / macOS 底层 API**。完整职责边界表见 `design.md` §2.4。

| 层 | 干什么 | 代表类型 |
| :--- | :--- | :--- |
| App Shell | 生命周期、DI 组装、菜单栏、窗口、全局热键 | `AppDelegate`, `AppContainer`, `StatusItemController`, `GlobalShortcutManager` |
| Presentation | SwiftUI 视图 + 通用组件 + Design Token | `CommandBarView`, `SettingsView`, `Jade*` |
| ViewModel | `@MainActor` 状态与用户意图 | `SearchPanelViewModel`, `OnboardingViewModel` |
| Service | 业务编排、async/await | `SearchService`, `ClipboardService`, `ScreenshotService`, `PermissionService` |
| Provider | 单一搜索源检索与结果构造 | `AppSearchSource`, `FileSearchSource`, `CalculatorSource`… |
| Data | 持久化、文件资源、内存索引 | `PersistenceController`, `AssistantClipboardRepository`, `InMemorySearchIndex` |

### AppContainer 是入口（先读它）

`Qingniao/App/Controllers/AppContainer.swift` 是**依赖注入根 / 组合根**——唯一知道「如何拼装整个对象图」的地方。它 `lazy` 构造并持有：Data 层（`InMemorySearchIndex`、`FileResourceStore`、`ClipboardRepository` 用 `IndexingClipboardRepository` 装饰）、Services（`ClipboardService`/`ClipboardMonitor`/`ScreenshotService`/`UpdateService`）、四个搜索源、5 个窗口/状态控制器、`GlobalShortcutManager`。`AppDelegate` 现在只做生命周期回调，把组装全权委托给 `AppContainer`。**要理解数据如何流动，从 AppContainer 顺藤摸瓜最快。**

---

## 6. 核心数据流（搜索 & 剪贴板）

**搜索**：`GlobalShortcutManager`（`⌥ Space`）→ `CommandBarController` 显示浮层 → `SearchPanelViewModel`（唯一 VM）→ `SearchService`（`SearchCore.swift`）并发聚合各 `SearchSource` → 合并排序，`finalScore = sourceBasePriority + textMatchScore + usageBoost`，总上限 12 条不分组。空输入走 `CommandBarHomeProvider`「最近使用+收藏」。

来源基础优先级：应用 100 / 命令 90 / 计算 85 / 设置 80 / **文件 75** / 剪贴板 70。

**剪贴板**：`ClipboardMonitor`（`NSPasteboard.changeCount` 自适应轮询 500ms/2s）→ `ClipboardService`（就在 `ClipboardMonitor.swift` 内）→ `AssistantClipboardRepository`（Core Data，唯一活动仓库，经 `IndexingClipboardRepository` 装饰器同步写入 `InMemorySearchIndex`）。文本/富文本/图片存 Core Data + 文件资源目录，去重靠 `contentHash`。**Core Data 是事实来源，内存索引可随时重建。**

依赖关系全图见 `api.md` §19（Mermaid）。

---

## 7. 你必须知道的技术债 & 约束

1. **双数据栈**：活动栈是 **Core Data**（`PersistenceController`）；**GRDB**（`DatabaseManager`）是历史遗留，v1.2 **不再写入、不重构**，仅保留兼容旧数据。写剪贴板时若命中 GRDB 遗留路径要 try/catch 容错、不崩溃。**新功能一律走 Core Data**，别往 GRDB 加东西。V1.x 计划统一单栈。
2. **关闭 Sandbox**：v1.2 移除 App Sandbox，保留 Hardened Runtime + `apple-events` entitlement，让重启 Finder/Dock 等 AppleEvents 命令可靠执行。命令严格白名单（15 条，含“打开剪贴板历史”），**永不支持任意 shell**。
3. **辅助功能按需申请**：Onboarding 只强制屏幕录制（截图依赖）；辅助功能改为首次真正用到时才经 `PermissionService.onDemandAccessibilityCheck()` 申请。全局热键用 KeyboardShortcuts 库，不依赖辅助功能。
4. **Design Token 硬约束靠 review**：View 里**禁止硬编码颜色/圆角/字号**，必须走 `Views/Design/Jade*`。无静态 lint，靠 code review 把关。
5. **Bundle ID 保留 `com.assistant.app`**：改名青鸟只改显示名/target/目录/module，Bundle ID 不动（它绑定 TCC 权限、Keychain、数据目录、登录项）。

---

## 8. 文档 vs 代码：已知差异（避免踩坑）

`design.md`/`api.md` 部分内容是**设计目标**，与当前代码有出入。以下以**代码为准**：

| 文档说 | 代码实际 |
| :--- | :--- |
| `@main` 类型为 `QingniaoApp` | 文件名是 `QingniaoApp.swift`，但类型仍叫 **`AssistantApp`**（改名未完成） |
| `SearchService` / `ClipboardService` 是独立文件 | 分别在 **`SearchCore.swift`** 和 **`ClipboardMonitor.swift`** 内 |
| 无 `DesignToken` 类型 | Design Token 就是 `Views/Design/` 下的 `Jade*` 枚举，没有叫 `DesignToken` 的类型 |
| `api.md` 称仓库改名为 `ClipboardRepository`（Qingniao 模块） | 文件名仍是 **`AssistantClipboardRepository.swift`**；`AppContainer` 里用的类型名是 `ClipboardRepository`（经 `IndexingClipboardRepository` 装饰）——类型/文件命名尚未完全统一 |
| `design.md` 列 5 类窗口控制器（含 `AnnotationWindowController`/`ScreenshotOverlayController`） | 实际是 **5 个**：Status/CommandBar/ClipboardHistory/Settings/**ScreenshotWindowController**（截图相关合并到一个），标注在 `Views/Annotation/` |
| 文件搜索权重 `design §7.4`=75 vs `PRD FR-SEARCH-11`=60 | 取 **75**（已在文档标注差异，测试以 75 为准） |

> 发现更多不一致时：优先信代码，然后按项目规范（`architecture-doc` 流程）回写更新架构文档，保持「开发与设计一致」。

---

## 9. 开发工作流 & 约定

本项目采用**分层多 Agent 执行模型**（见仓库根 `CLAUDE.md` 与全局规范）：

- **迭代文档**在 `doc/iterations/<版本>/`：`prd.md`、`tasks.json`（任务列表，`passes` 标记完成）、`progress.md`（历史记录）、`architecture/`、`test/`。开工前先读当前迭代的 `progress.md` 和 `tasks.json`。
- **单会话单任务**：一次只做一个 `tasks.json` 里 `passes:false` 的任务，完成且测试全绿后才置 `passes:true` 并追加 `progress.md`，再 `git commit`。
- **每个项目是独立 Git 仓库**，在项目根目录提交。commit message 要具体。
- **不提交半成品**：编译不过 / 测试不过 / 功能不完整的代码不许进主分支。
- **改代码先对齐技术方案**：动架构就先更新 `doc/architecture/` 下对应文档（`architecture-doc` 技能流程），再写代码。
- 并发约定：UI/ViewModel `@MainActor`；Service/Repository `async/await`；不向上层暴露 `NSManagedObject`。

### 提交前自检清单
1. `swift test` 全绿（当前基线 159）。
2. `xcodebuild -project Qingniao.xcodeproj -scheme Qingniao -configuration Debug build` → `BUILD SUCCEEDED`。
3. 新增文件在 SPM 和 Xcode 两套构建里都可编。
4. View 无硬编码样式，走 `Jade*` token。
5. 更新了 `progress.md` / `tasks.json`（若在迭代任务内）。

---

## 10. 速查表

| 我想… | 去哪里 |
| :--- | :--- |
| 加一个新搜索源 | 实现 `SearchSource`（`SearchCore.swift` §协议），在 `AppContainer` 实例化并注册；参考 `FileSearchSource` |
| 改搜索排序/权重 | `SearchCore.swift` 的 `SearchService`；权重常量见 `api.md` §3.5 |
| 改剪贴板存储 | `AssistantClipboardRepository.swift` + `ClipboardMonitor.swift`（走 Core Data） |
| 改 UI 样式/颜色 | `Views/Design/Jade*`（不要硬编码） |
| 加设置项 | `SettingKey`/`SettingsRoute`（`api.md` §12）+ `SettingsService` + `SettingsView` |
| 改全局热键 | `Services/Hotkey/GlobalShortcutManager.swift` |
| 加白名单命令 | `SystemCommandSource.swift`（15 条清单见 `design.md` §13，禁 shell） |
| 改数据模型 | Core Data（`PersistenceController`）+ 迁移，先读 `db.md` |
| 理解对象如何组装 | `AppContainer.swift`（从这开始） |
| 需求/验收标准 | `doc/prd.md` |
| 接口契约（协议签名） | `doc/architecture/api.md` |
```
