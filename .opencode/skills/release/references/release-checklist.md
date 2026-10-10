# 发布一致性清单 / Release Checklist

本文件是 `SKILL.md` 的配套参考。发布时按「事实 → 出现处」逐项核对；每项都应以代码/工程为准，而不是以旧文案为准。

## 1. 版本（单一事实来源）

| 位置 | 字段 | 要求 |
| --- | --- | --- |
| `Qingyu/Info.plist` | `CFBundleShortVersionString` | 版本真源，形如 `0.MINOR.PATCH`，主版本固定 `0` |
| `Qingyu/Info.plist` | `CFBundleVersion` | 构建号，正整数，与上一项同步递增 |
| `Qingyu.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | 必须等于 `CFBundleShortVersionString` |
| `Qingyu.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION` | 必须等于 `CFBundleVersion` |
| `CHANGELOG.md` | `## [Unreleased]` 或 `## [<版本>]` | 有对应条目 |

自动检查：`bash .opencode/skills/release/scripts/check-release-consistency.sh`

## 2. 文档事实 → 出现处

改任一项时，务必同步下列所有位置（“全部”以实际存在为准，不要漏改）。

### 最低系统版本（由 `MACOSX_DEPLOYMENT_TARGET` 决定）

- `README.md` / `README.zh-CN.md`：平台徽章、Download/下载 段
- `website/qingyu.html`：`hero` 徽章、`dl.req1`（中/英 i18n）
- `BUILD_README.md`：系统要求
- `docs/prd.md`：`FR-UI-34` / `FR-UI-35` / `D-093`
- `docs/architecture/design.md`：最低支持系统
- `docs/onboarding.md`：最低系统与前置
- `docs/tasks/README.md`：Global Constraints

### 分发方式

- `README.md` / `README.zh-CN.md`：Download/下载 段（`.dmg`、Developer ID + 公证、GitHub Releases、不在 Mac App Store、安装后自动清理安装包）
- `website/qingyu.html`：`dl.desc`、`dl.req1~4`、`dl.note`（中/英 i18n）
- `BUILD_README.md`：发布构建章节

### 账号 / 隐私口径

- `README.md` / `README.zh-CN.md`：简介、Privacy
- `website/qingyu.html`：`hero.sub`、`p.li2`、meta `description`
- `Qingyu/Resources/Localizable.xcstrings`：`privacy.local.body` 等隐私文案

### 功能与命令

- `README.md` / `README.zh-CN.md`：Features、内置命令表
- `website/qingyu.html`：Features 卡片、Roadmap、内置命令条数

### 版本号本身

- README / 网站使用动态徽章 `https://img.shields.io/github/v/release/freeabyss/qingyu`，**不得硬编码版本号**。
- 应用内「关于」、更新页、反馈邮件必须从 Bundle 读取版本与构建号（见第 4 节）。

## 3. 应用内文案

- `Qingyu/Resources/Localizable.xcstrings`：所有用户可见字符串（中/英）与实现一致。
- 中英两套都要改；新增 key 必须同时补 `en` 与 `zh-Hans`。

## 4. 人工验收点（自动化无法覆盖）

在「关于」页与相关页面确认：

- [ ] 显示的应用版本 = `CFBundleShortVersionString`，构建号 = `CFBundleVersion`
- [ ] 「检查更新」打开的是 GitHub Releases 页面，不会自动下载/安装
- [ ] 反馈邮件正文包含正确的版本号、构建号、macOS 版本
- [ ] 首次打开被 Gatekeeper 拦截时，文档给出的「隐私与安全性 → 仍要打开」路径可用
- [ ] 若本次改动了窗口 / 会话 / 悬浮层生命周期，`docs/test/cases.md`（「截图会话生命周期回归」）有对应回归用例

## 5. 发布产物

- DMG 命名：`Qingyu-<版本>.dmg`，同时生成 `.sha256`
- 必须为通用二进制：`lipo -info` 同时含 `arm64` 与 `x86_64`
- 已 Developer ID 签名 + Apple 公证（`spctl --assess` 通过）
- 挂在 GitHub Release 的 tag 为 `v<版本>`

## 6. 常用命令

```bash
# 一致性
bash .opencode/skills/release/scripts/check-release-consistency.sh

# 测试门禁
./scripts/verify.sh

# 版本（仅文档改动需发版时）
./scripts/bump-version.sh --set 0.MINOR.PATCH BUILD

# 本机打包并上传
./scripts/package-release.sh --upload

# 校验签名 / 公证
codesign --verify --deep --strict --verbose=2 dist/Qingyu.app
spctl --assess -vvv --type execute dist/Qingyu.app
xcrun stapler validate dist/Qingyu-<版本>.dmg
```
