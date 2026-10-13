# Task 014：截图选区交互与视觉细化

**目标：** 把截图的「手感」细节补齐：选区微调、辅助线、笔宽快捷键、选区内可配置的圆角/边框/阴影、取色格式，以及可在设置里重绑的鼠标动作。

**范围：** 键鼠交互补强、截图选区外观参数化、取色输出格式。不改会话状态机结构，不新增工具。

> 本任务为**细节补齐型**，以下 01–07 各自独立、互不阻塞，可按顺序逐条交付；每条单独跑验证并提交。

**相关模块：** `ScreenshotOverlay`、`CaptureSessionController`、`ScreenshotShortcutHintsView`、`ScreenshotToolbarController`、`AnnotationCanvas`、`ColorSampler`、`ScreenshotSettingsPage`。

## 业务规则（总）

- 所有新增快捷键必须**不与系统或既有绑定冲突**；冲突时以既有绑定为准并在设置页提示。
- 所有新增设置项都要有默认值，默认值下行为与当前版本**可感知地不倒退**（即：不加配置时不能变难用）。
- 新增快捷键都要出现在左下角快捷键提示视图中，且随上下文变化。
- 任何外观参数（圆角、边框、阴影）只影响**导出与复制的结果图**，不影响截图过程中的交互画面。

## 01 — 选区微调与辅助线

**规则：** 方向键把选区移动 1 像素；按住修饰键（默认 Shift）时改为缩放选区 1 像素（等价 Snipaste 的 `Shrink/Expand the snipping area by 1 pixel`）。按住 Tab 时临时显示/隐藏选区辅助线（对齐线），松开恢复。辅助线的显示偏好可在设置中设为「按住才显示」或「始终显示」。

**验收：** 单测覆盖方向键移动/缩放的坐标变化与边界钳制；真实操作：方向键每次位移恰为 1 物理像素。

## 02 — 笔宽与工具快捷键

**规则：** 滚轮在标注模式下调整笔宽；`[` / `]` 减小/增大笔宽；`1` / `2` 直接切到「细 / 粗」预设。范围与步进写入设置（含最大笔数上限）。这些快捷键只在标注模式生效，不劫持截图阶段的滚轮。

**验收：** 单测覆盖笔宽上下限与预设切换；真实操作：滚轮与 `[`/`]` 结果一致。

## 03 — 选区圆角、边框、阴影可配置

**规则：** 导出结果图支持四圆角半径、边框宽度与颜色、阴影宽度与颜色，四项可独立开关，默认值等于当前固定行为（阴影开关沿用现有 `screenshot.includeShadow`）。颜色从设计系统调色板取，允许自定义。参数非法（负值、超上限）时钳制到合法范围而非报错。

**验收：** 单测覆盖参数钳制与「关与开」的像素差异；真实导出 PNG 对比四项参数各变一次的结果。

## 04 — 取色输出格式

**规则：** 取色值的输出格式可配置：色彩空间（RGB / HSV / HSL）、是否大写十六进制、是否省略 `#`、分量之间是否加空格。默认输出为小写 `#rrggbb`。取色复制走系统剪贴板纯文本。

**验收：** 单测覆盖各格式组合的字符串输出（含边界值 0/255 与灰阶）；真实复制一次并校验剪贴板字符串。

## 05 — 鼠标动作可配置

**规则：** 截图过程中四种动作可配置：`Enter` 键、双击、中键、右键。可选动作为「复制并结束」「保存」「贴图」「不响应」。默认值等于当前行为。

**验收：** 单测覆盖动作分发矩阵；真实操作四种动作各触发一次。

## 06 — 长宽比锁定

**规则：** 拖拽选区时按住修饰键（默认 Shift）锁定当前长宽比；标注绘制矩形/椭圆时同一修饰键沿用该语义。

**验收：** 单测覆盖锁定后的坐标推导；真实拖拽确认比例恒定。

## 07 — 屏幕四角热区触发

**规则：** 可选开启屏幕四角热区，指针推入角落后触发指定命令（默认「区域截图」）。四角可各自配置，也可整体关闭（默认关闭）。热区尺寸可调。触发需要指针在角落**停留一小段时间**，避免误触；已在本会话中触发后，指针离开角落前不重复触发。

**验收：** 单测覆盖停顿判定、去重与边界；真实操作：推入右上角触发一次、推入后停留不重复触发、离开再回来可再次触发。

## 文件

- 新建：`Qingyu/Services/ScreenshotService/SelectionNudge.swift`（移动/缩放纯函数）
- 新建：`Qingyu/Services/ScreenshotService/OverlayAppearance.swift`（圆角/边框/阴影导出参数）
- 新建：`Qingyu/Services/ScreenshotService/ColorValueFormatter.swift`
- 新建：`Qingyu/Services/ScreenshotService/HotCornerMonitor.swift`
- 修改：`Qingyu/Views/Components/ScreenshotOverlay.swift`
- 修改：`Qingyu/Views/Components/ScreenshotShortcutHintsView.swift`
- 修改：`Qingyu/Views/Components/ScreenshotToolbarController.swift`
- 修改：`Qingyu/Views/Annotation/AnnotationCanvas.swift`
- 修改：`Qingyu/Services/ScreenshotService/ColorSampler.swift`
- 修改：`Qingyu/App/Controllers/CaptureSessionController.swift`
- 修改：`Qingyu/Models/AppSetting.swift`
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/SelectionNudgeTests.swift`、`OverlayAppearanceTests.swift`、`ColorValueFormatterTests.swift`、`HotCornerMonitorTests.swift`
- 回归：`CaptureSessionStateTests.swift`、`ScreenshotOverlayUITests.swift`、`SettingsServiceTests.swift`

## 接口

```swift
enum NudgeKind { case move, shrink, expand }

enum SelectionNudge {
    static func apply(
        _ rect: CGRect,
        kind: NudgeKind,
        axis: NudgeAxis,
        screenBounds: CGRect
    ) -> CGRect
}

struct OverlayAppearance: Equatable {
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var borderColor: CGColor
    var shadowWidth: CGFloat
    var shadowColor: CGColor
    var showsShadow: Bool
}

enum ColorValueFormat: String, CaseIterable, Codable {
    case rgb, hsv, hsl
}

struct ColorValueOptions: Equatable {
    var space: ColorValueFormat
    var uppercaseHex: Bool
    var omitHash: Bool
    var spacedComponents: Bool
}

enum ColorValueFormatter {
    static func string(r: UInt8, g: UInt8, b: UInt8, options: ColorValueOptions) -> String
}

enum SnipMouseAction: String, CaseIterable, Codable {
    case copy, save, pin, none
}

protocol HotCornerMonitoring: AnyObject {
    var isEnabled: Bool { get set }
    func commands() -> [HotCorner: HotCornerCommand]
}
```

## 步骤

1. 按 01 → 07 顺序逐条实现：先写该条的失败用例，再实现，再真机验证。
2. 每条完成后同步更新设置页与快捷键提示视图。
3. 全部完成后统一跑 `./scripts/verify.sh`，递增版本，提交。

## 交付状态（本轮）

> 本卡原计划 01–07 七个独立子项（卡内已声明「各自独立、可按顺序逐条交付」）。
> 已交付 **01 / 02 / 04（核心）/ 06**；其余各项的阻塞原因逐条记录如下。

| 子项 | 状态 | 说明 |
|---|---|---|
| 01 选区微调与辅助线 | ✅ 已交付 | 产品决策已确认（2026-10-13）：**圈选区域松开后进入可微调态**（新增 `CaptureSessionPhase.adjustingRegion`），方向键移动 1 物理像素、`⇧`+方向键沿轴对称伸缩、`Tab` 按住显示对齐辅助线、`Enter` 确认截取、`Esc` 取消。窗口/整屏单击仍即时锁定（它们本身不需要像素级微调）。`docs/prd/02-ui-spec.md` 与 `docs/tasks/README.md` 的产品规则已同步更新。 |
| 02 笔宽与工具快捷键 | ✅ 已交付 | `[` / `]` 与滚轮在三档笔宽间步进（到边界不循环）。数字键 `1`-`9` 已被 Task 013 的工具条分组占用，因此**不做** `1` / `2` 数字预设（原计划的该部分取消，避免与工具选择冲突）。 |
| 03 选区圆角/边框/阴影可配置 | ⛔ 未开工 | 需要在导出链路上新增一层合成（圆角裁剪 + 描边 + 阴影），涉及 `CaptureCompletionCoordinator` 的产物管线。 |
| 04 取色输出格式 | 🟡 核心已交付，落地入口缺失 | `ColorValueFormatter` + `ColorValueOptions`（RGB/HSV/HSL、十六进制大小写、省略 `#`、分量分隔）已实现并**被 `ColorString.hex` 复用**（保证是活代码）。但**尚未接入设置项与截图期取色入口**：全项目只有贴图的颜色标签在用 `ColorString`，`ColorSampler` 并未被截图链路调用 —— 也就是说「取色格式」目前缺少可配置的落地点；接通它需要先做「截图期取色」这个功能本身。 |
| 05 鼠标动作可配置 | ⛔ 未开工 | 需要新增设置项 + 会话分发矩阵（Enter / 双击 / 中键 / 右键）。 |
| 06 长宽比锁定 | ✅ 已交付 | 拖拽选区时按住 `⇧` 锁定长宽比：**首次按下时以当时的选区比例**为准，之后沿该比例投影；松开 `⇧` 立即恢复自由拖拽。 |
| 07 屏幕四角热区 | ⛔ 未开工 | 需要全局鼠标监听 + 停顿判定 + 去重，并新增设置项。 |

### 关于 04 的一处默认值决策

格式化器的十六进制默认取**大写**（`#RRGGBB`），与本卡原计划写的「默认小写」相反 ——
因为既有 `ColorString.hex` 就是大写且已被贴图颜色标签使用，改成小写会在本轮无意改变已有界面呈现。
颜色空间默认仍为 RGB、其余选项默认关闭，因此不改设置时行为与改动前完全一致。

### 验证记录

- `./scripts/verify.sh`：**436 项单元测试、0 失败**；`git diff --check` 通过。
- 新增用例 24 项，另按新流程更新既有断言：
  - `CaptureSessionStateTests` 新增 5 项（方向键平移、`⇧` 对称伸缩、越界与最小尺寸钳制、非可微调态忽略方向键、可微调态下 `⌘A` 仍可用），并把区域拖拽用例改为「进入可微调态 → 确认」；
  - `CaptureSessionControllerTests` 新增 2 项（拖拽进入可微调态后由 `confirmSelection` 交付目标、方向键事件驱动调整），另更新 3 项既有断言（区域锁定 / 提示跟随阶段 / 僵尸暗幕复现）；
  - `SelectionInteractionTests` 新增 17 项（长宽比投影 5 + 笔宽步进 3 + 取色格式 5 + 选区微调 4）。：长宽比投影 5 项（1:1 与任意比例、象限保持、非法比例与零位移、比例推导退化矩形）、笔宽步进 3 项（相邻档、边界钳制、方向 0）、取色格式 6 项（默认与既有呈现一致且与 `ColorString` 同源、大小写与省略 `#`、边界值补零、HSV/HSL 分量、分隔符、Codable 往返）。
- 工程：2 个新文件加入 `Qingyu.xcodeproj/project.pbxproj`（app 1 + test 1）。

## 已知边界

- 不做 Snipaste 的「色彩空间 / HDR 显示器校正」（涉及色彩管理，另立任务评估）。
- 不做「主题色 / 界面语言」类外观项（清羽已有自己的设计系统与语言设置）。
- 热区仅在「未在进行截图会话」时生效。
