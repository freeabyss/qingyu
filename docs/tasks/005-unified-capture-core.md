# Task 005：统一截图内核与自动模式判定

**目标：** 用一个截图会话模型表达窗口、区域和当前显示器全屏选择，并根据指针位置与鼠标操作自动判定模式，复用同一个像素捕获后端。

**范围：** 单一截图入口、纯状态机、目标模型、自动模式判定和捕获后端；本任务移除区域、窗口、全屏的独立入口。

**相关模块：** `ScreenshotService`、`ScreenshotWindowController`、`ScreenshotGeometry`。

**业务规则：** 初始状态默认选中指针所在窗口；指针位于最上方菜单栏或桌面空白区域时默认选中当前显示器全屏；只要左键发生拖拽，区域圈选优先于悬停默认值并自动截取区域；`⌘A` 选择当前显示器；选区最小 `5×5` 像素。

**技术约束：** 状态机不依赖 `NSWindow`；坐标统一保存为全局 AppKit point，捕获前再转换为显示器像素；捕获后端不管理 UI 生命周期。

**验收标准：** 窗口单击、区域拖拽、全屏和取消四条状态流可由单元测试驱动；Retina 与负坐标转换通过。

## 文件

- 新建：`Qingyu/Services/ScreenshotService/CaptureSessionState.swift`
- 新建：`Qingyu/Services/ScreenshotService/CaptureTarget.swift`
- 新建：`Qingyu/Services/ScreenshotService/ScreenCaptureBackend.swift`
- 修改：`Qingyu/Services/ScreenshotService/ScreenshotService.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/CaptureSessionStateTests.swift`
- 回归：`QingyuTests/AnnotationTests.swift`

## 接口

```swift
struct CaptureDisplay: Hashable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let pixelSize: CGSize
}

struct CaptureWindowCandidate: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let displayID: CGDirectDisplayID
}

enum CaptureTarget: Hashable {
    case window(CaptureWindowCandidate)
    case region(display: CaptureDisplay, globalRect: CGRect)
    case display(CaptureDisplay)
}

enum CaptureSessionPhase: Equatable {
    case targetingWindow(CaptureWindowCandidate?)
    case draggingRegion(start: CGPoint, current: CGPoint, display: CaptureDisplay)
    case locked(CaptureTarget)
    case cancelled
}

struct CaptureSessionState {
    private(set) var phase: CaptureSessionPhase
    init()
    mutating func pointerMoved(to point: CGPoint, display: CaptureDisplay, window: CaptureWindowCandidate?)
    mutating func mouseDown(at point: CGPoint, display: CaptureDisplay)
    mutating func mouseDragged(to point: CGPoint)
    mutating func mouseUp(at point: CGPoint)
    mutating func selectFullDisplay(_ display: CaptureDisplay)
    mutating func cancel()
}

protocol ScreenCaptureBackendProtocol: Sendable {
    func capture(_ target: CaptureTarget) async throws -> ScreenshotResult
}
```

`ScreenshotResult` 保留稳定的 `id: UUID` 供当前截图会话内部关联；MVP 不建立截图历史记录或记录导航。

## 步骤

- [ ] 写失败测试：

```swift
var state = CaptureSessionState()
state.pointerMoved(to: CGPoint(x: 100, y: 100), display: leftDisplay, window: candidate)
state.mouseDown(at: CGPoint(x: 100, y: 100), display: leftDisplay)
state.mouseUp(at: CGPoint(x: 100, y: 100))
XCTAssertEqual(state.phase, .locked(.window(candidate)))

state = CaptureSessionState()
state.mouseDown(at: CGPoint(x: 10, y: 10), display: rightDisplay)
state.mouseDragged(to: CGPoint(x: 110, y: 80))
state.mouseUp(at: CGPoint(x: 110, y: 80))
XCTAssertEqual(state.phase, .locked(.region(display: rightDisplay, globalRect: CGRect(x: 10, y: 10, width: 100, height: 70))))
```

再覆盖 `selectFullDisplay(_:)`、取消、最小选区和跨屏 pointer move。
- [ ] 为 `ScreenCaptureBackend` 写窗口 ID、显示器 ID、Retina 比例和负坐标裁剪测试。
- [ ] 运行：

```bash
xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu -only-testing:QingyuTests/CaptureSessionStateTests
```

预期：新类型尚不存在，测试编译失败。

- [ ] 实现状态机；`mouseUp` 在拖动不足最小尺寸时回到当前窗口候选，达到尺寸时锁定区域。
- [ ] 把现有 `CGWindowListCreateImage`、`CGDisplayCreateImage` 和区域裁剪移入 `ScreenCaptureBackend.capture(_:)`。
- [ ] 让旧 `captureRegion()`、`captureWindow()`、`captureScreen()` 暂时调用新后端，保持现有入口可用。
- [ ] 加入工程 target，运行 CaptureSessionStateTests 与 AnnotationTests，预期 PASS。
- [ ] 递增版本、校验版本字段、运行 `git diff --check`。
- [ ] 提交：`refactor(screenshot): add unified capture state and backend`。
