# Task 012：窗口与界面元素自动识别

**目标：** 截图时鼠标悬停即高亮**窗口**，在窗口内继续悬停则高亮**界面控件**，点击即选中；选区边缘靠近窗口/控件边界时自动吸附，让用户不必像素级对齐。

**范围：** 候选区域探测、悬停命中与高亮、边缘吸附判定、探测设置与忽略清单。不改捕获后端与完成动作。

**相关模块：** `WindowCandidateProvider`、`ScreenshotOverlay`、`CaptureSessionController`、`CaptureTarget`、`ScreenshotSettingsPage`。

**业务规则：**

- 悬停优先级：**控件 > 窗口 > 无**。指针在某个控件上时高亮该控件而非其所属窗口。
- 控件级探测需要「辅助功能」权限；**仅做窗口级探测不需要该权限**。未授权时静默降级为窗口级，不弹窗、不阻断截图（与现有权限按需申请策略一致）。
- 吸附：选区边缘进入吸附阈值后对齐到最近的候选边界；阈值可配置、可关闭。关闭后不吸附。
- 阈值按**逻辑点**计，不按物理像素，避免不同缩放屏幕手感不一致。
- 可配置忽略清单：命中清单内的应用时**不做控件级探测**，只做窗口级（用于规避个别程序探测卡顿/崩溃）。
- 探测失败、超时或返回空集合时：保持无高亮，截图流程继续，不得报错中断。
- 探测必须在**后台**执行并有超时上限；指针移动触发的探测不得阻塞主线程或造成输入卡顿。
- 进入截图会话时不做全量预扫描；按指针位置惰性探测并缓存**当前屏幕**的候选集合，跨屏后重建缓存。
- 点击选中后，选中区域与该候选区域一致；用户随后仍可自由调整（不锁定）。

**技术约束：**

- 窗口级探测使用 `CGWindowListCopyWindowInfo`（无需额外权限）；控件级探测使用 `AXUIElementCopyElementAtPosition` 系列接口，集中在单一 Service 内，便于替换与测试。
- 所有系统调用结果必须转换为内部值类型后再交给视图；视图不直接持有 `AXUIElement` / `CFDictionary`。
- 命中判定与吸附计算为**纯函数**，必须可单测（不依赖真实窗口系统）。
- `ThreadedWindowDetector` 式的后台探测需可取消：会话结束或指针快速移动时取消在途探测。
- 明确排除自身窗口与系统装饰窗口（菜单栏、Dock、桌面背景）作为候选。

**验收标准：**

- 单测覆盖：命中优先级（控件 > 窗口 > 无）、阈值吸附与关闭、忽略清单生效、空/超时结果不阻断、跨屏缓存重建、自身窗口被排除。
- 真实截图：悬停一个普通窗口得到窗口高亮；在 Safari 工具栏上悬停得到控件级高亮与窗口级高亮两种结果；未授权辅助功能时只有窗口级高亮且无弹窗。
- 连续快速移动指针 3 秒，界面无可感知卡顿（主线程无阻塞探测）。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Services/ScreenshotService/ElementCandidateProvider.swift`（控件级探测）
- 新建：`Qingyu/Services/ScreenshotService/CandidateHitTest.swift`（命中与吸附纯函数）
- 新建：`Qingyu/Services/ScreenshotService/CandidateProbeScheduler.swift`（后台惰性探测 + 取消 + 超时）
- 修改：`Qingyu/Services/ScreenshotService/WindowCandidateProvider.swift`
- 修改：`Qingyu/Views/Components/ScreenshotOverlay.swift`
- 修改：`Qingyu/App/Controllers/CaptureSessionController.swift`
- 修改：`Qingyu/Models/AppSetting.swift`
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/CandidateHitTestTests.swift`、`QingyuTests/ElementCandidateProviderTests.swift`、`QingyuTests/CandidateProbeSchedulerTests.swift`
- 回归：`QingyuTests/CaptureSessionControllerTests.swift`、`ScreenshotOverlayUITests.swift`

## 接口

```swift
enum CandidateKind: Equatable { case window, element }

struct CandidateRegion: Equatable {
    let kind: CandidateKind
    let frame: CGRect          // 逻辑坐标
    let ownerBundleID: String?
    let title: String?
}

/// 纯函数：命中优先级与边缘吸附
enum CandidateHitTest {
    static func hit(
        point: CGPoint,
        candidates: [CandidateRegion]
    ) -> CandidateRegion?

    static func snap(
        rect: CGRect,
        candidates: [CandidateRegion],
        threshold: CGFloat
    ) -> CGRect
}

protocol CandidateProbing: AnyObject {
    func probe(at screenPoint: CGPoint, screen: CGRect, options: ProbeOptions) async -> [CandidateRegion]
}

struct ProbeOptions: Equatable {
    var elementProbingEnabled: Bool
    var ignoredBundleIDs: Set<String>
    var timeout: TimeInterval
}
```

## 步骤

1. 先写 `CandidateHitTest` 的失败用例（优先级、吸附、阈值边界）。
2. 实现纯函数并转绿。
3. 实现 `ElementCandidateProvider`（AX 探测，权限缺失降级）。
4. 实现 `CandidateProbeScheduler`（惰性、可取消、有超时、跨屏重建）。
5. 接入 `ScreenshotOverlay` 高亮与 `CaptureSessionController` 选中。
6. 设置页新增：吸附阈值、控件探测开关、忽略清单。
7. 真机验证权限降级与手感；运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 不做 Snipaste 的「按程序切换检测算法」这种分程序自定义（只保留忽略清单），除非真机验证出现必须分类处理的程序。
- 不做 OCR / 视觉元素分割；控件级识别完全依赖辅助功能接口。
- **真实辅助功能权限下的行为未做自动化验收**：控件级高亮、忽略清单生效、吸附手感需实机确认（对应 SHOT-LIFE-006 手工冒烟）。
- 吸附候选为「该显示器上的全部可见窗口 + 当前悬停控件」，不做全屏控件预扫描 —— 与「进入会话不做全量预扫描」的规则一致。

## 验证记录

- `./scripts/verify.sh`：**400 项单元测试、0 失败**；`git diff --check` 通过。
- 新增用例：
  - `CandidateHitTestTests`（13 项）：命中优先级 element > window > nil、同类取面积最小、空/零尺寸候选、吸附阈值与边界、吸附后最小尺寸保护、点吸附双轴独立、忽略清单匹配。
  - `ElementCandidateProviderTests`（9 项）：关闭态零调用、Quartz→AppKit 坐标换算、`AXValue` 类型守卫（类型不符返回 nil 而非崩溃）。
  - `CandidateProbeSchedulerTests`（4 项）：关闭开关零调用、结果投递到主线程、取消后不回调、在途请求合并。
- 回归：`CaptureSessionControllerTests`（含新增 `FakeElementProvider`）与 `CaptureSessionStateTests` 保持通过；`docs/test/cases.md` 第 12 节新增 SHOT-LIFE-005（控件探测生命周期），原手工冒烟顺延为 SHOT-LIFE-006。
- 工程：6 个新文件加入 `Qingyu.xcodeproj/project.pbxproj`（app target 3 个、test target 3 个）。

### 顺手修复的一处既有脆弱性（与本任务无关，但门禁要求修复）

验证过程中 `PinWindowControllerTests.testScreenshotPinWithoutSelectionFallsBackToDefaultImageSize`
稳定失败：窗口尺寸为 **80×61** 而非 80×60。

- **根因**：`visibleFrame.height` 为奇数时（本机实测 865），`PinWindowLayout.cascadeOrigin`
  算出的中心 y 为 `402.5`；`NSWindow` 把窗口矩形整数化时 maxY 由 `462.5` 向上取整，
  高度被撑大 1pt。是否出现取决于菜单栏/Dock 造成的可见高度奇偶，因此同一台机器上时通时挂。
- **处置**：不放松断言，而是让 `cascadeOrigin` 的原点取整（`rounded()`），使窗口几何与
  `defaultSize` 严格一致且不随屏幕奇偶变化；新增
  `testCascadeOriginIsIntegralForOddVisibleHeight`，用 `NSIntegralRect` 钉住「整数化不得改变窗口尺寸」。
