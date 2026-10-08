# 界面重新设计：渲染证据

使用本轮 Xcode Debug 构建中的生产 SwiftUI 视图，由临时 AppKit 渲染程序离屏输出。剪贴板与命令栏内容是隔离测试数据，不是用户数据。图片按 Retina 比例导出。

| 页面 | 浅色 | 深色 | 检查结果 |
|---|---|---|---|
| 命令栏 | [查看](command-light.png) | [查看](command-dark.png) | 输入、结果层级、类型文字、底部提示可见 |
| 剪贴板 | [查看](clipboard-light.png) | [查看](clipboard-dark.png) | 页签、列表、阅读区、复制与次要动作可见 |
| 欢迎页 | [查看](onboarding-light.png) | [查看](onboarding-dark.png) | 最小尺寸下配置及页脚可见，开关右对齐 |
| 通用设置 | [查看](settings-light.png) | [查看](settings-dark.png) | 仅确认内容区；原生侧栏离屏未呈现 |
| 快速启动设置 | [查看](quick-launch-light.png) | — | 生产插件页独立渲染，使用设置父容器的背景 |
| 关于 | [查看](about-light.png) | — | 版本来自 Bundle，更新入口、反馈区与链接层级清楚；侧栏未呈现 |

[剪贴板最小尺寸](clipboard-minimum-light.png)：720×420pt，复制、置顶、收藏、删除均完整可见。

已通过 `./scripts/verify.sh`：307 项单元测试，0 失败；`git diff --check`、`plutil -lint` 和 Bundle／工程版本一致性检查通过。

局限：桌面自动化服务连续返回超时，未执行实际点击、键盘或拖动窗口验收。隐藏窗口离屏渲染不完整支持 NavigationSplitView 的原生侧栏，且控件可能呈现非激活外观；这些截图不能证明侧栏交互或活动窗口焦点状态已通过人工验收。

## 命令栏：空查询只有输入框

真实窗口截图，非离屏渲染：`screencapture -l <windowID>` 只截命令栏面板本身；实例以隔离数据目录 + `--uitest-skip-shortcuts --uitest-mark-onboarding-completed --uitest-trigger openSearch` 启动，截图后立即结束，应用自身的运行实例不受影响。查询文本用粘贴（⌘V）注入而非键入：`System Events keystroke` 会经过输入法，合成文本不提交到 SwiftUI 绑定（与 `CommandBarUITests.inputSearchText` 同一原因）。

| 状态 | 改动前 | 改动后 |
|---|---|---|
| 空查询 | [查看](command-input-before-empty.png) | [查看](command-input-after-empty.png) |
| 查询 `clipboard` | [查看](command-input-before-query.png) | [查看](command-input-after-query.png) |
| 清空查询后（⌘K） | — | [查看](command-input-cleared.png) |

逐像素细线检测（同尺寸图片的窗口阴影边距一致，可直接比较）：

| 图片 | 细线数量 | 面板几何（`CGWindowListCopyWindowInfo`） |
|---|---|---|
| 改动前 空查询 / 查询 | 2 / 2 | 760×128 / 760×560 |
| 最终 空查询 / 查询 | **0** / 1 | **760×56** / 760×560 |

面板顶边坐标（最终）：空查询 `-1041`、查询 `-1041`、清空后 `-1041`——三次完全一致，即输入文字展示结果时输入框不动，结果列表只在下方展开（改动前为空查询 `-953`、查询 `-1205`，输入框会随结果上移 252pt）。输入行顶边锚点为可见区中心上方 336pt（改动前 248pt），因此输入框同时比原先上移 88pt。

转场稳定性：收起 / 展开动画中途，输入行顶端偏移全程 `19–20pt`——真实 `screencapture -l` 抓帧，0.12s 动画内取到面板高 `528` / [`130`](command-transition-collapse-130pt.png) / [`271`](command-transition-expand-271pt.png) 的中间帧。修复前同样条件（离屏渲染，面板 560pt 高而内容仅 56pt）输入行被 SwiftUI 垂直居中，偏移 `271pt`。修复为根视图填满面板并顶部对齐（`frame(maxHeight: .infinity, alignment: .top)`）。

防抖窗口：粘贴查询后、结果返回前的帧内容区为空白（`contentTextTop = -1`，[查看](command-pending-window-blank.png)），不再出现「未找到匹配项」；结果返回后内容区首行文字位于面板顶边下方 `77pt`。修复前该窗口会显示空结果态，见[展开中间帧](command-transition-expand-271pt.png)。

## 设置页：主题功能移除 / 反馈不再要邮箱

真实窗口截图（`screencapture -l`，隔离实例 + `--uitest-trigger` 直接打开目标页）。窗口未聚焦，控件因此呈系统非激活外观。

| 页面 | 证据 | 要点 |
|---|---|---|
| 通用 | [查看](settings-general-no-theme.png) | 外观区仅「系统／浅色／深色」+「减小动态效果」，主题选择器与色板已移除 |
| 关于 | [查看](settings-about-no-email.png) | 反馈区仅「分类／正文／附加系统信息／发送反馈」，邮箱输入框已移除 |

同目录早先的 `settings-light.png` / `settings-dark.png` 是主题选择器移除前的离屏渲染记录。

## 关键词触发：网页搜索 / AI 对话

| 证据 | 说明 |
|---|---|
| [查看](command-keyword-websearch-row.png) | 真实命令栏：输入 `google qingyu smoke test` → 唯一一条「用 Google 搜索「qingyu smoke test」」且排在首位（回车即执行） |

浏览器端到端（回车后，`System Events` 读取前台窗口标题）：`qingyu smoke test - Google 搜索`。ChatGPT 路径只验证到 URL 构造（`https://chatgpt.com/?q=…`，见 `KeywordLaunchSourceTests`），**未真实打开**——该参数会在用户账号内自动提交提问。

## 关键词跳转目录（45 站点 + 用户定制）

| 证据 | 说明 |
|---|---|
| [查看](command-keyword-websearch-row.png) | `google qingyu smoke test` → 「用 Google 搜索…」排首位 |
| [查看](command-keyword-github-row.png) | 专业搜索：`github swift async` → 「用 GitHub 搜索…」 |
| [查看](command-keyword-doubao-clipboard-row.png) | 不支持预填的站点：结果行写明「打开并复制文字，粘贴发送」 |
| [查看](settings-quick-launch-page.png) | 快速启动设置页；「关键词快捷方式」分区位于下方，需滚动查看 |

真实端到端（回车后）：`github swift async` → 前台窗口标题 `Repository search results`；`豆包 你是谁` → 前台窗口标题 `豆包 - 字节跳动旗下 AI 智能助手`，且 `pbpaste` 内容恰为 `你是谁`（只含提问文字，不含关键词）。

**证据缺口：** 「关键词快捷方式」分区需滚动设置页才能看到，本轮自动化未能滚动该窗口（菜单栏 agent 无法被 System Events 置为最前台，Page Down 与注入滚轮事件均无效）。

证据局限：空查询只保留输入框属行为改动，回归由 `SearchPanelViewModelTests`（空态契约、`$query` 管道用例）与 `./scripts/verify.sh` 覆盖；该轮 `verify.sh` 仅 `ReleaseInfoServiceTests.testProjectHomepageContainsUS020ProductPageMaterialAndScopeGuards` 失败，原因是 `README.md` 被重写后不再包含 `FAQ` / `Mac App Store` 锚点，与本改动无关（本改动未触碰该测试读取的 `README.md`／`PRIVACY.md`／`CHANGELOG.md`／`THIRD_PARTY_NOTICES.md`）。`QingyuUITests/CommandBarUITests` 已尝试执行，但测试运行器在本机无法启用自动化模式（`Timed out while enabling automation mode`，与上文记录的桌面自动化超时属同一环境限制），故未取得 UI 用例结果；命令栏的可访问性标识符（`commandBar.searchField`、`commandBar.resultList`）及既有 UI 用例依赖经代码核对保持不变。

