# Task 010：桌面界面重新设计

**目标：** 按用户最新要求，忽略现有界面风格，从布局、字体层级、配色、控件和信息密度重新设计清羽，形成简洁、专业的 macOS 工具界面。

**范围：** 共享视觉系统、设置及插件设置页、命令栏、剪贴板列表与详情、欢迎界面。保持已有功能与业务行为，不改存储、快捷键或窗口／截图会话生命周期。

**相关模块：** `Views/Design`、`Views/Components`、`Views/Settings`、`Plugins/*/*SettingsPage.swift`、`Views/SearchPanel`、`Views/ClipboardList`、`Views/Onboarding`。

## 视觉决策

用户指定：**极简主义、轻质感、扁平化 + 轻拟物**。以留白和细分隔线组织内容；轻拟物只用于控件边缘高光与微弱接触阴影，不做重卡片、纹理装饰或大面积渐变。

- 主体为黑白灰，冷蓝色只用于主操作、选中、焦点；错误、警告保留语义色。替换旧 Jade 青绿色主题，但保留 Swift token API 名称以兼容已有调用。
- 外观设置提供六个可选主题：默认、石墨、海洋、薰衣草、森林、琥珀；主题只调整强调色与选中态，浅色／深色仍由独立外观模式控制。（主题功能已于第 12 节整体移除。）
- 浅色：白色内容层、浅灰工作区、深色文字；深色：炭黑工作区、稍亮内容层、浅色文字。使用动态颜色，强化对比度时加深边界。
- 设置：200pt 导航区，品牌区与导航分开；单色图标；大标题与说明建立页首层级；内容列限宽，分组标题、设置行、辅助说明各有明确层级。
- 命令栏：开放式大输入区，紧凑结果行，类型以次要文字呈现；真实应用图标保留；仅选中行显示执行提示，底部保留必要键盘提示。
- 剪贴板：工具栏含标题与搜索，类型用轻量页签；左侧为有节奏的内容列表，右侧为阅读区；复制为明确文字主按钮，其他操作为辅助图标。
- 控件统一为较小圆角、精确对齐、细边界、克制阴影；避免多重背景嵌套、过多徽章和装饰色块。
- 欢迎界面沿用同一套字体与表面体系，减少宣传式大图标与背景装饰。

## 业务规则与技术约束

- 保留当前工作区的 Qingyu 重命名、插件开关、搜索行为、剪贴板双栏详情及所有动作。
- 保留 accessibility identifier、本地化、Bundle 版本读取与键盘交互。允许新增明确必要的本地化文案。
- 不增加依赖、不修改工程结构、不改版本、不提交用户已有工作。
- 不更改截图/贴图生命周期；已有功能差异记录保留，不将视觉任务扩大为业务重写。

## 修改清单与执行计划

用户要求先写清修改，再按计划执行。以下清单固定本轮范围；前三步已有实现草稿，必须经过第四、五步验收，不能仅凭代码完成判定交付。

### 01 — 统一视觉基础

**目标：** 极简、轻质感、扁平化 + 轻拟物成为全应用统一语言。

**文件：** `JadeColor.swift`、`JadeFont.swift`、`JadeRadius.swift`、`JadeShadow.swift`、`JadeButton.swift`、`JadeTextField.swift`。

**要做的修改：**
- 青绿色替换为低饱和蓝灰，设置中性内容面／工作区／悬停面三层。
- 白字主按钮采用独立深色填充，次要按钮用中性文字；仅按钮保留轻微顶部高光和接触阴影。
- 圆角统一为 6、8、10、12、16pt，减轻浮窗投影；正文用系统语义字体，标题与搜索输入控制字号。
- 焦点边线、选中底色、风险图标继续可辨识。

**验收：** 深浅色下按钮和文本清晰，普通分组没有重投影，交互状态未丢失。

**状态：** 已实现并完成深浅色离屏审查；主题选择随后续集成验证一起检查。

### 02 — 重做设置与欢迎页

**目标：** 页面层级清楚，配置内容易扫描，缩小窗口也不拥挤。

**文件：** `SettingsView.swift`、`JadeSettingsComponents.swift`、三个插件的 `SettingsPage.swift`、`OnboardingView.swift`。

**要做的修改：**
- 设置导航增加独立品牌区，移除彩色图标块；页首用标题与一句说明。
- 通用、快速启动、剪贴板、截图采用统一内容宽度和分组布局。
- 调整语言、权限、黑名单多字段表单的排列，避免控件横向挤压。
- 关于页突出应用名称与动态版本，反馈独立成组。
- 欢迎页改成紧凑左对齐页首，配置合并为平整行组，权限说明使用细分隔；保留固定页脚与中间滚动。

**业务约束：** 不更改页面可见性、FeatureGate、设置绑定、权限申请、数据管理或向导完成规则。

**验收：** 设置 `920×640`、欢迎页 `720×520` 可读，必要操作保留，版本来自 Bundle。

**状态：** 已实现；内容区与欢迎页最小尺寸已离屏审查，原生侧栏实机验收待补。

### 03 — 重做命令栏与剪贴板

**目标：** 内容是视觉中心，搜索与复制路径清楚。

**文件：** `CommandBarView.swift`、`ClipboardHistoryView.swift`、`JadeClipboardRow.swift`、`ClipboardDetailPane.swift`。

**要做的修改：**
- 命令栏去掉框中框输入样式，使用开放式输入；结果行 52pt，标题／说明／类型分层。
- 去掉彩色类型徽章和分区装饰，仅选中行显示回车提示，保留真实应用图标与风险提示。
- 剪贴板顶部采用标题＋搜索工具栏，类型筛选采用下划线页签；左侧记录列表，右侧阅读区。
- 普通文本用系统正文，减少预览背景套层；复制改为文字主按钮，次要动作保留图标与悬停说明。

**业务约束：** 保留搜索、复制、删除、置顶、收藏、快捷键和详情加载；不改窗口尺寸控制及生命周期。

**验收：** 剪贴板 `720×420` 与默认尺寸都能显示复制及次要操作，长文本和文件路径不会推挤布局。

**状态：** 已实现并完成深浅色离屏审查。

### 04 — 集成审查与修正

**目标：** 确认实际渲染结果符合上述设计，而不只检查源码。

**执行顺序：**
1. 检查前三步差异，清理不完整修改、错误 token、重复背景、布局缩进和过时注释。
2. 使用临时隔离数据渲染生产 SwiftUI 视图：设置、命令栏、剪贴板的深浅色；补充关于、欢迎页与最小尺寸检查。
3. 根据渲染修复遮挡、截断、对齐或对比度问题。
4. 保留渲染图及检查记录；桌面交互服务若仍超时，明确不能以离屏图替代真实鼠标／键盘验收。

**状态：** 集成与离屏审查已完成；真实桌面交互验收受工具超时阻塞。

### 05 — 验证与交付

**目标：** 功能回归与项目规范通过，文档能够支持后续独立维护。

**执行顺序：**
1. 最终修改后运行 `./scripts/verify.sh`，确认全量单元测试与 `git diff --check` 通过。
2. 校验 `Info.plist` 格式及工程版本一致性；本轮不提交，因此不递增版本。
3. 同步 UI 规范、架构中的视觉 token 说明和任务索引，记录测试数、渲染证据与未验证项。
4. 交付修改摘要、可查看截图及验证结果。

**状态：** 最终全量验证通过，渲染证据与已知限制已记录；未提交。

### 06 — 侧栏不暴露隐藏功能

**目标：** 设置左侧选项卡只呈现当前已开放的设置页；隐藏功能不能通过侧栏或深链接进入。

**要做的修改：**
- 设置页列表统一经过 FeatureGate 过滤，不再直接展示注册表中已隐藏功能的贡献页。
- 插件设置元数据与详情视图复用同一可见页面集合，避免列表和内容入口不一致。
- 隐藏功能对应的设置路由保持当前页面，不改变用户正在查看的设置内容。

**验收：** 截图功能关闭时，侧栏仅显示通用、快速启动、剪贴板、关于；截图页不能通过路由打开；主题选择曾位于“通用”页、不新增左侧选项卡（该选择器已于第 12 节移除）。

**状态：** 已实现；`SettingsNavigationTests` 已覆盖侧栏与隐藏路由回归。

### 07 — 命令栏输入区简化为裸输入框

**目标：** 命令栏输入区不再是“框中框 + 独立分隔线”，而是一个裸输入框；结果区保持不变。

**文件：** `CommandBarView.swift`。

**要做的修改：**
- 删除输入区与结果区之间的独立 `Divider`，消除聚焦线与分隔线叠加而成的双线。
- 输入区只保留一条细线：静止 1pt 描边兼作分隔，聚焦加厚为 2pt 强调色，继续满足“焦点通过边线厚度反馈”。
- 输入行高度 72 → 56pt；左右内边距 `x4` → `x3`，使输入文字与结果行图标左缘对齐。

**业务约束：** 保留结果区、占位文字、清除动作、打开即聚焦、Esc／回车行为，以及 760×128（收起）／760×560（展开）窗口尺寸；不改 Controller 的尺寸控制与生命周期。

**验收：** 真实面板截图（同一路径、同一方法）对比：细线数量由 2 条降为 1 条，输入带高度减少 16pt，窗口几何不变。

**状态：** 已实现并完成真实面板截图验证；`./scripts/verify.sh` 310 项单元测试 0 失败通过。

### 08 — 空查询命令栏只保留输入框

**目标：** 命令栏空查询时不再渲染任何内容区（原「最近使用 / 收藏」首页与初始空态占位一并移除），面板高度回落到输入行高度。

**文件：** `Views/SearchPanel/CommandBarView.swift`、`ViewModels/SearchPanelViewModel.swift`、`App/Controllers/CommandBarController.swift`、`App/Controllers/AppContainer.swift`；删除 `Services/SearchEngine/CommandBarHomeProvider.swift`。

**要做的修改：**
- 视图：空查询不渲染 `content`；输入区与结果区之间的细线只在有关键词时绘制。
- ViewModel：移除 `recentResults` / `favoriteResults` / `homeProvider` / `loadHomeContent` / `hasHomeContent` / `homeSectionLimit` 与 `shouldExpandPanel`；「有无查询」统一由 `isQueryPresent(_:)` 一处实现。
- 控制器：新增共用几何契约 `CommandBarMetrics`（宽 760、输入行 56、结果区 560），空查询面板高度即输入行高度；尺寸只订阅 `$query` 的流值——`@Published` 在 willSet 发值，回调里重读属性会拿到旧查询，面板将永不展开。
- 装配：`AppContainer` 不再构造 `CommandBarHomeProvider`；同步移除工程文件中的对应条目与测试里的 home 用例。

**业务约束：** 结果区、占位文字、清除动作、打开即聚焦、Esc / 回车与危险命令确认保持不变；输入框在屏幕上的位置与改动前一致（`CommandBarMetrics.inputOnlyTopOffset`）。

**验收：** 真实面板截图（同一路径、同一方法）：空查询 `760×56`、有查询 `760×560`，两者顶边分别为 `-953` / `-1205`，即输入框停在原位置、只移除了它下方的区域。

**状态：** 已实现并完成真实面板截图验证。`./scripts/verify.sh`：308 项中仅 `ReleaseInfoServiceTests.testProjectHomepageContainsUS020ProductPageMaterialAndScopeGuards` 失败（`README.md` 被重写后不再包含 `FAQ` / `Mac App Store` 锚点，与本改动无关，本改动未触碰该测试读取的四个文档）。

### 09 — 命令栏输入框位置固定并上移

**目标：** 命令栏输入框的出现位置比原锚点上移，且输入文字展示结果时输入框不再移动，结果列表只在其下方展开。

**文件：** `Views/SearchPanel/CommandBarView.swift`、`App/Controllers/CommandBarController.swift`。

**要做的修改：**
- 把 `CommandBarController` 中内联的窗口定位数学提取为可测纯函数 `CommandBarMetrics.panelOriginY(visibleFrame:panelHeight:)`（提取阶段行为完全不变）。
- 输入行顶边改为收起 / 展开共用的锚点 `inputRowTopOffset`（336pt，原为 248pt），面板只向下生长。
- 可见区装不下时整体收拢进可见区（8pt 边距），避免小屏越界。

**业务约束：** 面板宽度、输入行高度、结果区高度、搜索结果与键盘行为保持不变。

**验收：** 真实面板几何（`CGWindowListCopyWindowInfo`）：空查询 / 有查询 / 清空后三次 `top` 均为 `-1041`（完全一致），`bottom` 分别为 `-985` / `-481` / `-985`，即输入框不动、列表只向下展开；相比改动前 `top = -953`，输入框上移 88pt。单元测试 `testPanelInputRowStaysAnchoredWhenResultsAppear` 先在旧锚点下失败（`968.0` ≠ `1220.0`）再通过。

**状态：** 已实现并完成真实面板几何验证。

### 10 — 命令栏转场时输入框不再闪动

**问题：** 输入文字展示结果、删除文字隐藏结果时，输入框会闪一下。

**根因：** 根视图只有内容高度（空查询时 56pt）。收起 / 展开动画中途面板高度在 56–560pt 之间，此时 SwiftUI 会把不足容器高度的根视图**垂直居中**，输入框先滑向面板中间再弹回；面板表面也只覆盖一小块。

**文件：** `Views/SearchPanel/CommandBarView.swift`。

**要做的修改：** 根视图填满面板并把内容钉在顶部（`frame(maxHeight: .infinity, alignment: .top)`），使输入行与面板表面在整个转场过程中稳定。

**验收：** 离屏渲染（760×56 / 760×280 / 760×560）输入行顶端偏移均 < 60pt（修复前 560pt 高时为 271pt）；真实转场帧（`screencapture -l`，0.12s 动画内抓到面板高 528 / 130 / 271pt 的中间帧）输入行偏移全程 19–20pt。

**状态：** 已实现，完成离屏渲染与真实转场双重验证。

**已知观察（已由第 11 节修复）：** 输入首个字符后的 180ms 防抖窗口内曾短暂显示「未找到匹配项」。

### 11 — 防抖窗口内不再闪「未找到匹配项」

**问题：** 输入首个字符后、结果返回前（180ms 防抖窗口）会短暂显示「未找到匹配项」；已有空结果时继续追加字符会再闪一次。

**根因：** 空结果态只看「查询非空 + 结果为空 + 不在搜索中」，没有判断结果是否已对应当前查询——查询刚变化时 `results` 仍是上一个查询的结果集。

**文件：** `ViewModels/SearchPanelViewModel.swift`、`Views/SearchPanel/CommandBarView.swift`。

**要做的修改：**
- 结果集记录它回答的查询 `resultsQuery`；抽出 `trimmedQuery`；`clearResults()` 一并清空。
- 空结果态判断抽出为 `shouldShowNoResults`：`hasQuery && visibleResults.isEmpty && !isLoading && resultsQuery == trimmedQuery`，视图改用它。

**验收：** `testNoResultsStateIsSuppressedWhileResultsArePending` 与 `testNoResultsStateStaysHiddenWhileNextQueryIsPending` 先在旧判断下失败、修复后通过；真实抓帧：粘贴「设置」后面板已展开（560）但结果未返回的帧内容区为空白（`contentTextTop = -1`），结果返回后正常显示（`77`）。

**状态：** 已实现，完成单元测试与真实抓帧验证。

### 12 — 移除主题功能与反馈邮箱输入

**目标：** 去掉可切换的主题功能（含玻璃材质窗口）与反馈表单里的邮箱输入。

**文件：** `Models/AppSetting.swift`、`Database/PersistenceController.swift`、`ViewModels/SettingsViewModel.swift`、`Views/Settings/SettingsView.swift`、`Views/SearchPanel/CommandBarView.swift`、`Views/ClipboardList/ClipboardHistoryView.swift`、`Views/Design/JadeColor.swift`、`Views/Design/JadeMaterial.swift`；`QingyuTests/SettingsServiceTests.swift`。

**要做的修改：**
- 删除 `ThemeChoice`、`theme.choice` 设置项与其默认值播种、ViewModel 状态与持久化、通用页主题选择器；两个浮动窗口不再读取主题；`JadeColor.accent(for:)` 与 `JadeMaterial.windowGlass` 一并删除，`jadeWindowSurface` 只保留实心面。
- 窗口强调色统一为品牌主色（`JadeColor.primary`，即原默认主题的强调色）；浅色／深色外观设置保持独立、不受影响。
- 反馈表单删除邮箱输入框与「邮箱」正文前缀，正文只含用户描述。

**业务约束：** 外观（跟随系统／浅色／深色）、语言、权限、数据及其他设置不变；反馈仍以 `mailto:` 打开用户邮件应用，收件人不变。

**验收：** `testThemeSettingIsGone` 先在 `theme.choice` 存在时失败、移除后通过；`testAppearanceModePersistsAndResets` 钉住存活的外观设置契约；真实界面截图：通用页外观区已无主题选择器（`settings-general-no-theme.png`）、关于页反馈区已无邮箱输入（`settings-about-no-email.png`）；`./scripts/verify.sh` 315 项 0 失败。

**状态：** 已实现并完成真实界面截图验证。

**遗留：** `management.theme.*`（16 个）与 `management.feedback.email*`（2 个）本地化键已无引用；`Views/Design/VisualEffectView.swift` 随玻璃主题失去唯一调用方，属未跟踪文件，保留未删。

### 13 — 关键词触发：网页搜索与 AI 对话

**目标：** 输入 `<关键词> <文字>`（如 `google 天气`、`chatgpt 帮我写个正则`）后，用默认浏览器打开对应网页并把文字作为查询词/提问传入。

**文件：** 新增 `Services/SearchEngine/KeywordLaunchSource.swift` 与 `QingyuTests/KeywordLaunchSourceTests.swift`；`Services/SearchEngine/SearchCore.swift`（新增 `SearchAction.openURL`、来源优先级、关键词结果排序规则）、`Services/SearchEngine/InMemorySearchIndex.swift`（新增来源 ID）、`ViewModels/SearchPanelViewModel.swift`（面板执行器与复制动作）、`Plugins/QuickLaunch/QuickLaunchPlugin.swift`（注册两个来源）；`QingyuTests/QuickLaunchPluginTests.swift`。

**要做的修改：**
- 新增 `.openURL(URL)` 动作，由默认浏览器打开；命令栏执行器与复制动作一并支持。
- 新增两个关键词来源（`.webSearch` / `.aiChat`），表项为纯数据（关键词、站点、标题前缀、URL 模板、类型与图标），新增站点只追加一条。
- 触发条件严格：关键词完整命中且其后必须有非空文字；`google`（无文字）仍走普通搜索。
- 排序：关键词触发结果必须排在「应用名命中」之前，否则 `google 天气` 会被 Google Chrome 抢走回车。
- 插件清单由五类来源变为七类，`QuickLaunchPluginTests` 断言同步更新。

**业务约束：** 其余来源、排序规则、快捷键与窗口行为不变；不新增设置项（关键词表为编译期常量）。

**验收：** `KeywordLaunchSourceTests` 7 项覆盖 URL 构造、大小写与中文别名、缺文字不触发、未登记关键词不触发、特殊字符编码与排序守卫（该守卫先在旧排序下失败：`google 天气` 首条为 `app`，修复后为 `webSearch`）；真实界面：命令栏 `google qingyu smoke test` 只显示一条「用 Google 搜索「qingyu smoke test」」且排在首位，回车后前台窗口标题为 `qingyu smoke test - Google 搜索`；`./scripts/verify.sh` 322 项 0 失败。

**状态：** 已实现并完成单元测试与真实浏览器端到端验证。

**待补：** 其余站点由用户提供清单后追加；每个站点需先核实其 URL 预填参数（ChatGPT 的 `?q=` 已核实：打开即预填并提交）。

### 14 — 关键词跳转目录 + 用户可改关键词 / 自定义条目

**目标：** 把关键词跳转从两条示例扩成完整站点目录，并让用户能改关键词、加自定义条目。

**文件：** `Services/SearchEngine/KeywordLaunchSource.swift`（目录 + 定制 + 解析 + 来源）、`Services/SearchEngine/SearchCore.swift`（新增 `.openURLWithClipboard`）、`Models/AppSetting.swift` 与 `Database/PersistenceController.swift`（新增 JSON 设置项与默认值）、`ViewModels/SettingsViewModel.swift`、`Plugins/QuickLaunch/QuickLaunchSettingsPage.swift`（编辑界面）、`App/AppDelegate.swift` + `App/UITestSupport.swift`（新增 `openQuickLaunch` 调试触发）；`QingyuTests/KeywordLaunchSourceTests.swift`。

**要做的修改：**
- 内置目录 45 条，分四组：Web Search（11）、专业搜索（13）、AI Search（7）、AI Chat（14）。同一关键词只能指向一个网址，因此跨组重复的站点（Brave Search / Kagi / ChatGPT / Gemini / Grok）只收录一次。
- 预填分两种：有纯链接生成器佐证的站点走 URL 预填；只有浏览器用户脚本代填的站点（DeepSeek / Kimi / Qwen / 豆包 / 元宝 / 智谱 / MiniMax / 通义 / Poe / Character.AI / Meta AI / Pi）打开站点并把文字放进剪贴板，结果行写明「打开并复制文字，粘贴发送」。
- 用户定制存为 JSON 设置项 `search.keywordLaunch`：`keywordOverrides`（条目 id → 关键词，留空即停用）与 `customEntries`（自定义条目，含 URL 模板与预填开关）。
- 解析规则：关键词按目录顺序先到先得，冲突者失去该关键词；URL 模板缺 `{query}` 的条目丢弃；设置页实时提示冲突。
- 设置页新增「关键词快捷方式」分区：按四个分组折叠展示内置条目并可编辑关键词，下方可增删自定义条目。

**业务约束：** 关键词触发结果仍排在应用名命中之前；其余来源与快捷键不变。

**验收：** `KeywordLaunchSourceTests` 17 项覆盖目录完整性、站点覆盖、URL 构造、大小写与中文别名、缺文字/未登记关键词不触发、特殊字符编码、剪贴板回退模式、关键词覆盖与停用、自定义项追加与丢弃、关键词冲突裁决、以及排序守卫；真实界面：`github swift async` 回车后前台窗口为 GitHub 搜索结果页，`豆包 你是谁` 回车后前台窗口为豆包且剪贴板内容恰为 `你是谁`；`./scripts/verify.sh` 332 项 0 失败。

**状态：** 已实现并完成单元测试与真实端到端验证。

**证据缺口：** 「关键词快捷方式」分区在设置页需滚动才能看到，本轮自动化未能滚动该窗口（该应用是菜单栏 agent，System Events 无法将其置为最前台，Page Down 与注入滚轮事件均无效），因此只有快速启动页顶部截图；分区本身已随页面渲染。

## 验收标准

- 三个主要窗口有完整一致的新视觉语言，整体布局可辨识地更新。
- 浅色和深色均清晰；最小尺寸主要操作可见；长内容可滚动或截断；复制、搜索、筛选、导航等行为保留。
- 图标按钮有辅助功能名称，主操作与危险操作易辨识，焦点与选中不只依赖色相。
- `./scripts/verify.sh` 全量单元测试及 `git diff --check` 通过。
- 通过实际 SwiftUI 渲染检查代表性页面；如桌面交互服务不可用，明确记录离屏渲染与人工交互验证的区别。

## 已知边界

- 当前剪贴板已经为列表／详情双栏，与旧 UI 规范单列描述不同；本任务保留双栏并同步展示规范。
- Task 004 已记录的语言与数据管理业务差异不在本任务处理。

## 验证记录

- 最终执行 `./scripts/verify.sh`：307 项单元测试、0 失败；`git diff --check` 通过。
- `plutil -lint Qingyu/Info.plist` 通过；Bundle 与工程版本／构建号一致，本轮未修改版本。
- [渲染证据与逐页记录](../test/artifacts/interface-redesign/README.md)：生产 SwiftUI 视图、隔离测试数据、浅色／深色、欢迎页最小尺寸与剪贴板最小尺寸。
- 渲染中发现并修复：内部内容被重复投影、深色辅助文字过暗、欢迎页开关未右对齐、关于页版本重复展示。
- 桌面自动化服务连续超时；原生设置侧栏在离屏输出中缺失，真实点击／键盘与侧栏显示仍待实机确认。
- 用户已有重命名、功能修改与未跟踪详情面板均保留；本轮没有提交、清理或重置工作区。
- 命令栏输入区简化（07）为纯视觉改动，无可断言的单元测试面，因此以真实窗口截图（`screencapture -l <windowID>`）与逐像素细线检测作为验收证据；回归由 `./scripts/verify.sh` 全量单元测试及 `SearchPanelViewModelTests` 的 `shouldExpandPanel` 面板展开契约覆盖。证据见[渲染证据](../test/artifacts/interface-redesign/README.md)「命令栏输入区简化」一节。
