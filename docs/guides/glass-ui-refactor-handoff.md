# 玻璃 UI 重构 · 交接文档

> 交接时间：2026-11-18 ｜ 基线提交 `c3a85c2` ｜ **2026-11-18 全部完成**（命令栏 `60a17b4`、设置+引导+收尾 `fe4b5f1`，版本 0.4.210 / 610）
> **2026-11-18 第二轮（0.4.211 / 611）：玻璃被 tint 盖死的根因修复**，见下方「零、0.4.211 玻璃根因修复」。
> 上游设计稿：`design-demos/`（`dir-3.html` 主界面板、`clipboard-3.html` 剪贴板；`settings-3.html` 已存在，设置页实现时曾缺失）

## 零、0.4.211 玻璃根因修复（必读）

**问题**：用户反馈「界面很奇怪，没有完全玻璃化」。根因是四个界面的玻璃都被自己的
叠加层盖死——`tint` α0.78~0.90，桌面最多透 14%~26%，观感是实心深色面板
（设置/引导用 `tintOpaque` α0.90，几乎完全不透明）。而设计稿意图是 25%~45% 的
梅紫纱、背景色明显透出。

**为什么上一轮没发现**：验证用的 `--uitest-capture-png` 走 `cacheDisplay` 离屏自绘，
**渲染不出 behind-window 玻璃与材质**，每轮「双外观验证」全绿但看到的从来不是真实效果。

**修复（`JadeGlass.swift` 双路径渲染，调用方无感知）**：
- **macOS 26+**：`NSGlassEffectView`（系统 Liquid Glass）。折射、明暗自适应、边缘高光、
  文字可读性全部由系统处理；`liquidTint*` 令牌只负责品牌色相（α ≤ 0.20 / 阅读档 0.38）。
  `jadeGlassEdge` 在 26+ 为 no-op（系统玻璃自带边缘，再画就是双描边）。
- **macOS 12–25 回退**：材质 + tint 叠加层不变，但 α 全面下调
  （tint 0.62/0.60、tintOpaque 0.74/0.78），玻璃能真正透出来。
- 调用侧：`jadeGlassSurface(radius:tint:)` 的 `tint` 参数从 `Color` 改为
  `JadeGlassTintKind`（`.standard` / `.reading`），三个原 `tintOpaque` 调用点已同步。

**测试锁**（`JadeDesignTokenTests`）：
- `testGlassSurfaceBackendMatchesOS`：26+ 必须走 `.liquidGlass`，旧系统必须走 `.materialFallback`。
- `testGlassTintsNeverCoverTheMaterial`：各档 tint 的 α 上限（回退 0.70/0.85、真玻璃 0.25/0.45），
  防止再次把玻璃盖死。

**新的真像素验证工具**：`--uitest-capture-live-png <path>`（DEBUG）。
用 `CGWindowListCreateImage` 截**真实合成像素**（玻璃的模糊/折射/边缘高光都在），
截自己进程的窗口不需要屏幕录制权限。注意：`screencapture` CLI 会按调用方过 TCC，
Debug 构建无授权会被拒（实测 exit 1），所以走进程内 API。
用法与 `--uitest-capture-png` 相同（可与 `--uitest-trigger` / `--uitest-dark-appearance` 组合）。

**仍然有效的约束**：后台启动的 app（含 agent 触发的 `open`）会被 macOS 的后台应用管理
推迟显示窗口——窗口创建了但没有合成表面。live 截图若只拍到壁纸，先让 app 获得真实用户激活。

## 一、任务目标

把已评审通过并选定（用户明确选「方向三 · 玻璃」）的设计语言，完整落到 SwiftUI 真实程序中。

**完成的定义**：四个界面全部玻璃化、双外观（深/浅）截图验证、`./scripts/verify.sh` 全绿、版本号递增并提交。

| 界面 | 状态 |
|---|---|
| 剪贴板历史窗口 `ClipboardHistoryView` | ✅ 已完成（`c3a85c2`） |
| 命令栏 `CommandBarView` | ✅ 已完成（`60a17b4`） |
| 设置窗口 `SettingsView`（含五个子页） | ✅ 已完成（`fe4b5f1`） |
| 首启引导 `OnboardingView` | ✅ 已完成（`fe4b5f1`，纳入并完成） |

## 补充：第三阶段新增的令牌与组件（`fe4b5f1`）

- `JadeGlass.tintOpaque`：长时阅读窗口叠加底（深 α0.90 / 浅 α0.86），设置与引导的根使用
- `JadeGlass.cardFill`：卡片浮层（深白 α0.08 / 浅白 α0.55），`JadeSettingsCard`、引导卡片、详情卡片
- `jadeGlassSurface(radius:tint:)`：叠加底可自定义
- `JadeSegmentedPicker`（`JadeSettingsComponents.swift`）：胶囊轨道 + 实心选中段，
  替换会盖死玻璃的系统 `.segmented`；全仓 6 处已统一（注释工具栏在画布窗口，保留系统样式）
- 设置/引导窗口宿主已 `backgroundColor = .clear + isOpaque = false`；`jadeWindowSurface` 已删除

## 二、已完成部分（剪贴板窗口）

### 新增令牌层

`Qingyu/Views/Design/JadeGlass.swift`（新文件，已登记 pbxproj 四处引用）

| 令牌 | 用途 | 深色 / 浅色 |
|---|---|---|
| `tint` / `tintNS` | 压在系统材质上的叠加底 | `#0D071C` α0.78 / 暖白 α0.74 |
| `edge` | 1pt 外描边 | 白 α0.42 / 黑 α0.10 |
| `innerHighlight` | 顶部 32% 内高光 | 白 α0.26 / 白 α0.60 |
| `separator` | 分隔线 | 白 α0.14 / 黑 α0.08 |
| `rowHover` / `rowSelected` | 行悬停 / 选中底 | 白 α0.06 / α0.10；黑 α0.045 / α0.075 |
| `selectionMark` | 选中左竖条 | 白 α0.95 / 品牌蓝灰 |
| `keycapFill` / `keycapBorder` | 键位胶囊 | 白 α0.20 / α0.26；黑 α0.06 / α0.12 |
| `controlHover` / `controlActive` | 控件悬停 / 激活底 | 白 α0.16 / 黑 α0.06–0.10 |

修饰器：
- `jadeGlassSurface(radius:)` — 系统材质 `.hudWindow` + `tint` 叠加 + 圆角裁剪
- `jadeGlassEdge(radius:lineWidth:)` — 外描边 + 顶部内高光

### 已改文件

| 文件 | 改动 |
|---|---|
| `ClipboardHistoryView.swift` | 根视图 `jadeWindowSurface` → `jadeGlassSurface + jadeGlassEdge`；列表容器移除不透明底；分隔线改 `JadeGlass.separator`；搜索框/暂停横幅改 `controlHover`；新增 `shortcutHintBar` + `keycap` + `isFileItemSelected`；toast `bottomInset` 加提示条高度 |
| `ClipboardDetailPane.swift` | 移除整体 `surface1` 底；删除「复制到剪贴板」按钮；失败原因条改 `controlHover`；放大按钮底色改 `controlHover` |
| `JadeListRow.swift` | 行选中/悬停改 `JadeGlass.rowSelected / rowHover`；`JadeRowActionStyle.tileBackground` 改 `controlHover` |
| `JadeDesignTokenTests.swift` | `testRowActionStyleRevealsOnHover` 断言由 `JadeColor.surface3` 改为 `JadeGlass.controlHover` |
| `Localizable.xcstrings` | 新增 4 条五语种键：`clipboard.shortcut.copy/pin/delete/fileExtra` |

## 三、命令栏改造清单（下一步直接照做）

文件：`Qingyu/Views/SearchPanel/CommandBarView.swift`

1. **第 66 行** `.jadeWindowSurface(radius: .xxl)` → 改为：
   ```swift
   .jadeGlassSurface(radius: .xxl)
   .jadeGlassEdge(radius: .xxl)
   ```
2. **结果行背景**（`CommandBarResultRow` 内）：`JadeColor.primaryFill` / `JadeColor.surface2` 换成 `JadeGlass.rowSelected` / `JadeGlass.rowHover`；选中描边可用 `JadeGlass.edge`。
3. **第 417 行** `.background(JadeColor.surface1.opacity(0.9), in: JadeRadius.sm.shape)`（⏎ 徽标底）→ `JadeGlass.keycapFill`，描边 `JadeGlass.keycapBorder`。
4. **输入行/底部快捷键行**的分隔线改 `JadeGlass.separator`。
5. 检查是否有 `.background(JadeColor.surface1|surface2|surface3)` 残留——**任何不透明底都会把玻璃盖死**（见踩坑一）。

## 四、设置窗口改造清单

文件：`Qingyu/Views/Settings/SettingsView.swift`（928 行）与 `JadeSettingsComponents.swift`

已定位的不透明底（**全部要处理**）：
- 第 48 行 `.background(JadeColor.surface1.ignoresSafeArea())`
- 第 105 行 `.background(JadeColor.surface1)`（侧栏）
- 第 545 行 `.background(JadeColor.surface1)`
- 第 730 行 `.background(JadeColor.surface1)`

改造要点：
1. 窗口根 → `jadeGlassSurface + jadeGlassEdge`；**但设置是长时阅读窗口**，建议 `tint` 用更不透明的变体（可新增 `JadeGlass.tintOpaque`，α0.90/0.86），避免桌面内容干扰阅读。
2. 侧栏选中项 → `JadeGlass.controlActive` 胶囊底（对应设计稿的 `it.on`）。
3. 卡片/分组底（`settingsCard`）→ 半透明 `controlHover` 或新增 `JadeGlass.cardFill`。
4. 主题/语言分段控件 → 胶囊形，选中态实心白（深色）/实心深（浅色）。
5. 开关（Toggle）在玻璃上需确认拇指与轨道对比度。

## 五、验证方法（每个界面改完都要跑）

```bash
# 1. 构建
xcodebuild -project Qingyu.xcodeproj -scheme Qingyu -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO

# 2. 真实截图（深色 + 浅色）
open -a DerivedData/Build/Products/Debug/Qingyu.app --args \
  -AppleLanguages "(zh-Hans)" -AppleLocale zh_CN \
  --uitest-dark-appearance --uitest-trigger openClipboard \
  --uitest-mark-onboarding-completed --uitest-data-dir /tmp/qy-g \
  --uitest-capture-delay 6 --uitest-capture-png /tmp/qy-win/dark.png
# 去掉 --uitest-dark-appearance 再拍浅色

# 3. ⚠️ 必须清理语言污染（否则 verify 会误报）
defaults delete com.freeabyss.qingyu AppleLanguages

# 4. 门禁
./scripts/verify.sh
```

可用 `--uitest-trigger`：`openClipboard` / `openSearch` / `openSettings` / `openClipboardSettings` / `openScreenshotSettings` / `openAbout` / `openOnboarding`。
注意 **`openSettings` 只打开「通用」页**，不能代表其它设置页已验证。

## 六、踩坑记录（务必先读）

### 1. 只换根视图 = 白做
玻璃是「背景层」。只要内部还留着 `JadeColor.surface1/surface2/surface3` 这类**不透明底**，材质就被完全盖住。
现象：详情区变成一块黑/白实心区。修法：逐个移除内部 surface 底，换成 `JadeGlass.*` 半透明令牌。

### 2. `-AppleLanguages` 会持久化并污染测试
用 `-AppleLanguages "(zh-Hans)"` 启动截图后，该值被写入应用域 UserDefaults，
后续 `xcodebuild test` 读到中文语言，导致本地化断言失败（表现为「换算 vs Convert」「计算 vs Calculator」）。
**每轮截图后必须**：`defaults delete com.freeabyss.qingyu AppleLanguages`

### 3. 新 Swift 文件要手工登记 pbxproj
本项目没有 `PBXFileSystemSynchronizedRootGroup`，新增源文件需在 `project.pbxproj` 补四处：
`PBXBuildFile`、`PBXFileReference`、group `children`、`Sources` phase。

### 4. 玻璃的真实可读性风险
真实窗口背后是**桌面内容**（纯白网页 / 深色编辑器都可能），不像设计稿有固定彩色壁纸。
因此材质只负责层次，可读性由 `tint` 叠加层保证。**改动 `tint` 透明度必须重新测对比度**：
要求正文 ≥ 4.5:1，测量方法是排除文字像素后取行带背景中位数。

### 5. 设计稿里的固定壁纸不可复现
`design-demos/dir-3.html` 用彩色渐变模拟背景。真实程序里没有这层壁纸，
所以「玻璃感」会比设计稿弱——这是正确取舍，不要为了追效果降低可读性。

## 七、验收标准

- [ ] 命令栏、设置、引导（若纳入）全部使用 `jadeGlassSurface + jadeGlassEdge`
- [ ] 代码库中不存在界面层残留的不透明 `surface1/2/3` 大块底色（`grep -rn "background(JadeColor.surface" Qingyu/Views`）
- [ ] 深色 / 浅色截图各一套，肉眼确认层次与文字清晰
- [ ] `./scripts/verify.sh` 全绿（本地化键数、全量用例）
- [ ] `Qingyu/Info.plist` 与 `project.pbxproj` 版本号同步递增，构建号 +1
- [ ] 提交信息说明「问题 → 改动 → 验证」
- [ ] `git push origin main`

## 八、可直接复制的下一步命令

```bash
cd /Users/abyss/workspace/my/projects/qingyu
# 1) 先看命令栏现状
sed -n '55,80p' Qingyu/Views/SearchPanel/CommandBarView.swift
# 2) 按第三节改完，构建
xcodebuild -project Qingyu.xcodeproj -scheme Qingyu -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO
# 3) 截图 + 清理 + 门禁（见第五节）
```
