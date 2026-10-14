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
```
（实际实现与上面的草稿一致，另加 `CapturePresetCatalog`（上限 / 排序 / 增删改）、
`CapturePresetStore`（持久化 + `suggestedName`）与 `ScreenDescriptor.visibleFrame`
—— 尺寸预设必须钳制到**可见区**，因此描述符需要可见区而不只是 frame。）

```swift

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

## 交付记录（2026-10-14）

**✅ 已交付。** 关键实现决策：

- **持久化**：沿用设置项机制（`SettingKey.screenshotPresets` + JSON `[CapturePreset]`），**未新增数据库表**。`CapturePresetStore` 为 `@MainActor` 仓库，每次写操作立即落盘；会话期只读快照，避免交互期被落盘抖动影响。
- **区域预设的坐标语义（与原卡片不同，已记录）**：`rect` 存的是**相对目标屏幕 `frame` 原点的偏移**，不是全局绝对坐标。显示器重新排布后绝对坐标必然失效，相对偏移仍然正确。`displayID` 用 `CGDirectDisplayID` 的字符串形式（稳定标识，不用数组下标）。
- **断屏与越界**：屏幕缺失返回 `.screenUnavailable`、矩形放不下返回 `.outOfBounds`，两者都在叠层上给**内联提示**（`updateNotice`），**不静默改用其它屏幕、不悄悄改位置**。
- **尺寸预设**：以指针为中心，钳制到该屏可见区；尺寸大于可见区时截断而非报错。
- **清单 UI 不新建窗口**：直接在截图叠层（`CaptureOverlayContentView`）上绘制，只有活动屏渲染。键位：`P` 打开、`↑`/`↓` 选择（到边界回卷）、`Enter` 套用、`Esc` 关闭；空集合时 `P` 不响应。
- **套用不结束会话**：区域预设直接落到可微调态，用户可继续微调后再 `Enter` 确认；已锁定/已取消时拒绝套用。
- **持久化与并发的两个坑（已修）**：
  1. 只写在协议扩展里的方法对**存在类型走静态派发**，替身与真实叠层的实现永远不会被调用 —— `updatePresetPicker` / `updateNotice` 因此改为**协议要求 + 扩展默认实现**。
  2. `switchActiveDisplay(notifyState: false)` 是 `start()` 的首帧语义，会**整个重置会话状态**；套用预设后若走它，刚套用的选区会被立刻抹掉。改为新增 `focusActiveDisplay(on:)`（只切活动屏+刷新叠层）。
- **创建入口**：卡片提到的「以当前选区保存」入口落在**会话内**（`⌘S` 区域 / `⌘⇧S` 尺寸），而不是设置页；设置页负责改名 / 排序 / 删除（删除带二次确认）。会话开始时重新装载一次预设，因此设置页的改动无需重启即可生效。
- **排序稳定性**：`order` 相同时用原数组位置做稳定兜底 —— Swift 的 `sorted` 不是稳定排序，依赖其巧合顺序会让 `move` 结果随机漂移（该缺陷在实现过程中被测试捕获）。

**测试：** `CapturePresetTests` 18 条（落位、断屏、越界、钳制、上限、排序、持久化往返、Codable）+ `CaptureSessionControllerTests` 新增 11 条（套用进入可微调态且不结束会话、断屏/越界内联提示、尺寸居中与不超屏、清单开关与回卷、空集合不响应、套用高亮项、保存区域/尺寸、未框选与满额提示）。

## 步骤

1. 先写 `PresetResolver` 失败用例（含屏幕缺失与边界钳制），转绿。
2. 实现 `CapturePreset` 与持久化（JSON 设置项 + 默认值）。
3. 实现设置页预设编辑器（增删改排序、区域预设「以当前选区保存」入口）。
4. 实现会话内预设清单叠加层与快捷键。
5. 真机验证跨屏与断屏分支；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做「自动记住上次选区」（Snipaste 的 `Reuse the last snipping areas`）——如需，另立小任务，因为它与预设是不同语义。
- 不做预设的导入导出与云同步。

## 状态

| 项 | 状态 | 说明 |
|---|---|---|
| 预设区域与预设尺寸 | ✅ 已交付 | 数据 / 落位 / 目录 / 持久化 + 会话内清单（`P` / `↑↓` / `Enter` / `Esc`）+ 会话内创建（`⌘S` / `⌘⇧S`）+ 设置页改名 / 排序 / 删除。详见上「交付记录」。 |
