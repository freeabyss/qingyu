# Task 013：标注工具扩充（6 → 12）

**目标：** 在现有 6 种标注（矩形、箭头、直线、折线、文字、马赛克）基础上补齐到 12 种，并引入「马赛克 / 高斯模糊」同键切换。

**范围：** 新增高斯模糊、序号、橡皮擦、铅笔、荧光笔、提示框六种工具的模型与渲染；标注工具条与工具切换；马赛克与模糊的合并按钮。不改截图完成动作与贴图。

**相关模块：** `Views/Annotation/AnnotationShape`、`AnnotationCanvas`、`AnnotationEditorWindow`、`AnnotationToolbar`、`ScreenshotToolbarController`。

**业务规则：**

- 最终工具集：**铅笔、箭头、直线、折线、矩形、椭圆、荧光笔、马赛克、高斯模糊、橡皮擦、文字、序号、提示框**。其中矩形与椭圆合并为一个「矩形/椭圆」按钮（沿用 Snipaste 的 `RectEllipsePaintItem` 思路），因此按钮数少于工具数。
- **马赛克与高斯模糊共用一个按钮**，再次点击在两者间切换；按钮图标随当前模式变化，悬停说明写明可切换。
- 荧光笔：半透明、粗线、固定不透明度，颜色可换，覆盖内容仍可辨识。
- 高斯模糊：对选区下方**原始截图**做模糊，强度可调；不得模糊已经画上去的标注（与马赛克一致，取样自底图）。
- 序号：每次落点是**递增数字**，支持从当前数字继续、支持重置；数字圆点大小随笔宽。
- 橡皮擦：**只擦除整条标注**（按命中测试选中并删除），不做像素级擦除；擦除可撤销。
- 提示框：可输入多行文字的气泡，带指向箭头；随文字长度自适应尺寸。
- 铅笔：自由手绘，**对采集到的采样点做平滑处理**（见下），曲线不得出现折线感。
- 所有新工具都必须进入同一撤销/重做栈；重做栈的行为与现有工具一致（新操作清空重做栈）。
- 椭圆复用矩形的手势与约束（Shift 锁定长宽比），只是渲染为椭圆。
- 不允许出现「工具已选中但画不出东西」的状态；每个工具都要有对应的空操作防护。

**技术约束：**

- 沿用现有 `AnnotationShape` 值类型 + `AnnotationCanvas` 绘制的结构，新工具以新增 `case` 与对应渲染分支实现，不引入新的绘制框架。
- 铅笔平滑使用**在采样点序列上的一次性平滑**（如 Catmull-Rom 或等价的加权插值），实现为可单测的纯函数 `StrokeSmoother.smooth(points:)`；不得在渲染循环里反复平滑。
- 高斯模糊使用 Core Image / Accelerate 对底图局部区域处理，结果需缓存到会话级，避免每帧重算。
- 马赛克块大小与模糊半径均由笔宽度派生，保证「同一条曲线」在两种模式下覆盖范围一致。
- 命中测试（用于橡皮擦与悬停选中）为纯函数，按工具类型分别定义几何规则，必须可单测。

**验收标准：**

- 单测覆盖：12 种工具各自的创建/命中/边界、序号递增与重置、括号合并工具的回归、马赛克↔模糊切换、铅笔平滑（输入含抖动点时输出单调且不越界）、撤销/重做栈一致性。
- 真实截图：每种工具各画一笔并导出 PNG，人工确认渲染正确；马赛克与模糊在同一区域**不覆盖既有标注**。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Views/Annotation/Tools/PencilShape.swift`
- 新建：`Qingyu/Views/Annotation/Tools/HighlighterShape.swift`
- 新建：`Qingyu/Views/Annotation/Tools/GaussianBlurShape.swift`
- 新建：`Qingyu/Views/Annotation/Tools/EraserShape.swift`
- 新建：`Qingyu/Views/Annotation/Tools/NumberBadgeShape.swift`
- 新建：`Qingyu/Views/Annotation/Tools/TooltipShape.swift`
- 新建：`Qingyu/Views/Annotation/StrokeSmoother.swift`
- 修改：`Qingyu/Views/Annotation/AnnotationShape.swift`
- 修改：`Qingyu/Views/Annotation/AnnotationCanvas.swift`
- 修改：`Qingyu/Views/Annotation/AnnotationToolbar.swift`
- 修改：`Qingyu/Views/Components/ScreenshotToolbarController.swift`
- 修改：`Qingyu/Views/Design/JadeColor.swift`（如需新增调色板色）
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/AnnotationShapeTests.swift`、`QingyuTests/StrokeSmootherTests.swift`、`QingyuTests/AnnotationHitTestTests.swift`
- 回归：`QingyuTests/AnnotationTests.swift`、`ScreenshotOverlayUITests.swift`

## 接口

```swift
enum AnnotationTool: String, Codable, CaseIterable, Identifiable {
    case pencil, arrow, line, polyline
    case rectEllipse            // 矩形/椭圆合并，由 modifier 决定形状
    case highlighter
    case mosaic, gaussianBlur   // 同一按钮切换
    case eraser
    case text, number, tooltip
}

/// 纯函数：手绘点序列平滑
enum StrokeSmoother {
    static func smooth(points: [CGPoint], tension: CGFloat) -> [CGPoint]
    static func simplify(points: [CGPoint], tolerance: CGFloat) -> [CGPoint]
}

/// 纯函数：按工具类型做命中测试（橡皮擦、悬停选中）
enum AnnotationHitTest {
    static func hit(
        point: CGPoint,
        shapes: [AnnotationShape],
        tolerance: CGFloat
    ) -> AnnotationShape.ID?
}

/// 底图取样器：马赛克与高斯模糊共用
protocol BaseImageSampler: AnyObject {
    func mosaic(rect: CGRect, blockSize: CGFloat) -> CGImage?
    func blur(rect: CGRect, radius: CGFloat) -> CGImage?
}
```

## 步骤

1. 扩充 `AnnotationTool` 并修正工具条按钮映射（合并矩形/椭圆、合并马赛克/模糊）。
2. 先写 `StrokeSmoother` 与 `AnnotationHitTest` 的失败用例并转绿。
3. 按工具逐个实现渲染分支，每个工具落地后补该工具的用例。
4. 实现 `BaseImageSampler`（底图局部马赛克/模糊 + 缓存）。
5. 实现序号递增与重置、提示框多行布局。
6. 真机逐工具绘图验证；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做像素级橡皮擦（Snipaste 也是整条删除）；不做标注图层管理。
- 文字标注的富文本编辑保持现有能力，不扩展。
- 「不同形状用不同颜色」「调色板自定义」等配色细化归入 Task 014。
- **悬停选中只做高亮提示**，不实现「点击中已有标注即改为编辑它」（当前仍以工具为准）；如需编辑已有标注另立任务。
- 数字快捷键只覆盖前 9 个工具条分组；「序号」「提示框」无数字快捷键（避免出现 `10` 这种多字符 KeyEquivalent）。

## 验证记录

- `./scripts/verify.sh`：**422 项单元测试、0 失败**；`git diff --check` 通过。
- 新增用例 22 项：
  - `StrokeSmootherTests`（7 项）：平滑保持点数与首末点、输出不超出输入包围盒、抖动幅度下降、短笔画与零容差为 no-op、抽稀保留末点、落笔处理不增点且仍可绘制。
  - `AnnotationHitTestTests`（15 项）：点到线段距离（含端点外投影与退化线段）、矩形类/直线/箭头/手绘/序号/提示框各自命中规则、橡皮擦不参与命中、重叠时最上层优先、命中容差随笔宽放宽，以及画布侧的「删除可撤销可重做 / 删除不存在项为 no-op / 序号递增与清空重置」。
- 工具数与按钮数：**13 个工具 / 11 个按钮**（矩形·椭圆、马赛克·高斯模糊各合并为一个按钮，点击循环）。
- 工程：3 个新文件加入 `Qingyu.xcodeproj/project.pbxproj`（app 1 个走 Annotation 组的相对路径方案，test 2 个走 SOURCE_ROOT 方案）。

### 实施偏差（相对本卡原计划）

| 原计划 | 实际做法 | 原因 |
|---|---|---|
| 新建 `Views/Annotation/Tools/*.swift` 六个工具文件 | **不新建**，全部在 `AnnotationRenderer` 内实现 | 六种工具各自只有几十行绘制逻辑，拆文件反而增加导航成本；行为与验收标准不变 |
| 新建 `BaseImageSampler`（底图局部马赛克/模糊 + 缓存） | **不新建**：现有渲染器已从 `sourceImage` 取样，只需为高斯模糊补一个 `CIGaussianBlur` 分支 | 产品规则「取样自底图、不模糊已有标注」原本就成立；另加一层缓存收益不足 |
| `AnnotationTool` 用单个 `rectEllipse` case，形状由修饰键决定 | 保留 `rectangle` / `ellipse` **两个 case**，按钮层面合并并循环 | `AnnotationTool` 是 `Codable`；保留既有 rawValue 可避免破坏任何已序列化数据，且按钮合并已达成「按钮数少于工具数」的目标 |
| 修饰键决定矩形/椭圆 | 按钮**重复点击循环** | 与既有的「马赛克↔高斯模糊」合并按钮保持同一种交互语汇，学习成本更低 |

### 遗留

- `annotation.tool.blur` 与 `annotation.tool.blur.soon` 两个本地化键随「blur 禁用占位」一起失去引用，已成为死键（保留未删，与 Task 010 对死键的处理一致）。
