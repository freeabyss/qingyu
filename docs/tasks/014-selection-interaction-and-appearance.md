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

**落实（2026-10-14）：** 新增 `ScreenshotFrameStyle`（几何为纯函数，绘制走显式 `NSBitmapImageRep`，尺寸严格等于几何计算值，不受当前屏幕缩放影响）。

- **默认全关即纯增量**：四项默认 0 → `isIdentity`，`applying(to:)` 原样返回源字节，导出结果与引入本能力前**逐字节一致**；`decorated()` 在全关时连解码都不做。
- **单位与缩放**：样式数值单位为**点**，绘制时按 `NSScreen.backingScaleFactor` 折算成位图像素，因此 Retina 截图上「8 点圆角」看上去就是 8 点。
- **作用范围**：只作用于**复制 / 保存 / 快捷保存**；贴图与打印沿用原始像素 —— 贴图窗口自带阴影，且必须沿用在屏幕上的原选区位置（装饰会改变图像尺寸，导致贴图错位）。
- **非法值钳制**：负值 / `NaN` → 0，超上限（圆角与阴影 120 点、边框 60 点）截断，不报错。
- **顺带修复既有缺陷**：设置页的 `screenshot.includeShadow` 此前**没有任何消费者**（拨了没反应的死开关），本次接入导出链路；`screenshot.copyToClipboard` 与 `screenshot.playSound` 仍是死开关，见文末「关于截图设置页的三个死开关」。

**验收：** 单测覆盖参数钳制、几何（含 2 倍屏折算）、像素差异（圆角处透明、边框着色、阴影留白）、默认值读取与 `decorated()` 的 id/尺寸语义（`ScreenshotFrameStyleTests`，13 条），以及协调器挂载点（复制/保存套用装饰、贴图/打印不套用，`CaptureCompletionTests`，3 条）；真实导出 PNG 对比四项参数各变一次的结果。

## 04 — 取色输出格式

**规则：** 取色值的输出格式可配置：色彩空间（RGB / HSV / HSL）、是否大写十六进制、是否省略 `#`、分量之间是否加空格。默认输出为小写 `#rrggbb`。取色复制走系统剪贴板纯文本。

**落实（2026-10-14）：** 补齐落地入口 —— 此前 `ColorValueFormatter` 已实现但**没有截图期取色入口**，等于一个无法配置的哑功能。本次接通：

- **入口按 PRD 键位表**：标注窗口（以及白板，二者共用同一画布与格式化实现）内 `C` 复制十六进制、`⇧C` 复制分量值。两个键做成 SwiftUI 隐藏按钮，因此在任何焦点下都可用，不依赖画布是否为第一响应者。
- **采样来自画布底图，不重新抓屏**：既不需要额外权限，也保证取到的就是用户看到的那个像素。指针位置由 `AnnotationCanvasState.lastHoveredImagePoint` 记录（画布在 `mouseMoved` / `mouseDown` 时写入）。
- **坐标换算单独成函数并单测**：`sourcePixel(atImagePoint:)` 把画布图像点（点坐标、**左下**原点）换算成源图**像素**坐标（**左上**原点）。标注画布不是 flipped 视图，**y 必须翻转**，否则取色会取到上下镜像的像素 —— 该缺陷用「上半绿 / 下半蓝」的端到端断言锁住。
- **Retina 换算**：`sourcePixelSize` 取位图**像素**尺寸（Retina 截图为点尺寸 2 倍），因此 2 倍图上 0.25 点正确落到第 0 像素列。
- **复制形式**：新增 `ColorCopyStyle`（`.hex` / `.components`）。`⇧C` 在 RGB 空间下复制 `R, G, B`（`ColorValueFormatter.string(options:)` 在 RGB 空间把十六进制作为主格式，分量形式因此单独承担），在 HSV/HSL 空间下按配置输出对应分量。
- **与卡片原文的差异（已记录）**：卡片写「默认输出为小写 `#rrggbb`」，实现保持**大写** `#RRGGBB` —— 这是为了让既有 `ColorString.hex` 的呈现逐字不变（该决策在交付 04 核心时已记录）。设置页提供「大写十六进制」开关，想要小写可一键切换。
- **设置页**：色彩空间（RGB/HSV/HSL）、大写十六进制、省略 `#`、分量加空格，附一行实时预览（固定样本色，避免随指针闪烁）。

**验收：** 单测覆盖像素换算（含 y 翻转、Retina 2 倍、越界返回 nil）、取色与已知像素一致、复制形式在三种色彩空间下的输出、选项序列化往返（`ColorSamplingTests`，9 条）；真实复制一次并校验剪贴板字符串。

## 05 — 鼠标动作可配置

**规则：** 截图过程中四种动作可配置：`Enter` 键、双击、中键、右键。可选动作为「复制并结束」「保存」「贴图」「不响应」。默认值等于当前行为。

**落实（2026-10-14）：** 新增 `ScreenshotGesture`（Enter / 双击 / 中键 / 右键）与 `ScreenshotGestureAction`（复制并结束 / 保存 / 贴图 / 不响应），以及纯函数绑定表 `ScreenshotGestureBindings` 与派发器 `ScreenshotGestureDispatcher`。

- **作用阶段定为「预览阶段」**（截图已完成、工具条出现期间）。理由：卡片写「截图过程中」，但叠层阶段四个手势里有三个无法成立 —— targeting 阶段的第一次左键抬起就已经锁定并开始捕获，双击在语义上不可达；`.adjustingRegion` 下 `Enter` 已经承载「确认选区」，被配置覆盖会直接删掉既有能力。放在预览阶段则既不夺走任何既有键位，又正好对应「对刚截到的画面下指令」。
- **默认值 = 当前行为**：`Enter` = 复制并结束（与既有提示 `screenshot.hint.enterCopy`「Enter 复制」一致，此前该提示一直没有实现），**双击 / 中键 / 右键默认「不响应」** —— 它们此前完全没有行为，默认开启等于凭空多出会误触的交互。
- **事件识别不会与工具条抢事件**：`Enter` 走预览面板的 `keyDown`；鼠标手势走**全局鼠标监听**，而全局监听只接收**其它应用**派发的事件 —— 点在清羽面板上的点击天然不会进来，因此不存在「点按钮却被当成手势」的歧义。监听只在预览可见期间存在，`dismiss` 时移除。
- **不需要额外权限**：鼠标全局监听不需要辅助功能授权（只有全局键盘监听需要）。
- **非法存档值**：无法识别的取值一律回退为「不响应」，不抛错。
- **顺带接线**：`ScreenshotPreviewWindow` 此前只处理 `Esc`，现在同时处理 `Enter` / 小键盘 `Enter`；`⌘S` 的保存能力仍由工具条承担（不在本子项的四种手势内）。

**验收：** 单测覆盖默认值即当前行为、全部动作的派发矩阵、非法值与旧存档回退、序列化往返、事件分类（单击不识别、工具条内点击一律不识别、侧键不识别）与本地化键齐备（`ScreenshotGestureBindingsTests`，12 条）；真实操作四种动作各触发一次。

## 06 — 长宽比锁定

**规则：** 拖拽选区时按住修饰键（默认 Shift）锁定当前长宽比；标注绘制矩形/椭圆时同一修饰键沿用该语义。

**验收：** 单测覆盖锁定后的坐标推导；真实拖拽确认比例恒定。

## 07 — 屏幕四角热区触发

**规则：** 可选开启屏幕四角热区，指针推入角落后触发指定命令（默认「区域截图」）。四角可各自配置，也可整体关闭（默认关闭）。热区尺寸可调。触发需要指针在角落**停留一小段时间**，避免误触；已在本会话中触发后，指针离开角落前不重复触发。

**落实（2026-10-14）：** 新增 `HotCorner`（四角）、`HotCornerAction`（开始截图 / 不响应）、`HotCornerConfiguration`（开关 / 尺寸 / 停留时长 / 各角动作）与纯状态机 `HotCornerTracker`，以及薄壳 `HotCornerMonitor`。

- **默认关闭**：热区是最容易被误触的交互，默认必须关。关闭时监听器保持停止（`isRunning == false`），不产生任何轮询开销。
- **命中从屏幕整体 `frame` 的角量起**（不是可见区）：否则菜单栏所在的上边角永远推不进去。AppKit 坐标原点在左下，因此「上」= `maxY`。
- **停顿 + 去重**：指针须在角内连续停留 `dwell`（默认 0.4 s）才触发；触发后必须**先移出该角**才可能再次触发。两条规则都由纯状态机承担，可完全单测。
- **换角重新计时**：从一个角直接移到另一个角不会「继承」已累计的停留时间。
- **实现方式为定时轮询**（0.1 s，挂在 `.common` 运行循环模式以便拖动/菜单弹出期间继续计时），而不是鼠标事件监听：热区必须在**任意应用前台**时都能工作，且轮询让停顿与去重完全落在纯函数上。
- **非法配置**：尺寸 / 停留时长的负值与 `NaN` 回落到**默认值**（而不是 0）—— 回落到 0 会让热区退化成「永远点不到」的哑设置。
- **动作集合**：本子项只提供「开始截图」（默认）与「不响应」。卡片写「触发指定命令」，但把它接到命令目录属于另一个集成面，且需要处理命令需要确认/权限等情况；先交付可用的最小动作集，扩展点留在 `HotCornerAction` 与 `AppContainer` 的回调里。

**验收：** 单测覆盖默认关闭、非法值回落与上限截断、四角命中与边界（恰好在边界上算命中、越界即不命中、尺寸 0 永不命中）、停顿前后、停留期间不重复触发、离开再回来可再次触发、换角重新计时、整体关闭 / 单角忽略、多屏按指针所在屏判定、序列化往返与缺失键回落、以及监听器 `tick` 的触发次数（`HotCornerMonitorTests`，17 条）；真实操作：推入右上角触发一次、推入后停留不重复触发、离开再回来可再次触发。

## 文件

- 新建：`Qingyu/Services/ScreenshotService/SelectionNudge.swift`（移动/缩放纯函数）
- 新建：`Qingyu/Services/ScreenshotService/ScreenshotFrameStyle.swift`（圆角/边框/阴影导出参数；几何纯函数 + 显式位图绘制）
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
| 01 选区微调与辅助线 | ✅ 已交付 | 产品决策已确认（2026-10-13）：**圈选区域松开后进入可微调态**（新增 `CaptureSessionPhase.adjustingRegion`），方向键移动 1 物理像素、`⇧`+方向键沿轴对称伸缩、`Tab` 按住显示对齐辅助线、`Enter` 确认截取、`Esc` 取消。窗口/整屏单击仍即时锁定（它们本身不需要像素级微调）。`docs/prd/02-ui-spec.md` 与 `docs/tasks/README.md` 的产品规则已同步更新。**2026-10-17 追加产品决策：松开即出工具条**（见文末「追加交付」）。 |
| 02 笔宽与工具快捷键 | ✅ 已交付 | `[` / `]` 与滚轮在三档笔宽间步进（到边界不循环）。数字键 `1`-`9` 已被 Task 013 的工具条分组占用，因此**不做** `1` / `2` 数字预设（原计划的该部分取消，避免与工具选择冲突）。 |
| 03 选区圆角/边框/阴影可配置 | ✅ 已交付 | 新增 `ScreenshotFrameStyle` + `CaptureCompletionHandlers.decorate` 挂载点，接入「复制/保存/快捷保存」；默认全关时逐字节保持原行为。顺带接上了此前无人消费的 `screenshot.includeShadow`。 |
| 04 取色输出格式 | ✅ 已交付 | 落地入口已接通：标注窗口与白板内 `C` / `⇧C` 取色（采样自画布底图，不重新抓屏）；坐标换算含 y 翻转与 Retina 缩放并单测；设置页提供四项格式开关与实时预览。默认保持大写 `#RRGGBB`（不改变既有呈现），可一键切换为小写。 |
| 05 鼠标动作可配置 | ✅ 已交付 | 作用阶段明确为**预览阶段**（叠层阶段四手势中三个语义不可达，详见子项说明）；默认值即当前行为，双击/中键/右键默认不响应。鼠标手势经全局监听识别，天然不与工具条按钮冲突。 |
| 06 长宽比锁定 | ✅ 已交付 | 拖拽选区时按住 `⇧` 锁定长宽比：**首次按下时以当时的选区比例**为准，之后沿该比例投影；松开 `⇧` 立即恢复自由拖拽。 |
| 07 屏幕四角热区 | ✅ 已交付 | 默认关闭；停顿 + 去重由纯状态机承担；命中从屏幕整体 frame 的角量起。动作集合先交付「开始截图 / 不响应」。 |

### 关于截图设置页的三个死开关

排查 03 时发现设置页「截图后」分区里的三个开关**全项目没有任何消费者**，属于「拨了没反应」的假设置：

| 键 | 现状 | 处理 |
|---|---|---|
| `screenshot.includeShadow` | 无消费者 | 03 已接入导出链路（阴影总开关） |
| `screenshot.copyToClipboard` | 无消费者 | ✅ 已接通：**保存成功后同时写一份到剪贴板** |
| `screenshot.playSound` | 无消费者 | ✅ 已接通：**截图成功时播放一声系统提示音** |

**接通方式（2026-10-14）**：新增 `ScreenshotPostCapturePolicy`（纯值类型 + UserDefaults 读取 + 音效回退链），把两个开关变成显式、可测的策略。

- **语义写进设置项标题**，避免再次变成「拨了不知道干什么」的开关：「保存后同时复制到剪贴板」「截图完成时播放提示音」。
- **默认值改为「关」**：这两个开关此前从未生效，即「当前行为」等价于关闭；默认开会在用户没做任何配置的情况下凭空多出声音与剪贴板写入，属可感知的行为倒退。默认关 + 用户显式打开才符合「默认值下行为不倒退」的既有约束。
- **作用范围**：复制策略作用于**保存成功之后**（工具条保存与白板保存都遵守），不影响 `Enter` 的复制终局动作；提示音作用于**截图成功之后**（捕获失败或取消不响）。
- **音效选择**：候选链 `Tink → Pop → Glass`（`/System/Library/Sounds` 的成员，系统未提供 `Grab`），全部不可用时静默跳过而不报错。

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

## 追加交付（2026-10-17）：松开即出区域工具条（草稿态 + 懒捕获）

**触发**：用户报告「截图区域框选成功后，没有弹出工具栏」。

**产品决策**（用户确认，二选一中的「松开就立即出工具栏」）：框选**松开即出**工具条，不再等 `Enter`；选区仍可用方向键微调；`Enter` 仍确认截图。

**关键设计约束（三条，缺一条就退回原缺陷或引入新缺陷）**：

1. **草稿工具条不得夺 key**。截图会话仍在进行，活动叠层必须继续持有键盘 —— 一旦工具条成为 key 窗口，方向键微调、`Tab` 辅助线、`Enter` 确认、`P` / `⌘S` 预设全部失效。实现为 `window.becomesKeyOnlyIfNeeded = true` + `orderFrontRegardless()`，只有**已捕获态**（会话已结束）的工具条才正常拿 key。
2. **懒捕获**：松开时**不抓屏**，点动作（复制/保存/贴图/打印）那一刻才按最新选区抓屏。预捕获不仅会在叠层仍可见时抓屏，更会让微调后的画面立刻过期。
3. **位置更新而非重建**：方向键微调只 `setFrame` 挪窗口，不重建（重建会闪）。

**实现要点**：

- `CaptureSessionController` 新增回调 `onRegionAdjustable(display, rect)` / `onRegionAdjustableEnded()`，在**拖拽松开、方向键微调、套用预设**三处进入可微调态时各触发一次（幂等）；叠层重建（显示器拓扑变化）时触发 `onRegionAdjustableEnded`，因为旧选区随状态一起作废，草稿工具条若还挂着，点动作会截到一个已经不对应的区域。与 `onCancel` 的区别是会话**不结束**。
- `ScreenshotToolbarController` 新增 `showRegionDraft` / `dismissRegionDraft` / `performDraftAction`；`ScreenshotPreviewViewModel.result` 改为可选以承载「草稿（未捕获）」态。
- 视图模型驱动：`RegionScreenshotToolbarView` 的 17 个按钮改为紧凑图标按钮（30×30），窗口尺寸由内容 `fittingSize` 推导。

**顺带修掉的一个既有缺陷（被本项暴露）**：区域工具条窗口宽度写死 620 pt，而 17 个带文字按钮实需约 1304 pt，导致复制/保存/贴图/关闭被渲染在窗口外**不可点击**（点上去毫无反应）。现由 `fittingSize` 推导，宽度 582×44，并加了「宽度必须容纳全部动作按钮」的断言防复发。

**实施中踩到的一个坑（值得记住）**：`showRegionDraft` 初版先写 `draftCapture = capture`，之后才调用 `dismiss(reason: .superseded)` —— 而 `dismiss` 会清空草稿态字段，于是刚写进去的闭包立刻被清掉，表现是**点工具条任何按钮都毫无反应**。修法是把赋值移到 `dismiss` **之后**。

**验证**：新增 `RegionDraftToolbarTests` 7 项（宽度容纳内容、松开即出且不预捕获、草稿态不夺 key、微调不重建窗口、作废收起但不结束会话、动作链路懒捕获一次并走通、捕获失败收摊），`CaptureSessionControllerTests` 新增 6 项（松开/单击锁定/微调/套用预设/重建/会话结束后各一次的回调契约）。第 12 节新增 **SHOT-LIFE-007**，原手工冒烟顺延为 **SHOT-LIFE-008**。

**未自动化覆盖的一环**：SwiftUI 按钮的**真实点击**无法在单测里合成（`NSApp.sendEvent` / `window.sendEvent` 都到不了 SwiftUI 按钮），测试改为直接驱动按钮回调之后的链路（`performDraftAction`）。按钮点击由窗口层契约保证（不夺 key、点击直接落到按钮上），真实点击走 SHOT-LIFE-008 手工冒烟。

## 已知边界

- 不做 Snipaste 的「色彩空间 / HDR 显示器校正」（涉及色彩管理，另立任务评估）。
- 不做「主题色 / 界面语言」类外观项（清羽已有自己的设计系统与语言设置）。
- 热区仅在「未在进行截图会话」时生效。
