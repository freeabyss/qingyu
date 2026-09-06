# Task 007：截图完成、记录与标注增强

**目标：** 统一截图完成动作，加入运行期截图记录、像素取色和 PRD 规定的标注工具。

**范围：** 复制、保存、快捷保存、打印、标注完成、运行期记录、选区微调、放大镜与颜色复制。

**相关模块：** `ScreenshotToolbarController`、`AnnotationCanvas`、`AnnotationShape`、Task 005–006 的截图会话。

**业务规则：** 只有复制、保存、快捷保存或贴图进入记录；失败和取消保留会话且不记录；记录默认 20、范围 `1…200`；导出只含已完成标注。

**技术约束：** 所有终局经过一个完成协调器；历史为内存队列；颜色采样使用捕获图像像素；截图会话状态不写 Core Data。

**验收标准：** 每个成功终局只写一条记录；`,`/`.` 边界不循环；取色格式正确；直线、折线、文字旋转及清除规则有测试。

## 文件

- 新建：`Qingniao/Services/ScreenshotService/CaptureHistory.swift`
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
    case print
}

enum CaptureCompletionOutcome {
    case completed(CaptureCompletion)
    case printed
}

@MainActor final class CaptureHistory {
    init(maximumCount: Int = 20)
    func record(_ result: ScreenshotResult, completion: CaptureCompletion)
    func previous(from id: UUID?) -> ScreenshotResult?
    func next(from id: UUID?) -> ScreenshotResult?
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
let history = CaptureHistory(maximumCount: 2)
history.record(resultA, completion: .copied)
history.record(resultB, completion: .saved(saveURL))
history.record(resultC, completion: .quickSaved(quickSaveURL))
XCTAssertEqual(history.previous(from: resultC.id)?.id, resultB.id)
XCTAssertEqual(ColorString.hex(red: 18, green: 52, blue: 86), "#123456")
XCTAssertEqual(ColorString.rgb(red: 18, green: 52, blue: 86), "18, 52, 86")
```

AnnotationTests 增加折线完成、清空后不可重做、文字旋转和 `⇧` 水平复位断言。
- [ ] 运行三个定向测试 target，确认新增 API 尚不存在。
- [ ] 实现 `CaptureHistory`、截图设置默认值和 `CaptureCompletionCoordinator`；把工具条及标注窗口的复制、保存、快捷保存、贴图与打印路径接入协调器；只有 `.completed` 写入历史。
- [ ] 实现放大镜采样、`C`/`⇧C`、WASD/方向键/修饰键像素操作和 `,`/`.` 记录回放。
- [ ] 扩展标注模型与渲染：直线、折线、系统颜色面板、宽度快捷键、文字缩放/旋转/`⇧` 复位。
- [ ] 保证草稿、工具条和快捷键提示不进入扁平化结果；复制、保存、打印失败保留会话。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/CaptureCompletionTests \
  -only-testing:QingniaoTests/ColorSamplerTests \
  -only-testing:QingniaoTests/AnnotationTests \
  -only-testing:QingniaoTests/SettingsServiceTests
```

- [ ] 递增版本、校验版本字段、运行 `git diff --check`。
- [ ] 提交：`feat(screenshot): add capture history completion and annotation tools`。
