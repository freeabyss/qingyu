# Snipaste 截图 / 贴图 能力参考

> 外部产品对标资料。用于清羽 Qingyu「截图」与「贴图」两个功能的能力补强参考。
> 生成方式：对 Snipaste 2.11.3 (macOS, `com.Snipaste`) 的**本地已安装产物**做静态分析（Ghidra + 符号/字符串/配置键提取），
> 并从其自带的 25 个语言包（`.qm`）中提取出完整的中英双语界面文案。
> 本文只记录**功能与交互设计**，不涉及任何代码或素材的复制。

## 1. 资料来源与可信度

| 来源 | 能得到什么 | 可信度 |
|---|---|---|
| 语言包 `.qm`（本机提取） | 完整界面文案（中文 1372 条 + 英文源文案 968 条） | 实测 |
| 配置键（二进制字符串） | 107 个设置项名称 | 实测 |
| 类名元对象（导出符号） | 114 个模块/类名 | 实测 |
| 反编译 | 具体算法 | 仅少量完成 |
| 本文第 3、4 节的「交互行为」 | 由文案与配置键**推断** | 推断 |

---

## 2. 截图（Snip）

### 2.1 触发方式

| 方式 | 证据 |
|---|---|
| 全局热键 | `Hotkey/all`, `Hotkey/enable`, `Snip hotkey` |
| 托盘图标左/中/右键 | `Control/tray_left_click` / `tray_middle_click` / `tray_right_click` |
| **屏幕四角热区** | `Control/enable_hot_corner` + `hot_corner_{top_left,top_right,bottom_left,bottom_right}_command` + `hot_corner_size` |
| 命令行 | `-o silent`、`--delay TIME`、`--active-screen` |

> 热区（把鼠标推到屏幕某个角就触发）是 Snipaste 很有辨识度的一点，Qingyu 目前没有。

### 2.2 选区与自动识别

| 能力 | 证据 |
|---|---|
| 自由框选 | `Interface/free_select`, `Free select` |
| **自动检测窗口/界面元素** | `Snip/detect_windows`, `Auto detect the regions of windows when snipping.` |
| 检测界面**控件**（需辅助功能权限） | `Snip/detect_ui_elements`, `Window element detection` |
| 吸附/锚点阈值 | `Snip/anchors_threshold`（`Specify the distance threshold for edge attachment`） |
| 忽略特定程序（另用一套算法） | `Enter bundle names/paths separated by commas (e.g. snipaste.app, games/*)` |
| 检测时的过渡动画 | `Snip/animated_region_transition` |
| **预设区域 / 预设尺寸** | `Snip/preset_regions`, `Snip/preset_sizes`, `Edit preset sizes/regions`, `Edit presets...` |
| 复用上次选区 | `Reuse the last snipping areas` |

### 2.3 放大镜（Magnifier）— 细节最丰富的一块

| 能力 | 证据 |
|---|---|
| 磁贴像素缩放倍数 | `Interface/magnifier_pixel_scale`, `Physical pixel (px)` |
| 显示坐标 | `Interface/show_coordinate`, `Screen coordinate` |
| 显示网格线 | `Interface/show_magnifier_grid_lines` |
| 显示提示 | `Interface/show_magnifier_tips` |
| 放大镜内显示遮罩 | `Show the mask in the magnifier.` |
| 在放大镜中显示的内容可勾选 | `In the magnifier, show:` |
| 可强制唤起 | `Show the magnifier if it is not visible` |
| 尺寸按钮 | `Magnify` / 类 `MagnifyPaintItem` / `PixelUnitButton` |

### 2.4 视觉与输出

| 能力 | 证据 |
|---|---|
| 选区圆角 | `Snip/corner_radius`, `Corner radius` |
| 边框宽度/颜色 | `Output/border_width`, `Output/border_color`（`Set the width of the border around the snipping area.`） |
| 阴影宽度/颜色 | `Output/shadow_width`, `Output/shadow_color` |
| 光标是否入镜 | `Snip/never_capture_cursor`, `Check this if you never need cursor capture. You will gain better response time on entering snipping.` |
| 色彩空间 / HDR | `Interface/color_space`, `Adjust colors for screenshots taken on HDR monitors` |
| 取色值格式 | `Interface/color_values`（RGB/HSV/HSL/HSI/HEX）、`Interface/uppercase_hex`（HEX 颜色值大写）、`Interface/copy_without_sharp` |
| 自动去除 alpha 通道 | `Output/auto_alpha_channel_removal` |
| 图片质量 / 文件名模板 / 记住扩展名 | `Output/image_quality`, `Output/file_name_pattern`, `Output/remember_image_extension` |
| 自动保存路径 / 快速保存路径 | `Output/auto_save_path`, `Output/quick_save_path` |
| 元数据写入 | `Misc/software_metadata` |
| 主题色 / 字体 | `Interface/theme_color`, `Interface/font`, `Snipaste 的主题色`, `Snipaste 的界面语言` |

### 2.5 截图历史与白板

| 能力 | 证据 |
|---|---|
| **截图历史（可回放）** | `Replay snipping history`, `A successful screenshot will be recorded (and can be reviewed)`, `Internal/history_dir` |
| 历史最大条数 | `Set the max number of history records for snipping, which are stored in history/snip.` |
| **内置白板模式** | `Enter whiteboard mode`, `transparent-whiteboard`（透明背景白板）, `--color [COLOR]`, `--active-screen` |

> 「截图历史 + 回放」和「白板模式」是两个 Qingyu 完全没有、但差异化价值很高的能力。

### 2.6 键鼠交互细节

| 能力 | 证据 |
|---|---|
| 方向键移动选区 1 像素 | `Move the snipping area by 1 pixel` |
| Esc 退出截图 | `Quit snipping (Esc)` |
| Enter 的动作可配置 | `Which action to perform for pressing 'Enter' when snipping.` |
| 双击的动作可配置 | `Which action to perform for double-click when snipping.` |
| 中键的动作可配置 | `Which action to perform for middle-click when snipping.` |
| Tab 临时切换辅助线 | `Show/Hide the auxiliary lines if snipping`, `You can also temporarily toggle it by pressing the Tab key when snipping.` |
| 收缩选区 1 像素 | `Shrink the snipping area by 1 pixel` |
| 声音 | `Snip/clipboard_sound`, `Interface/sound_file`, `snip.wav` / `bubble.wav` |
| 失去焦点自动退出 | `Snip/abort_on_focus_out`, `Quit snipping if any window of other programs is activated.` |
| Ctrl+C 最小间隔 | `Snip/ctrl_c_min_interval`（防抖） |
| 忽略模拟的复制命令 | `Snip/ignore_simulated_copy_command` |
| 文件对话框时隐藏 | `Snip/hidden_on_file_dialog` |

---

## 3. 标注（Annotate）

Snipaste 标注工具共 **12 种**（类名证据 + 文案）：

| 工具 | 类 | Qingyu 是否已有 |
|---|---|---|
| 铅笔（自由手绘） | `PencilPaintItem` | ❌ |
| 箭头 | `ArrowPaintItem` | ✅ |
| 直线 | `LinePaintItem` | ✅ |
| 折线 | `LinestripPaintItem` | ✅（polyline） |
| 矩形 / 椭圆 | `RectEllipsePaintItem` | ✅（仅矩形） |
| 荧光笔（半透明高亮） | `HightlightPaintItem` | ❌ |
| 马赛克 | `MosaicPaintItem` | ✅ |
| **高斯模糊** | `vBlur` / `hBlur` / `BlurInfo` | ❌ |
| 橡皮擦 | `EraserPaintItem` | ❌ |
| 文字 | `TextPaintItem` | ✅ |
| **序号（数字标记）** | `NumberPaintItem` / `NumberCounter` | ❌ |
| **提示框** | `TooltipItem` | ❌ |

### 3.1 标注交互细节

| 能力 | 证据 |
|---|---|
| **马赛克 / 高斯模糊同一个按钮切换** | `Click this icon to toggle between mosaic and Gaussian blur.` |
| 笔宽调整（滚轮 / `1` `2` / `[` `]`） | `To change the pen width, please scroll the mouse wheel or press '1' or '2' or press '[' or ']'.` |
| 最大笔数 | `Interface/max_pens` |
| 撤销 / 重做 | `Undo (Ctrl+Z)` / `Remove all edits (cannot be undone)` |
| **平滑鼠标路径** | 类 `SmoothMousePath` |
| **长宽比锁定** | 类 `LockAspectRatioButton`、`GeometryGuard` |
| 新标注自动选中 | `Annotate/auto_select_on_creation` |
| 按住修饰键即时更新 | `Annotate/instant_update_on_keyboard_modifier` |
| 橡皮擦重编辑 | `Interface/reedit_eraser` |
| 不同形状用不同颜色 | `Interface/separate_colors_for_shapes` |
| 调色板 | `Interface/palette`、`ColorBoard` |
| 悬停选中任意类型标注 | `Enable selecting any types of drawn annotations on hovering. If unchecked, only the active type of annotations can be selected...` |
| 退出标注 | `Quit annotating` |
| 默认标注工具 | `Default annotation:` |

---

## 4. 贴图（Paster）

### 4.1 窗口行为

| 能力 | 证据 |
|---|---|
| 钉在屏幕上（置顶浮窗） | `Pin the screenshot to the screen as a floating window`, `Pin to screen` |
| **磁性吸附**（贴到窗口/屏幕边缘） | `Paste/magnetic_attach_threshold`, `Specify the distance threshold for edge attachment for image windows, in pixels` |
| **不透明度可调** | `Opacity`、`Hotkey2/key_for_opacity` |
| **鼠标点击穿透** | `Mouse click-through`、`Hotkey2/...`、`The shortcut to toggle the click-through mode of the image under the cursor.` |
| **缩放热键** | `Hotkey2/key_for_zoom` |
| 全虚拟桌面置顶 | `Pin on all virtual desktops` |
| 禁止边框缩放 | `Paste/disable_frame_resize` |
| 最大窗口尺寸 | `Paste/max_window_size` |
| 激活时置前 | `Paste/activate_on_pasted` |
| 关闭/恢复最近关闭 | `A closed image window can be recovered by another pasting if the number of closed images d...`（restore 容量） |
| 双击 / Double-tap X 关闭 | `The 'Double-tap X' action has been cancelled.` |
| 隐藏全部 / 显示全部 | `Hide all images` |
| 组切换后闪烁提示 | `Flash the image windows after you have switched to another image group.`、`Let the border of a new image window flash.` |
| 新窗口阴影 | `Let new image windows have shadows. You can also find this option in the context menu of individual image window...` |

### 4.2 内容类型与转换

| 能力 | 证据 |
|---|---|
| 图片 / 文本 / 富文本 / 颜色 都能贴 | `PinPayload` 对应 `Text2Image`、`Paste/text_*` |
| **文件路径 → 转成图片贴出** | `If you paste again, the file path will be converted into an image and be pasted` |
| 拖拽网页图片到贴图窗口自动下载 | `Misc/auto_download_max_image_size_mb`、`Misc/allowed_url_schemes` |
| 文字贴图排版 | `Paste/text_font` / `text_color` / `text_backgroud_color` / `text_margin` / `max_text_line_width` / `force_html_wrap` |
| 多选含活动窗口 | `Paste/include_active_window_for_multiselection` |
| 文件对话框时隐藏 | `Paste/hidden_on_file_dialog` |

### 4.3 图像组（Image Groups）

| 能力 | 证据 |
|---|---|
| 图像组管理窗口 | `Manage Groups`、`Manage groups`、`show-group-manager`、类 `GroupManagerDialog` |
| 切换组 | `Switch to another image group`、`switch-group-prev`、`Image groups:` |
| 移动到组 / 清空组 / 导出组 | `Move to group`、`Empty the current image group`、`Export image group(s)` |
| 新建 / 重命名 / 删除空组 | `New group name:`、`Group name:`、`Remove empty groups` |
| 组切换确认 | `Are you sure you want to close selected group(s)? This action cannot be undone.` |

---

## 5. 与 Qingyu 现状的差距

### 5.1 Qingyu 已具备

- 触发：全局热键、菜单栏；三种来源（区域 / 窗口 / 全屏）
- 预览工具条：复制 / 保存 / 另存为 / 贴图 / 标注 / 取消
- 标注：矩形、箭头、直线、折线、文字、马赛克（6 种）
- 贴图：置顶浮窗、级联定位、鼠标事件切换、恢复最近关闭、隐藏/显示全部、右键菜单
- 设置：保存目录、格式（仅 PNG）、复制到剪贴板、音效、含阴影、路径转图片、恢复容量、鼠标事件热键
- 快捷键提示视图

### 5.2 差距清单（按建议优先级）

#### P0 — 与 Snipaste 差距最大、对截图体验影响最直接

| 项 | Snipaste 做法 | Qingyu 现状 | 价值 |
|---|---|---|---|
| **放大镜** | 像素级放大 + 坐标 + 网格线 + 遮罩 | 无（仅有 `ColorSampler` 取色） | 精确选区必备 |
| **窗口/界面元素自动识别** | 悬停即高亮窗口与控件，多点吸附 | 有 `WindowCandidateProvider`，但无控件级与吸附阈值 | 大幅提升选区效率 |
| **截图历史 + 回放** | 成功截图自动入库，可回看 | 无 | ⚠️ **与既有产品决策冲突**：Task 007 已确认「移除截图历史，仅保留打开保存文件夹」。若要引入需先改 PRD，不能直接当差距补 |
| **白板模式** | 透明背景白板，可指定颜色/屏幕 | 无 | 差异化能力强 |
| **预设区域 / 预设尺寸** | 可编辑的常用选区 | 无 | 高频提效 |

#### P1 — 体验打磨，成本可控

| 项 | 说明 |
|---|---|
| 选区圆角 / 边框色宽 / 阴影色宽 可调 | Qingyu 目前仅「含阴影」开关 |
| 标注：高斯模糊 | 与马赛克同键切换 |
| 标注：序号 / 提示框 / 荧光笔 / 橡皮擦 / 铅笔 | 补齐后 6 → 11 种 |
| 笔宽快捷调整（滚轮、`[` `]`、`1` `2`） | — |
| 方向键移动/收缩选区 1 像素 | — |
| Esc / Enter / 双击 / 中键 动作可配置 | — |
| 鼠标路径平滑 | 手绘曲线质量 |
| 长宽比锁定 | Shift 约束 |
| 取色值格式与 HEX 大写 | 现有取色输出未格式化 |
| 屏幕四角热区触发 | — |
| 色彩空间 / HDR 显示器校正 | — |
| JPEG 格式（Qingyu 现在 JPG 是禁用占位） | — |

#### P2 — 贴图侧增强

| 项 | 说明 |
|---|---|
| 磁性吸附（贴边） | `MagneticWindow`，阈值可调 |
| 点击穿透 / 缩放 / 透明度 三个热键 | Qingyu 只有鼠标事件一个热键 |
| 图像组（多组贴图管理） | 工程量较大，建议单独排期 |
| 拖拽网页图片自动下载 | 需网络白名单 |
| 文字贴图排版参数 | 字体/颜色/边距/换行 |
| 文件路径转图片 | Qingyu 已有开关 |

#### 不建议复刻

- 许可证 / 激活 / 购买流程（`Licensing`、`UnlockProDialog`、`PRO` 相关文案）
- 自动更新与更新源（`FvUpdater`、`Update/*`）
- 分享按钮（`ShareUI`）
- 云端 OCR（Baidu / Tencent / OCR.space 后端及其密钥配置）
- Windows 专属项（管理员权限、计划任务、任务栏、`Win2D` 等）

---

## 6. 关键结论

1. Qingyu 的截图/贴图**骨架已经完整**，差距集中在**「选区精确度」和「标注丰富度」**两块，而不是功能缺失。
2. 投入产出比最高的三件事：**放大镜**、**窗口/控件自动识别**、**预设区域与尺寸**（放大镜与选区微调本已写在 Task 007 范围内，属未交付项）。
3. Snipaste 的差异化价值很大程度来自**「截图历史 + 白板 + 图像组」这套「截图不止于截图」的产品思路**。其中**截图历史与清羽既有产品决策冲突**（Task 007 已确认移除），不应作为差距直接补齐；白板与图像组需先确认产品定位。
4. 交互细节（Tab 切辅助线、`[` `]` 调笔宽、方向键微调、双击/中键可配置）成本低、体感提升明显，适合作为独立小任务批量补齐。

---

## 附：证据文件位置

本机分析产物（不属于仓库）：

| 内容 | 路径 |
|---|---|
| 语言包提取结果（25 个语言，中英全量） | `…/T/opencode/snipaste-survey-derived/snipaste-lang-strings.json` |
| 已还原的 111 条加密字符串 | `…/T/opencode/snipaste-survey-derived/snipaste-decoded-strings.json` |
| 完整分析报告（含配置键、类清单、算法） | `…/T/opencode/snipaste-static-survey.md` |
| Ghidra 持久化分析工程 | `~/tools/ghidra-projects/snipaste.{gpr,rep}` |
