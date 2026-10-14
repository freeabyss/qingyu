# Task 017：贴图交互增强

**目标：** 把贴图窗口从「能贴」提升到「好用」：可磁性吸附到窗口/屏幕边缘，可用热键切换点击穿透、缩放与透明度，双击即可关闭。

**范围：** 贴图窗口的移动吸附、三个新增热键、双击行为、贴图操作的快捷键提示。不改载荷解析与恢复队列语义。

**相关模块：** `PinWindowController`、`PinWindowView`、`PinItem`、`PinStore`、`Views/Pinning`、`ScreenshotSettingsPage`。

> 本任务为**增强型**，01–04 各自独立，可按序逐条交付；每条单独跑验证并提交。

## 业务规则（总）

- 所有新增热键都作用于**光标下的贴图窗口**；光标下没有贴图时：点击穿透热键作用于**全部**贴图（等价于整体切换），缩放与透明度热键不响应（不报错）。
- 新增热键都必须在贴图窗口获得焦点时可用，且不与截图/搜索/剪贴板的既有绑定冲突。
- 贴图窗口的每一个新交互都不得改变既有的「关闭 / 恢复 / 销毁 / 隐藏」语义与恢复队列容量规则。

## 01 — 磁性吸附

**规则：** 拖动贴图窗口时，其边缘在进入吸附阈值后对齐到**同屏内其它可见窗口的边缘**或屏幕可见区边缘；阈值可配置、可关闭。按住修饰键（默认 ⌘）拖动时临时禁用吸附。吸附只影响拖动结束时的落位，不改变贴图尺寸（除非吸附到屏幕边缘且用户拖动的是缩放手柄）。

**落实（2026-10-14）：** 新增 `PinSnapping`（全部为纯函数，不依赖真实屏幕）。每轴独立处理：把贴图的 左/中/右（下/中/上）与每个参照物的同样三条边**两两比对**，阈值内位移最小者胜出 —— 因此「边对边」「中对中」「首尾相邻贴合」三种情形用同一套逻辑覆盖。同距离冲突时**屏幕边缘优先于窗口边缘**。吸附只改原点并取整，**不改尺寸**。

- **参照物**：当前屏可见区 + 同屏其它可见窗口（`CGWindowListCopyWindowInfo` 只取 `layer == 0` 且不透明的窗口，跳过桌面/状态栏等浮层）。CG 全局坐标（原点在主屏左上）→ AppKit 坐标（原点在主屏左下）的换算由 `appKitRect(fromCGWindowBounds:primaryScreenHeight:)` 承担并单独测试 —— 不换算会得到上下颠倒的吸附结果。
- **默认值决策**：阈值默认 **8 点（开启）**。这与 Task 012 截图选区吸附「默认关闭」不同，是有意为之：磁性吸附是本子项的主体能力，默认关闭等于交付了看不见的功能；截图选区吸附默认关闭是为了不干扰像素级框选。0 即关闭。
- **不接管鼠标事件**：只监听 `NSWindow.didMoveNotification`，在鼠标松开后落位（`NSEvent.pressedMouseButtons` 轮询确认拖动结束），因此贴图内容里的文本选择、双击关闭等既有交互完全不受影响。吸附自身触发的移动通知用 `isApplyingSnap` 短路，避免递归。窗口关闭/销毁/整体销毁时统一 `teardownSnapping` 摘掉监听与待办定时器。
- **临时禁用**：拖动结束时按住 ⌘ 则不吸附。
- **阈值清洗**：负值 / `NaN` / 非有限值 → 0（关闭）；上限 40 点（`PinSnapping.maximumThreshold`）。

**验收：** 单测覆盖吸附候选组装与退化矩形过滤、阈值边界与关闭、最近者优先、首尾相邻贴合、中对中、屏幕边缘优先、尺寸不变、CG→AppKit 坐标换算（`PinSnappingTests`，12 条）；真实拖拽：靠近另一个窗口边缘时贴边到位，按住 ⌘ 时不吸附。

## 02 — 点击穿透热键

**规则：** 一个可重绑热键切换「光标下贴图」的鼠标事件穿透；无贴图时整体切换。切换后该贴图**不响应鼠标**，`⌘` 等键盘事件仍可作用于它（用于「先穿透再统一操作」）。已穿透的贴图在视觉上有明确但克制的标识（如边框样式变化），避免用户找不到它。关闭并重新打开应用后穿透状态**不持久化**。

**落实（2026-10-14）：** 穿透键改为**作用于光标下的贴图**；光标下没有贴图时保持原有「整体切换」语义（两条分支都覆盖测试）。新增虚线描边作为穿透态的视觉标识 —— 穿透后贴图不再响应鼠标，用户无法靠点击或悬停找到它，没有标识等于「贴图消失了」；标识刻意只改描边，不动不透明度等其它观感。

- **光标命中**：`NSApp.orderedWindows` 取前到后顺序，命中多个时取最靠前的那个；刚创建、尚未参与窗口排序的贴图按补齐处理。
- **不持久化**：穿透状态存在运行期 `PinStore` 内，`destroyAll()` 后清零（已覆盖测试）。
- **可测试性**：光标位置判定存在偶发性（测试机上鼠标实际位置），因此加入 `pinUnderCursorProvider` 注入点，单测注入固定结果；生产路径为 nil，走真实命中。

**验收：** 单测覆盖「有/无光标下贴图」两条分支、来回切换、整体切换语义、穿透不持久化与视觉标识开关（`PinInteractionTests`）；真实操作：穿透后点击穿过到底层窗口，快捷键可切回。

## 03 — 缩放与透明度热键

**规则：** 两个可重绑热键分别调整光标下贴图的**缩放**与**不透明度**。缩放有上下限（默认 10%–500%）并可恢复 100%；不透明度有上下限（默认 10%–100%）并可恢复 100%。调整只改变该贴图窗口的显示参数，**不修改原始图像数据**（复制与保存时仍导出原始尺寸内容）。参数越界时钳制而非报错。

**落实（2026-10-14）：** 新增 4 个可重绑全局快捷键（放大 / 缩小 / 提高不透明度 / 降低不透明度），默认键位 `⌃⌥=`、`⌃⌥-`、`⌃⌥]`、`⌃⌥[`，全部作用于光标下的贴图；光标下没有贴图时**不响应、不报错**。

- **与卡片原文的偏差（已记录）**：卡片设想「一个热键 + 按住修饰键反向」，但全局快捷键按**精确组合**匹配，单一组合无法在按下修饰键时改变语义（按下 ⇧ 后组合不再匹配，事件根本不会到达）。因此改为每个方向一个可重绑热键，语义更明确，也不引入「静默额外注册一个带 ⇧ 的组合」这种可冲突的行为。这不是简化，而是唯一自洽的实现方式。
- **上下限与恢复 100%**：不新增 `PinDisplaySettings`，直接复用既有的 `PinTransform.clampScale`（10%–800%）/ `clampOpacity`（10%–100%）与 `resetScaleAndOpacity()`（既有「中键复位」）。卡片接口草稿里的 `PinDisplaySettings` 会与 `PinTransform` 形成两份重复实现，故**不引入**。恢复默认仍由窗口内中键承担，不额外占用全局快捷键。
- **只改显示参数**：缩放/不透明度不触碰 `payload`，复制与保存导出的仍是原始尺寸与内容（已覆盖测试）。

**验收：** 单测覆盖缩放/不透明度在上限与下限的钳制、无光标下贴图时不响应、以及「调整后原始图像数据不变」（`PinInteractionTests`）；真实操作：同一张图缩放后复制到剪贴板，内容与原始一致。

## 04 — 双击关闭与快捷键提示

**规则：** 双击贴图窗口即关闭（进入恢复队列，遵循现有容量规则），可在设置中关闭该行为。光标悬停在贴图窗口上时显示一行克制的快捷键提示（可整体关闭），内容随当前可用热键变化。

**落实（2026-10-14）：** 双击关闭**此前已实现**（`PinEventContainerView.mouseUp`：无修饰键 + `clickCount == 2` → `onClose`，进入恢复队列），本次保留原语义并补测试覆盖，不重复实现。

- **悬停提示**：贴图容器新增 `NSTrackingArea`，鼠标进入时在底部显示一行 `Esc 关闭 · 中键 复位 · 双击 关闭 · ⌃⌥= 缩放 · …`，离开即隐藏。内容由 `PinShortcutHints` 纯函数组装：**未绑定的项不出现**、最多 6 项、超出截断，因此「内容随当前可用热键变化」。
- **可整体关闭**：新增设置 `pin.showsShortcutHints`（默认开），关闭后不插入提示行。

**验收：** 单测覆盖未绑定项跳过、已绑定项出现、上限截断与空键位跳过、以及开关关闭时不插入提示行（`PinInteractionTests`）；真实操作：双击后可从菜单恢复；悬停提示内容与实际绑定一致。

## 文件

- 新建：`Qingyu/Services/Pinning/PinSnapping.swift`（吸附候选与阈值纯函数）
- 新建：`Qingyu/Services/Pinning/PinDisplaySettings.swift`（缩放/透明度/穿透的运行期状态）
- 修改：`Qingyu/App/Controllers/PinWindowController.swift`
- 修改：`Qingyu/Views/Pinning/PinWindowView.swift`
- 修改：`Qingyu/Models/PinItem.swift`、`Qingyu/Models/AppSetting.swift`
- 修改：`Qingyu/Models/PinPayloadFactory.swift`（如需保证导出用原始数据）
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`（三个热键 + 开关）
- 修改：`Qingyu/App/Controllers/AppContainer.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/PinSnappingTests.swift`、`QingyuTests/PinDisplaySettingsTests.swift`、`QingyuTests/PinWindowControllerTests.swift`（回归扩充）
- 回归：`QingyuTests/PinStoreTests.swift`、`QingyuUITests/PinWindowUITests.swift`

## 接口

```swift
struct SnapCandidate: Equatable {
    let rect: CGRect
    let source: SnapSource      // .screenEdge / .window
}

enum SnapSource: Equatable { case screenEdge, window }

enum PinSnapping {
    /// 返回吸附后的矩形；未命中返回原矩形
    static func snap(
        draggingRect: CGRect,
        candidates: [SnapCandidate],
        threshold: CGFloat
    ) -> CGRect
}

struct PinDisplaySettings: Equatable {
    var scale: CGFloat          // 0.1 ... 5.0
    var opacity: CGFloat        // 0.1 ... 1.0
    var isClickThrough: Bool

    static let `default` = PinDisplaySettings(scale: 1, opacity: 1, isClickThrough: false)

    mutating func adjustScale(step: CGFloat)
    mutating func adjustOpacity(step: CGFloat)
    mutating func resetScale()
    mutating func resetOpacity()
}
```

## 步骤

1. 先写 `PinSnapping` 与 `PinDisplaySettings` 的失败用例（含钳制与恢复默认），转绿。
2. 按 01 → 04 顺序接入窗口行为，每条补真机验证。
3. 设置页补齐三个热键与三个开关，处理热键冲突提示。
4. 运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做图像组的批量操作（归 Task 018）。
- 不做贴图旋转/翻转（如已有则保留，不在本轮扩展）。
- 穿透状态不持久化；缩放与透明度是否持久化按现有 `PinStore` 语义决定，本任务不改变其规则。
