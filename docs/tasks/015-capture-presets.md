# Task 015：预设区域与预设尺寸

**目标：** 让用户把常用选区保存为**预设区域**（带屏幕位置）与**预设尺寸**（固定宽高），一键把自己放到那个范围，省去每次重新框选。

**范围：** 预设的数据模型与持久化、预设管理界面、截图过程中的预设唤起与套用。不改捕获后端与完成动作。

**相关模块：** `CaptureSessionController`、`ScreenshotOverlay`、`ScreenshotSettingsPage`、`Models/AppSetting`、`Database/PersistenceController`。

**业务规则：**

- **两类预设语义不同，不可混用：**
  - **预设区域**：记录屏幕标识 + 逻辑坐标矩形。套用时把选区**直接放置**在该位置（含跨屏：若目标屏幕已断开，该预设标记为不可用，套用时报内联提示，不静默改用其它屏幕）。
  - **预设尺寸**：只记录宽高。套用时**以当前指针位置为中心**生成该尺寸的选区，并钳制到当前屏幕可见范围内。
- 预设数量上限（默认 20）与排序由用户维护；重名允许但显示时以序号区分。
- 截图会话中唤起预设：使用一个专用快捷键（默认 `Tab` 之外的未占用键）打开预设清单；方向键选择、回车套用、Esc 取消。清单只在会话内出现，不改变会话状态。
- 套用预设**不结束会话**，用户可继续微调后再执行完成动作。
- 预设是用户数据，随数据目录一起备份/迁移；不写入 Core Data 的业务表以外结构（沿用现有设置持久化方式）。
- 删除预设需要二次确认；删除后不可恢复（不做回收站）。
- 预设为空时快捷键不响应，不弹出空清单。

**技术约束：**

- 预设集合序列化为 JSON 存于现有设置项机制，沿用 `Models/AppSetting` 的既有模式，不新增数据库表。
- 套用计算（区域落位、尺寸居中 + 钳制）为**纯函数**，必须可单测，且不依赖真实屏幕。
- 屏幕识别使用稳定的屏幕标识（`NSScreen` 的显示 UUID / `CGDirectDisplayID`），不使用数组下标，避免显示器顺序变化导致预设错位。
- 清单 UI 为主窗口内叠加层，不新建窗口。

**验收标准：**

- 单测覆盖：区域落位、尺寸居中与钳制、屏幕缺失分支、上限与排序、空集合不响应、序列化往返一致。
- 真实操作：保存一个区域预设与一个尺寸预设，各自套用后选区几何与预期一致；拔掉外接屏后套用该屏区域预设，出现内联不可用提示而非错误落位。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Models/CapturePreset.swift`
- 新建：`Qingyu/Services/ScreenshotService/PresetResolver.swift`（落位/居中/钳制纯函数）
- 新建：`Qingyu/Views/Components/PresetPickerOverlayView.swift`
- 新建：`Qingyu/Views/Settings/PresetEditorView.swift`
- 修改：`Qingyu/App/Controllers/CaptureSessionController.swift`
- 修改：`Qingyu/Views/Components/ScreenshotOverlay.swift`
- 修改：`Qingyu/Views/Components/ScreenshotShortcutHintsView.swift`
- 修改：`Qingyu/Models/AppSetting.swift`、`Qingyu/Database/PersistenceController.swift`
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/PresetResolverTests.swift`、`QingyuTests/CapturePresetStoreTests.swift`
- 回归：`CaptureSessionStateTests.swift`、`SettingsServiceTests.swift`、`ScreenshotOverlayUITests.swift`

## 接口

```swift
enum CapturePresetKind: String, Codable { case region, size }

struct CapturePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var kind: CapturePresetKind
    /// kind == .region 时有效
    var displayID: String?
    var rect: CGRect?
    /// kind == .size 时有效
    var size: CGSize?
    var order: Int
}

enum PresetApplyError: Error, Equatable {
    case screenUnavailable(displayID: String)
    case outOfBounds
}

enum PresetResolver {
    static func resolve(
        regionPreset: CapturePreset,
        availableScreens: [ScreenDescriptor]
    ) -> Result<CGRect, PresetApplyError>

    static func resolve(
        sizePreset: CapturePreset,
        pointerLocation: CGPoint,
        screen: ScreenDescriptor
    ) -> CGRect
}

struct ScreenDescriptor: Equatable {
    let displayID: String
    let frame: CGRect        // 逻辑坐标
}
```

## 步骤

1. 先写 `PresetResolver` 失败用例（含屏幕缺失与边界钳制），转绿。
2. 实现 `CapturePreset` 与持久化（JSON 设置项 + 默认值）。
3. 实现设置页预设编辑器（增删改排序、区域预设「以当前选区保存」入口）。
4. 实现会话内预设清单叠加层与快捷键。
5. 真机验证跨屏与断屏分支；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做「自动记住上次选区」（Snipaste 的 `Reuse the last snipping areas`）——如需，另立小任务，因为它与预设是不同语义。
- 不做预设的导入导出与云同步。
