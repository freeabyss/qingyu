# Task 006：多显示器截图叠层与快捷键提示

**目标：** 在所有显示器创建统一截图叠层，指针跨屏时切换截图上下文，并在当前显示器左下角显示可用快捷键。

**范围：** 多屏窗口管理、窗口命中检测、鼠标交互、当前屏切换、提示 UI；不处理截图完成后的标注和贴图。

**相关模块：** `ScreenshotOverlay`、Task 005 的 `CaptureSessionState` 与捕获后端。

**业务规则：** 进入状态即高亮指针所在窗口；单击锁定窗口；按住左键拖拽选择区域；`⌘A` 锁定当前显示器；`Esc` 取消全部叠层。

**技术约束：** 每个 `NSScreen` 一个 borderless window；所有 window 共享一个会话状态；窗口命中排除青鸟自身截图叠层、菜单栏和桌面；提示固定在当前显示器左下安全边距内。

**验收标准：** 两个显示器上只有指针所在屏展示活动高亮和提示；跨屏后 100ms 内切换；完成或取消时关闭全部叠层。

## 文件

- 新建：`Qingniao/Services/ScreenshotService/WindowCandidateProvider.swift`
- 新建：`Qingniao/App/Controllers/CaptureSessionController.swift`
- 修改：`Qingniao/Views/Components/ScreenshotOverlay.swift`
- 新建：`Qingniao/Views/Components/ScreenshotShortcutHintsView.swift`
- 修改：`Qingniao/App/Controllers/ScreenshotWindowController.swift`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 测试：`QingniaoTests/CaptureSessionControllerTests.swift`
- UI 测试：`QingniaoUITests/ScreenshotOverlayUITests.swift`

## 接口

```swift
protocol DisplayProviding {
    var displays: [CaptureDisplay] { get }
    func display(containing point: CGPoint) -> CaptureDisplay?
}

protocol WindowCandidateProviding {
    func candidate(at point: CGPoint, on display: CaptureDisplay) -> CaptureWindowCandidate?
}

@MainActor final class CaptureSessionController {
    private(set) var state: CaptureSessionState
    private(set) var activeDisplayID: CGDirectDisplayID?
    func start()
    func handle(_ event: CaptureInputEvent)
    func cancel()
}

enum CaptureInputEvent {
    case pointerMoved(CGPoint)
    case mouseDown(CGPoint)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case selectFullDisplay
    case cancel
}
```

测试文件内定义 `RecordingOverlayWindowFactory`，记录 `createdDisplayIDs` 与 `closedDisplayIDs`，避免单元测试创建真实全屏窗口。

## 快捷键提示

| 状态 | 左下角提示 |
|---|---|
| 窗口选择 | `单击 截取窗口`、`拖拽 选择区域`、`⌘A 全屏`、`Esc 取消` |
| 区域拖拽 | `松开 完成选区`、`Esc 取消` |
| 选区锁定 | `Enter 复制`、`⌘S 保存`、`空格 工具栏`、`Esc 取消` |
| 标注 | `⌘Z 撤销`、`⇧⌘Z 清空`、`Enter 复制`、`Esc 取消` |

## 步骤

- [ ] 写失败测试，注入左右两个显示器和记录创建/关闭次数的 window factory：

```swift
controller.start()
XCTAssertEqual(windowFactory.createdDisplayIDs, [leftDisplay.id, rightDisplay.id])
controller.handle(.pointerMoved(CGPoint(x: rightDisplay.frame.midX, y: rightDisplay.frame.midY)))
XCTAssertEqual(controller.activeDisplayID, rightDisplay.id)
controller.cancel()
XCTAssertEqual(windowFactory.closedDisplayIDs.count, 2)
```
- [ ] 写 UI 测试 hook `--uitest-screenshot-displays 2`，断言活动叠层有 `screenshot.shortcutHints`，非活动叠层隐藏提示。
- [ ] 运行定向测试，确认类型与标识符缺失导致失败。
- [ ] 实现 `WindowCandidateProvider`，用 `CGWindowListCopyWindowInfo` 按 z-order 返回指针下第一个可捕获窗口。
- [ ] 重构 `ScreenshotOverlayController` 为 `CaptureSessionController`：枚举 `NSScreen.screens` 建窗，使用全局坐标分发事件，共享 Task 005 状态。
- [ ] 实现 `ScreenshotShortcutHintsView` 和按状态生成的提示数组；位置使用显示器 visible frame 左下角 16pt inset。
- [ ] 监听 `NSApplication.didChangeScreenParametersNotification`，变化时重建叠层和坐标映射。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/CaptureSessionControllerTests \
  -only-testing:QingniaoUITests/ScreenshotOverlayUITests
```

- [ ] 递增版本、校验版本字段、运行 `git diff --check`。
- [ ] 提交：`feat(screenshot): add multi-display unified overlay and hints`。
