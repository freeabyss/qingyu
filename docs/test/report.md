# Mac Super Assistant（Assistant）v1.0.0 测试执行报告

## 版本记录

| 版本 | 上线日期 | 说明 |
|------|---------|------|
| v1.0.0 | 2026-07-02 | 首次上线，Mac Super Assistant MVP（22 个用户故事） |

> 本文件为 v1.0.0 迭代的测试执行结果、通过/失败统计与自动化基线摘要。用例定义见同目录 [cases.md](cases.md)，开发进度流水见 [../progress.md](../progress.md)。

## 执行结果摘要卡片

| 维度 | 结果 |
| :--- | :--- |
| 任务完成 | 22/22 通过（US-001 ~ US-022） |
| `swift test` | 124/124 通过、0 失败 |
| `xcodebuild build` | `** BUILD SUCCEEDED **` |
| `xcodebuild test` | 119/119 通过、0 失败，`** TEST SUCCEEDED **` |
| 阻塞项 | 无 |
| 手动验收 | 系统权限/菜单栏/全局快捷键/真实截图/邮件/浏览器等 P0/P1 手动项需在 release-candidate 环境执行（后台子 Agent 未虚构人工结果） |

已知遗留 warning：`--skip-update` deprecation warning、既有 Swift 6 Sendable/NSLock warning，不影响测试通过。

---

## 2026-08-22：当前产品基线完善

- 修复 Xcode 测试 Target 未设置 `DEVELOPMENT_TEAM` 导致宿主 App 与测试 bundle Team ID 不一致、无法加载测试的问题；应用、单元测试和 UI 测试 Target 现统一使用 `454XB348PX`。
- `xcodebuild test -only-testing:QingyuTests/SystemCommandSourceTests`：通过。覆盖新增“打开剪贴板历史”白名单命令、中文/英文别名搜索及专用通知路由。
- `xcodebuild test -only-testing:QingyuTests/SearchPanelViewModelTests -only-testing:QingyuTests/HotkeyConflictDetectorTests`：通过。覆盖命令栏有首页内容时自动展开，以及快捷键冲突检测。
- `xcodebuild test -only-testing:QingyuTests/SearchPanelViewModelTests`：通过。新增覆盖空输入首页的“打开剪贴板历史”、区域/窗口/全屏截图快捷操作。
- `xcodebuild test -only-testing:QingyuUITests/CommandBarUITests/testTCUI023SearchOpensClipboardHistory`：通过。覆盖命令栏英文别名搜索、回车路由到独立剪贴板历史窗口，以及命令栏关闭。
- `xcodebuild test -only-testing:QingyuUITests/CommandBarUITests`：通过。命令栏完整 UI 回归通过，确认新增首页快捷操作未破坏输入、回车、ESC 与空输入行为。
- `xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu -destination 'platform=macOS'`：完整 Xcode 测试套件通过。
- `xcodebuild build-for-testing`：通过。清理快捷键冲突检测和测试辅助代码中的 Swift 6 并发/弃用警告；仍有 Xcode 26 SDK 与项目 macOS 13 部署目标的 XCTest 链接警告，不影响编译和测试通过。
- `xcodebuild test -only-testing:QingyuTests/HotkeyConflictDetectorTests -only-testing:QingyuTests/SystemCommandSourceTests`：通过。确认六个可重绑定快捷键的默认值、冲突检测与包含“打开剪贴板历史”的 15 条白名单命令目录；首次启动即注册全局入口，欢迎向导不会阻断搜索、剪贴板历史或截图快捷键。

---

## 执行记录（时间线）

### 2026-06-12 - US-001 App Shell 验证

- `swift test --skip-update`：通过，执行 35 个 XCTest，35 通过、0 失败。
- `xcodebuild -project SnapVault.xcodeproj -scheme SnapVault -configuration Debug build`：通过，产物为 `Assistant.app`。
- `xcodebuild test -project SnapVault.xcodeproj -scheme SnapVault -configuration Debug`：通过,执行 35 个 XCTest，35 通过、0 失败。
- 验证重点：macOS 13 deployment target 保持 13.0；Info.plist 保持 `LSUIElement=true`；菜单栏 App Shell 与菜单项已具备构建级验证，真实菜单栏交互仍按手动验收 `MENU-001` ~ `MENU-004` 执行。

### 2026-06-12 - US-009 CalculatorSource 计算与单位换算验证

- `swift test --skip-update`：通过，执行 87 个 XCTest，87 通过、0 失败。
- `xcodebuild -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug build`：通过，`** BUILD SUCCEEDED **`。
- `xcodebuild test -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug`：通过，执行 87 个 XCTest，87 通过、0 失败，`** TEST SUCCEEDED **`。
- 验证重点：基础四则、括号、小数、除零/非法表达式防护、长度/重量/数据大小/温度换算、货币/复杂函数/变量/历史/范围外单位拒绝、`SearchService.execute(.copyText)` 写入系统剪贴板。

### 2026-06-13 - US-021 测试基线与自动化验收

- `swift test --skip-update`：通过，执行 122 个 XCTest，122 通过、0 失败。
- `xcodebuild -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug build`：通过，`** BUILD SUCCEEDED **`。
- `xcodebuild test -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug`：通过，执行 117 个 XCTest，117 通过、0 失败，`** TEST SUCCEEDED **`。
- 验证重点：确认并记录 SwiftPM/Xcode 测试入口；建立自动化覆盖矩阵，覆盖 SearchSource、搜索排序、拼音、CalculatorSource、单位换算、contentHash 去重、Core Data 临时 store、FileResourceStore 临时目录、ClipboardRepository、InMemorySearchIndex、黑名单、使用统计；整理 P0/P1 自动化或手动验证方式，权限、截图、全局快捷键、菜单栏、Onboarding 等系统交互保留为手动验收清单。

### 2026-06-13 - US-022 MVP 集成验收与文档收尾

- 依赖状态：`.claude/task.json` 中 US-001 ~ US-021 均为 `passes=true`、`blocked=false`，US-022 依赖满足。
- 文档一致性：复核 `doc/prd.md`、`doc/architecture.md`、`doc/architecture_db.md`、`doc/architecture_api.md`、`doc/test.md` 与当前实现；`doc/prd.md` 和 `doc/architecture_db.md` 的未提交内容确认属于当前 Assistant MVP 文档基线（Core Data + 文件系统、Provider 架构、GitHub Release + 项目主页发布、范围排除），纳入本次收尾提交。
- 范围外能力检查：确认 MVP 用户入口不包含账号、支付、订阅、Mac App Store、任意 shell、sudo、关机/重启系统/注销、签名公证或自动安装更新；检查更新入口打开 GitHub Releases 手动下载。旧 SnapVault 兼容源码中遗留的 OCR / ContentStore / FileSearchSource 实现已从 SwiftPM target 与 Xcode App target 构建输入排除，避免进入 MVP 构建产物；源文件仍留存为历史兼容归档，后续可单独清理。
- GitHub Release + 项目主页发布材料：复核 `README.md`、`PRIVACY.md`、`CHANGELOG.md`、`THIRD_PARTY_NOTICES.md`、`ReleaseLinks`、`appcast.xml`，确认项目主页、隐私政策、反馈邮箱、版本记录和 GitHub Releases 链接已准备；真实截图/GIF 仍需发布前从候选构建捕获。
- `swift test --skip-update`：通过，执行 124 个 XCTest，124 通过、0 失败。仍有 `--skip-update` deprecation warning 与既有 Swift 6 Sendable/NSLock warning，不影响通过。
- `xcodebuild -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug build`：通过，`** BUILD SUCCEEDED **`。
- `xcodebuild test -project /Users/abyss/workspace/abyss/assistant/SnapVault.xcodeproj -scheme SnapVault -configuration Debug`：通过，执行 119 个 XCTest，119 通过、0 失败，`** TEST SUCCEEDED **`。
- 手动验收记录：本次后台子 Agent 无法可靠操作真实菜单栏、系统权限弹窗、全局快捷键、屏幕录制授权、辅助功能授权、真实截图捕获、邮件客户端和浏览器页面；未虚构人工结果。相关 P0/P1 手动项仍按 [cases.md](cases.md) 第 5/6/7 节在 release-candidate 环境执行。
- 已知问题 / 后续建议：发布前捕获 README 所列产品截图/GIF；在真实 macOS 环境复测 Onboarding 权限拒绝/授权、菜单栏无 Dock、全局快捷键、截图三模式、剪贴板真实格式恢复、邮件反馈和 GitHub Releases 打开；扩大公开分发前补齐 Developer ID 签名与 Apple Notarization；后续单独删除或归档未参与构建的旧 SnapVault OCR/文件搜索源码和旧本地化键。

---

## v1.0.1（2026-07-02，Issue #1、PR #2）

- **swift test**：126/126 全绿（基线由 v1.0.0 的 124 提升 +2）
- **xcodebuild test**：119/119 TEST SUCCEEDED（新增用例未纳入 Xcode SnapVaultTests target，P2 遗留）
- **手动验收**：TC-M-001（Debug 启动无弹窗）/ TC-M-002（Release 启动无弹窗）/ TC-M-003（检查更新跳浏览器）均由 @user 亲自执行通过
- **覆盖 AC**：AC-1 / AC-2 / AC-3 / AC-4 全通过
- **详情**：doc/iterations/v1.0.1/test/report.md

---

## v1.1.0（2026-07-03，Issue #3、PR #4）

- **swift test**：134/134 全绿（v1.0.1 基线 126 → 134，+8：T-001 新增 2 + T-002 新增 6）
- **xcodebuild test**：125/125 TEST SUCCEEDED（v1.0.1 基线 119 → 125；新增 T-002 用例追加到既有 OnboardingViewModelTests.swift 随 target 执行；T-001 的 PermissionServiceProtocolConformanceTests.swift 未纳入 Xcode target，P2 遗留，与 v1.0.1 处理一致）
- **手动验收（@user）**：TC-M-001~M-006 通过（TCC 注册弹窗 / App 出现在列表 / 授权后 Continue / Skip 7 步可见 / Alert Cancel 无副作用 / Skip 进主界面）
- **code review**：T-001/T-002/T-003 APPROVED；clipboardEnabled 显式 false 落地
- **未验证（留待下一迭代，诚实标注）**：
  - TC-M-007 跳过后重启不重弹（代码层 TC-U-004 单测覆盖持久化，端到端未验）
  - TC-M-008 hotkey 触发按需申请 Alert（代码层 AppDelegate.ensureScreenRecordingPermission 补 request + code review 通过，端到端未验）
  - TC-M-009 SettingsViewModel 权限入口（P2 遗留：未改为注入 + 未补 request）
- **详情**：doc/iterations/v1.1.0/test/report.md

---

## v1.2.0（2026-07-03 定稿用例；开发完成，T-019 自动化回归全绿 2026-07-06；2026-07-07 上线，Issue #5、PR #6）

> 品牌改名清羽 Qingyu 迭代。v1.2 测试用例已在 `cases.md` 第 11 节定稿（新增 98 条 TC，P0=49/P1=42/P2=7，前缀 TOK/BRAND/DATA/DI/SEARCH-F/SEARCH-E/SHOT-FS/SHOT-UI/ONB-V2/PERM-OD/CODE/DIST/UPD/SHORTCUT/SETNEW/REG/BUILD/ROBUST/ACC/I18N），并对第 5 节受 UI 重设计影响的旧 TC 就地标注「v1.2 修订」。评审记录见 `doc/iterations/v1.2.0/test/review.md`（结论 APPROVED_WITH_MINOR_FIXES，阻塞级 0）。
>
> **T-019 执行结果已回填**——见本节「自动化回归实际执行结果」「静态校验结果」「手工验收清单」「已知遗留」。以下为原计划执行范围，保留供追溯。

### 计划执行范围

- **`swift test --skip-update`**：
  - 新增/待建：`DesignTokenTests`、`BrandingConsistencyTests`、`DataMigrationTests`、`AppContainerTests`、`GlobalShortcutTests`、`HotkeyConflictDetectorTests`、`OnDemandPermissionTests`。
  - 转接线回归：`FileSearchSourceTests`（从未实例化 → 接线后回归）。
  - 增补：`SearchServiceCoreTests`（文件权重 75）、`SearchPanelViewModelTests`（空态最近+收藏、⌘1-6、⌘K）、`OnboardingViewModelTests`（单屏、按需权限、completedAt 持久化）、`PermissionServiceProtocolConformanceTests`（onDemandAccessibilityCheck 三 conformer）、`CalculatorSourceTests`（换算并入回归）、`UpdateServiceTests`（无 Sparkle、跳 Releases）。
  - 删除：`UnitConverterSourceTests`、OCR 相关测试。
  - 基线：v1.1 为 swift 134；删旧增新后于开发完成时重新核定（预期净增，具体数回填）。
- **`xcodebuild build` / `xcodebuild test`**：改名后 scheme/target/product 名 Qingyu 应能构建（BUILD-002）；Xcode target 测试基线 v1.1 为 125，回填实际数。
- **脚本 / 静态校验（可入 CI）**：版本号三源一致（BRAND-007）、entitlements 关 Sandbox + apple-events（DIST-001/002）、无 Sparkle 残留（UPD-001）、死代码 grep（CODE-001~005）、强制解包 grep（ROBUST-001）、build_and_run.sh pgrep Qingyu（BUILD-001）。
- **手工验收清单范围**：
  - 品牌/图标：BRAND-005；关于页 1.2.0（BRAND-006）。
  - 文件搜索 E2E：AC-FILE（SEARCH-F-005）。
  - 全屏截图热键 E2E：AC-FULLSCREEN（SHOT-FS-002）。
  - Onboarding 单屏 + 屏幕录制 TCC + 辅助功能稍后 + 重启不重弹：ONB-V2-001/003/005/008、PERM-OD-002。
  - 分发签名：AC-CMD-SANDBOX（DIST-003）、AC-SIGN（DIST-004/005）、Gatekeeper、公证 staple。
  - 截图标注 UI：SHOT-UI-001~005（pill 工具条、mosaic、blur 禁用 tooltip）。
  - 设置新页：SETNEW-001~005（外观/数据/清空/打开目录/侧栏分组）。
  - 无障碍：ACC-001~005（VoiceOver、键盘遍历、对比度、减弱动效）。
  - i18n：I18N-002（长英文不截断）。
  - 剪贴板/命令/截图/权限回归：REG-001~007。
- **上线前专项校验**：反馈邮箱 qingyu_freeabyss@163.com 真实可收件（BRAND-004）；官网/隐私政策 URL（qingyu.app 域名）最终确定。

### 自动化回归实际执行结果（T-019，2026-07-06）

> 执行人：后台子 Agent（T-019 全量自动化回归）；macOS：Darwin 25.5.0（arm64）；构建方式：xcodebuild + swift test 命令行。手工/系统交互项未由 Agent 虚构，统一标「待上线前手工验证」。

| 维度 | 计划 | 实际 |
|------|------|------|
| `swift test` | 全绿，基线重新核定 | **159 / 159 通过、0 失败**（v1.1 基线 134 → 159，净增 25） |
| `xcodebuild build`（Debug clean build） | BUILD SUCCEEDED（target Qingyu） | **`** BUILD SUCCEEDED **`** |
| `xcodebuild build`（Release） | BUILD SUCCEEDED | **`** BUILD SUCCEEDED **`**（ad-hoc 签名，note: Disabling hardened runtime with ad-hoc codesigning） |
| `xcodebuild test`（Debug） | 全绿 | **148 / 148 通过、0 失败，`** TEST SUCCEEDED **`** |
| P0 TC（49 条） | 全过 | 自动化覆盖部分全绿；系统交互 P0 待上线前手工验证（清单见下） |
| 阻塞项 | 期望 0 | **0**（Release build 未因 codesign 证书失败；ad-hoc 签名通过） |

### 静态校验结果（脚本 a~f，全部通过）

| 项 | 命令要点 | 结果 |
|----|---------|------|
| a | grep `Mac Super Assistant`（swift/plist/entitlements，排除 CHANGELOG/doc） | **无匹配** ✔ 品牌改名彻底 |
| b | grep `try!` / `as! ` / `fatalError`（排除 init(coder)） | **仅 4 处 `fatalError("init(coder:) has not been implemented")`**（SettingsWindowController / ClipboardHistoryWindowController / AnnotationEditorWindow / ScreenshotOverlay），均为允许的 NSCoder 样板；无其他危险强解包 ✔ |
| c | grep `SUPublicEDKey` / `SUFeedURL` / `SUEnableAutomaticChecks`（Info.plist） | **无匹配** ✔ Sparkle 残留已清 |
| d | grep `com.apple.security.app-sandbox`（Qingyu.entitlements） | key 存在，值 **`<false/>`** ✔ Sandbox 已关 |
| e | grep `TODO` / `FIXME` / `XXX`（swift，排除 #Preview/test） | **无匹配** ✔ 无剩余 TODO |
| f | `codesign -d --entitlements`（Release build 产物） | `app-sandbox=false`、`automation.apple-events=true`、`files.user-selected.read-write=true`、`get-task-allow=true`、`screencapture=true` ✔ 与预期一致（DIST-001/002/003） |

版本号三源一致（BRAND-007）：`MARKETING_VERSION = 1.2.0`（pbxproj）、`CFBundleShortVersionString = 1.2.0`（Info.plist）✔。

### 手工验收清单（P0 手工项，待上线前人工验证）

以下 P0 手工 TC 涉及真实系统权限弹窗、菜单栏交互、全局快捷键、真实截图捕获、Gatekeeper/公证等，后台 Agent 无法可靠执行,统一标注「**待上线前手工验证**」：

- 品牌/图标：BRAND-005（菜单栏清羽单色 template 图标）、BRAND-006（关于页显示 1.2.0）
- 文件搜索 E2E：SEARCH-F-005（AC-FILE）
- 全屏截图热键 E2E：SHOT-FS-002（AC-FULLSCREEN，⌃⌥⌘3）
- Onboarding 单屏 + 屏幕录制 TCC + 辅助功能稍后 + 重启不重弹：ONB-V2-001 / ONB-V2-003 / ONB-V2-005 / ONB-V2-008、PERM-OD-002
- 分发签名：DIST-003（AC-CMD-SANDBOX，AppleEvents 真实执行）、DIST-004 / DIST-005（AC-SIGN，Developer ID + Gatekeeper + 公证 staple）
- 截图标注 UI：SHOT-UI-001~005（pill 工具条、mosaic、blur 禁用 tooltip）
- 设置新页：SETNEW-001~005（外观/数据/清空/打开目录/侧栏分组）
- 无障碍：ACC-001~005（VoiceOver、键盘遍历、对比度、减弱动效）
- i18n：I18N-002（长英文不截断）
- 剪贴板/命令/截图/权限回归：REG-001~007
- 上线前专项：BRAND-004（反馈邮箱 qingyu_freeabyss@163.com 可收件）、qingyu.app 域名官网/隐私政策 URL 最终确定

### 已知遗留

- **`SearchBlacklistRepositoryTests` flaky**：`testAddList...` / `testSearchServiceFilters...` 偶发 `*** Collection was mutated while being enumerated (NSGenericException)`，为 Core Data/NSSet fixture 并发问题（与 v1.2 代码改动无关，`git stash` 剔除改动后仍可复现）。`swift test` 本次首跑亦偶发一次 NSException crash，重跑即绿（159/159）。建议后续单独任务修 fixture 并发。
- Release build 采用 ad-hoc 签名（无 Developer ID 证书环境）；hardened runtime 在 ad-hoc 下被禁用。源码合入不受影响，Developer ID 签名 + Apple 公证 staple 属发布步骤，留待上线前执行（DIST-004/005）。
- 既有 Swift 6 Sendable/NSLock concurrency warning 若干，不影响构建与测试通过。
