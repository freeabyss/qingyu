# Task 008：贴图

**目标：** 将剪贴板或成功截图转换为跨 Space 置顶贴图，并实现关闭、恢复、销毁和变换。

**范围：** 载荷解析、运行期状态、贴图窗口、键鼠交互和设置。

**相关模块：** 系统剪贴板、Task 007 完成协调器、截图设置页、AppKit window level。

**业务规则：** 解析顺序为图像、颜色、HTML、纯文本、文件路径；恢复队列默认 1、范围 `0…20`；退出应用销毁全部运行期贴图；贴图之间不建立分组关系。

**技术约束：** HTML 仅本地富文本渲染；脚本与远程资源关闭；窗口使用 `.floating`、`.canJoinAllSpaces`、`.fullScreenAuxiliary`；状态不持久化。

**验收标准：** 五类载荷、缩放/透明度边界、旋转/翻转、关闭/恢复/销毁、隐藏、替换和鼠标穿透均有测试。

## 文件

- 新建：`Qingniao/Models/PinItem.swift`
- 新建：`Qingniao/Services/Pinning/PinPayloadFactory.swift`
- 新建：`Qingniao/Services/Pinning/PinStore.swift`
- 新建：`Qingniao/App/Controllers/PinWindowController.swift`
- 新建：`Qingniao/Views/Pinning/PinWindowView.swift`
- 修改：`Qingniao/Models/AppSetting.swift`
- 修改：`Qingniao/Views/Components/ScreenshotToolbarController.swift`
- 修改：`Qingniao/App/Controllers/AppContainer.swift`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 测试：`QingniaoTests/PinPayloadFactoryTests.swift`、`PinStoreTests.swift`、`PinWindowControllerTests.swift`
- UI 测试：`QingniaoUITests/PinWindowUITests.swift`

## 接口

```swift
enum PinPayloadKind: Equatable { case image, color, attributedText, text }

enum PinPayload: Equatable {
    case image(Data)
    case color(red: UInt8, green: UInt8, blue: UInt8)
    case attributedText(NSAttributedString)
    case text(String)

    var kind: PinPayloadKind { get }
}

struct PinItem: Identifiable, Equatable {
    let id: UUID
    var payload: PinPayload
    var transform: PinTransform
    var isHidden: Bool
    var ignoresMouseEvents: Bool
}

struct PinTransform: Equatable {
    var scale: CGFloat
    var opacity: CGFloat
    var quarterTurns: Int
    var flippedHorizontally: Bool
    var flippedVertically: Bool
}

@MainActor final class PinStore {
    func add(payload: PinPayload) -> PinItem
    func close(_ id: UUID)
    func restoreLatestClosed() -> PinItem?
    func destroy(_ id: UUID)
    func hideAll()
    func showAll()
    func destroyAll()
}
```

## 步骤

- [ ] 写失败测试覆盖解析和生命周期：

```swift
XCTAssertEqual(try factory.makePayload(from: imagePasteboard).kind, .image)
XCTAssertEqual(try factory.makePayload(from: hexPasteboard).kind, .color)
let pin = store.add(payload: .text("example"))
store.close(pin.id)
XCTAssertEqual(store.restoreLatestClosed()?.id, pin.id)
store.destroy(pin.id)
XCTAssertNil(store.restoreLatestClosed())
```

再覆盖文件路径首次转图片/再次转文本、HTML 过滤和恢复队列容量。
- [ ] 写变换测试：缩放钳制 `10%…800%`，不透明度钳制 `10%…100%`，中键复位，旋转和翻转。
- [ ] 运行 Pin 三组单元测试，确认新类型缺失导致失败。
- [ ] 实现 `PinPayloadFactory` 与 `PinStore`；图片解码失败或载荷无效时返回明确错误且不创建空贴图。
- [ ] 实现 `PinWindowController` 和窗口 View，接入滚轮、数字键、双击、中键、`⌘V`、关闭、销毁、隐藏和鼠标穿透。
- [ ] 将 Task 007 的 `.pinned` 完成动作接到 `PinWindowController.present(_:)`；截图成功贴图只创建贴图，不写入截图历史。
- [ ] 添加截图设置：文件路径转图片、恢复队列容量、鼠标穿透快捷键。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao \
  -only-testing:QingniaoTests/PinPayloadFactoryTests \
  -only-testing:QingniaoTests/PinStoreTests \
  -only-testing:QingniaoTests/PinWindowControllerTests \
  -only-testing:QingniaoUITests/PinWindowUITests
```

- [ ] 递增版本、校验版本字段、运行 `git diff --check`。
- [ ] 提交：`feat(pinning): add runtime pin windows and lifecycle`。
