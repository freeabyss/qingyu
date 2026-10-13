# Task 011：截图放大镜

**目标：** 在截图选区内提供像素级放大镜，显示放大画面、屏幕坐标与订阅网格，让用户能精确到像素地定位选区边界。

**范围：** 放大镜视图、放大倍数与显示项设置、与现有选区叠层的联动、点击取色的坐标来源统一。不引入新的截图入口，不改会话生命周期。

**相关模块：** `ScreenshotOverlay`、`CaptureSessionController`、`CaptureSessionState`、`ColorSampler`、`ScreenshotSettingsPage`、`Views/Components`。

**业务规则：**

- 放大镜在鼠标进入选区或选区建立后显示，跟随光标；靠近屏幕边缘时自动翻转到内侧，不越出当前显示器可见范围。
- **取样来源（与 Snipaste 的差异，实施时确认）**：Snipaste 在进入截图时**冻结整屏**，放大镜读取该冻结位图。清羽当前**不冻结屏幕**（`ScreenCaptureBackend` 在目标锁定后才 `CGDisplayCreateImage`），因此改为用
  `CGWindowListCreateImage(rect, .optionOnScreenBelowWindow, 叠层窗口号, .bestResolution)`
  在**叠层窗口下方按需取样**：
  - 优点：不会把清羽自己的暗幕与选框拍进放大镜；无需引入整屏冻结，不改变 Task 005/007 的捕获契约与会话生命周期；
  - 代价：放大画面取自「请求那一刻」的屏幕，与最终捕获并非同一次采样（屏幕静止时二者一致；有视频/动画时可能有极小差异）。
  - 若日后改为冻结帧模型，只需替换 `MagnifierSourcing` 的实现，视图与几何换算不变。
- 显示项可独立开关：像素网格线、屏幕坐标、放大倍数标签、选区外遮罩。默认网格与坐标开、遮罩开。
- 放大倍数可取 `2×/4×/8×/16×`，默认 `8×`；倍数切换即时生效，不重建会话。
- **坐标一律为物理像素**（与 `Physical pixel (px)` 语义一致），并同时给出逻辑坐标；两套坐标不得混用。
- 光标位于选区内时，放大镜中心点与取色点必须是**同一个采样点**；取色结果复用该点的像素，不另开采样路径。
- 放大镜只在截图会话期间存在，会话结束后不保留任何状态。

**技术约束：**

- 放大采用对原始位图的**最近邻**采样，禁止插值（插值会让像素边界渲染失真，失去放大镜的意义）。
- 放大镜视图为主窗口内的叠加层，不新建窗口，不改变窗口层级。
- 坐标换算集中在单一纯函数中（逻辑坐标 ⇄ 物理像素 ⇄ 位图索引），该函数必须可单测；禁止在视图里散落换算。
- 多显示器下以**指针所在屏幕**的 scale 与原点进行换算。

**验收标准：**

- 单测覆盖：坐标换算三向一致性、边缘翻转、倍数切换、显示项开关组合、取色点与放大镜中心点同源。
- 真实截图：在 1× 与 2× 显示器上各抓一帧，放大镜中心像素与 `ColorSampler` 取色结果一致。
- `./scripts/verify.sh` 全量单元测试与 `git diff --check` 通过。

## 文件

- 新建：`Qingyu/Views/Components/MagnifierOverlayView.swift`
- 新建：`Qingyu/Services/ScreenshotService/MagnifierGeometry.swift`（坐标换算纯函数）
- 修改：`Qingyu/Views/Components/ScreenshotOverlay.swift`
- 修改：`Qingyu/App/Controllers/CaptureSessionController.swift`
- 修改：`Qingyu/Services/ScreenshotService/CaptureSessionState.swift`
- 修改：`Qingyu/Services/ScreenshotService/ColorSampler.swift`
- 修改：`Qingyu/Models/AppSetting.swift`、`Qingyu/Views/Design/JadeColor.swift`（如需新增设置项）
- 修改：`Qingyu/Plugins/Screenshot/ScreenshotSettingsPage.swift`
- 修改：`Qingyu.xcodeproj/project.pbxproj`
- 测试：`QingyuTests/MagnifierGeometryTests.swift`、`QingyuTests/MagnifierStateTests.swift`
- 回归：`QingyuTests/CaptureSessionStateTests.swift`、`ColorSamplerTests.swift`、`ScreenshotOverlayUITests.swift`

## 接口

```swift
struct MagnifierGeometry {
    /// 逻辑坐标（屏幕 points）→ 物理像素采样点
    static func samplePoint(
        logicalPoint: CGPoint,
        screenFrame: CGRect,
        scale: CGFloat
    ) -> CGPoint

    /// 采样点 → 放大镜框（自动翻转，保证落在 visibleFrame 内）
    static func magnifierFrame(
        samplePoint: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        anchorAbove: Bool
    ) -> CGRect

    /// 采样点 → 原始位图中的像素索引
    static func bitmapIndex(
        samplePoint: CGPoint,
        captureRect: CGRect,
        bitmapScale: CGFloat
    ) -> (x: Int, y: Int)?
}

enum MagnifierDisplayOption: String, CaseIterable, Codable {
    case grid, coordinate, zoomLabel, mask
}

struct MagnifierConfiguration: Equatable {
    var isEnabled: Bool
    var zoom: Int              // 2/4/8/16
    var options: Set<MagnifierDisplayOption>
}
```

## 步骤

1. 先在 `MagnifierGeometryTests` 写失败用例（含 2× 屏与边缘翻转），锁定换算契约。
2. 实现 `MagnifierGeometry` 纯函数，测试转绿。
3. 实现 `MagnifierOverlayView`（最近邻放大 + 网格 + 坐标 + 倍数标签 + 遮罩）。
4. 接入 `ScreenshotOverlay`，与选区和取色点联动。
5. 新增设置项与截图设置页显示项；默认值按业务规则。
6. 真实 1×/2× 屏截图验证中心像素与取色一致。
7. 运行 `./scripts/verify.sh`，递增版本，提交。

## 已知边界

- 本任务只做「选区过程中」的放大镜；标注阶段的像素级取色沿用 `ColorSampler`，不在本轮改造。
- 不实现 Snipaste 的「放大镜像素缩放倍数」以外的取色格式选项（HEX 大写等），那些归入 Task 014。
- **真实屏幕录制环境下的手工验收尚未执行**：多屏组合、1×/2× 混合缩放下的放大镜中心与 `ColorSampler` 取色一致性，需要在有屏幕录制权限的实机上确认（对应 SHOT-LIFE-005 手工冒烟）。

## 验证记录

- `./scripts/verify.sh`：**374 项单元测试、0 失败**；`git diff --check` 通过。
- 新增用例：`MagnifierGeometryTests` 13 项（逻辑点⇄像素、采样窗口钳制、放大镜框翻转、Quartz 坐标换算）、`MagnifierSampleTests` 2 项、`MagnifierStateTests` 9 项（配置收敛、取样来源契约、取消后不回调、在途请求合并、与捕获裁剪的坐标一致性）。
- 回归：原有截图会话生命周期用例 SHOT-LIFE-001/002/003 保持通过；`docs/test/cases.md` 第 12 节新增 SHOT-LIFE-004（取样生命周期），原手工冒烟顺延为 SHOT-LIFE-005。
- 工程：5 个新文件已加入 `Qingyu.xcodeproj/project.pbxproj`（app target 3 个、test target 2 个）；编译零错误、我新增文件零警告。
- 版本：`0.3.41` → `0.3.42`（构建号 `341` → `342`）；`plutil -lint Qingyu/Info.plist` 通过，`MARKETING_VERSION` 与 `CFBundleShortVersionString` 一致。

### 实施中确认的一处设计偏差

见「业务规则」第 2 条：清羽不冻结屏幕，因此放大镜改为在叠层窗口**下方**按需取样（`CGWindowListCreateImage` + `.optionOnScreenBelowWindow`）。
「放大镜中心点 == 取色采样点 == 最终捕获裁剪点」由 `testMagnifierSamplePointMatchesCaptureCropConvention` 钉住。

### 与既有产品规则的一次冲突（已按规则处理，未放宽测试）

首次实现把开关键命名为 `screenshot.magnifier.enabled`，触发
`SettingsServiceTests.testClipboardIsOnlyFunctionalEnableDisableSetting` 失败 ——
该用例用 `.enabled` 后缀把「功能性开关」限定为**剪贴板与登录启动两项**。
放大镜只是截图功能的显示偏好，不应计为第三个功能开关，因此**改键名为 `screenshot.magnifier.show`**。
