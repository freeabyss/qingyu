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

**验收：** 单测覆盖吸附候选选择（取最近）、阈值边界、修饰键禁用、屏幕边缘与窗口边缘优先级；真实拖拽：靠近另一个窗口边缘时贴边到位。

## 02 — 点击穿透热键

**规则：** 一个可重绑热键切换「光标下贴图」的鼠标事件穿透；无贴图时整体切换。切换后该贴图**不响应鼠标**，`⌘` 等键盘事件仍可作用于它（用于「先穿透再统一操作」）。已穿透的贴图在视觉上有明确但克制的标识（如边框样式变化），避免用户找不到它。关闭并重新打开应用后穿透状态**不持久化**。

**验收：** 单测覆盖「有/无光标下贴图」两条分支与状态复位；真实操作：穿透后点击穿过到底层窗口，快捷键可切回。

## 03 — 缩放与透明度热键

**规则：** 两个可重绑热键分别调整光标下贴图的**缩放**与**不透明度**。缩放有上下限（默认 10%–500%）并可恢复 100%；不透明度有上下限（默认 10%–100%）并可恢复 100%。调整只改变该贴图窗口的显示参数，**不修改原始图像数据**（复制与保存时仍导出原始尺寸内容）。参数越界时钳制而非报错。

**验收：** 单测覆盖缩放/透明度钳制、恢复默认、按快捷键时的步进方向（同一键在按住修饰键时反向）；真实操作：同一张图缩放后复制到剪贴板，内容与原始一致。

## 04 — 双击关闭与快捷键提示

**规则：** 双击贴图窗口即关闭（进入恢复队列，遵循现有容量规则），可在设置中关闭该行为。光标悬停在贴图窗口上时显示一行克制的快捷键提示（可整体关闭），内容随当前可用热键变化。

**验收：** 单测覆盖双击关闭开关与恢复队列一致；真实操作：双击后可从菜单恢复；悬停提示内容与实际绑定一致。

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
