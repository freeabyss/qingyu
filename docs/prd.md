# PRD：清羽 Qingyu

> 中文名：清羽 · 英文名：Qingyu · Bundle ID：`com.freeabyss.qingyu`

## 版本记录

| 版本 | 上线日期 | 说明 |
|------|---------|------|
| v1.0.0 | 2026-07-02 | 首次上线，MVP（22 个用户故事）。当时产品暂定名为 Mac Super Assistant。 |
| v1.0.1 | 2026-07-02 | Bug 修复：修复启动时"无法启动更新程序"弹窗（Issue #1、PR #2）。产品行为无变化：MVP 阶段"检查更新"继续跳转 GitHub Releases。 |
| v1.1.0 | 2026-07-03 | Bug 修复 + 新功能（Issue #3、PR #4）：修复 onboarding 屏幕录制权限申请断点（PermissionService 新增 `requestScreenRecordingPrompt()` 触发 TCC 注册）+ 新增 onboarding "跳过设置"入口（skip 状态分支 + footer Skip 按钮 + 确认 Alert + 双语文案）。遗留：重启不重弹 onboarding、按需申请 Alert 端到端、设置页权限入口待本迭代验证（见 AC-6/AC-7）。 |
| v1.2.0 | 2026-07-03 | 产品全面审视 + 品牌改名清羽 Qingyu（Issue #5）。关键变更：① 品牌命名正式落地（中文清羽、英文 Qingyu，Bundle ID 保留 `com.freeabyss.qingyu`）；② 文件搜索接入（FileSearchSource 补齐接线，MVP 能力闭环）；③ 全屏截图补全全局快捷键（默认 `⌃⌥⌘3`，可重绑）；④ 版本号三源修正统一为 1.2.0（Xcode MARKETING_VERSION / Info.plist / CHANGELOG）；⑤ onboarding 辅助功能权限由强制改为按需申请；⑥ 关闭 App Sandbox，改为 Developer ID 签名 + notarytool 公证 + GitHub Releases 分发；⑦ 死代码清理（OCR / UnifiedSearch / UnitConverterSource 等）；⑧ 文档路径交叉引用修正（doc/test/cases.md、doc/architecture/design.md 等）。 |

---

## 1. 引言 / 概述

清羽（Qingyu）是一款 macOS 原生效率工具，定位为 **增强版 Spotlight + 常用效率工具集成中心**。

产品通过一个统一搜索入口，将应用启动、剪贴板历史、截图、内置命令、计算器、文件搜索、设置等高频能力聚合在一起。同时，对于需要更复杂交互的能力，提供轻量管理中心或专用面板承载。

产品自 v1.0.0 起即以 **小范围公开测试级产品（public beta-ready）** 标准交付：功能深度保持克制，产品体验、权限引导、隐私说明、设置、稳定性和发布资料按公开产品方向设计。自 v1.2.0 起，发布分发正式升级为 **Developer ID 签名 + Apple Notarization 公证 + GitHub Releases 分发**（不上 Mac App Store），使系统控制类内置命令（重启 Finder/Dock、切换外观等）可靠工作。

> 命名说明：本产品曾在 v1.0.0–v1.1.0 期间以"Mac Super Assistant"为暂定名、以"Assistant / SnapVault"为工程内部代号。自 v1.2.0 起正式定名清羽 Qingyu；本文除历史决策语境外，一律使用当前正式名。

---

## 2. 产品定位

### 2.0 命名策略

命名于 v1.2.0 正式定案，不再有"暂定名""发布前再定"等悬而未决表述：

- **中文名**：清羽
- **英文名**：Qingyu（首字母大写；正式对外文案统一使用此拼写）
- **Bundle ID**：`com.freeabyss.qingyu`（**保留不变**）
  - 原因：Bundle ID 是 macOS TCC 权限（屏幕录制、辅助功能等）、Keychain、Application Support 数据目录、开机启动项的绑定键。若修改 Bundle ID，已授权用户会丢失全部权限、需重新授权，剪贴板/截图历史数据目录也会失联。因此显示名、工程 target 名、源码目录、对外文案全面改为清羽 / Qingyu，但 Bundle ID 保持 `com.freeabyss.qingyu` 不动（见决策 D-102）。
- **反馈邮箱**：qingyu_freeabyss@163.com
- **GitHub 仓库**：github.com/freeabyss/qingyu（仓库路径保留，不改 repo 名，避免既有链接、Release、Issue 失效）

### 2.1 核心定位

产品核心定位为：

> 以 Spotlight 式统一搜索入口为主，以截图、剪贴板、命令、应用启动、文件搜索等工具能力为支撑的 macOS 效率中心。

产品不是单纯的应用启动器，也不是松散的工具箱，而是：

- **搜索入口优先**：所有核心功能都应能通过搜索框触发。
- **独立面板补充**：剪贴板历史、设置、权限等低频/复杂操作可通过管理中心完成。
- **开箱即用**：默认启用主要能力，减少用户前置配置和认知负担。
- **本地优先**：剪贴板、截图、配置等数据默认只保存在用户本机。

### 2.2 与现有工具的关系

产品目标不是完整复制某一个工具，而是覆盖以下工具的高频场景：

| 工具类型        | 代表产品                              | 本产品覆盖方向                 |
| ----------- | --------------------------------- | ----------------------- |
| 应用启动 / 命令入口 | Spotlight / Alfred / Raycast      | 统一搜索框、应用启动、内置命令、计算器、文件搜索 |
| 剪贴板管理       | Maccy / Paste                     | 文本、图片、文件剪贴板历史           |
| 截图工具        | iShot / Shottr / CleanShot X      | 区域/全屏/窗口截图，轻量标注，复制/保存   |
| 系统效率工具      | Magnet / iStat Menus / CleanMyMac | 作为长期功能方向：窗口控制、资源监控、应用卸载 |

---

## 3. 目标

### 3.1 产品目标

- 提供一个统一入口，让用户通过快捷键快速完成常用 macOS 操作。
- 支持应用启动、剪贴板历史、基础截图、轻量标注、文件搜索和内置命令。
- 以可公开发布产品的标准交付，包含首次引导、权限管理、隐私说明、设置页面和清晰菜单栏入口。
- 默认开箱即用，减少用户在安装后的配置负担。
- 所有用户数据默认仅保存在本地，不上传、不同步、不训练。

### 3.2 MVP 原则

1. **功能深度按演示级克制**：不追求每个模块都完整替代专业工具。
2. **交付质量按公开发布级要求**：首次引导、权限、设置、隐私、错误状态必须清晰。
3. **统一入口优先**：核心功能必须能通过搜索框触发。
4. **Provider 架构优先**：搜索结果来源从第一天按 SearchSource / Provider 模式设计。
5. **默认开启，显式告知**：尽量减少配置，但在 Onboarding 和隐私说明中明确告知默认行为。
6. **诚实交付**：文档只声明已实现或本迭代确定补齐的能力；未实现能力明确标记为"v1.2 待补"或"V1.x/V2.x 规划"。

---

## 4. 用户画像

### 4.1 普通办公人员

- 快速启动常用应用。
- 复制过的内容可以找回。
- 快速截图并标注后发送。
- 不想学习复杂命令和规则。

### 4.2 产品经理 / 运营 / 设计协作用户

- 高频截图。
- 截图后添加矩形框、箭头、文字、马赛克。
- 截图后快速复制到聊天工具或保存文件。
- 管理最近复制过的文本、链接、图片和文件。

### 4.3 程序员 / 高级用户

- 快速启动开发工具。
- 快速找回复制过的代码片段、链接、路径。
- 通过内置命令完成常用系统操作。
- 通过文件搜索快速定位主目录下的文档、代码和资源文件。
- 希望长期支持更多高级能力，例如窗口控制、资源监控、自定义命令等。

---

## 5. 产品范围

### 5.1 MVP 必须包含

MVP 功能集（8 项）：

1. **统一搜索入口**
   - 默认快捷键 `⌥ Space` 呼出。
   - Spotlight 外观 + Raycast 行为模型。
   - 支持结果列表、图标、类型、说明、键盘选择、回车执行。

2. **应用启动**
   - 搜索并启动常规应用目录中的 `.app`。
   - 搜索范围：`/Applications`、`~/Applications`、`/System/Applications`。

3. **剪贴板历史**
   - 默认开启记录。
   - 支持文本、图片、文件三类内容。
   - 文件只保存引用/路径，不复制文件内容。
   - 只按时间淘汰，默认保留最近 30 天。
   - 不做敏感内容过滤，因为数据仅本地保存。

4. **截图系统**
   - 支持区域截图、全屏截图、窗口截图。
   - 区域/窗口/全屏均支持全局快捷键触发（全屏快捷键 v1.2 补齐，见 FR-SHOT-FULLSCREEN）。
   - 截图后显示预览和工具栏。
   - 工具栏提供复制、保存、标注工具、取消。
   - 标注工具支持矩形框、箭头、文字、马赛克（mosaic）、撤销/重做。blur 独立模糊工具列入 V1.x 路线图，v1.2 保持 mosaic。

5. **内置命令执行**
   - 只支持内置白名单命令（14 条，见第 8 章）。
   - 不支持搜索框直接执行任意 shell。
   - MVP 不支持用户自定义 shell 命令。

6. **文件搜索（v1.2 补齐）**
   - 通过统一搜索框搜索用户主目录常用位置下的文件与文件夹。
   - v1.2 完成 FileSearchSource 接线，使 `⌥ Space` 能返回文件结果并执行"打开 / 在 Finder 中显示"（见 FR-SEARCH-FILE）。

7. **管理中心**
   - 首页 / 概览。
   - 剪贴板历史。
   - 设置。
   - 权限。

8. **菜单栏 App 形态与首次启动 Onboarding**
   - App 常驻菜单栏，默认无 Dock 图标。
   - 菜单栏入口包含：打开搜索、剪贴板、截图、设置、关于、退出。
   - 完整首次引导；MVP 必要权限（屏幕录制）在引导中完成，辅助功能改为按需申请（见 FR-ONBOARD-ACCESSIBILITY-ONDEMAND）。

### 5.2 MVP 搜索源

MVP 搜索源包含：

- 应用（Applications Source）
- 剪贴板（Clipboard Source）
- 内置命令 / 截图命令（Command Source）
- 计算器 / 单位换算（Calculator / Converter Source）
- 设置项（Settings Source）
- 文件（File Search Source，v1.2 接入）

搜索源配置：

- MVP 的搜索源配置只提供开关级能力。开关语义为：是否参与搜索结果展示。
- 对剪贴板这类隐私敏感功能，额外提供"启用剪贴板历史记录"开关。
- 另提供具体搜索结果黑名单，用于隐藏某个 App、某条内置命令、某个设置入口等具体结果；黑名单不等同于停用功能模块。

### 5.3 MVP 不包含

MVP 明确不包含以下内容：

- 付费限制、支付系统、授权码、订阅、账号系统、账号登录、云端账户体系。
- 任意 shell 执行、用户自定义命令。
- 插件市场或第三方插件系统。
- 文件全文搜索 / 文件内容索引（v1.2 只做文件名/路径搜索，不做内容全文检索）。
- **OCR 图片文字识别**（明确不支持；相关死代码 v1.2 清理，能力列入 V2.x）。
- 录屏、长截图、截图贴图、截图历史管理。
- 云同步、多设备同步、团队协作。
- AI 能力。
- 应用卸载、资源监控、窗口控制完整功能。
- blur 独立模糊标注工具（v1.2 仅 mosaic；blur 列入 V1.x）。
- 数据备份/导出能力（v1.2 不做，见 FR-DATA-EXPORT-BACKUP，列入 V1.x）。

### 5.4 长期功能地图

PRD 记录完整愿景，但开发按版本分期。长期功能包括：

- 窗口控制、资源监控、应用卸载。
- OCR、录屏 / GIF、长截图、截图历史。
- blur 独立模糊工具、更多截图标注工具。
- 数据备份/导出、iCloud 同步（可选）。
- 自定义命令、工作流、插件或扩展能力。
- AI 总结、翻译、智能搜索。

---
## 6. 核心用户故事

> 状态标记：✅ 已在 v1.0–v1.1 交付；🔧 v1.2 补齐；⏳ V1.x/V2.x 规划。

### US-001：首次启动引导与权限初始化 ✅（v1.2 调整为按需申请辅助功能）

**描述：** 作为新用户，我想在首次启动时完成必要权限授权和基础认知，以便进入应用后功能可以开箱即用。

**验收标准：**

- [ ] 首次启动展示完整 Onboarding。
- [ ] Onboarding 说明默认快捷键 `⌥ Space`。
- [ ] Onboarding 说明剪贴板历史默认开启且仅本地保存。
- [ ] Onboarding 引导用户授予屏幕录制权限（截图必需）。
- [ ] Onboarding 不再强制勾选辅助功能权限，仅解释其未来用途（见 US-012）。
- [ ] 屏幕录制权限未授予时，用户停留在权限页；权限页提供"打开系统设置"和"重新检测"按钮。
- [ ] Onboarding 提供"跳过设置"入口（带二次确认 Alert）。
- [ ] 用户完成或跳过 Onboarding 后进入菜单栏常驻状态。

### US-002：菜单栏 App 入口 ✅

**验收标准：**

- [ ] App 默认常驻菜单栏、默认不显示 Dock 图标。
- [ ] 菜单栏包含"打开搜索""剪贴板""截图（点击直接执行区域截图）""设置""关于""退出"。

### US-003：统一搜索入口 ✅

**验收标准：**

- [ ] 默认快捷键为 `⌥ Space`，用户可在设置中修改。
- [ ] 搜索框采用居中极简样式，下方显示结果列表。
- [ ] 结果项显示图标、标题、类型和说明。
- [ ] 支持上下键选择、回车执行主动作、ESC 关闭。
- [ ] MVP 不要求实现完整 Action Panel。

### US-004：SearchSource Provider 架构 ✅

**验收标准：**

- [ ] 搜索源抽象为 SearchSource / Provider，每个 Provider 有唯一 id、启用状态、搜索能力和执行能力。
- [ ] AppSource、ClipboardSource、CommandSource、CalculatorSource、SettingsSource、FileSearchSource 以独立 Provider 形式存在。
- [ ] 设置中的搜索源开关能控制对应 Provider 是否参与搜索展示。
- [ ] 新增 Provider 不需要重写主搜索 UI。

### US-005：搜索结果多动作模型 ✅

**验收标准：**

- [ ] SearchResult 支持 primaryAction 和 secondaryActions。
- [ ] MVP UI 只执行 primaryAction，不要求展示 Cmd+K 动作面板。
- [ ] 后续可基于 secondaryActions 增加右键菜单或动作面板。

### US-006：应用启动 ✅

**验收标准：**

- [ ] MVP 扫描 `/Applications`、`~/Applications`、`/System/Applications`，只索引 `.app` bundle。
- [ ] 搜索结果显示应用图标和名称；回车通过系统方式启动应用。

### US-007：剪贴板历史记录 ✅

**验收标准：**

- [ ] 剪贴板历史默认开启，支持文本、图片、文件引用。
- [ ] 文件历史只保存元信息，不复制文件内容；原文件移动或删除后标记为不可用。
- [ ] 剪贴板数据仅本地保存，不上传、不同步、不训练；不做敏感内容自动过滤。

### US-008：剪贴板历史管理 ✅

**验收标准：**

- [ ] 管理中心包含剪贴板历史页面，支持文本/图片/文件展示、搜索、删除单条、清空全部、暂停/恢复记录。
- [ ] 默认按时间淘汰，默认保留最近 30 天；设置中可调整保留周期。

### US-009：截图与轻量标注 ✅（v1.2 补全全屏快捷键）

**验收标准：**

- [ ] 支持区域、全屏、窗口截图；菜单栏"截图"点击后直接执行区域截图。
- [ ] 区域/窗口/全屏均可通过全局快捷键触发（全屏快捷键 v1.2 补齐）。
- [ ] 截图后显示预览和浮动工具栏，工具栏包含复制、保存、取消、标注工具入口。
- [ ] 标注支持矩形框、箭头、文字、马赛克（mosaic）、撤销/重做。
- [ ] 复制/保存/取消行为符合 FR-SHOT-26~32。

### US-010：内置白名单命令 ✅

**验收标准：**

- [ ] MVP 只支持内置白名单命令，不支持任意 shell 或用户自定义命令。
- [ ] 中风险命令执行前需要确认；高风险命令不在 MVP 中提供。
- [ ] 关闭 Sandbox 后，重启 Finder/Dock、切换深浅色等 AppleEvents 命令可靠执行（见 FR-PERM-APPLE-EVENTS）。

### US-011：管理中心 ✅

**验收标准：**

- [ ] 管理中心包含首页/概览、剪贴板历史、设置、权限。
- [ ] 首页显示快捷入口、权限状态、当前开启的搜索源和快捷键提示。
- [ ] 设置页支持快捷键设置、搜索源开关、剪贴板保留时间、截图保存位置。
- [ ] 权限页支持权限状态查看、重新检测、打开系统设置。

### US-012：文件搜索 🔧（v1.2 补齐）

**描述：** 作为用户，我想在统一搜索框中输入文件名找到主目录下的文件，以便快速打开或在 Finder 中定位。

**验收标准：**

- [ ] FileSearchSource 在 AppDelegate 中实例化并注册进搜索服务。
- [ ] 输入不少于 2 个字符触发文件搜索。
- [ ] 默认索引范围为用户主目录常用位置：`~/Desktop`、`~/Documents`、`~/Downloads`（默认排除隐藏目录、系统缓存、`Library`）。
- [ ] 文件结果显示文件名、路径、类型图标。
- [ ] 主动作为"打开文件"，次级动作为"在 Finder 中显示"。
- [ ] 搜索响应满足性能目标（见 §11.1），大目录下不阻塞 UI。

### US-013：全屏截图全局快捷键 🔧（v1.2 补齐）

**验收标准：**

- [ ] 全屏截图提供独立全局快捷键，默认 `⌃⌥⌘3`（与 macOS 默认 `⇧⌘3` 错开）。
- [ ] 用户可在设置的快捷键区重新绑定。
- [ ] 快捷键冲突时给出提示并要求重新录制。

---
## 7. 功能需求

> 每条 FR 标注交付状态：✅ 已交付（v1.0–v1.1）；🔧 v1.2 补齐/修订；⏳ 规划。

### 7.1 搜索入口 ✅

- FR-SEARCH-1：系统必须提供一个全局搜索入口。
- FR-SEARCH-2：默认全局快捷键必须为 `⌥ Space`。
- FR-SEARCH-3：用户必须可以在设置中修改全局快捷键。
- FR-SEARCH-4：搜索框必须支持结果列表展示。
- FR-SEARCH-5：结果项必须包含图标、标题、类型和说明。
- FR-SEARCH-6：回车必须执行当前选中结果的主动作。
- FR-SEARCH-7：ESC 必须关闭搜索框。
- FR-SEARCH-8：搜索源必须可通过设置开关控制是否展示。
- FR-SEARCH-8a：所有 MVP 搜索源默认必须开启，包括应用、剪贴板、内置命令/截图命令、计算器/单位换算、设置项、文件搜索。
- FR-SEARCH-8b：MVP 只有剪贴板提供功能启用/停用开关；其他功能模块不提供独立功能开关。
- FR-SEARCH-8c：搜索结果必须支持黑名单机制，黑名单内的结果不予展示。
- FR-SEARCH-8d：搜索黑名单用于隐藏用户不希望看到的具体结果，不等同于停用功能模块。
- FR-SEARCH-8e：MVP 搜索黑名单粒度只支持屏蔽具体搜索结果。
- FR-SEARCH-8f：MVP 黑名单可用于隐藏某个 App、某条内置命令、某个设置入口等具体结果。
- FR-SEARCH-8g：MVP 不支持规则黑名单（按关键词、路径、来源规则批量隐藏）。
- FR-SEARCH-8h：MVP 不实现搜索结果右键菜单或完整次级动作入口。
- FR-SEARCH-8i：MVP 搜索黑名单只能通过设置页管理，允许查看、添加和移除已隐藏结果。
- FR-SEARCH-8j：黑名单移除后，对应搜索结果必须可以重新展示。
- FR-SEARCH-8k：从搜索结果右键菜单或次级动作加入黑名单作为后续版本能力预留。
- FR-SEARCH-9：统一搜索结果排序必须采用"来源基础优先级 + 文本匹配分数"的综合评分模型。
- FR-SEARCH-10：MVP 必须实现最近使用加权，至少记录应用启动次数、最后启动时间、命令执行次数、最后执行时间，并用于搜索排序加分。
- FR-SEARCH-10a：最近使用加权必须保持本地记录，不上传用户行为数据。
- FR-SEARCH-11：默认来源基础优先级为：应用 100、命令 90、计算/换算 85、设置 80、文件 75、剪贴板 70（D-121 调整文件权重至 75，高于剪贴板）。
- FR-SEARCH-12：MVP 必须支持应用名称、命令名称、设置项名称的拼音搜索和拼音首字母搜索。
- FR-SEARCH-13：MVP 剪贴板正文与文件名暂不做拼音索引，只做原文搜索。
- FR-SEARCH-14：搜索框空输入时显示"最近使用 + 收藏"列表（最多 5 条最近 + 最多 5 条收藏），不显示通用推荐；具体交互见 §9.3 与 D-120（FR-SEARCH-14/15 原始约束已由 D-120 演进取代）。
- FR-SEARCH-15：（已由 FR-SEARCH-14 与 D-120 取代，保留编号以追溯历史）
- FR-SEARCH-16：搜索触发必须按来源区分：应用、命令、设置输入 1 个字符开始搜索。
- FR-SEARCH-17：剪贴板搜索和文件搜索必须在输入不少于 2 个字符时触发。
- FR-SEARCH-18：计算器/单位换算必须在检测到表达式或单位模式时触发。
- FR-SEARCH-19：统一搜索结果 MVP 不按来源分别限制数量，而是采用总结果数上限。
- FR-SEARCH-20：排序后的所有来源结果必须合并后按总上限截断。
- FR-SEARCH-21：MVP 搜索结果最多展示 12 条。
- FR-SEARCH-22：MVP 不提供搜索结果数量上限配置。
- FR-SEARCH-23：搜索结果不显示分组标题，但显示来源类型图标与徽章（P-01 规范）。
- FR-SEARCH-24：每条搜索结果必须通过图标和类型标签标识来源。
- FR-SEARCH-25：命令栏支持 ⌘1-6 切换搜索源（所有/应用/命令/剪贴板/文件/设置），不支持 ⌘1-9 直接执行结果（数字键用于切源）。
- FR-SEARCH-26：搜索结果模型和 UI 布局预留未来直接执行结果的数字快捷键扩展空间。
- FR-SEARCH-27：搜索框必须在失焦时自动关闭。
- FR-SEARCH-28：搜索框必须支持点击外部关闭、切换到其他 App 关闭、按 ESC 关闭、再次按全局快捷键关闭。
- FR-SEARCH-29：执行搜索结果主动作后，搜索框必须自动关闭。

### 7.2 搜索源 / Provider ✅

- FR-PROVIDER-1：系统必须使用 SearchSource / Provider 模式组织搜索源。
- FR-PROVIDER-2：MVP 必须包含 AppSource、ClipboardSource、CommandSource、CalculatorSource、SettingsSource、FileSearchSource。
- FR-PROVIDER-3：每个 Provider 必须能独立搜索并返回 SearchResult。
- FR-PROVIDER-4：每个 SearchResult 必须支持主动作。
- FR-PROVIDER-5：每个 SearchResult 应支持次级动作，但 MVP UI 可以不展示。
- FR-PROVIDER-6：CalculatorSource MVP 必须支持基础四则运算、括号和小数。
- FR-PROVIDER-7：CalculatorSource MVP 必须支持常用单位换算：长度、重量、数据大小、温度。
- FR-PROVIDER-8：CalculatorSource MVP 不支持货币换算、复杂函数、变量和计算历史。
- FR-PROVIDER-9：CalculatorSource 结果回车后的主动作必须是复制计算/换算结果到系统剪贴板。
- FR-PROVIDER-10：计算/换算结果是否进入剪贴板历史，必须遵循统一剪贴板监听与去重逻辑，不为计算器单独建立历史。
- FR-PROVIDER-11：SettingsSource MVP 必须包含页面级入口和具体设置区块入口。
- FR-PROVIDER-12：SettingsSource MVP 至少包含：打开设置、打开权限、打开剪贴板历史、打开搜索源设置、打开快捷键设置、打开截图设置、打开关于。
- FR-PROVIDER-13：SettingsSource MVP 不支持在搜索结果中直接切换设置开关。
- FR-PROVIDER-14：SettingsSource 长期目标是扩展为全量设置项索引和安全的设置直接操作。
- FR-PROVIDER-15（历史清理）：v1.2 必须移除并列存在的 legacy UnifiedSearchService / UnifiedSearchViewModel 与重复实现的 UnitConverterSource，统一走 SearchService + CalculatorSource，避免两套实现产生行为分歧。

### 7.2a 文件搜索 🔧（v1.2 补齐，FR-SEARCH-FILE）

- FR-SEARCH-FILE-1：FileSearchSource 必须在 App 启动时实例化并注册到 SearchService（v1.2 修复其从未被实例化导致 `⌥ Space` 搜不到文件的问题）。
- FR-SEARCH-FILE-2：默认索引范围为用户主目录常用位置：`~/Desktop`、`~/Documents`、`~/Downloads`。
- FR-SEARCH-FILE-3：默认排除隐藏文件/目录、`~/Library`、系统缓存目录及 `.app` 包内部内容。
- FR-SEARCH-FILE-4：v1.2 只做文件名/路径匹配，不做文件内容全文检索（OCR/全文索引不在范围内）。
- FR-SEARCH-FILE-5：文件结果必须显示文件名、所在路径和类型图标。
- FR-SEARCH-FILE-6：文件结果主动作为"打开文件"（系统默认应用），次级动作为"在 Finder 中显示"。
- FR-SEARCH-FILE-7：文件搜索必须在输入不少于 2 个字符时触发，并使用异步执行，避免阻塞搜索 UI。
- FR-SEARCH-FILE-8：索引范围是否可由用户在设置中配置，作为 V1.x 增强项；v1.2 先固定为默认三目录（见第 16 章待解决问题）。
- FR-SEARCH-FILE-9：文件搜索结果同样受搜索源开关和结果黑名单机制约束。

### 7.3 应用启动 ✅

- FR-APP-1：MVP 必须扫描 `/Applications`。
- FR-APP-2：MVP 必须扫描 `~/Applications`。
- FR-APP-3：MVP 必须扫描 `/System/Applications`。
- FR-APP-4：MVP 只索引 `.app` bundle。
- FR-APP-5：应用启动结果必须支持回车启动。
- FR-APP-6：长期目标是支持更广泛应用索引，但不进入 MVP。

### 7.4 剪贴板 ✅

- FR-CLIP-1：剪贴板历史默认开启。
- FR-CLIP-2：系统必须支持记录文本剪贴板。
- FR-CLIP-3：系统必须支持记录图片剪贴板。
- FR-CLIP-4：系统必须支持记录文件剪贴板。
- FR-CLIP-5：文件剪贴板只保存文件引用/路径，不复制文件内容。
- FR-CLIP-6：剪贴板历史只按时间淘汰。
- FR-CLIP-7：默认保留周期为 30 天。
- FR-CLIP-8：系统必须提供清空剪贴板历史能力。
- FR-CLIP-9：系统必须提供暂停/恢复剪贴板记录能力。
- FR-CLIP-10：系统不做敏感内容自动过滤。
- FR-CLIP-11：系统必须明确说明剪贴板数据仅本地保存。
- FR-CLIP-12：MVP 必须支持剪贴板历史置顶。
- FR-CLIP-13：置顶内容必须显示在剪贴板列表顶部。
- FR-CLIP-14：置顶内容不受自动过期清理影响。
- FR-CLIP-15：MVP 不支持收藏分类和标签系统。
- FR-CLIP-16：剪贴板历史项点击或回车后的默认动作必须是复制到系统剪贴板。
- FR-CLIP-17：MVP 不自动向当前前台应用发送粘贴动作。
- FR-CLIP-17a：MVP 剪贴板历史页面暂不实现右键菜单。
- FR-CLIP-17b：用户必须可以通过键盘选择剪贴板历史项，并按回车将该内容放回系统剪贴板。
- FR-CLIP-18：剪贴板历史页面必须提供类型筛选：全部、文本、图片、文件。
- FR-CLIP-19：剪贴板历史项必须显示类型标识。
- FR-CLIP-19a：剪贴板历史页面必须提供独立搜索框。
- FR-CLIP-19b：剪贴板历史页面搜索框只搜索剪贴板历史，不搜索其他来源。
- FR-CLIP-19c：剪贴板历史页面搜索必须在输入时即时触发。
- FR-CLIP-19d：剪贴板历史页面搜索必须使用 debounce 避免频繁查询。
- FR-CLIP-19e：默认无搜索时置顶项显示在最上方，其余按复制时间倒序。
- FR-CLIP-19f：搜索时优先显示置顶匹配项，其余按匹配度和时间综合排序。
- FR-CLIP-20：图片剪贴板历史必须保存原图，用于恢复到系统剪贴板。
- FR-CLIP-21：图片剪贴板历史必须生成缩略图，用于列表快速展示。
- FR-CLIP-22：图片历史的自动清理必须遵循剪贴板保留时间策略。
- FR-CLIP-23：MVP 必须在设置页或剪贴板历史页显示剪贴板历史存储占用。
- FR-CLIP-24：MVP 不按存储容量自动清理剪贴板历史。
- FR-CLIP-25：显示存储占用的位置必须提供清空历史入口或跳转到清空历史操作。
- FR-CLIP-26：剪贴板历史保留时间必须提供预设：7 天、30 天、90 天、永久。
- FR-CLIP-27：默认保留时间必须为 30 天。
- FR-CLIP-28：MVP 不支持输入任意自定义保留天数。
- FR-CLIP-29：清空全部剪贴板历史必须显示二次确认对话框。
- FR-CLIP-30：二次确认文案必须明确提示"此操作不可撤销"。
- FR-CLIP-31：删除单条剪贴板历史 MVP 可以不做二次确认。
- FR-CLIP-32：剪贴板历史必须基于内容 hash 去重。
- FR-CLIP-33：重复复制相同内容时不新增记录，只更新原记录的复制时间。
- FR-CLIP-34：去重后的记录必须按更新后的复制时间重新排序。
- FR-CLIP-35：重复复制已置顶的内容时更新复制时间但保持置顶状态。
- FR-CLIP-36：MVP 必须支持保存富文本剪贴板的纯文本内容和 RTF/HTML 原始格式数据。
- FR-CLIP-37：剪贴板历史展示和搜索必须使用纯文本内容。
- FR-CLIP-38：放回系统剪贴板时必须尽量恢复原始 RTF/HTML 格式。
- FR-CLIP-39：原始富文本格式恢复失败时必须降级为纯文本复制，不得导致操作失败或崩溃。
- FR-CLIP-40：剪贴板监听必须基于 `NSPasteboard.general.changeCount` 轮询实现。
- FR-CLIP-41：MVP 必须采用自适应轮询：默认/活跃 500ms，长时间无变化后降到 2s，检测到变化后恢复 500ms。
- FR-CLIP-42：剪贴板监听必须在后台常驻运行。
- FR-CLIP-43：剪贴板历史结构化数据必须持久化存储（当前实现见 §10.6）。
- FR-CLIP-44：图片原图、缩略图、RTF/HTML 原始格式等较大对象必须存储在文件系统中，并由数据库保存资源路径或标识。
- FR-CLIP-45~59：内存索引、大对象目录结构、UUID 文件命名、内容 hash 去重、资源缺失容错等细节保持 v1.0 已交付实现，本次不变更。

### 7.5 截图 ✅（v1.2 补全全屏快捷键）

- FR-SHOT-1：系统必须支持区域截图。
- FR-SHOT-2：系统必须支持全屏截图。
- FR-SHOT-3：系统必须支持窗口截图。
- FR-SHOT-4：截图完成后必须进入预览状态并显示工具栏。
- FR-SHOT-5：工具栏必须包含复制、保存、标注工具、取消。
- FR-SHOT-6：工具栏不提供抽象"完成"按钮。
- FR-SHOT-7：标注必须支持矩形框、箭头、文字、马赛克（mosaic）、撤销/重做。blur 独立模糊工具不在 v1.2 范围（见 FR-ANNOTATE-BLUR）。
- FR-SHOT-8：复制必须复制当前截图及其标注结果。
- FR-SHOT-9：保存必须保存当前截图及其标注结果。
- FR-SHOT-10：截图默认保存目录必须为 `~/Desktop`（与 macOS 原生截图、Raycast 等主流工具默认一致），设置页可改；D-032 同步修订。
- FR-SHOT-11：首次保存截图时，如果默认目录不存在，系统必须自动创建。
- FR-SHOT-12：设置页必须允许用户修改截图保存目录。
- FR-SHOT-13：截图保存文件名必须默认使用时间戳格式 `Screenshot yyyy-MM-dd HH.mm.ss.png`。
- FR-SHOT-14：MVP 截图保存格式只支持 PNG。
- FR-SHOT-15：JPG、WebP、压缩质量设置不进入 MVP。
- FR-SHOT-16：MVP 标注样式必须提供少量预设：颜色、线宽、文字大小。
- FR-SHOT-17：标注颜色预设必须至少包含红、黄、蓝、绿、白、黑。
- FR-SHOT-18：标注线宽预设必须包含细、中、粗。
- FR-SHOT-19：文字大小预设必须包含小、中、大。
- FR-SHOT-20：MVP 不提供完整颜色选择器、字体选择器和透明度设置。
- FR-SHOT-21~25：截图流程中 ESC 始终取消当前流程（区域/窗口选择取消截图，预览丢弃并关闭，标注中退出）。
- FR-SHOT-26：截图工具栏点击复制后，截图结果必须写入系统剪贴板。
- FR-SHOT-27：截图复制后必须进入剪贴板历史，遵循普通图片剪贴板记录逻辑。
- FR-SHOT-28：截图工具栏点击保存后，只保存文件，不额外写入剪贴板历史。
- FR-SHOT-29：MVP 不实现截图历史页。
- FR-SHOT-30：截图保存成功后必须显示轻提示。
- FR-SHOT-31：轻提示文案必须让用户知道截图已保存，可包含保存目录信息。
- FR-SHOT-32：MVP 不要求在保存成功提示中提供"在 Finder 中显示"按钮。
- **FR-SHOT-FULLSCREEN 🔧（v1.2 补齐）**：全屏截图必须提供独立全局快捷键，默认 `⌃⌥⌘3`（与 macOS 系统默认 `⇧⌘3` 错开，避免冲突）；用户可在设置的快捷键区重新绑定；注册冲突时提示重录。修复此前全屏截图只能走命令面板、无全局热键的缺口。
- **FR-ANNOTATE-BLUR ⏳（V1.x 规划）**：blur 独立模糊工具列入 V1.x 路线图；v1.2 标注工具只提供 mosaic 马赛克，不声明"模糊"能力，避免与实际实现不符。

### 7.6 内置命令 ✅

- FR-CMD-1：MVP 只允许内置白名单命令。
- FR-CMD-2：系统不得允许用户在搜索框直接执行任意 shell。
- FR-CMD-3：MVP 不支持用户自定义 shell 命令。
- FR-CMD-4：中风险命令执行前必须显示确认。
- FR-CMD-5：MVP 不提供关机、重启、注销、删除文件、杀进程、sudo、任意 shell。
- FR-CMD-6：切换深色/浅色模式不需要确认。
- FR-CMD-7：MVP 需要确认的内置命令包括：清空剪贴板历史、重启 Finder、重启 Dock。
- FR-CMD-8：每个内置命令必须维护中英文别名。
- FR-CMD-9：无论当前界面语言，用户输入中文或英文关键词都必须能搜索到对应内置命令。
- FR-CMD-10：内置命令必须支持中文拼音索引和拼音首字母搜索。

### 7.7 管理中心与菜单栏 ✅（v1.2 修订版本号与发布相关项）

- FR-UI-1：App 必须以菜单栏 App 形态运行。
- FR-UI-2：App 默认不显示 Dock 图标。
- FR-UI-3：菜单栏必须包含打开搜索、剪贴板、截图、设置、关于、退出。
- FR-UI-4：菜单栏"截图"点击后必须直接进入区域截图。
- FR-UI-5：管理中心必须包含首页 / 概览、剪贴板历史、设置、权限。
- FR-UI-6：App 完成首次 Onboarding 后必须默认启用开机启动。
- FR-UI-7：设置页必须提供关闭开机启动的选项。
- FR-UI-8：关于页必须按发布级产品设计，包含应用名称（清羽 Qingyu）、版本号、构建号、官网/项目主页、隐私政策、检查更新、反馈入口、第三方许可和版权信息。
- **FR-UI-ABOUT-VERSION 🔧（v1.2 修）**：关于页显示的版本号必须与 Xcode `MARKETING_VERSION` 及 `Info.plist` 的 `CFBundleShortVersionString` 完全一致，v1.2 统一显示为 `1.2.0`。修复此前工程版本停留在 `0.1.0`、关于页/CHANGELOG 三源不一致的问题（见 FR-UI-36、D-108）。
- FR-UI-9：MVP 必须提供"检查更新"能力。
- FR-UI-10：MVP 的"检查更新"发现新版本后打开项目主页或下载页，由用户手动下载安装。
- FR-UI-11：MVP 不集成完整自动下载、自动安装和重启更新流程。
- FR-UI-12：MVP 实际分发渠道必须支持 GitHub Release。
- FR-UI-13：MVP 必须准备简单官网或项目主页，用于承载下载入口、隐私说明和反馈入口。
- FR-UI-14：MVP 不进入 Mac App Store。
- FR-UI-15："检查更新"必须打开官网下载页或 GitHub Release 页面。
- FR-UI-15a~15c：官网/项目主页采用标准产品页结构，包含产品名称、Slogan、核心功能、截图/演示、下载按钮、版本记录、隐私政策、反馈邮箱、FAQ，并解释必要权限用途。
- **FR-UI-16 🔧（v1.2 改）**：v1.2 起必须完成 Developer ID 签名。不再保留"MVP 阶段暂不强制签名"的过渡表述。
- **FR-UI-17 🔧（v1.2 改）**：v1.2 起必须完成 Apple Notarization 公证（notarytool），并 staple 票据。
- FR-UI-18：MVP 必须提供隐私政策文档或页面。
- FR-UI-19：隐私政策必须说明剪贴板数据仅本地保存、截图仅本地处理、不上传、不同步、不训练、如何关闭记录、如何清空数据。
- FR-UI-20：关于页必须提供隐私政策入口。
- FR-UI-21~24：错误/崩溃反馈必须由用户显式点击并确认后才可上报，展示数据范围并允许取消；隐私政策说明其数据范围与用户控制方式。
- FR-UI-25：MVP 错误/崩溃反馈渠道必须优先使用邮件反馈，目标邮箱为 qingyu_freeabyss@163.com。
- FR-UI-26：邮件反馈可预填应用版本、macOS 版本、错误摘要和用户补充说明。
- FR-UI-27：MVP 不要求提供 GitHub Issue 反馈入口和内置反馈后端。
- FR-UI-28：MVP 必须支持中文和英文两种界面语言。
- FR-UI-29：默认语言必须跟随系统语言。
- FR-UI-30：核心 UI、Onboarding、权限说明、隐私说明、错误提示和关于页必须完成中英文文案，且品牌名统一为清羽 / Qingyu。
- FR-UI-30a：App 图标采用简洁抽象效率工具风格，不绑定单一功能。
- FR-UI-30b：菜单栏图标必须使用单色 template 风格，适配深色/浅色模式。
- FR-UI-31：设置页必须提供语言切换：跟随系统、简体中文、English。
- FR-UI-32：语言默认选项必须为"跟随系统"。
- FR-UI-33：如果运行时切换语言实现复杂，MVP 可以提示用户重启后生效。
- FR-UI-34：MVP 最低支持系统版本必须为 macOS 12 Monterey；发行包必须为通用二进制，同时支持 Apple 芯片与 Intel 芯片。
- FR-UI-35：如果某些功能在 macOS 12 上 API 受限（例如 macOS 13 起可用的 `SMAppService`），必须提供兼容分支或明确降级提示。
- **FR-UI-36 🔧（v1.2 修）**：版本号必须三源一致——Xcode `MARKETING_VERSION=1.2.0`、`Info.plist` `CFBundleShortVersionString=1.2.0`、`CHANGELOG.md` 补全 v1.0.0 / v1.0.1 / v1.1.0 / v1.2.0 条目。任何一处不一致视为发布阻塞（见 D-108）。
- **FR-UI-37 🔧（v1.2 改，PERM-APPLE-EVENTS）**：见 §7.9。

**v1.2 设计语言相关新增条目（细则见第 9 章）：**

- **FR-UI-DESIGN-TOKENS 🔧（v1.2 新增）**：必须建立统一 Design Token 层（`JadeColor` / `JadeRadius` / `JadeSpace` / `JadeFont` / `JadeShadow` / `JadeMaterial` 等枚举或扩展），Light/Dark 双模式取值按 §9.2；界面禁止散落硬编码颜色/圆角/间距/字号。
- **FR-UI-COMMAND-BAR 🔧（v1.2 新增）**：命令栏必须按 §9.4 P-01 规范实现（居中浮层、20px 圆角、ultraThinMaterial、56px 输入框、44px hint bar、`⎋` 关闭、空态显示最近使用+收藏）。
- **FR-UI-CLIPBOARD-WINDOW 🔧（v1.2 新增）**：剪贴板历史管理窗口必须按 §9.4 P-02 实现（独立 NSWindow、两栏 NavigationSplitView、64px 行、hover 操作、预览 Sheet、swipe action、底部状态栏）。
- **FR-UI-SETTINGS-WINDOW 🔧（v1.2 新增）**：设置窗口必须按 §9.4 P-03 实现（独立窗口、200px 侧栏、含概览/剪贴板/快捷键/截图/搜索源/外观/权限/数据/更新/关于/反馈分组；数据页含清空/导出/打开目录）。
- **FR-UI-SCREENSHOT-OVERLAY 🔧（v1.2 新增）**：截图区域选择叠层必须按 §9.4 P-04 实现（0.4 遮罩、十字准星、选区描边+尺寸 pill、窗口高亮模式、`⎋` 取消）。
- **FR-UI-SCREENSHOT-ANNOTATE 🔧（v1.2 新增）**：截图预览与标注必须按 §9.4 P-05 实现（居中 NSPanel、顶部/底部工具 pill、六色 swatch、三档线宽、撤销重做、blur 禁用并标注 v1.3）。
- **FR-UI-ONBOARDING 🔧（v1.2 新增）**：Onboarding 必须按 §9.4 P-06 实现（单屏 720×520；屏幕录制主按钮触发 TCC；辅助功能"稍后再说"不强制；开始使用按钮的可用条件按 P-06）。
- **FR-UI-HOTKEYS 🔧（v1.2 新增）**：快捷键体系必须按 §9.6 总表实现，冲突在设置页行内提示并提供一键替换。
- **FR-UI-EMPTY-STATES 🔧（v1.2 新增）**：空态 / 错误态必须按 §9.7 的图标与文案规范实现。
- **FR-UI-A11Y 🔧（v1.2 新增）**：无障碍必须按 §9.8 实现（accessibilityLabel、Tab 遍历、装饰图标隐藏、WCAG AA、VoiceOver、动态字体、尊重系统无障碍设置）。
- **FR-UI-I18N 🔧（v1.2 新增）**：国际化必须按 §9.9 实现（简中 + 英文、xcstrings、locale 格式化、长字符串布局兼容）。
- **FR-UI-ASSETS 🔧（v1.2 新增）**：品牌资产必须按 §9.10 交付（AppIcon 全尺寸自定义、菜单栏双态模板图标、Onboarding 大图、About 96×96；dmg 背景可上线前补）。

### 7.8 Onboarding 与权限 ✅（v1.2 改为按需申请辅助功能）

- FR-ONBOARD-1：系统必须提供完整首次启动 Onboarding。
- FR-ONBOARD-2：Onboarding 必须解释快捷键、剪贴板默认开启、本地保存和必要权限。
- FR-ONBOARD-3：MVP 必要权限（屏幕录制）必须在 Onboarding 阶段完成。
- FR-ONBOARD-4：用户拒绝屏幕录制权限时，系统必须停留在权限引导页。
- FR-ONBOARD-5：权限引导页必须提供打开系统设置、重新检测、退出应用等操作。
- **FR-ONBOARD-6 🔧（v1.2 改）**：Onboarding 顺序调整为：欢迎、搜索入口与快捷键、剪贴板历史与本地隐私说明、截图与屏幕录制权限、（辅助功能改为"仅说明用途、不强制申请"）、开机启动、完成。
- FR-ONBOARD-7：每个权限请求必须在对应功能说明之后出现。
- **FR-ONBOARD-ACCESSIBILITY-ONDEMAND 🔧（v1.2 改，取代原 FR-ONBOARD-8/9）**：
  - Onboarding 不再强制勾选/申请辅助功能权限，也不因未授予辅助功能而阻断完成。
  - Onboarding 仅用一屏说明辅助功能"会被哪些未来能力用到"（自动粘贴、模拟快捷键、控制其他 App、窗口控制等）。
  - 当用户**首次真正触发**需要辅助功能的能力时，才弹出 TCC 申请与说明 Alert（按需申请）。
  - 理由：MVP 阶段辅助功能几乎未被使用（全局热键由 KeyboardShortcuts 库实现，无需辅助功能），强制申请是转化风险。
- FR-ONBOARD-10：屏幕录制权限必须在 Onboarding 阶段完成，用于截图功能。
- FR-ONBOARD-11：如果用户未授予屏幕录制权限，则不能完成 Onboarding 进入完整产品体验（截图能力依赖）。
- FR-ONBOARD-12：剪贴板历史默认开启，但 Onboarding 必须要求用户显式确认已知晓该行为。
- FR-ONBOARD-13：剪贴板确认文案必须说明：默认开启、数据仅本地保存、可随时暂停记录或清空历史。
- FR-ONBOARD-14：MVP 的剪贴板 Onboarding 步骤不提供复杂配置开关。
- FR-ONBOARD-15：Onboarding 中必须尝试注册默认快捷键 `⌥ Space`。
- FR-ONBOARD-16：如果默认快捷键注册失败或检测到冲突，必须要求用户重新录制快捷键。
- FR-ONBOARD-17：用户必须设置一个可成功注册的快捷键后，才能完成 Onboarding。
- FR-ONBOARD-18（skip）：Onboarding 必须提供"跳过设置"入口，点击后弹二次确认 Alert；确认后进入菜单栏常驻状态（v1.1 已交付）。
- **FR-ONBOARD-19 🔧（v1.2 验证，AC-6）**：应用重启后，若已完成或跳过过 Onboarding，必须不再重弹 Onboarding。v1.2 必须端到端验证闭环。
- **FR-ONBOARD-20 🔧（v1.2 验证，AC-7）**：按需权限申请的说明 Alert 必须在首次触发相关能力时正确弹出，并可打开系统设置。v1.2 必须端到端验证闭环。

### 7.9 分发与系统权限 🔧（v1.2 改，FR-PERM-APPLE-EVENTS）

- **FR-PERM-APPLE-EVENTS-1**：v1.2 关闭 App Sandbox（`com.apple.security.app-sandbox` 移除/置否），保留 Hardened Runtime 及必要 entitlements，以保证 AppleEvents 类命令（重启 Finder、重启 Dock、切换深浅色）可靠执行，不再静默失败。
- **FR-PERM-APPLE-EVENTS-2**：产品明确不上 Mac App Store，走 GitHub Releases 分发，因此可以合理关闭 Sandbox。
- **FR-PERM-APPLE-EVENTS-3**：发布要求为 Developer ID 签名 + notarytool 公证 + staple + GitHub Releases，非 MAS 分发（见 §11.4）。
- **FR-PERM-APPLE-EVENTS-4**：首次触发需要控制其他 App 的 AppleEvents 命令时，系统会弹出 Automation 授权，产品应有对应说明文案。

### 7.10 数据备份与迁移 ⏳（v1.2 不做导出，FR-DATA-EXPORT-BACKUP）

- **FR-DATA-EXPORT-BACKUP-1**：数据存储位置必须明确——剪贴板结构化数据、设置、使用统计、黑名单存于 `~/Library/Application Support/Qingyu/`（沿用 `com.freeabyss.qingyu` 容器路径，因 Bundle ID 不变），大对象（图片原图/缩略图/RTF）存于该目录下 `Clipboard/Images/`、`Clipboard/Thumbnails/`、`Clipboard/RichText/`。
- **FR-DATA-EXPORT-BACKUP-2**：跨版本升级必须采用 Core Data lightweight migration，保证用户升级到 v1.2 后历史数据不丢失。
- **FR-DATA-EXPORT-BACKUP-3**：数据目录必须与 Time Machine 兼容（不设置排除标志），随系统备份。
- **FR-DATA-EXPORT-BACKUP-4**：主动导出/备份为用户操作的能力（导出剪贴板历史/设置）列入 V1.x，v1.2 不实现，但本章预留说明，避免用户误以为已支持。

### 7.11 快捷键体系

统一说明清羽的全局热键、面板内快捷键与用户可自定义范围。

**全局热键（系统级，App 未激活时也生效）：**

| 功能 | 默认快捷键 | 可自定义 | 状态 |
|------|-----------|---------|------|
| 呼出统一搜索 | `⌥ Space` | 是 | ✅ |
| 区域截图 | `⇧⌃⌘4`（与 macOS 原生 `⇧⌘4` 对齐，增加 control 避免冲突） | 是 | ✅（v1.2 修正默认值，原 `⌃⌥⌘4` 为示例值） |
| 窗口截图 | `⇧⌃⌘5`（与 macOS 原生 `⇧⌘5` 对齐，增加 control 避免冲突） | 是 | ✅（v1.2 修正默认值，原 `⌃⌥⌘5` 为示例值） |
| 全屏截图 | `⌃⌥⌘3` | 是 | 🔧 v1.2 补齐 |

> 全局热键统一由 KeyboardShortcuts 库实现，不依赖辅助功能权限。截图热键默认值均加 `⌃⌥⌘` 修饰以避开 macOS 系统截图默认键，确切默认组合以设置页展示为准；冲突时提示重录。

**搜索面板内快捷键：**

| 按键 | 行为 |
|------|------|
| `↑` / `↓` | 上下选择结果 |
| `⏎` | 执行当前结果主动作 |
| `ESC` | 关闭搜索框 |
| 再次按 `⌥ Space` | 关闭搜索框 |

**管理中心/剪贴板页快捷键（沿用系统惯例）：**

| 按键 | 行为 |
|------|------|
| `⌘C` | 将选中剪贴板历史项复制回系统剪贴板 |
| `⌘A` | 全选（列表内）|
| `⌘,` | 打开设置 |
| `⌘W` | 关闭当前窗口 |

**用户可自定义范围：**

- MVP 允许用户重绑全部全局热键（搜索、区域/窗口/全屏截图）。
- 面板内导航/执行键（↑↓⏎ESC）为固定行为，MVP 不开放自定义。
- 快捷数字键（`⌘1`~`⌘9`）为 V1.x 预留，MVP 不实现。

### 7.12 空态与错误态设计

明确各状态下的产品行为，避免出现空白页或无反馈：

| 状态 | 产品行为 |
|------|---------|
| 搜索空输入 | 只显示输入提示占位，不展示任何推荐/最近内容（FR-SEARCH-14/15）。 |
| 搜索无匹配结果 | 显示"未找到匹配结果"提示，保留输入框。 |
| 剪贴板历史为空 | 显示空态插画/文案："暂无剪贴板历史"，说明复制内容后会自动记录。 |
| 首次启动无数据 | 完成 Onboarding 后进入空态，引导用户尝试 `⌥ Space`。 |
| 屏幕录制权限被拒绝 | 截图触发时提示权限缺失，提供"打开系统设置"入口，不崩溃。 |
| 辅助功能权限被拒绝 | 仅在用户触发需要它的能力时提示；未触发不打扰。 |
| 文件搜索索引进行中 | 若首次索引耗时，显示"正在建立文件索引…"提示，不阻塞其他来源结果。 |
| 加载失败 / 资源丢失 | 剪贴板资源文件缺失时显示"资源已丢失"，复制/恢复时提示失败原因（FR-CLIP-57/58）。 |
| 快捷键注册冲突 | 提示冲突并要求重新录制（FR-ONBOARD-16、FR-SHOT-FULLSCREEN）。 |

### 7.13 卸载与数据清理

- FR-UNINSTALL-1：用户将清羽拖入废纸篓后，App 主体被删除，但用户数据默认保留在 `~/Library/Application Support/Qingyu/`（Core Data store + 大对象目录）与偏好设置中。
- FR-UNINSTALL-2：设置页必须提供"清空所有数据"入口，一键删除剪贴板历史、使用统计、黑名单及大对象文件，并显示二次确认（不可撤销）。
- FR-UNINSTALL-3：隐私政策/FAQ 必须说明数据目录位置及手动彻底清理方式（删除 App + 删除 Application Support 目录）。
- FR-UNINSTALL-4：MVP 不内置"卸载器"，也不在卸载时自动清理数据（避免误删备份）。

### 7.14 无障碍（Accessibility / VoiceOver）

> 此处"Accessibility"指屏幕阅读器等无障碍能力，与第 7.8 节 macOS 辅助功能 TCC 权限是不同概念。

- FR-A11Y-1：核心可交互控件（搜索框、结果项、按钮、开关、列表项）必须具备可读的 accessibility label 或提示，供 VoiceOver 朗读。
- FR-A11Y-2：核心操作必须可全键盘完成：搜索、选择、执行、关闭、剪贴板复制回、设置切换。
- FR-A11Y-3：菜单栏图标与菜单项必须有可读名称。
- FR-A11Y-4：全面的屏幕阅读器优化（动态朗读顺序、复杂控件描述）作为 V1.x 持续改进项；v1.2 保证基础可用。

---
## 8. MVP 内置命令白名单

MVP 支持以下 14 条命令：

1. 打开系统设置。
2. 打开本应用设置。
3. 打开下载目录。
4. 打开应用程序目录。
5. 打开桌面目录。
6. 区域截图。
7. 全屏截图。
8. 窗口截图。
9. 清空剪贴板历史（需要确认）。
10. 暂停 / 恢复剪贴板记录。
11. 检查权限状态。
12. 重启 Finder（需要确认）。
13. 重启 Dock（需要确认）。
14. 切换深色 / 浅色模式。

**执行路径说明（v1.2 关闭 Sandbox 后）：**

- 命令 6–8（截图）走截图子系统，依赖屏幕录制权限。
- 命令 12–14（重启 Finder / 重启 Dock / 切换外观）依赖 AppleEvents。v1.2 关闭 App Sandbox 后，这些命令通过 AppleEvents / NSAppleScript 可靠执行；首次控制其他 App 时可能触发 Automation 授权，产品应有说明文案（见 FR-PERM-APPLE-EVENTS）。
- 命令 1–5、9–11 为本地文件/应用内操作，不依赖 AppleEvents。

MVP 明确不支持：关机、重启系统、注销、删除文件、杀进程、sudo、任意 shell、搜索框直接执行用户输入命令。

---

## 9. 设计语言与交互

> 本章定义清羽 Qingyu v1.2 的视觉设计系统、交互范式、页面规范与通用组件，作为后续架构与开发的直接依据。所有 Design Token 以可被代码映射的形式给出；具体命名/枚举实现由架构文档承接（见 `doc/architecture/design.md`）。

### 9.1 设计哲学

- **现代极简 Pro 工具风**：参考 Raycast / Arc 的克制美学，不拟物、不过度装饰；界面服务于效率，视觉退居其后。
- **本地优先、隐私优先、键盘优先**：所有数据默认本地保存；所有主要功能都能仅靠键盘完成，鼠标操作作为补充。
- **明暗双模式跟随系统**：默认跟随 macOS 外观（可在外观页覆盖），Light/Dark 双套 Token 一一对应。
- **系统一致性**：优先使用系统语义色、系统材质、SF Symbols 与系统字体，让清羽"像 macOS 原生的一部分"。

### 9.2 Design Tokens

以下 Token 为设计与开发的共同契约，Light/Dark 双模式取值如下（架构层映射为 `JadeColor` / `JadeRadius` / `JadeSpace` / `JadeFont` / `JadeShadow` / `JadeMaterial` 等，见 FR-UI-DESIGN-TOKENS）。

#### 9.2.1 品牌色

| Token | 说明 | Light | Dark |
|-------|------|-------|------|
| Jade 500 | 主色 | `#0A9488` | `#2DD4BF` |
| Jade 600 | 深主色 / hover | `#087A70` | `#14B8A6` |
| Jade 50 | 主色底（选中态/浅底） | `#E6F7F5` | `#0D3D39` |

- **语义色**：直接走系统色，不自定义——`systemGreen` / `systemRed` / `systemOrange` / `systemYellow` / `systemBlue` / `systemIndigo` / `systemPurple` / `systemPink` / `systemGray`。用于成功/危险/警告/信息等语义反馈，自动适配深浅色与增强对比度。

#### 9.2.2 中性色

| Token | 系统映射 | Light | Dark |
|-------|---------|-------|------|
| Text Primary | `NSColor.labelColor` | `#0D0D0D` | `#F5F5F7` |
| Text Secondary | `NSColor.secondaryLabelColor` | `#4A4A4A` | `#A1A1A6` |
| Text Tertiary | `NSColor.tertiaryLabelColor` | `#8E8E93` | `#6C6C70` |
| Surface 1 | `NSColor.windowBackgroundColor` | `#FFFFFF` | `#1E1E1E` |
| Surface 2 | `NSColor.controlBackgroundColor` | `#F5F5F7` | `#2A2A2A` |
| Surface 3 | hover / pressed | `#ECECEE` | `#3A3A3C` |
| Border | 分隔线/描边 | `rgba(0,0,0,0.08)` | `rgba(255,255,255,0.08)` |
| Overlay | 全屏遮罩 | `rgba(0,0,0,0.4)` | `rgba(0,0,0,0.4)` |

> 中性色优先绑定系统动态色（`labelColor` 等），上表十六进制值为设计基准/降级取值，保证与系统"增强对比度""降低透明度"一致。

#### 9.2.3 圆角（radius）

| Token | 值 | 用途 |
|-------|----|------|
| radius-sm | 6px | 小徽章 / 小按钮 |
| radius-md | 8px | 按钮 / 输入框 / chip |
| radius-lg | 12px | 卡片 / 行项 |
| radius-xl | 16px | 窗口 / panel |
| radius-2xl | 20px | command bar / overlay pill |

> 所有圆角统一使用 `.continuous`（苹果连续曲率），不使用直角矩形圆角。

#### 9.2.4 间距（space，4px 基准）

| Token | 值 |
|-------|----|
| space-1 | 4px |
| space-2 | 8px |
| space-3 | 12px |
| space-4 | 16px |
| space-6 | 24px |
| space-8 | 32px |

#### 9.2.5 字号（SF Pro）

| Token | 规格 | 用途 |
|-------|------|------|
| display | 40pt bold | 启动页 / Onboarding 大 logo |
| title-1 | 28pt semibold | 窗口标题 |
| title-2 | 22pt semibold | section 大标题 |
| title-3 | 17pt semibold | 卡片标题 / 结果首行 |
| body | 13pt regular | 主阅读正文 |
| callout | 12pt regular | 辅助说明 |
| subhead | 11pt medium | 副标题 / 元信息 / breadcrumb |
| caption | 10pt medium | 快捷键提示 / 徽章 / tab 计数 |
| command-bar-input | 20pt regular | 命令栏输入框 |

> 字体统一使用系统 SF Pro；正文字号跟随系统"字体大小"设置动态缩放（见 9.8）。

#### 9.2.6 阴影（shadow）

| Token | 值 |
|-------|----|
| shadow-sm | `0 1px 2px rgba(0,0,0,0.06)` |
| shadow-md | `0 4px 16px rgba(0,0,0,0.10)` |
| shadow-lg | `0 8px 32px rgba(0,0,0,0.18), 0 0 0 1px Border` |
| shadow-xl | `0 24px 64px rgba(0,0,0,0.28), 0 0 0 1px Border`（command bar 专用） |

#### 9.2.7 材质（NSVisualEffectMaterial / SwiftUI `.material`）

| 场景 | 材质 |
|------|------|
| Command Bar | `.ultraThinMaterial`（HUD 毛玻璃） |
| 工具条 / pill | `.ultraThinMaterial` |
| 管理窗口 | 默认 `windowBackground`（可在外观页切换材质） |
| Sheet / 弹窗 | `.thinMaterial` |
| 全屏遮罩 | black opacity 0.4 |

#### 9.2.8 动效（motion）

| Token | 规格 | 用途 |
|-------|------|------|
| spring | response 0.22, damping 0.8 | 面板弹出 |
| ease-out | 150ms | 列表切换 / hover |
| toast | slide + fade 200ms in/out | 轻提示 |

> 所有动画必须尊重系统"减弱动态效果"设置（`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`）：开启时降级为无位移的即时/淡入淡出。

#### 9.2.9 图标（iconography）

- 统一使用 **SF Symbols 5+**，weight 统一 `.medium`。
- App Icon 与菜单栏 `statusItem` 使用清羽 glyph（玉色鸟剪影）；菜单栏图标为单色 template，适配深浅色。
- 结果类型图标底色规则：透明度 15% 同色底 + 同色前景 glyph。

| 结果类型 | 底色 |
|---------|------|
| app | blue |
| command | purple |
| calculator | jade |
| settings | indigo |
| clipboard | orange |
| file | green |
| conversion | pink |

### 9.3 核心交互范式

- **全局唤起**：`⌥ Space` 唤起 Command Bar（可在设置重绑）。
- **Command Bar 定位**：屏幕居中，y-offset 120px；宽 760px；高度随结果动态 128–560px。
- **结果列表**：行高 44px；左侧 32×32 类型图标（圆角 radius-md 8px）；右侧显示类型 badge + `⏎` 提示。
- **选中态**：Jade 50 底色 + Jade 500 图标；行圆角 radius-lg（12px）；内边距 4px 8px。
- **键盘操作**：`↑` `↓` 选择、`⏎` 执行、`⌘1`–`⌘6` 切换搜索源、`⌘C` 复制、`⌘,` 打开设置、`⎋` 关闭、`⌘K` 清空输入。
- **命令栏空态**：显示"最近使用"（最近 5 条）+ "收藏"（类 Raycast 首页）。
- **危险命令二次确认**：清空剪贴板 / 重启 Finder / 重启 Dock 等触发二次确认弹窗，弹窗内命令名以红色强调。

> 注：命令栏空态展示"最近使用+收藏"属 v1.2 交互升级（见 D-120），与 §7.1 中"MVP 搜索框空输入不展示推荐"的旧约束存在演进关系——空态首页展示的是最近使用/收藏入口而非搜索推荐结果，以引导用户上手；具体取舍以本章为准。

### 9.4 页面规范

共 6 个主要页面 + 3 个工具浮层。每页写明结构、尺寸与关键交互。

#### P-01 Command Bar（命令栏，核心）

- 20px 圆角（radius-2xl）、shadow-xl、`.ultraThinMaterial`。
- 顶部输入框 56px 高、水平 padding 20px，左侧放大镜图标，placeholder："搜索应用、命令、文件、剪贴板…"。
- 结果组之间以 1px 分隔线（Border 色）分隔。
- 计算器 / 单位换算命中时，答案固定显示在结果列表第一行。
- 文件搜索结果显示：文件名 + 路径 + 大小 + 修改时间。
- 底部 44px 高 hint bar：caption 字号、tertiary 字色、居中显示常用快捷键提示。
- 右上角无关闭按钮（`⎋` 关闭）。

#### P-02 剪贴板历史管理窗口

- 独立 `NSWindow`，最小 880×600，可自由缩放。
- 两栏 `NavigationSplitView`：侧栏 180px + 主列表。
- 侧栏：过滤项（全部 / 文本 / 图片 / RTF / 文件 / 置顶 / 收藏）+ 按时间分组（今天 / 昨天 / 更早）+ 底部操作（清空全部 / 设置）。
- 主列表：`LazyVStack`，行高 64px；每行 40×40 缩略图（图/文/RTF/文件 icon）+ 主标题 + 副信息（类型 · 大小 · 时间）；hover 时右侧浮现 4 个 28×28 IconButton（置顶 / 复制 / 预览 / 删除）。
- 点击行 / `⏎` 复制并关闭窗口；`空格` / `⌘Y` 打开预览 Sheet（图片缩放 / 长文本滚动 / 文件信息）。
- 支持 swipe action：右滑收藏、左滑删除。
- 底部状态栏：总条数 / 存储占用 / 保留期。
- `⌘F` 聚焦搜索框。

#### P-03 设置 / 管理中心

- 独立 `NSWindow`（Settings scene 亦可，但为统一体验采用独立窗口，经 `⌘,` 或命令栏打开），最小 920×640。
- `NavigationSplitView` 侧栏 200px，分组：
  - 概览（Overview）
  - 剪贴板（Clipboard）
  - 快捷键（Shortcuts）
  - 截图（Screenshot）
  - 搜索源（Search Sources）
  - 外观（Appearance）
  - 权限（Permissions）
  - 数据（Data）—— 含"清空所有数据""导出数据""打开数据目录"按钮（v1.2 新增；导出能力本体列入 V1.x，见 FR-DATA-EXPORT-BACKUP）
  - 更新（Updates）
  - 关于（About）
  - 反馈（Feedback）
- **概览页**：应用图标 + 版本 + 版权，下方 2×N stat cards（使用天数 / 日均启动 / 剪贴数 / 截图数），常用开关（开机启动 / 外观 / 更新提醒）。
- **快捷键页**：每个命令一行显示 HotkeyRecorder；冲突时行内红色警告 + 一键替换按钮。
- **关于页**：图标 96×96、radius-xl；版本号必须与 `MARKETING_VERSION` 一致（见 FR-UI-ABOUT-VERSION）。
- **权限页**：每个权限一行，标题 + 状态（绿点 / 橙三角）+ 按钮（打开系统设置 / 重试）。

#### P-04 截图区域选择（Screenshot Overlay）

- 全屏遮罩 black opacity 0.4，十字准星。
- 拖拽选区：白色 2pt 描边、半透明白色填充；尺寸标签居中 / 跟随鼠标，黑底白字 caption、pill 圆角 radius-md，显示 W×H + 坐标。
- 窗口截图模式：hover 窗口整体高亮（Jade 20% 透明填充 + Jade 2pt 描边），窗口下方显示窗口名 pill。
- `⎋` 取消；拖拽完成后进入 P-05 预览。

#### P-05 截图预览 + 标注

- 屏幕中央 `NSPanel`，最大 1100×820，无边框、20px 圆角、`.ultraThinMaterial`。
- 顶部工具 pill（悬浮居中）：框选 rect / 箭头 arrow / 文字 text / 马赛克 mosaic /（blur 禁用 + tooltip"v1.3 支持"）。
- 画布：截图居中显示在 black opacity 0.8 背景上。
- 底部工具 pill（悬浮居中）：撤销 / 重做按钮、颜色 swatches（red / yellow / jade / green / white / black 六个 20pt 圆形）、线宽 segmented（细 2 / 中 4 / 粗 8）、主操作按钮组（取消 / 复制 / 保存）。
- 马赛克使用 `CIPixellate` scale 10，保持现有实现。
- 快捷键：`⌘Z` / `⇧⌘Z` 撤销重做、`⌘C` 复制、`⌘S` 保存、`⎋` 取消。
- 保存走"保存到上次目录"（默认 `~/Desktop`）；`⌥` + 点击保存弹出 `NSSavePanel` 选择路径。

#### P-06 Onboarding（首次启动）

- 单页 / 单屏，居中 720×520，24px 圆角（radius-xl），shadow-xl。
- 顶部大图标（jade bird glyph 80×80，或 SF Symbol `bird` 大字号 jade 色）+ "欢迎使用清羽 / Qingyu"（display 字号）+ 一句话 slogan："你的本地 Mac 效率中心"。
- 中段 3 个配置项（卡片式）：`⌥ Space` 命令栏热键录制、剪贴板历史默认开关、开机启动开关。
- **屏幕录制权限段**：解释文案 + 主按钮"授予屏幕录制权限"（点击触发 TCC）。
- **辅助功能段**：解释文案"辅助功能用于未来的快捷操作，你可以在用到时再授予" + 次按钮"稍后再说"（不强制，v1.2 核心变更，见 FR-ONBOARD-ACCESSIBILITY-ONDEMAND）。
- **底部**：主按钮"开始使用"（disabled 直到屏幕录制权限已授权，或用户点了"暂不开启"）+ 左下"跳过设置" link + 右下"隐私政策" link。

#### 工具浮层

除上述 6 个主页面外，另有 3 个轻量工具浮层：截图尺寸/坐标标签 pill、Toast 轻提示、Tooltip；规格见 9.5。

### 9.5 通用组件规范

可复用组件（架构层作为独立 View 沉淀）：

- **JadeButton**：primary / secondary / destructive / link 四种样式。
- **JadeTextField**：带图标前缀、清空按钮，focus 时 jade 边框。
- **HotkeyRecorder**：基于 KeyboardShortcuts 库，带冲突提示。
- **StatCard**：概览页统计卡片。
- **ListRow**：统一 44px / 64px 行高、选中态、hover 操作。
- **Pill Badge**：类型 / 计数 / 快捷键徽章。
- **Tooltip**：hover 0.5s 后显示。
- **Toast**：底部居中，3s 自动消失，jade / red 两种。
- **ConfirmationDialog**：危险操作通用，红色标题。
- **PermissionGate**：权限未授予时的占位 + 引导按钮。

### 9.6 快捷键体系总表

> 本节为 v1.2 完整快捷键体系；与 §7.11 快捷键需求条目一致，本节为设计侧总表。用户可重绑范围见 §7.11。

**全局快捷键（用户可重绑）：**

| 功能 | 默认快捷键 |
|------|-----------|
| 打开命令栏 | `⌥ Space` |
| 区域截图 | `⇧⌃⌘4` |
| 窗口截图 | `⇧⌃⌘5` |
| 全屏截图（v1.2 新增） | `⌃⌥⌘3` |
| 打开剪贴板历史 | `⌥⌘C` |
| 打开设置 | `⌥⌘,` |

**命令栏内：**

| 按键 | 行为 |
|------|------|
| `↑` / `↓` | 选择 |
| `⌘1`–`⌘6` | 切换搜索源（所有 / 应用 / 命令 / 剪贴板 / 文件 / 设置） |
| `⏎` | 执行当前项 |
| `⌘C` | 复制当前项（文本 / 路径 / 结果值） |
| `⌘K` | 清空输入 |
| `⌘,` | 打开设置 |
| `⎋` | 关闭 |
| `Tab` | 补全（文件名 / 应用名模糊补全，匹配唯一时） |

**剪贴板历史：**

| 按键 | 行为 |
|------|------|
| `↑` / `↓` / `j` / `k` | 选择 |
| `⏎` / `⌘C` | 复制并关闭 |
| `空格` / `⌘Y` | 预览 |
| `⌫` | 删除当前项 |
| `⌘F` | 搜索 |
| `⌘A` | 全选 |
| `/` | 聚焦搜索框 |

**标注编辑器：**

| 按键 | 行为 |
|------|------|
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做 |
| `⌘C` | 复制到剪贴板 |
| `⌘S` | 保存 |
| `⎋` | 取消 |
| `1`–`4` | 切换工具（矩形 / 箭头 / 文字 / 马赛克） |

**设置窗口：**

| 按键 | 行为 |
|------|------|
| `⌘F` | 搜索设置 |
| `⌘W` | 关闭 |
| `⎋` | 关闭 |

### 9.7 空态与错误态设计

> 补充 §7.12，给出每种状态的图标与文案规范。

| 状态 | 图标 | 主文案 | 辅助 / 操作 |
|------|------|--------|------------|
| 搜索无结果 | `magnifyingglass` | 未找到匹配项 | 尝试换个关键词或检查搜索源设置 |
| 剪贴板空（首次/全部清空） | `clipboard` | 剪贴板历史为空 | 复制任意内容后会显示在这里 |
| 剪贴板未启用 | `hand.raised.slash` | 剪贴板历史已关闭 | [开启] 按钮 |
| 文件搜索索引中 | `ProgressView` | 正在索引你的文件… | 可继续使用其他搜索源 |
| 权限被拒 | `lock.shield` | 权限被拒（解释文案） | [打开系统设置] 按钮 |
| 网络反馈错误（仅反馈邮件失败） | — | 红色 alert | 提示重试 |
| 通用错误 | `exclamationmark.triangle.fill` | 错误信息 | [重试] |

### 9.8 无障碍（Accessibility）

> 与 §7.14（VoiceOver 需求）呼应，此处为设计规范。

- 所有控件具备 `accessibilityLabel`。
- 所有交互元素支持 `Tab` 键盘遍历。
- 所有装饰性 SF Symbol 标记 `.accessibilityHidden(true)`。
- 对比度满足 WCAG AA。
- VoiceOver 朗读控件角色、状态与结果类型。
- 字体大小跟随系统"字体大小"设置（动态类型，body 支持到 15pt）。
- 尊重系统"减弱动态效果""增强对比度""降低透明度"设置。

### 9.9 国际化（i18n / L10n）

- 首发支持 简体中文 + English（美国）。
- 所有用户可见字符串使用 `Localizable.xcstrings`，禁止硬编码。
- 日期 / 时间 / 数字使用 `DateFormatter` / `NumberFormatter` 走 locale。
- 布局支持最长语言字符串（英文平均比中文长 1.5–2×），避免固定宽度导致截断。
- 快捷键按 locale 自动调整（如有必要）。

### 9.10 品牌资产清单（v1.2 交付物）

- **AppIcon**：mac 全尺寸 16 / 32 / 64 / 128 / 256 / 512 / 1024，jade 鸟 logo（必须自定义）。
- **MenubarIcon**：模板图标，2 种状态（普通 / 新剪贴提示）。
- **Onboarding 大图**：鸟 glyph。
- 除 AppIcon 外，所有图标优先使用 SF Symbol。
- **About 页应用图标**：96×96。
- **发布页 / dmg 背景**：v1.2 可不做，上线前补（见第 16 章）。

---
## 10. 技术考量

> 本章仅从产品/非功能视角说明约束；具体实现方案见 `doc/architecture/design.md`、`doc/architecture/db.md`、`doc/architecture/api.md`。用户不可见的实现细节不进入功能章节。

### 10.1 技术栈

- SwiftUI + AppKit + 原生 macOS API。
- 选择原因：搜索框、菜单栏、截图、剪贴板、权限、应用启动均依赖 macOS 原生能力；原生实现性能与系统体验更好；签名、公证、权限管理更符合 Apple 生态；MVP 不需要跨平台。

### 10.2 核心架构

- 系统采用 SearchSource / Provider 模式；Provider 是内置搜索源，不等同于第三方插件系统。
- MVP 不做插件市场、热加载或外部扩展。
- 多动作模型从数据层预留，UI 第一版只执行主动作。

### 10.3 隐私与数据策略

- 所有剪贴板历史仅本地存储；截图和图片数据仅本地处理。
- 不上传、不同步、不训练用户数据；不做敏感内容过滤。
- 通过 Onboarding 和隐私说明明确告知以上行为。

### 10.4 权限策略

- 采用完整 Onboarding；屏幕录制权限在首次启动阶段完成。
- 辅助功能权限改为按需申请（v1.2），首次触发相关能力时才请求（见 FR-ONBOARD-ACCESSIBILITY-ONDEMAND）。
- 权限页必须解释用途，并提供打开系统设置与重新检测。
- 除屏幕录制外，其他非必要权限不应提前请求。

### 10.5 分发模式（v1.2 更新）

- **签名与公证**：Developer ID Application 证书签名 + Apple `notarytool` 公证 + `stapler` staple 票据。
- **分发渠道**：GitHub Releases（github.com/freeabyss/qingyu/releases）。
- **不上 Mac App Store**：因产品需关闭 Sandbox 以可靠执行 AppleEvents 系统命令，MAS 沙盒策略与之冲突。
- **检查更新**："检查更新"发现新版本后跳转 GitHub Releases 页面，由用户手动下载安装。**不集成 Sparkle 自动更新**；此前文档中的 Sparkle 自动更新占位已删除，MVP 不做自动下载/安装/重启更新。
- **Sandbox**：v1.2 关闭 App Sandbox（保留 Hardened Runtime 与必要 entitlements）。

### 10.6 存储选型与已知技术债

- **当前实现（诚实说明）**：写入路径使用 Core Data，搜索/导出路径使用 GRDB，存在 Core Data + GRDB 双栈并存的架构债，可能引入数据一致性风险。此为用户不可见的实现细节，不暴露到功能章节。
- **v1.2 决策**：不做大规模存储重构（风险高、收益不确定），保持现状交付，但将"存储栈统一"列为已知技术债，重点关注数据一致性（见 §11 非功能需求）。
- **未来方向（V1.x）**：统一到单一栈——迁移到 SwiftData 或统一 Core Data 单栈，消除双栈一致性风险。具体方案在 `doc/architecture/design.md` 记录。
- **大对象**：图片原图、缩略图、RTF/HTML 原始数据存于文件系统，按类型分目录（`Clipboard/Images/`、`Clipboard/Thumbnails/`、`Clipboard/RichText/`），数据库保存资源路径/标识；文件名使用 UUID；去重依赖内容 hash。
- **搜索索引**：Core Data 持久化 + 轻量内存索引；统一搜索和剪贴板页优先查内存索引，再按需加载详情/大对象。

### 10.7 死代码清理（v1.2）

以下代码在 v1.2 清理，使代码与文档一致（用户不可见，仅工程健康度）：

- `MenuBarView` + `UnifiedSearchViewModel` + `UnifiedSearchService`（legacy 未使用路径）。
- `UnitConverterSource`（与 CalculatorSource 重复实现）。
- `OCRService` + `ContentStore` + 相关 DB 迁移列 / UI 筛选（OCR 从未接线，MVP 不含 OCR）。
- **FileSearchSource 不删除，改为接线启用**（见 FR-SEARCH-FILE）。
- `build_and_run.sh` 中 `pgrep -x SnapVault` 改为匹配新进程名 `Qingyu`。

---
## 11. 非功能需求

### 11.1 性能

- 冷启动目标：≤ 1 秒。
- 搜索结果响应目标：≤ 100ms（本地来源）。
- 文件搜索响应：常用目录下 ≤ 300ms 返回首批结果，异步执行不阻塞其他来源。
- 后台空闲 CPU：≤ 1%。
- 后台常驻内存目标：≤ 150MB，理想 ≤ 100MB。

### 11.2 可用性

- 用户首次完成/跳过 Onboarding 后，应无需额外配置即可使用搜索、剪贴板、截图、文件搜索和内置命令。
- 搜索入口必须稳定响应全局快捷键。
- 菜单栏必须始终可作为找回入口。
- 基础 VoiceOver 可用性：核心控件有可读 label，核心操作可全键盘完成（见 §7.14）。

### 11.3 稳定性与数据完整性

- 权限缺失时必须给出明确提示。
- 截图失败时必须有错误提示和恢复路径。
- 剪贴板记录失败时不得导致 App 崩溃。
- 文件剪贴板路径失效时必须显示"文件已移动或删除"一类状态。
- **数据一致性（重点关注）**：在 Core Data + GRDB 双栈并存期间，写入与搜索/导出路径必须保证同一条记录的展示一致；资源文件缺失需容错展示，不得崩溃。
- **跨版本迁移**：升级到 v1.2 后，历史剪贴板数据必须通过 Core Data lightweight migration 保留不丢失。

### 11.4 发布要求（v1.2 更新）

- v1.2 起必须完成 Developer ID 签名 + Apple Notarization 公证（notarytool）+ staple。
- 分发渠道为 GitHub Releases，不上 Mac App Store。
- 关闭 App Sandbox，保留 Hardened Runtime 与必要 entitlements。
- 版本号三源一致（MARKETING_VERSION / Info.plist / CHANGELOG，见 FR-UI-36）。
- 需要提供隐私说明、关于页、退出 App 能力。

### 11.5 卸载与备份兼容

- 数据目录位于 `~/Library/Application Support/Qingyu/`，与 Time Machine 兼容，随系统备份，不设置排除标志。
- 提供设置内"清空所有数据"入口；卸载不自动清理数据。

---

## 12. 测试与验收策略

MVP 测试范围至少包含：

1. **单元测试**：SearchSource/Provider 搜索逻辑、评分与排序、拼音与首字母匹配、CalculatorSource 运算与换算、剪贴板 hash 去重、Core Data 模型与持久化。
2. **集成测试**：剪贴板监听→持久化→索引更新→展示全链路；统一搜索聚合各来源结果；黑名单过滤；最近使用加权；资源路径关联；**文件搜索来源接入统一搜索**。
3. **手动验证清单**：Onboarding 流程、权限授权/拒绝/重检、菜单栏入口、搜索框开关行为、应用启动、剪贴板文本/富文本/图片/文件记录与恢复、截图区域/全屏/窗口+标注+复制/保存、设置项、关于页/隐私政策/反馈邮件/检查更新。

### 12.1 v1.2 必验项（回归 + 新增）

- **AC-FILE（文件搜索 E2E）**：`⌥ Space` 输入文件名，能在 `~/Desktop`/`~/Documents`/`~/Downloads` 命中文件，回车打开、次级动作在 Finder 中显示。
- **AC-FULLSCREEN（全屏截图热键）**：默认 `⌃⌥⌘3` 触发全屏截图；设置内可重绑；冲突提示重录。
- **AC-VERSION（版本号一致）**：关于页显示 `1.2.0`，与 MARKETING_VERSION、Info.plist、CHANGELOG 一致。
- **AC-ONBOARD-ACCESSIBILITY**：Onboarding 不再强制辅助功能；跳过辅助功能仍可完成 Onboarding。
- **AC-6（重启不重弹）**：完成/跳过 Onboarding 并重启 App 后不再弹 Onboarding。
- **AC-7（按需申请 Alert）**：首次触发需要辅助功能的能力时正确弹出说明 Alert 并可打开系统设置。
- **AC-CMD-SANDBOX**：关闭 Sandbox 后，重启 Finder/Dock、切换深浅色等命令在真实环境可执行、不静默失败。
- **AC-SIGN**：产物完成 Developer ID 签名与公证，Gatekeeper 校验通过。

> 上述策略同步到 `doc/test/cases.md`，并按用户故事拆分为可执行测试清单；测试执行记录见 `doc/test/report.md`。

---

## 13. 成功指标

- 用户完成/跳过首次启动引导后，可以通过 `⌥ Space` 打开搜索框。
- 用户可以在搜索框内启动常规应用目录中的 App。
- 用户可以通过搜索框搜索并打开主目录常用位置下的文件（v1.2 新增）。
- 用户复制文本、图片或文件后，可以在剪贴板历史中找回。
- 用户可以完成区域、全屏、窗口截图（全屏支持全局快捷键），并复制或保存截图。
- 用户可以通过搜索框执行内置白名单命令，系统控制类命令可靠生效。
- 用户可以在设置中启用/禁用搜索源展示、修改全局快捷键（含全屏截图热键）。
- App 能以菜单栏常驻方式稳定运行；关于页版本号正确显示 1.2.0。
- 所有剪贴板和截图数据均只保存在本地。

---
## 14. 后续版本规划

### 14.0 商业模式规划

MVP 完全免费，不做任何付费限制，不接入支付、授权码、订阅或账号系统。PRD 保留未来 Pro 方向，但不进入 MVP。

### 14.1 V1.x

- 数据备份 / 导出能力（剪贴板历史、设置导出/导入）。
- blur 独立模糊标注工具、更多截图标注工具。
- 文件搜索索引范围用户可配置、更广索引来源。
- 存储栈统一（Core Data + GRDB 双栈收敛到 SwiftData 或单 Core Data 栈）。
- 插件 / Workflow 基础能力。
- 窗口控制、资源监控基础展示、应用卸载、截图历史。
- iCloud 同步（可选）。
- Cmd+K 动作面板、搜索结果快捷数字键、自定义内置命令。
- 无障碍（VoiceOver）深度优化。

### 14.2 V2.x

- OCR 图片文字识别。
- 剪贴板跨设备 / 多设备同步。
- AI 命令、AI 总结 / 翻译 / 内容理解、智能搜索。
- 工作流自动化、完整插件系统。
- Pro 付费模式（高级截图、OCR、录屏/GIF、高级窗口控制、高级工作流、云同步等可能进入 Pro）。

---

## 15. 当前已确认决策记录

| 编号 | 决策 |
| --- | --- |
| D-001 | 产品定位为增强版 Spotlight + 多效率工具集成中心。 |
| D-002 | 主交互模型为搜索框主入口，复杂功能提供独立面板/管理中心。 |
| D-003 | MVP 功能集为应用启动、剪贴板历史、基础截图 + 轻量标注、内置白名单命令、文件搜索。 |
| D-004 | PRD 记录完整愿景，但开发按版本分期。 |
| D-005 | MVP 功能深度按演示级克制，发布流程按公开产品标准。 |
| D-006 | 技术栈选择纯 SwiftUI + AppKit 原生 macOS App。 |
| D-007 | 统一入口采用 Spotlight 外观 + Raycast 行为模型。 |
| D-008 | MVP 搜索源包含应用、剪贴板、内置命令、计算/换算、设置、文件。 |
| D-009 | 搜索源配置 MVP 只做简单开关级。 |
| D-010 | 搜索源开关控制是否展示，剪贴板另有记录开关。 |
| D-011 | 剪贴板默认开启，强调开箱即用。 |
| D-012 | 首次启动采用完整 Onboarding。 |
| D-013 | Onboarding 完成 MVP 必要权限（屏幕录制）；辅助功能 v1.2 起改为按需申请。 |
| D-014 | 用户拒绝屏幕录制权限时停留在权限页，不能进入完整体验。 |
| D-015 | 从第一天采用 SearchSource / Provider 模式。 |
| D-016 | SearchResult 支持主动作和次级动作，MVP UI 只执行主动作。 |
| D-017 | 内置命令 MVP 只支持白名单，不支持任意 shell。 |
| D-018 | 截图 MVP 支持区域、全屏、窗口、复制、保存、轻量标注。 |
| D-019 | 标注 MVP 支持矩形框、箭头、文字、马赛克（mosaic）、撤销/重做；blur 列入 V1.x。 |
| D-020 | 截图后弹出工具栏，无抽象完成按钮，提供复制、保存、标注、取消。 |
| D-021 | 剪贴板历史支持文本、图片、文件。 |
| D-022 | 文件剪贴板只保存路径/引用，不复制文件内容。 |
| D-023 | 剪贴板只按时间淘汰，默认 30 天。 |
| D-024 | 不做敏感内容过滤，理由是数据仅保存在用户本地。 |
| D-025 | 默认搜索快捷键为 `⌥ Space`，用户可修改。 |
| D-026 | App 形态为菜单栏 App，无 Dock 图标。 |
| D-027 | MVP 管理中心包含首页/概览、剪贴板历史、设置、权限。 |
| D-028 | 菜单栏入口为打开搜索、剪贴板、截图、设置、关于、退出。 |
| D-029 | 菜单栏"截图"为直接动作，执行区域截图。 |
| D-030 | 应用启动 MVP 只索引 `/Applications`、`~/Applications`、`/System/Applications` 下的 `.app`。 |
| D-031 | MVP 默认启用开机启动，设置中允许关闭。 |
| D-032 | 截图默认保存目录为 `~/Desktop`（v1.2 修订，与 macOS 原生默认一致；原 `~/Pictures/Screenshots` 在 v1.0 设定但从未作为产品对外承诺），首次保存自动创建，设置可改。 |
| D-033 | 截图文件默认时间戳命名：`Screenshot yyyy-MM-dd HH.mm.ss.png`。 |
| D-034 | MVP 截图保存格式只支持 PNG。 |
| D-035 | MVP 标注样式提供少量预设：颜色、线宽、文字大小。 |
| D-036 | MVP 剪贴板历史支持置顶，不做收藏分类和标签系统。 |
| D-037 | 剪贴板历史项默认动作为复制到系统剪贴板；不自动粘贴到前台应用。 |
| D-038 | 统一搜索排序采用来源基础优先级 + 文本匹配分数 + 最近使用加权综合评分。 |
| D-039 | 应用/命令/设置项支持拼音搜索；剪贴板正文与文件名只做原文搜索。 |
| D-040 | 搜索框空输入时不展示任何推荐/最近内容。 |
| D-041 | 搜索触发分来源规则：应用/命令/设置 1 字符起，剪贴板/文件 2 字符起，计算/换算按模式触发。 |
| D-042 | 统一搜索结果合并排序后按总上限 12 条截断。 |
| D-043 | MVP 搜索结果不显示分组标题，靠图标和类型标签标识来源。 |
| D-044 | CalculatorSource 支持四则/括号/小数与长度/重量/数据/温度换算。 |
| D-045 | CalculatorSource 结果主动作为复制到系统剪贴板。 |
| D-046 | SettingsSource 采用页面级 + 具体区块入口，不直接切换开关。 |
| D-047 | 关于页按发布级产品设计，含名称、版本号、构建号、主页、隐私政策、检查更新、反馈、许可、版权。 |
| D-048 | MVP"检查更新"跳转下载页手动下载，不做自动下载/安装/重启更新。 |
| D-049 | 发布渠道采用 GitHub Release + 简单官网/项目主页，不进入 Mac App Store。 |
| D-050 | （已被 D-103 取代）原"MVP 暂不强制签名公证"；v1.2 起强制 Developer ID 签名 + 公证。 |
| D-051 | MVP 必须提供隐私政策，从关于页进入。 |
| D-052 | 错误/崩溃反馈须用户点击并确认后才可上报，不静默上传。 |
| D-053 | 反馈渠道为邮件，反馈邮箱 qingyu_freeabyss@163.com。 |
| D-054 | 支持中文/英文界面，默认跟随系统语言。 |
| D-055 | 设置提供语言切换：跟随系统/简体中文/English。 |
| D-056 | （已被 D-101 取代）原暂定名 Mac Super Assistant / 内部代号 Assistant；v1.2 正式定名清羽 Qingyu。 |
| D-057 | Onboarding 按功能逐项引导，权限请求出现在对应功能说明之后。 |
| D-058 | （已被 D-104 取代）原强制辅助功能权限；v1.2 改为按需申请。 |
| D-059 | 屏幕录制权限必须在 Onboarding 阶段完成，未授权不能进入完整体验。 |
| D-060 | 剪贴板历史默认开启，Onboarding 中用户显式确认知晓。 |
| D-061 | Onboarding 必须注册可用快捷键 `⌥ Space` 后才能完成。 |
| D-062 | 所有 MVP 搜索源默认开启，用户可在设置中关闭展示。 |
| D-063 | 剪贴板历史页提供类型筛选：全部/文本/图片/文件。 |
| D-064 | 图片剪贴板保存原图 + 缩略图，清理遵循保留时间。 |
| D-065 | 显示剪贴板存储占用，但不按容量自动清理。 |
| D-066 | 保留时间预设：7/30/90 天、永久；默认 30 天。 |
| D-067 | 清空全部剪贴板历史二次确认，删除单条可不确认。 |
| D-068 | 暂不实现搜索结果快捷数字键，模型/UI 预留空间。 |
| D-069 | 搜索框失焦、点击外部、切 App、ESC、再次快捷键、执行主动作后均关闭。 |
| D-070 | 截图流程中 ESC 始终取消当前流程。 |
| D-071 | 截图复制后写入系统剪贴板并进入剪贴板历史。 |
| D-072 | 截图保存只保存文件，不写剪贴板历史；不实现截图历史页。 |
| D-073 | 截图保存成功显示轻提示。 |
| D-074 | 切换深浅色不确认；需确认命令仅清空剪贴板历史、重启 Finder、重启 Dock。 |
| D-075 | 内置命令维护中英文别名并支持拼音/首字母搜索。 |
| D-076 | 只有剪贴板提供功能开关；搜索结果支持黑名单机制。 |
| D-077 | 搜索黑名单只屏蔽具体结果，不支持规则批量隐藏。 |
| D-078 | MVP 不实现搜索结果右键菜单；黑名单只在设置页管理。 |
| D-079 | 剪贴板历史页暂不实现右键菜单，回车放回系统剪贴板。 |
| D-080 | 剪贴板历史页独立搜索框，即时搜索 + debounce。 |
| D-081 | 剪贴板列表默认置顶在上，搜索时置顶匹配项优先。 |
| D-082 | 剪贴板基于内容 hash 去重，重复复制更新时间。 |
| D-083 | 富文本保存纯文本 + RTF/HTML，恢复失败降级纯文本。 |
| D-084 | 剪贴板监听基于 changeCount 自适应轮询，后台常驻。 |
| D-085 | （见 D-109）MVP 数据存储为 Core Data + 文件系统；当前存在 Core Data + GRDB 双栈技术债。 |
| D-086 | Core Data 持久化 + 轻量内存搜索索引。 |
| D-087 | 大对象按类型分目录，UUID 命名，内容 hash 去重。 |
| D-088 | 资源缺失只做容错展示，不主动清理孤儿文件。 |
| D-089 | App 图标简洁抽象效率风格；菜单栏图标单色 template。 |
| D-090 | 官网/项目主页采用标准产品页结构。 |
| D-091 | MVP 完全免费，不接入支付/订阅/账号。 |
| D-092 | MVP 不需要账号系统，也不预留复杂账号架构。 |
| D-093 | MVP 最低支持 macOS 12 Monterey；发行包为通用二进制，同时支持 Apple 芯片与 Intel 芯片。 |
| D-094 | MVP 需要明确测试策略并写入测试文档。 |
| D-101 | **（v1.2.0，2026-07-03）品牌名正式定案：中文清羽、英文 Qingyu（首字母大写）。取代 D-056。全文（除历史语境）统一使用此名。** |
| D-102 | **（v1.2.0）Bundle ID 保留 `com.freeabyss.qingyu` 不变，避免用户 TCC 权限、Keychain、数据目录、开机启动项失效；仅改显示名/target/源码目录/文案。** |
| D-103 | **（v1.2.0）关闭 App Sandbox，采用 Developer ID 签名 + notarytool 公证 + staple + GitHub Releases 分发（非 MAS），保留 Hardened Runtime，使 AppleEvents 命令可靠工作。取代 D-050。** |
| D-104 | **（v1.2.0）辅助功能权限改为按需申请，onboarding 不再强制；首次触发相关能力时才请求。取代 D-058。** |
| D-105 | **（v1.2.0）v1.2 接入文件搜索（FileSearchSource 接线），默认索引范围限定 `~/Desktop`/`~/Documents`/`~/Downloads`，只做文件名/路径匹配，不做全文/OCR。** |
| D-106 | **（v1.2.0）清理死代码：OCRService/ContentStore、legacy UnifiedSearch(Service/ViewModel)、重复 UnitConverterSource 及相关 DB/UI；FileSearchSource 保留并接线。** |
| D-107 | **（v1.2.0）全屏截图补全全局快捷键，默认 `⌃⌥⌘3`（与系统截图键错开），用户可重绑。** |
| D-108 | **（v1.2.0）版本号三源必须一致：Xcode MARKETING_VERSION=1.2.0、Info.plist CFBundleShortVersionString=1.2.0、CHANGELOG 补全 v1.0.0/v1.0.1/v1.1.0/v1.2.0；关于页显示与之一致。** |
| D-109 | **（v1.2.0）确认当前 Core Data + GRDB 双栈为已知技术债，v1.2 不做存储重构；V1.x 统一到 SwiftData 或单 Core Data 栈，重点关注数据一致性。** |
| D-110 | **（v1.2.0）确认 MVP 不含 OCR，OCR 列入 V2.x；相关死代码 v1.2 删除。** |
| D-111 | **（v1.2.0）数据目录 `~/Library/Application Support/Qingyu/`，跨版本采用 Core Data lightweight migration，与 Time Machine 兼容；提供设置内"清空所有数据"入口；卸载不自动清理数据。** |
| D-112 | **（v1.2.0）UI 设计语言定为"现代极简 Pro 工具风"（参考 Raycast / Arc），不拟物、不过度装饰，本地/隐私/键盘优先（见第 9 章）。** |
| D-113 | **（v1.2.0）品牌色定为 Jade / Teal（Light `#0A9488` / Dark `#2DD4BF`），意象贴合"清羽"；语义色直接走系统色。** |
| D-114 | **（v1.2.0）命令栏形态为独立 command bar 浮层 + 独立管理窗口（剪贴板/设置），非菜单栏下拉。** |
| D-115 | **（v1.2.0）明暗双模式跟随系统；浮层/工具条材质统一使用 `.ultraThinMaterial`。** |
| D-116 | **（v1.2.0）Onboarding 改为单屏布局（720×520）；辅助功能改为按需申请（与 D-104 一致）。** |
| D-117 | **（v1.2.0）blur 独立模糊工具延后至 v1.3，v1.2 标注只保留 mosaic 马赛克（与 D-019/FR-ANNOTATE-BLUR 一致，明确 v1.3 目标版本）。** |
| D-118 | **（v1.2.0）建立统一 DesignToken 层（Color / Font / Radius / Spacing / Shadow / Material），禁止散落硬编码（见 FR-UI-DESIGN-TOKENS）。** |
| D-119 | **（v1.2.0）双剪贴板行组件、双搜索结果体系、三套 Toast 在 v1.2 统一为单套通用组件（见 §9.5）。** |
| D-120 | **（v1.2.0）命令栏空态默认显示"最近使用 + 收藏"（类 Raycast 首页），与旧 FR-SEARCH-14/15"搜索空输入不展示推荐"为演进关系：空态展示的是最近使用/收藏入口而非搜索推荐结果，以本章为准。** |
| D-121 | **（v1.2.0）搜索源默认权重调整为：应用 100、命令 90、计算/换算 85、设置 80、文件 75、剪贴板 70（文件权重由 60 提至 75，因为文件搜索 v1.2 接入成为常用能力）。** |
| D-122 | **（v1.2.0）命令栏支持 ⌘1-6 数字快捷键切换搜索源（所有/应用/命令/剪贴板/文件/设置），替代原 FR-SEARCH-25"不实现数字快捷键"的约束；直接执行结果的数字快捷键保留扩展空间（FR-SEARCH-26）。** |

> 说明：原 D-095~D-100 记录的是旧文件名（doc/architecture.md 等）修复动作，自我指涉且引用已失效路径，v1.2 清理移除；相关文档现位于 `doc/architecture/design.md`、`doc/architecture/db.md`、`doc/architecture/api.md`、`doc/test/cases.md`。

---

## 16. 待解决问题

以下为 v1.2 当前仍需澄清的问题（已解决项如"产品正式名 / 图标方向 / Slogan"已在 D-101、第 9 章定案并移除）：

1. 文件搜索默认索引范围是否需要在 v1.2 就开放用户配置，还是先固定 `~/Desktop`/`~/Documents`/`~/Downloads`（当前倾向后者，配置能力放 V1.x）？
2. 文件搜索是否需要增量索引/文件系统监听，还是每次查询时实时遍历即可满足性能目标？
3. blur 独立模糊工具何时进入（当前目标 v1.3，是否与更多标注工具打包一次交付）？
4. 是否在 V1.x 提供 iCloud 同步，同步范围（仅设置 / 含剪贴板历史）与冲突策略如何定？
5. Pro 付费功能边界如何划分（哪些能力免费、哪些进入 Pro），是否需要账号体系支撑？
6. 存储栈统一（Core Data + GRDB → SwiftData 或单栈）的迁移时机与数据迁移验收标准？
7. 截图底层实现优先 ScreenCaptureKit 还是兼容性更强的 CGWindow/CGDisplay（影响 macOS 13 兼容分支）？
8. AppIcon 最终设计：v1.2 内由开发用 SF Symbol 鸟 glyph（jade 色）占位，正式自定义 AppIcon 可后补——是否需要在上线前完成正式设计稿？
9. 官网/项目主页 URL 与隐私政策 URL 是否最终确定（域名 qingyu.app 是否启用）？
10. 全屏/区域/窗口截图默认快捷键组合的最终取值是否需与常见第三方截图工具再做一次冲突排查？
11. 是否需要自定义 dmg 安装背景（v1.2 可不做，上线前决定）？
