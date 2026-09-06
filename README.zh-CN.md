# 青鸟 Qingniao

[English](README.md) | **简体中文**

> 你的青羽 Mac 效率伙伴 —— 本地优先的 macOS 效率中心。

青鸟 Qingniao 是一款原生 macOS 效率助手。它常驻菜单栏，通过 `⌥ Space` 快捷键唤起，并默认将剪贴板、截图和设置数据保留在本机。

## 产品页清单

| 项目 | 内容 |
| --- | --- |
| 产品名称 | 青鸟 Qingniao |
| 标语 | 你的青羽 Mac 效率伙伴。 |
| 核心功能 | 命令栏搜索(应用 / 命令 / 文件 / 剪贴板 / 计算器 / 设置)、剪贴板历史、区域 / 窗口 / 全屏截图与标注、安全内置命令、统一设置中心。 |
| 应用图标 | `assets/product/` 中的青玉 `bird` 图标占位(正式图标后补)。 |
| 截图 / 演示 GIF | `assets/product/` 占位素材(`command-bar.png`、`clipboard-history.png`、`screenshot-annotation.gif`)。在更大范围分发前基于 v1.2 发布版捕获。 |
| 下载按钮 | [从 GitHub Releases 下载最新版本](https://github.com/freeabyss/assistant/releases)。 |
| 版本历史 | [CHANGELOG.md](CHANGELOG.md) 与 [GitHub Releases](https://github.com/freeabyss/assistant/releases)。 |
| 隐私政策 | [PRIVACY.md](PRIVACY.md)。 |
| 反馈邮箱 | [feedback@qingniao.app](mailto:feedback@qingniao.app)。 |
| FAQ | 查看 [常见问题](#常见问题)。 |

## 下载

[下载最新版本](https://github.com/freeabyss/assistant/releases)

青鸟通过 GitHub Releases 分发,采用 Developer ID 签名并经过公证。不含账号系统、支付、订阅、许可证密钥,也不通过 Mac App Store 交付。

## 核心功能

- **`⌥ Space` 命令栏**:居中的命令栏,统一搜索应用、命令、文件、剪贴板项、计算器结果与设置。使用 `⌘1`–`⌘6` 切换搜索源(全部 / 应用 / 命令 / 剪贴板 / 文件 / 设置)。
- **`⌥⌘C` 剪贴板历史**:本地记录文本、富文本、图片和 Finder 文件引用,支持搜索、置顶、收藏与一键清除。
- **截图与标注**:支持区域(`⇧⌃⌘4`)、窗口(`⇧⌃⌘5`)与全屏(`⌃⌥⌘3`)截图;支持矩形、箭头、文本与马赛克标注;可复制或保存为 PNG。
- **安全内置命令**:仅可运行固定白名单内的 15 条常用 macOS 命令（含“打开剪贴板历史”）。危险操作需要二次确认。
- **`⌘,` 设置中心**:集中管理快捷键、搜索源、外观、权限、数据与更新。

## 截图与演示素材

产品页在更大范围分发之前,应包含以下发布素材(占位文件位于 `assets/product/`):

1. `assets/product/command-bar.png` — 命令栏,展示应用、命令、文件、计算器与剪贴板结果示例。
2. `assets/product/clipboard-history.png` — 剪贴板历史窗口,包含类型筛选、搜索、置顶、删除、存储用量与清空入口。
3. `assets/product/screenshot-annotation.gif` — 截图预览、标注工具栏、复制、保存与取消流程。
4. `assets/product/onboarding-permissions.png` — 单屏 onboarding 与按需权限说明。

这些素材是预留占位,应在最终发布准备阶段基于已签名的发布版本捕获。

## 权限说明

青鸟只申请所需的 macOS 权限,且在请求前会给出解释:

- **屏幕录制**:区域、窗口与全屏截图所必需。截图在本地处理,不会上传。
- **辅助功能**:按需申请 —— 仅在真正需要该权限的功能被使用时才申请,而非在 onboarding 中申请。
- **Apple Events / 自动化**:仅用于用户显式触发的白名单内置命令。应用不会执行任意 Shell 命令。
- **剪贴板访问**:macOS 对剪贴板读取不会单独弹出权限提示,因此 onboarding 与隐私政策明确说明:剪贴板历史默认开启、仅本地存储,可随时暂停或清空。

## 隐私默认设置

- 剪贴板元数据与内容存储在本地的 Core Data 与应用支持目录中(`~/Library/Application Support/Qingniao/`)。
- 截图在本地捕获、标注、复制或保存,默认目录为 `~/Desktop`。
- 文件类型的剪贴板历史仅存储文件引用与路径,不复制文件内容。
- 不接入任何账号系统、云同步、埋点后端、支付或订阅。
- 反馈仅由用户主动发送邮件;不会静默发送诊断数据。

完整内容请阅读 [隐私政策](PRIVACY.md)。

## 版本历史

发布说明见 [CHANGELOG.md](CHANGELOG.md)。应用内的 **检查更新** 操作会打开 [GitHub Releases](https://github.com/freeabyss/assistant/releases),用户可手动下载更新。青鸟不会自动下载、自动安装或重启以完成更新。

## 反馈

请将 bug 报告、建议与反馈发送至 [feedback@qingniao.app](mailto:feedback@qingniao.app)。应用生成的反馈邮件会包含应用版本、构建号、macOS 版本、可选的错误摘要以及你的备注。不会附带剪贴板历史、截图、文件或自动崩溃日志。

## 常见问题

### 青鸟 Qingniao 免费吗？

免费。青鸟完全免费,不含支付、订阅、许可证密钥、账号或 Mac App Store 流程。

### 我在哪里下载更新？

使用 [GitHub Releases](https://github.com/freeabyss/assistant/releases)。应用的 **检查更新** 按钮会打开同一页面。

### 应用会上传我的剪贴板或截图吗？

不会。剪贴板历史、截图、设置与搜索使用数据均为本地优先,除非你在反馈邮件中手动附带相关信息,否则不会离开你的 Mac。

### 我可以关闭剪贴板历史吗？

可以。你可以在“设置”中暂停剪贴板记录,并在剪贴板历史窗口或通过内置命令清空历史。

### 为什么应用需要屏幕录制权限？

macOS 要求截图捕获必须获得屏幕录制权限。该权限仅用于区域、窗口与全屏截图。

### 为什么应用需要辅助功能权限？

青鸟按需申请辅助功能权限 —— 仅在真正需要该权限的功能被使用时才申请,便于你在授予前作出决定。

### 青鸟支持任意 Shell 命令吗？

不支持。仅提供固定白名单内的 15 条安全内置命令（含“打开剪贴板历史”）。任意 Shell、`sudo`、关机、重启系统、注销、删除文件与结束进程等操作均不在范围内。

### 是否已在 Mac App Store 上架？

否。青鸟通过 GitHub Releases 分发,采用 Developer ID 签名并经过公证。

## 第三方声明

请见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
</content>
