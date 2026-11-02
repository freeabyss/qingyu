# 设计评审：验证手段与已知盲区

这份文档记录清羽（Qingyu）界面评审所用的验证手段，以及**当前环境无法验证**的部分。
目的是让后续维护者知道：哪些结论有真实渲染证据支撑，哪些只是代码层面成立。

## 一、可用的验证手段

### 1. 离屏渲染快照（`QingyuTests/DesignSnapshotTests.swift`）

用 `ImageRenderer` 把真实 SwiftUI 视图渲染成 PNG，断言渲染成功、像素尺寸一致、画面非单色。
覆盖：剪贴板空/加载/行列表/最小宽度、设置 section（常规与大字号）、组件对照、详情空态。

**局限**：AppKit 支撑的控件（TextField / Toggle / ProgressView / List）会被画成黄色占位块。
看到黄色方块不代表界面坏了，只代表「此处不可离屏验证」。

### 2. 真实窗口自绘（`--uitest-capture-png <path>`）

让窗口用 `cacheDisplay(in:to:)` 把自己画成 PNG。走视图自己的绘制路径，
AppKit 控件、滚动内容、侧栏列表都能真实绘制。

配套参数：
- `--uitest-capture-delay <秒>`：截图前等待时长
- `--uitest-capture-window-size`（见 `--uitest-window-size <WxH>`）：改窗口尺寸
- `--uitest-dark-appearance`：强制深色外观（系统级偏好无法伪造，只能进程内设）
- `--uitest-large-text`：把 `JadeFont.scale` 设为 1.35
- `--uitest-search-query <文本>` / `--uitest-search-slow <秒>`：命令栏结果与搜索中状态
- `--uitest-toast <文本>`：在剪贴板窗口里显示一条 toast
- `--uitest-open-pin`：打开贴图窗口
- `--uitest-clipboard-disabled`：强制剪贴板关闭态

**局限**：`cacheDisplay` 会跳过 `PlatformContainer` 里的滚动内容（窗口 PNG 里那块显示为空白）；
钩子会额外把每个滚动文档单独导出为 `<base>-scrollN.png` 绕过。

## 二、当前环境无法验证的部分

| 项目 | 原因 |
| --- | --- |
| 截图会话与贴图工具条 | 需要真实屏幕录制授权（`screencapture` 报 `could not create image from display`） |
| 悬停提示 / hover 底色 / 焦点描边 / 穿透虚线 | 需要真实鼠标与键盘焦点，离屏渲染无法呈现 |
| VoiceOver 实际朗读 | 需要真实辅助功能会话 |
| 系统「增强对比度」渲染 | 系统级偏好，`NSWorkspace` 读数在进程内无法伪造 |

这些项目的相关代码已按规范实现并有单元测试兜底，但**没有视觉证据**。
修改这些区域时，请在有屏幕录制授权与真实指针/辅助功能的环境中重新验证。

## 三、自动化门禁

`./scripts/verify.sh` 依次执行：
1. `git diff --check`（空白错误 / 冲突标记）
2. `Localizable.xcstrings` JSON 合法性
3. **本地化一致性**（`scripts/check-localization.py`）：五语言齐全、en/fr 不得含中文、禁止中英并排
4. 测试文件登记检查
5. 全量单元测试（含设计快照、颜色对比度、字号缩放、相对时间等回归）

已知的一类**不覆盖**：代码层硬编码的用户可见字符串（例如存储层写入的 `summary`）。
资源文件里的文案由第 3 步覆盖，代码里的字面量需要人工审查。

### 3. 已人工核对过的真实渲染（截至第 199 轮）

下列页面/状态已用真实窗口自绘验证过，未发现缺陷：

- 剪贴板窗口：空态、加载态、有内容、选中详情、最小尺寸 860×420、宽屏、深色、
  中文/日文/法文、大字号、剪贴板关闭、toast、长文本、图像条目
- 命令栏：空态、有结果（类型标签 应用/命令/设置）、搜索中、无结果
- 设置：通用/快速启动/剪贴板/截图/关于 五页，浅色+深色+中文+日文+法文+大字号+宽屏+最小尺寸
- 引导页、组件对照图、贴图窗口

**关于副标题的双语对照（不是缺陷）**：命令栏结果里设置项/系统命令的副标题显示英文名，
是 PRD §02-ui-spec 明确要求的「固定显示对应中英文名称」——帮助用户确认该项的命令名。
看到英文副标题不要当作未翻译。
