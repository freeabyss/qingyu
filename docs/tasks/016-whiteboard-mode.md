# Task 016：白板模式

**目标：** 提供一个全屏可写画布，用同一套标注工具作画，用于讲解、临时记录、屏幕演示；不必先截图。

**范围：** 白板会话、画布底图两种模式、背景色、目标屏幕选择、与现有标注工具复用、退出与导出。不改截图捕获与贴图。

**相关模块：** `AnnotationCanvas`、`AnnotationShape`、`CaptureSessionController`、`Views/Annotation`、`App/Controllers`。

**业务规则：**

- 白板是一个**独立会话类型**，与截图会话互斥：白板进行中不允许启动截图，反之亦然。
- 底图两种模式：
  - **冻结底图**：以当前屏幕冻结画面为底（等同于「截全屏后直接进入标注」的复用形态）。
  - **纯色底图**：以纯色（默认白）为底，不读取屏幕内容 —— 此模式**不要求屏幕录制权限**。
- 目标屏幕：默认当前指针所在屏幕；可指定为某一屏幕；多屏时可选择「所有屏幕各开一个白板」。
- 背景色可配置（调色板 + 自定义），冻结底图模式下不改变底图只改变画布的填充行为（纯色模式专属）。
- 白板中的完成动作：**复制**、**保存**、**贴图**、**清空**、**退出**。不做「取消」（退出时若已有笔迹需二次确认）。
- 空白白板（无任何笔迹）退出时不弹确认、不产生任何文件与剪贴板写入。
- 笔迹在会话结束前始终可撤销/重做，与标注行为一致。
- 白板会话不写入任何历史记录（与既有产品决策一致：清羽不做截图历史）。
- 退出白板后屏幕恢复原状：不残留窗口、不改变窗口层级、不保留任何常驻进程或定时器。

**技术约束：**

- 复用 `AnnotationCanvas` / `AnnotationShape` / `AnnotationToolbar`，白板只提供「底图 + 会话包装」，**不得复制一份标注实现**。
- 纯色底图模式必须能在**未授予屏幕录制权限**时完整工作（这是本任务硬性要求，需有测试或明确的人工验收记录）。
- 白板窗口为无边框全屏窗口，覆盖单屏或所有屏；层级与截图叠层一致，退出时确保关闭。
- 会话状态纳入现有会话状态机体系（新增一个会话种类），遵守既有的生命周期回归用例要求（见 `docs/test/cases.md` 截图会话生命周期一节）。

**验收标准：**

- 单测：会话种类互斥、空白退出无副作用、清空行为、撤销重做、背景色参数钳制。
- 真实操作：纯色白板在**关闭屏幕录制权限**下可正常画线与导出；冻结底图白板显示当前屏幕内容；多屏「所有屏幕」模式各屏均可书写；退出后无残留窗口。
- 生命周期回归：切换会话、连续开关 10 次不出现遗留窗口或定时器（对齐既有回归用例的判定方式）。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Models/WhiteboardSession.swift`
- 新建：`Qingyu/Services/WhiteboardService/WhiteboardBackground.swift`（纯色 / 冻结底图两种来源）
- 新建：`Qingyu/App/Controllers/WhiteboardWindowController.swift`
- 新建：`Qingyu/Views/Whiteboard/WhiteboardCanvasView.swift`
- 修改：`Qingyu/Views/Annotation/AnnotationCanvas.swift`（抽出可复用底图接口）
- 修改：`Qingyu/Views/Annotation/AnnotationToolbar.swift`
- 修改：`Qingyu/App/Controllers/AppContainer.swift`、`Qingyu/App/Controllers/CaptureSessionController.swift`（互斥）
- 修改：`Qingyu/Models/AppSetting.swift`
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotPlugin.swift`（注册白板入口与快捷键）
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/WhiteboardSessionTests.swift`、`QingyuTests/WhiteboardBackgroundTests.swift`、`QingyuTests/CaptureSessionStateTests.swift`（互斥回归）
- UI 测试：`QingyuUITests/WhiteboardUITests.swift`

## 接口

```swift
enum WhiteboardBackgroundKind: String, Codable { case frozen, solid }

struct WhiteboardSession: Equatable {
    let id: UUID
    var background: WhiteboardBackgroundKind
    var solidColor: CGColor
    var displayIDs: [String]      // 空表示「所有屏幕」
    var shapes: [AnnotationShape]
}

enum WhiteboardBackgroundSource {
    /// 纯色：不读取屏幕，无需屏幕录制权限
    case solid(CGColor)
    /// 冻结底图：来自 CaptureService 的一次性抓屏
    case frozen(CGImage)
}
```

## 步骤

1. 先写 `WhiteboardSession` 与互斥规则的单测（含空白退出无副作用）。
2. 抽出 `AnnotationCanvas` 的底图接口，确认既有截图标注回归全绿。
3. 实现两种底图来源，并验证纯色模式在无屏幕录制权限下可用。
4. 实现全屏窗口控制器与多屏模式。
5. 注册入口与快捷键，接入完成动作（复制/保存/贴图/清空/退出）。
6. 补充生命周期回归用例并跑通；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做 Snipaste 的 `transparent-whiteboard`（透明底 + 其它应用可见）——那要求白板窗口本身可点击穿透并与桌面合成，属于另一个交互模型，需先确认产品是否要。
- 不做白板的持久化与历史（清羽不做截图历史）。
