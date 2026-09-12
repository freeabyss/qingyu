# Task 007：截图完成与标注增强

**目标：** 统一截图完成动作，加入像素取色和 PRD 规定的标注工具。

**范围：** 复制、保存、快捷保存、标注完成、选区微调、放大镜与颜色复制。

**相关模块：** `ScreenshotToolbarController`、`AnnotationCanvas`、`AnnotationShape`、Task 005–006 的截图会话。

**业务规则：** 复制、保存、快捷保存或贴图只结束当前截图会话，不产生截图历史记录；快捷保存目录默认是系统图片目录，用户可通过仅允许选目录的文件夹选择器修改；修改目录只影响后续保存，不迁移旧截图；“打开保存截图文件夹”在目录不存在时先自动创建，再由 Finder 打开该目录，定位目录本身；若已有该目录窗口则激活并复用；创建或打开失败时仅在操作按钮旁以内联文字显示本地化的“无法打开保存截图文件夹：{系统原因}”错误并保留当前目录配置，成功后不额外显示 Toast；按钮不显示处理中或禁用状态，重复触发只执行一次；青鸟不自动删除用户保存的截图文件；“保存”打开以该目录为初始位置的系统保存面板，默认填入可修改且不含扩展名的 `Screenshot-YYYYMMDD-HHmmss` 文件名，只输入不含扩展名的文件名，默认 PNG 并可选 JPEG 或 PNG，JPEG 固定 90% 质量、透明区域铺白且扩展名为 `.jpg`，PNG 保留透明度且扩展名为 `.png`，保存前校验文件名符合 macOS 系统命名要求，同名覆盖确认保持 macOS 保存面板原生行为；“快捷保存”始终以 PNG 写入同一目录并在成功后显示 2 秒“图片已保存到 {完整目录路径}”提示；快捷保存使用固定英文前缀 `Screenshot` 和用户当前系统本地时间生成的 `Screenshot-YYYYMMDD-HHmmss.png` 文件名，不随界面语言切换；冲突时禁止覆盖并自动追加递增序号；已配置目录但不可用时直接失败，不静默回退；失败和取消保留会话；导出只含已完成标注。

**技术约束：** 所有终局经过一个完成协调器；颜色采样使用捕获图像像素；截图会话状态不写 Core Data。

**验收标准：** 每个成功终局只结束一次会话；取色格式正确；直线、折线、文字旋转及清除规则有测试。

## 文件

- 新建：`Qingniao/Services/ScreenshotService/CaptureCompletionCoordinator.swift`
- 新建：`Qingniao/Services/ScreenshotService/ColorSampler.swift`
- 修改：`Qingniao/Models/AppSetting.swift`
- 修改：`Qingniao/Views/Components/ScreenshotToolbarController.swift`
- 修改：`Qingniao/Views/Annotation/AnnotationShape.swift`
- 修改：`Qingniao/Views/Annotation/AnnotationCanvas.swift`
- 修改：`Qingniao/Views/Annotation/AnnotationEditorWindow.swift`
- 修改：`Qingniao/Views/Annotation/AnnotationToolbar.swift`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 测试：`QingniaoTests/CaptureCompletionTests.swift`、`QingniaoTests/ColorSamplerTests.swift`
- 回归：`QingniaoTests/AnnotationTests.swift`、`SettingsServiceTests.swift`

## 接口

```swift
enum CaptureCompletion: Equatable {
    case copied
    case saved(URL)
    case quickSaved(URL)
    case pinned(UUID)
}

enum CaptureCompletionAction {
    case copy
    case save
    case quickSave
    case pin
}

enum CaptureCompletionOutcome {
    case completed(CaptureCompletion)
}

@MainActor final class CaptureCompletionCoordinator {
    func perform(_ action: CaptureCompletionAction, result: ScreenshotResult) async throws -> CaptureCompletionOutcome
}

enum ColorString {
    static func hex(red: UInt8, green: UInt8, blue: UInt8) -> String
    static func rgb(red: UInt8, green: UInt8, blue: UInt8) -> String
}
```

`AnnotationTool` 增加 `.line` 与 `.polyline`；`AnnotationShape` 增加 `points: [CGPoint]` 和 `rotationRadians: CGFloat`。

## 步骤

- [ ] 写失败测试：

```swift
XCTAssertEqual(ColorString.hex(red: 18, green: 52, blue: 86), "#123456")
XCTAssertEqual(ColorString.rgb(red: 18, green: 52, blue: 86), "18, 52, 86")
```

AnnotationTests 增加折线完成、清空后不可重做、文字旋转和 `⇧` 水平复位断言。
- [ ] 运行三个定向测试 target，确认新增 API 尚不存在。
- [ ] 实现截图设置默认值和 `CaptureCompletionCoordinator`；把工具条及标注窗口的复制、保存、快捷保存与贴图路径接入协调器；成功终局只结束当前会话，不写入截图历史。
- [ ] 实现放大镜采样、`C`/`⇧C`、WASD/方向键/修饰键像素操作。
- [ ] 扩展标注模型与渲染：直线、折线、系统颜色面板、宽度快捷键、文字缩放/旋转/`⇧` 复位。
- [ ] 保证草稿、工具条和快捷键提示不进入扁平化结果；复制、保存或快捷保存失败保留会话；验证截图不产生历史记录，且截图设置提供“打开保存截图文件夹”（目录不存在时自动创建，创建失败提示错误并保留目录配置）；验证快捷保存目录、文件名、格式、编码、Toast 和错误重试规则。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/CaptureCompletionTests \
  -only-testing:QingniaoTests/ColorSamplerTests \
  -only-testing:QingniaoTests/AnnotationTests \
  -only-testing:QingniaoTests/SettingsServiceTests
```

- [ ] 递增版本、校验版本字段、运行 `git diff --check`。
- [ ] 提交：`feat(screenshot): add capture completion and annotation tools`。

## P2 实现默认值

- “打开保存截图文件夹”按钮采用 300ms 防抖窗口；防抖期间不改变按钮外观，不显示加载或禁用状态。
- 每次新的目录操作开始时清除上一次内联错误；成功打开后不显示额外提示。
- Finder 打开与窗口激活使用 macOS `NSWorkspace` 能力；目标为目录本身，已存在的目录窗口优先激活复用。

## 已知实现不一致（待后续修复）

以下记录用于将现有实现对齐本任务已确认的产品规则：

- 当前实现仍包含 `CaptureHistory`、截图记录导航和相关 UI；产品规则要求移除截图历史，仅保留设置中的“打开保存截图文件夹”。

- `CaptureCompletionCoordinator.live()` 当前将快捷保存目录默认到 `~/Desktop`，并在读取失败时回退到临时目录；应改为默认系统图片目录，且已配置目录不可用时不得静默回退。
- `CaptureCompletionCoordinator.defaultFilename(for:)` 与 `ScreenshotToolbarController` 当前使用 `Screenshot yyyy-MM-dd HH.mm.ss`；应统一为 `Screenshot-YYYYMMDD-HHmmss`。
- `CaptureCompletionCoordinator` 的快捷保存当前直接写入目标 URL；应在文件已存在时自动追加递增序号，禁止覆盖。
- `ScreenshotToolbarController` 当前读取独立的 `screenshot.saveDirectory` 并默认桌面；普通保存面板和快捷保存应共享截图设置中的快捷保存目录，默认使用系统图片目录。
- 当前截图设置页只有目录选择器，尚未提供“打开保存截图文件夹”按钮；需增加该入口，并实现目录不存在时自动创建、创建失败或配置指向文件时在按钮旁以内联文字提示错误且保留当前目录配置，不提供重试按钮；按钮不禁用，仅做防抖，成功打开不显示额外 Toast。
- 当前快捷保存成功路径未按产品规则显示“图片已保存到 {完整目录路径}”2 秒提示；需补充成功 Toast 及自动消失计时。
- `CaptureCompletionCoordinator.live()` 当前普通保存面板仅允许 PNG；产品规则要求默认 PNG 且允许用户选择 JPEG 或 PNG，需补充格式选择与对应编码。
- 当前实现未定义 JPEG 编码质量；需固定为 90%，且不新增用户质量调节控件。
- 当前实现未定义 JPEG 透明区域处理；需在 JPEG 编码前铺白，PNG 保留透明度。
