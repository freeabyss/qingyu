# Task 018：贴图图像组

> ⚠️ **执行前需产品决策。** 本任务引入「分组」这一新的产品概念，会改变贴图的组织方式与菜单结构。
> 在开始实现前，必须先确认第 1 节的两个问题，并将结论写入 `docs/prd/01-product-prd.md`。
> 未完成决策前，本任务**不应开工**。

**目标：** 让用户把贴图按用途分成多组（如「参考图」「对比图」「临时」），可整组切换、隐藏、清空与导出。

**范围：** 分组模型与持久化、组切换与组管理界面、批量操作、与既有恢复队列/隐藏语义的整合。

**相关模块：** `PinStore`、`PinWindowController`、`PinItem`、`Views/Pinning`、`Models/AppSetting`。

## 1. 执行前决策（阻塞）

1. **是否引入「分组」概念？** 现有产品规则是「贴图之间不建立分组关系」（Task 008 已确认）。引入分组需以新决策覆盖该规则，并说明对现有「隐藏全部 / 关闭全部 / 恢复最近关闭」的影响。
2. **分组是否持久化？** 现有贴图状态不持久化（退出应用即销毁）。若分组要跨启动保留，需明确保存的内容（仅元数据还是含图像），以及随之而来的磁盘占用与隐私说明更新。

建议默认（若用户无特别要求）：**引入分组，但分组只存在于运行期、不持久化**，与现有「退出即销毁」语义保持一致，改动面最小。

## 2. 业务规则（在决策通过后生效）

- 分组是**运行期**概念：默认只有一个「默认组」，所有新建贴图进入当前组。
- 切换组：把当前组的贴图整体隐藏（不销毁），把目标组的贴图整体显示；切换不改动任何贴图的几何位置。
- 移动到组：把选中的贴图从当前组移入目标组；若目标组当前不可见，该贴图随之隐藏。
- 清空组：关闭该组全部贴图并**清出恢复队列**（与「隐藏」不同，清空后不可恢复），需要二次确认。
- 导出组：把该组内全部贴图按序号导出到用户选择的目录（一次目录选择，多文件写入），命名规则与现有单张保存一致并追加序号；同名冲突时追加递增序号，不覆盖。
- 删除组：仅允许删除空组；删除后不可恢复。
- 关闭/恢复/销毁的既有语义**全部按组生效**：恢复队列是每组的队列，切换组不会把别组的贴图恢复出来。
- 组切换后需要对用户有明确反馈（避免「贴图去哪了」）：默认以组名短暂提示，不做闪烁动画。
- 组名允许重名；组数量上限（默认 10）。

**技术约束：**

- 分组归属放在现有运行期 Store 内，不新增数据库表（与「贴图状态不持久化」一致）。
- 每组一个独立的恢复队列，容量沿用现有 `restoreCapacity` 设置。
- 导出为批量文件写入：必须处理部分失败（某张写失败不中止整体），并在结束时报告成功/失败计数。
- 组管理界面复用现有设计系统组件，不新建窗口框架。

**验收标准：**

- 单测：分组创建/切换/移动/清空/删除空组、每组独立恢复队列、导出部分失败计数、上限与重名、组切换不改变几何位置。
- 真实操作：两组各放 2 张贴图，反复切换 5 次，屏幕上贴图集合与预期一致且无残留窗口；导出 4 张得到 4 个文件。
- 生命周期回归：连续切换与退出，无遗留窗口/定时器。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Services/Pinning/PinGroupStore.swift`
- 新建：`Qingyu/Views/Pinning/PinGroupBarView.swift`
- 新建：`Qingyu/Views/Pinning/PinGroupManagerView.swift`
- 新建：`Qingyu/Services/Pinning/PinGroupExporter.swift`
- 修改：`Qingyu/Services/Pinning/PinStore.swift`
- 修改：`Qingyu/App/Controllers/PinWindowController.swift`
- 修改：`Qingyu/Views/Pinning/PinWindowView.swift`
- 修改：`Qingyu/Models/AppSetting.swift`
- 修改：`Qingyu/App/Controllers/AppContainer.swift`
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotPlugin.swift`（组切换入口与快捷键）
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/PinGroupStoreTests.swift`、`QingyuTests/PinGroupExporterTests.swift`
- 回归：`PinStoreTests.swift`、`PinWindowControllerTests.swift`、`PinWindowUITests.swift`

## 接口

```swift
struct PinGroup: Identifiable, Equatable {
    let id: UUID
    var name: String
    var itemIDs: [UUID]
    var restoreQueue: [UUID]
}

protocol PinGroupStoring: AnyObject {
    var groups: [PinGroup] { get }
    var currentGroupID: UUID { get }
    var maxGroups: Int { get }

    func createGroup(name: String) -> UUID?
    func renameGroup(_ id: UUID, to name: String)
    func deleteEmptyGroup(_ id: UUID) throws
    func switchTo(_ id: UUID)
    func move(itemIDs: [UUID], to groupID: UUID)
    func clearGroup(_ id: UUID, confirmed: Bool)
}

struct PinGroupExportResult: Equatable {
    let exported: Int
    let failures: [(id: UUID, reason: String)]
}
```

## 步骤

1. **先完成第 1 节决策并更新 PRD。**（未完成不得进入下一步）
2. 写 `PinGroupStore` 失败用例（含每组独立恢复队列），转绿。
3. 实现组切换与移动，接入贴图窗口显示/隐藏。
4. 实现组管理界面与组切换反馈提示。
5. 实现导出（批量 + 部分失败上报）。
6. 补充生命周期回归；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做跨设备/云同步。
- 不做组内的贴图排序拖拽（按创建顺序）。
- 不做「组切换闪烁动画」（Snipaste 用闪烁提示，清羽以文字提示替代，符合现有设计语言）。
