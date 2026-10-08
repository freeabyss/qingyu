# v1.2.0 测试用例评审记录（清羽 Qingyu）

- **评审日期**：2026-07-03
- **关联版本**：v1.2.0
- **评审对象**：`doc/test/cases.md` 第 11 节「清羽 Qingyu v1.2 测试用例」（新增 98 条 TC）+ 第 5 节旧 TC 的「v1.2 修订」标注
- **评审依据**：`doc/prd.md`（清羽 v1.2，1346 行）、`doc/architecture/design.md` v17、`api.md` v3、`db.md` v3、`doc/iterations/v1.2.0/architecture/review.md`（架构评审 6 个改善级问题 M-1~M-6）
- **评审人**：test subagent（用例作者自评审）
- **评审结论**：**APPROVED_WITH_MINOR_FIXES**
  - 阻塞级问题：**0**
  - 改善级问题：**4**（均已在本轮直接修订进 cases.md，见第四节）

---

## 一、评审方法

1. 通读 v1.2 PRD 全部 FR / US / AC / D-101~D-122 决策，抽取所有 v1.2 标记为 🔧（补齐/修订）的需求点作为覆盖基准。
2. 通读架构评审 review.md，将 6 个改善级问题（M-1~M-6）逐一映射到看护用例。
3. 对照任务指令给定的 18 项核心变化（a~r）逐条核对是否有 TC 覆盖，重点关注「容易遗漏」的配置类改动（改名/版本号/关 Sandbox/删 Sparkle/数据迁移）。
4. 按 6 维评审清单（覆盖完整性、边界充分性、可执行性、独立性、优先级合理、负面用例）逐条检查每个 TC。
5. 复核自动化可行性标注（swift / xcodebuild / 脚本静态 / 手工 / E2E）是否与被测对象性质匹配。
6. 交叉检查 TC 之间是否矛盾，以及 TC 与 PRD/架构是否冲突（冲突不自行改 PRD/架构，只记录）。

---

## 二、覆盖矩阵（P0 FR / AC → TC）

| P0 FR / AC | 描述 | 覆盖 TC | 覆盖判定 |
|------------|------|---------|----------|
| FR-SEARCH-FILE-1~9 / US-012 / AC-FILE | 文件搜索接入 | SEARCH-F-001~009 | ✅ 完整（接线/三目录/触发/异步/字段/权重/无结果/性能/黑名单） |
| FR-SHOT-FULLSCREEN / US-013 / AC-FULLSCREEN | 全屏截图热键 | SHOT-FS-001~004 | ✅ 完整（默认键/E2E 触发/重绑/冲突） |
| FR-UI-ONBOARDING / P-06 / D-116 | Onboarding 单屏 | ONB-V2-001~008 | ✅ 完整 |
| FR-ONBOARD-ACCESSIBILITY-ONDEMAND / AC-7 / D-104 | 辅助功能按需 | ONB-V2-005 / PERM-OD-001~003 | ✅ 完整（含三 conformer 编译看护） |
| FR-ONBOARD-19 / AC-6 | 重启不重弹 | ONB-V2-008 | ✅（承接 v1.1 遗留 TC-M-007，端到端闭环） |
| FR-UI-ABOUT-VERSION / FR-UI-36 / AC-VERSION / D-108 | 版本号三源一致 | BRAND-006 / BRAND-007 | ✅ 完整 |
| §2.0 / D-101 / D-102 | 品牌改名 + Bundle ID 不变 | BRAND-001~007 | ✅ 完整（Bundle ID 保持 com.freeabyss.qingyu 单列 P0） |
| FR-DATA-EXPORT-BACKUP / db §8.4 / D-111 | 数据目录迁移 | DATA-001~005 | ✅ 完整（move/fallback/lightweight/清空/路径） |
| FR-PERM-APPLE-EVENTS / D-103 / AC-CMD-SANDBOX / AC-SIGN | 关 Sandbox + 签名公证 | DIST-001~006 | ✅ 完整 |
| §10.5 移除 Sparkle | 更新策略 | UPD-001~003 | ✅ 完整 |
| §10.7 / D-106 死代码 | 死代码清理 | CODE-001~005 | ✅ 完整（UnifiedSearch/MenuBarView/UnitConverter/OCR/Toast） |
| design §2.5/§16 / M-1 | AppContainer DI + AppDelegate 瘦身 | DI-001~003 | ✅ |
| FR-UI-DESIGN-TOKENS / D-118 | Design Token | TOK-001~006 | ✅ 完整（含 M-2 硬编码看护） |
| FR-UI-COMMAND-BAR / D-120 / D-122 | 命令栏空态/切源 | SEARCH-E-001~005 | ✅ |
| FR-UI-HOTKEYS / FR-ONBOARD-16 | 快捷键冲突检测 | SHORTCUT-001~004 | ✅ |
| FR-UI-SETTINGS-WINDOW / P-03 | 设置新页 | SETNEW-001~005 | ✅ |
| review M-6 强制解包 | 健壮性整改 | ROBUST-001~002 | ✅ |
| FR-UI-A11Y / §9.8 / §7.14 | 无障碍 | ACC-001~005 | ✅ |
| FR-UI-I18N / §9.9 | 国际化 | I18N-001~004 | ✅ |
| §12.1 全 MVP 回归 | 回归 | REG-001~007 | ✅ |
| BUILD 脚本/工程名 | build_and_run/scheme | BUILD-001~002 | ✅ |
| SHOT-UI 标注 UI | pill/mosaic/blur 禁用 | SHOT-UI-001~005 | ✅ |

### 架构 6 改善级问题（M-1~M-6）看护映射

| # | 架构改善级问题 | 看护 TC |
|---|----------------|---------|
| M-1 | AppDelegate 拆分回归风险 | DI-001/002/003 + REG-007（全套回归） |
| M-2 | DesignToken 全量迁移易残留硬编码 | TOK-006（核心页硬编码走查） |
| M-3 | FileSearchSource 检索选型/性能 | SEARCH-F-008（≤300ms 首批） |
| M-4 | 概览页「截图数」统计落点未建模 | SETNEW-005（概览 stat cards 含截图数） |
| M-5 | 关闭 Sandbox 安全审视 | DIST-001（关 sandbox）+ DIST-002（最小 entitlements + Hardened Runtime） |
| M-6 | 强制解包批量整改 | ROBUST-001/002 |

**结论**：6 个改善级问题每个至少 1 条 TC 看护，无遗漏。

---

## 三、6 维评审清单结果

- [x] **覆盖完整性**：所有 v1.2 🔧 需求点、18 项核心变化、8 个 AC、6 个架构改善级问题均有 TC。「容易遗漏」的配置类改动（Bundle ID 不变 BRAND-001、版本号三源 BRAND-007、关 Sandbox DIST-001、删 Sparkle UPD-001、数据迁移 DATA-001~005）均单列 P0/独立 TC。
- [x] **边界充分性**：含边界/负面用例——数据迁移失败 fallback（DATA-002）、文件搜索 1 字符不触发/无结果（SEARCH-F-004/007）、热键冲突（SHORTCUT-001/SHOT-FS-004）、屏幕录制未授权禁用完成（ONB-V2-004）、大目录性能（SEARCH-F-008）、长英文不截断（I18N-002）。
- [x] **可执行性**：每条 TC 有明确前置/步骤/预期，可判定通过与否。模糊项已在本轮修订（见第四节）。
- [x] **独立性**：TC 之间无强制执行顺序依赖；共享验收（清空数据 DATA-004 与 SETNEW-003）以交叉引用标注同一验收点，不重复断言。
- [x] **优先级合理**：P0（49）集中在核心路径与改名/迁移/文件搜索/全屏热键/onboarding/分发/死代码；P1（42）覆盖增强与配置；P2（7）覆盖边缘（Tab 补全、导出灰禁、对比度、动态字体、日期本地化）。P0 数远超任务要求「30+」。
- [x] **负面用例**：迁移失败、权限拒绝、热键冲突、危险命令拒绝（REG-003）、blur 禁用、无结果态均覆盖。

---

## 四、发现的问题与本轮修订（改善级，已直接改进 cases.md）

1. **[已修订] 文件搜索「拼音/首字母匹配」与 PRD FR-SEARCH-13 冲突**：任务指令 SEARCH-F 要求「拼音/首字母/原名匹配」，但 PRD FR-SEARCH-13 明确「文件名暂不做拼音索引，只做原文搜索」。**处理**：SEARCH-F-003 以 PRD 为准，只把「原文匹配」列为 P0 断言，拼音/首字母不作为 v1.2 门禁（如实现选择支持另补 P2），并在 TC 内注明冲突来源。**未改 PRD/架构**。

2. **[已修订] 截图保存默认目录两处不一致**：PRD FR-SHOT-10 = `~/Pictures/Screenshots`，§9.4 P-05 = 「上次目录，默认 `~/Desktop`」。**处理**：在第 5.5 节 v1.2 修订注 + SHOT-007 保持以 FR-SHOT-10（`~/Pictures/Screenshots`）为测试基线，并记录该文档差异，交 leader 校准。**未自行改文档**。

3. **[已修订] 区域/窗口截图默认热键两值并存**：§9.6 总表 = `⇧⌃⌘4/5`，§7.11 与 PRD 示例/US-013 = `⌃⌥⌘4/5`。**处理**：SHOT-FS-001 全屏键 `⌃⌥⌘3` 两处一致无争议；SHORTCUT-002 以 §9.6 总表 `⇧⌃⌘4/5` 为断言基线并注明「以设置页展示为准」，记录差异交 leader。

4. **[已修订] 空态语义演进需明确基线**：FR-SEARCH-14/15「空输入不展示推荐」与 §9.3/D-120「空态显示最近+收藏」表面冲突。**处理**：SEARCH-E-001 与第 5.3 节修订注明确以 D-120 为准（展示入口而非搜索推荐结果），与架构评审 PRD 反馈 #2 一致。

> 以上 4 项均为文档内既存不一致的下游映射，测试侧已选定明确基线并记录，不构成用例本身缺陷，故为改善级、非阻塞。

---

## 五、对 PRD / 架构的反馈（测试视角，未改动源文档）

以下为测试评审中确认的、仍存在于 PRD/架构文档内的不一致点，转呈 leader 决定是否校准（架构评审 review.md 第五节已列 #1/#2，此处补充测试关注的 #3/#4）：

1. **[承接架构反馈 #1] FR-SEARCH-11 文件优先级 60 vs §9.3/D-121 的 75**：架构与本用例集均已采用 75（SEARCH-F-006），建议 PRD 将 FR-SEARCH-11 的 60 更正为 75。
2. **[承接架构反馈 #2] FR-SEARCH-14/15 空态 vs D-120**：建议 PRD 在 FR-SEARCH-14/15 加指向 D-120 的交叉引用。
3. **[新增] 截图保存默认目录冲突**：FR-SHOT-10（`~/Pictures/Screenshots`）vs §9.4 P-05（默认 `~/Desktop`）。建议 PRD/design 统一（测试暂以 FR-SHOT-10 为准）。
4. **[新增] 区域/窗口截图默认热键取值**：§9.6（`⇧⌃⌘4/5`）vs §7.11/US-013 示例（`⌃⌥⌘4/5`）。§7.11 已注「以设置页展示为准」，建议两处对齐取值。

> 结论：无「测试上不可行」的需求；上述均为文档内取值/表述对齐类，不阻塞开发。

---

## 六、自动化可行性评估

| 类型 | 适用 TC（示例） | 说明 |
|------|-----------------|------|
| swift（`swift test`） | TOK-001~005、DATA-001~004、DI-001/003、SEARCH-F-001~004/006/009、SEARCH-E-001~004、SHOT-FS-001/003/004、ONB-V2-002~006/008、PERM-OD-001~003、SHORTCUT-001/004、CalculatorSource/命令/应用回归 | 逻辑层、ViewModel、Provider、迁移逻辑、协议 conformer 可注入替身，全部纯 Swift 可测 |
| xcodebuild（`xcodebuild test`） | BUILD-002、随 App target 的 ViewModel 测试 | 构建级 + Xcode target 内测试 |
| 脚本/静态（可入 CI） | BRAND-001/002/003/007、DIST-001/002、UPD-001、CODE-001~005、ROBUST-001、BUILD-001 | Info.plist/pbxproj/entitlements 解析、源码 grep、版本三源比对 |
| 手工 / E2E UI | SHOT-FS-002、SHOT-UI-001~005、DIST-003/004/005、UPD-002、ONB-V2-001/007、PERM-OD-002（E2E 部分）、SETNEW-002/005、ACC-001~005、I18N-002、REG-005/006、BRAND-004/005 | 系统权限弹窗、真实截图、Gatekeeper、签名公证、VoiceOver、菜单栏图标、真实邮件/浏览器等系统交互不可靠自动化 |

**评估结论**：自动化标注与被测对象性质匹配。逻辑与配置类尽量 swift/脚本自动化（可回归、可入 CI）；系统交互类诚实标注手工/E2E，不虚构自动化能力。多数 TC 为「swift + 手工」混合，自动化覆盖逻辑、手工补系统交互。

---

## 七、结论

- **状态**：**APPROVED_WITH_MINOR_FIXES**
- **阻塞级问题**：**0**
- **改善级问题**：**4**（第四节 4 项文档不一致的下游映射，已在本轮直接修订进 cases.md 并选定测试基线）
- **需 leader 校准的源文档不一致点**：**4**（第五节，均不阻塞，测试已选定基线）
- **P0 TC 数**：49（≥ 任务要求 30+）；覆盖改名/迁移/文件搜索/全屏热键/onboarding/分发/死代码全部核心路径
- **架构 6 改善级问题（M-1~M-6）**：每个至少 1 条 TC 看护，无遗漏
- **是否可进入 ⑤ 开发**：**是**。用例集自洽、可执行、追溯完整；开发按 review.md §八 T-A~T-O 推进，每完成一批可对应回填 report.md v1.2.0 执行结果。
