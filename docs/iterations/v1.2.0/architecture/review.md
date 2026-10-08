# v1.2.0 架构评审记录（清羽 Qingyu）

- **评审日期**：2026-07-03
- **关联版本**：v1.2.0
- **评审对象**：`doc/architecture/design.md`（v17）、`doc/architecture/api.md`（v3）、`doc/architecture/db.md`（v3），对照 `doc/prd.md`（清羽 v1.2）与现网代码（`SnapVault/` 源码树）
- **评审人**：arch-review subagent
- **评审结论**：**APPROVED_WITH_MINOR_FIXES**
  - 阻塞级问题：**0**（评审中发现的阻塞级缺陷已在本轮直接修订进三份架构文档，下一环输入自洽）
  - 改善级问题：**6**（不阻塞开发，建议在 ⑤ 拆任务时以任务跟踪）

---

## 一、评审方法

1. 通读 v1.2 PRD（1344 行，17 章 + 第 9 章设计语言 + D-101~D-120 决策 + 第 16 章待解决问题）。
2. 基于现有架构文档 v2/v16 修订（非从零重写），保留 v1.0–v1.1 已交付实现的稳定契约。
3. 对照现网代码抽样核验关键事实（见下表），确保文档描述与代码现状一致、改造点可落地。
4. 逐条覆盖任务清单 17 个已知问题，映射到 design/api/db 的具体章节与接口。

**代码事实核验（抽样，已确认）：**

| 事实 | 核验结果 |
| :--- | :--- |
| AppDelegate god object | `SnapVault/App/AppDelegate.swift` = **955 行**，确认 |
| Sandbox 开、缺 apple-events | `SnapVault.entitlements` `app-sandbox=true`，无 automation.apple-events，确认 |
| 版本号三源不一致 | pbxproj `MARKETING_VERSION=0.1.0`、`PRODUCT_NAME=Assistant`；Info.plist `CFBundleShortVersionString=0.1.0`，确认 |
| FileSearchSource 未接线 | `FileSearchSource.swift` = **522 行**；`App/` 下无 `FileSearchSource(` 实例化，确认 |
| 双仓库 | `AssistantClipboardRepository.swift`=739、`ContentRepository.swift`=541 行，确认 |
| 死代码存在 | `MenuBarView.swift`/`OCRService.swift`/`ContentStore.swift`/`UnitConverterSource.swift`/`UnifiedSearchService.swift` 均存在，确认 |
| 强制解包点 | `CalculatorSource.swift:351` `try! NSRegularExpression`，确认；PreviewPanel 在 `Views/Preview/PreviewPanel.swift` |
| Sparkle 残留 | `Info.plist`/`Resources/appcast.xml`/`AppDelegate`/`Logger`/`UpdateService` 均含 Sparkle 引用，确认 |
| build_and_run | `pgrep -x "SnapVault"`、`PROJECT_NAME=SnapVault`、`APP_PATH=.../Assistant.app`，确认 |

---

## 二、评审中直接修订（原阻塞级 → 已解决，故最终阻塞级=0）

以下问题若不解决会导致下一环（⑤ 开发）输入不自洽或编译/运行失败，已在本轮直接改进架构文档：

1. **协议新增方法的 conformer 完整性**（承接 v1.1 评审教训）：`PermissionServiceProtocol.onDemandAccessibilityCheck()` 为新增方法，`MockPermissionService` / `StaticPermissionService` 两 conformer 必须同步补齐，否则编译失败。已在 api.md §13 显式标注两 conformer 需补。
2. **改名后仓库命名冲突**：GRDB 版 `ClipboardRepository`（386 行）删除后，其名字被回收给 Core Data 活动仓库（原 `AssistantClipboardRepository`）。若不明确，会出现两个 `ClipboardRepository` 语义混淆。已在 api.md §2.1 改名清单 + §6 明确"名字回收给活动仓库，GRDB 版已删除"。
3. **首次启动判定键迁移**：Onboarding 单屏化后由 `onboarding.completed`(Bool) 改为 `onboarding.completedAt`(Date?)，若不定义迁移，旧用户会被重弹 Onboarding（违反 AC-6）。已在 db.md §8.3/§8.4 定义迁移（旧 true → 写非空时间戳）。
4. **数据目录改名的数据丢失风险**：`Assistant/` → `Qingyu/` 若无迁移，等于旧数据失联。已在 db.md §8.4 定义 move 迁移 + lightweight migration + 失败 fallback（备份旧库 + 新建空库，不阻塞启动）。
5. **文件搜索权重取值冲突（PRD 内部不一致）**：见第五节 PRD 反馈 #1。已在 design §7.4 / api §3.5 采用 75 并显式标注与 FR-SEARCH-11(60) 的差异，避免开发无所适从。

---

## 三、改善级问题（minor，不阻塞，建议 tasks.json 跟踪）

| # | 问题 | 建议 | 归属版本 |
| :--- | :--- | :--- | :--- |
| M-1 | AppDelegate 拆分（955 行 → AppContainer + 6 控制器）范围大，一次性重构回归风险高 | ⑤ 拆分为独立任务，按控制器分批切；先落 AppContainer 组装根 + StatusItemController，再逐个迁窗口逻辑；保留全套测试回归 | v1.2 |
| M-2 | DesignToken 全量 View 迁移面广，易残留硬编码 | 先落 Token 定义 + 核心页（命令栏/剪贴板/设置）迁移，其余页分批；code review 把关 | v1.2（核心）/ v1.x（收尾） |
| M-3 | FileSearchSource 检索实现选型（Spotlight metadata vs FileManager enumerator）影响性能与 macOS 13 兼容 | ⑤ 开发前定选型；建议 Spotlight 优先 + FileManager 降级；补性能验收（≤300ms 首批） | v1.2 |
| M-4 | 概览页"截图数"统计来源未在数据层显式建模（UsageStat 仅 application/command） | db 层确认截图计数落点（扩展 UsageStat targetType 或单独计数键） | v1.2 |
| M-5 | 关闭 Sandbox 的安全审视（失去沙盒隔离） | 保留 Hardened Runtime + 最小 entitlements；命令严格白名单不变；文档已列 entitlements 清单，⑤ 落地时逐项核对 | v1.2 |
| M-6 | 强制解包点批量整改（PreviewPanel `as!`、AppDelegate `localEventMonitor!`、CalculatorSource `try!`、ReleaseInfoService `URL(string:)!`） | ⑤ 归一为一个"健壮性整改"任务，改 `guard let`/`as?`/预编译常量 regex/静态合法 URL | v1.2 |

---

## 四、遗留问题（留 V1.x / V2.x）

- **存储栈统一**（Core Data + GRDB → SwiftData 或单 Core Data 栈）：v1.2 仅标注技术债 + 加一致性容错，不重构。迁移时机与数据迁移验收标准留 V1.x（PRD 第 16 章 #6）。
- **blur 独立模糊标注工具**：v1.3（D-117）。
- **文件搜索索引范围用户可配置 / 增量索引监听**：V1.x（PRD 第 16 章 #1/#2）。
- **导出/备份能力本体**：V1.x（FR-DATA-EXPORT-BACKUP）。
- **无障碍深度优化**（动态朗读顺序、复杂控件描述）：V1.x；v1.2 保证基础可用。
- **Cmd+K 动作面板、搜索结果快捷数字键执行、自定义命令**：V1.x。
- **OCR、AI、云同步、插件系统、Pro**：V2.x。

---

## 五、对 PRD 的反馈（架构视角）

> 以下为架构评审发现的 PRD 内部不一致/待澄清点。**未改动 PRD**，列出供 leader 决定是否回头校准 PRD。

1. **[需 PRD 校准] 文件搜索来源基础优先级取值冲突**：
   - PRD **FR-SEARCH-11** 明列"文件 **60**"；
   - PRD **§9.3 核心交互范式** / 本任务指令建议"文件权重 **75**"。
   - 架构文档已按 §9.3 采用 **75** 并标注差异。建议 PRD 将 FR-SEARCH-11 的 60 更正为 75（或明确二者语义不同），消除单一文档内两值并存。

2. **[已在架构层协调，PRD 可选补注] 命令栏空态语义演进**：PRD FR-SEARCH-14/15"空输入不展示推荐" 与 §9.3/D-120"空态显示最近使用+收藏"存在表面冲突。PRD D-120 已注明为"演进关系（展示入口而非搜索推荐结果）"，架构按 D-120 落地。建议 PRD 在 FR-SEARCH-14/15 处加一句指向 D-120 的交叉引用，避免开发只读 FR 时误解。

3. **[术语澄清，已在文档内处理] 两种 "Accessibility"**：PRD §7.14 已区分"无障碍(VoiceOver)"与 §7.8"辅助功能 TCC 权限"。架构文档沿用该区分（design §19 无障碍 vs §3.1 辅助功能按需）。无需改 PRD，提示 ⑤ 开发勿混淆。

4. **[无冲突，仅记录] 截图默认热键表述**：PRD §7.11 用"示例 `⌃⌥⌘4/5`"，§9.6 总表用 `⇧⌃⌘4/5`。架构 §5.2 采用 §9.6 总表值（`⇧⌃⌘4`/`⇧⌃⌘5`/全屏 `⌃⌥⌘3`）。建议 PRD §7.11 与 §9.6 对齐取值（本身 PRD §7.11 已注"确切默认组合以设置页展示为准"，不阻塞）。

> 结论：无"架构上不可行"的 PRD 需求。上述 #1 为唯一建议 PRD 实际改字的点（60→75），其余为交叉引用/表述对齐类，可选。

---

## 六、5 个关键设计决策回顾（对照 design.md）

1. **AppDelegate god object 拆分为 AppContainer + 窗口控制器群**（design §2.5/§16/§17，api §17）：955 行手工组装 → DI 根 + StatusItemController + 5 类窗口控制器 + GlobalShortcutManager。分层数量不变（仍 6 层），属职责归位。评价：方向正确，是本迭代最大结构收益，也是最大回归风险（M-1 跟踪）。

2. **双搜索/双仓库/OCR/双 Toast 死代码收敛**（design §3.2/§3.3/§3.7，api §21 Removed 表）：删除 UnifiedSearch* + MenuBarView + UnitConverterSource + OCRService/ContentStore/ContentRepository + GRDB ClipboardRepository，Toast 三套并一套 JadeToast。评价：使代码与文档一致，降低维护面；`FileSearchSource` 例外——不删而接线。

3. **FileSearchSource 接入 + 全屏截图热键**（design §3.2/§9/§3.4/§5.2，api §5/§14）：补齐两处 MVP 能力闭环（此前 522 行文件搜索代码从未实例化、全屏截图无全局热键）。评价：明确了 AppContainer 实例化注册、默认三目录、Spotlight/FileManager 选型、权重 75、`FileSearchResult`/`openFile`/`revealInFinder` 契约，可落地。

4. **关闭 Sandbox + Developer ID 签名公证 + 移除 Sparkle**（design §18/§3.8，api §15）：entitlements 清单明确（移除 app-sandbox、加 apple-events、启用 Hardened Runtime），使 AppleEvents 命令可靠；更新只跳 GitHub Releases。评价：与 D-103 一致，安全审视留 M-5 跟踪。

5. **DesignToken 层 + 统一组件 + Onboarding 单屏 + 辅助功能按需**（design §3.7/§3.1，api §18/§13/§16.3，db §8）：建立 Jade* Token 与统一组件，Onboarding 7 步 → 单屏、`onboardingCompletedAt` 判定、辅助功能 `onDemandAccessibilityCheck()`。评价：与 PRD 第 9 章 + D-104/D-116/D-118 一致；迁移键与 conformer 完整性已在评审中补齐（第二节 #1/#3）。

---

## 七、是否可进入 ⑤ 开发测试

**可以。** 阻塞级问题 0（已在本轮修订消解），6 条 minor 均为"⑤ 拆任务跟踪/开发前定选型"类，不阻塞架构进入开发。建议 ⑤ 按下节模块划分拆任务。

---

## 八、建议 v1.2 任务拆解（供 ⑤.2 leader 亲自拆任务参考）

按模块/主题给出大致边界与数量建议（**仅供参考，最终以 leader 拆分为准**），预估 **12–15 个开发任务**：

| # | 模块/主题 | 大致范围 | 依赖 |
| :--- | :--- | :--- | :--- |
| T-A | 改名与版本号 | target/module/目录 SnapVault→Qingyu；MARKETING_VERSION/Info.plist/CHANGELOG 三源 1.2.0；build_and_run.sh pgrep；Bundle ID 保留 | 无（先行） |
| T-B | 数据目录迁移 | Assistant/→Qingyu/ move + store 重命名 + lightweight migration + fallback | T-A |
| T-C | AppContainer + AppDelegate 瘦身 | DI 根 + 生命周期剥离 | T-A |
| T-D | 窗口控制器拆分 | StatusItem/CommandBar/ClipboardHistory/Settings/Annotation/ScreenshotOverlay | T-C |
| T-E | 死代码清理（搜索侧） | 删 UnifiedSearch*/MenuBarView | T-C |
| T-F | 死代码清理（OCR/仓库侧） | 删 OCRService/ContentStore/ContentRepository/GRDB ClipboardRepository + ocrText 字段/表 | T-B |
| T-G | UnitConverterSource 合并 | 删独立源，能力并入 CalculatorSource | T-E |
| T-H | FileSearchSource 接入 | AppContainer 实例化注册 + FileSearchResult + 打开/Finder 动作 + 性能 | T-C |
| T-I | 全屏截图热键 + 悬浮 pill 工具栏 | registerFullscreenCapture + ScreenshotToolbar 改造 | T-D |
| T-J | Onboarding 单屏 + 辅助功能按需 | OnboardingViewModel 单屏化 + onDemandAccessibilityCheck + onboardingCompletedAt | T-B/T-C |
| T-K | 关闭 Sandbox + 签名公证 + 移除 Sparkle | entitlements + Developer ID + notarytool + 删 Sparkle | T-A |
| T-L | DesignToken 层 + 统一组件 | Jade* Token + JadeButton/TextField/ListRow/JadeToast 等 + 三套 Toast 收敛 | T-A |
| T-M | 设置外观/数据页 + 快捷键冲突检测 | Appearance/Data 页 + 清空所有数据 + HotkeyConflictDetector | T-L |
| T-N | 健壮性整改 | 强制解包点批量改安全写法 | 可并行 |
| T-O | 测试同步 | 删 OCR/UnitConverter 相关测试；FileSearchSourceTests 转接线回归；补 AppContainer/权限 conformer 测试 | 各功能任务后 |

---

## 九、最终结论

- 状态：**APPROVED_WITH_MINOR_FIXES**
- 阻塞级问题：**0**（原 5 项在评审中直接修订进 design/api/db，已消解）
- 改善级问题：**6**（M-1~M-6，tasks.json 跟踪，不阻塞）
- PRD 需实际改字点：**1**（FR-SEARCH-11 文件优先级 60→75），其余为可选交叉引用/表述对齐
- 可进入 ⑤ 开发测试：**是**
