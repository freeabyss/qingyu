---
name: Qingyu 发布
description: 清羽 Qingyu 的端到端发布流程。当用户说“发布 / 发版 / 出新版本 / release / 上传安装包 / 打 tag”时使用：核对并修正 README、网站、CHANGELOG 等描述与最新版本一致，运行测试门禁与版本一致性检查，递增版本，构建通用二进制 DMG 并上传到 GitHub Release，最后提交并推送所有变更到 GitHub。也适用于只执行其中某一步（如只核对文档一致性、只上传安装包）。
---

# 清羽 Qingyu 发布流程

面向本仓库的发布 skill。目标：把「文档与版本一致 → 测试通过 → 出通用 DMG → 上传 Release → 提交推送」串成一条可复用、可核查的流程。

## 开始前先读

- `AGENTS.md`：版本管理（主版本固定 `0`，只递增后两位；版本单一事实来源是 `Qingyu/Info.plist`）与测试门禁。
- `scripts/verify.sh`：提交前必须通过的全量单元测试 + `git diff --check`。
- `scripts/bump-version.sh`：版本递增 / 手动设定。
- `scripts/package-release.sh`：编译通用二进制（arm64 + x86_64）→ 签名 → 公证 → 生成 DMG → 可选上传。
- `.github/workflows/release.yml`：推送 `v*` tag 后由 CI 自动构建并上传 Release。
- `references/release-checklist.md`：逐文件的描述同步清单与人工验收点。

## 铁律

1. **版本只在一处改**：`Qingyu/Info.plist` 与 `Qingyu.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 必须一致。不要在任何 UI、文案、测试、文档里硬编码版本号。
2. **提交前必须过测试门禁**：`./scripts/verify.sh` 失败则不得提交，不允许删测试应付。
3. **不要手动 bump 后再提交**：`.githooks/pre-commit` 会在提交包含源码/工程/字符串改动时自动 `--bump`；手动 bump 会导致二次递增。只有在“本次只有文档改动却仍需发版”时才手动 `--set`。
4. **绝不覆盖无关改动**：工作区可能有他人在途改动，提交前先看 `git status`，只把你确认属于本次发布的内容纳入（发布场景默认 `git add -A`，但要先核对）。
5. **安装包不入库**：`dist/` 已在 `.gitignore`，DMG 只上传到 Release。

## 步骤

### 1. 同步并修正文档描述

以当前代码/工程为准，逐项核对下面的“事实”，修正所有出现处（清单见 `references/release-checklist.md`）：

- **最低系统版本**：由 `MACOSX_DEPLOYMENT_TARGET` 决定，目前为 macOS 12 Monterey。
- **分发方式**：GitHub Releases 分发的 `.dmg`，Developer ID 签名 + Apple 公证，通用二进制（Apple 芯片 + Intel），安装后首次启动清理下载的安装包。
- **下载方式**：双击 `.dmg` → 拖入「应用程序」；首次打开若被拦截 → 系统设置 → 隐私与安全性 → 仍要打开。
- **无需账号**：账号/云同步/埋点/支付相关表述要统一（当前口径：「无需账号」，不接入云同步、埋点或支付服务）。
- **功能与命令数量**：内置命令条数、设置页、快捷键等要与实现一致。
- **版本**：README/网站用动态徽章（`img.shields.io/github/v/release/...`），不要写死版本号；`CHANGELOG.md` 该版本或 `[Unreleased]` 有对应条目。
- **应用内**：确认「关于」页、更新页、反馈邮件都从 Bundle 读取版本与构建号（见 `references/release-checklist.md` 的人工验收项）。

改完运行一致性检查：

```bash
bash .opencode/skills/release/scripts/check-release-consistency.sh
```

全部 `OK`（或只剩可解释的 `WARN`）再继续。

### 2. 版本递增

优先让提交钩子自动处理：把代码/工程改动 `git add` 后正常提交，钩子会 `--bump` 并在同一次提交里带上 `Info.plist` 与 `project.pbxproj`。

若本次**只有文档改动但需要发版**，手动指定（`0.MINOR.PATCH` + 正整数构建号）：

```bash
./scripts/bump-version.sh --set 0.3.41 341
plutil -lint Qingyu/Info.plist
```

### 3. 测试门禁

```bash
./scripts/verify.sh
```

必须看到全量单元测试通过且 `git diff --check` 无输出。

> 若本机 `git` 被 Xcode 许可证拦截（报 “You have not agreed to the Xcode license agreements”），两种处理：
> - 建议一次性接受：`sudo xcodebuild -license accept`；
> - 无 sudo 时拆分执行：`DEVELOPER_DIR=/Library/Developer/CommandLineTools git diff --check` 与
>   `xcodebuild test -project Qingyu.xcodeproj -scheme Qingyu -destination 'platform=macOS' -only-testing:QingyuTests`。
>   本机没有开发者签名证书时，测试可加 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`。

### 4. 提交并推送

```bash
git status                     # 先确认要提交的范围
git add -A
git commit -m "release: 说明本次发布内容"   # pre-commit 钩子自动递增版本
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Qingyu/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Qingyu/Info.plist)"
echo "发布版本：$VERSION ($BUILD)"
git push
```

### 5. 构建安装包并上传 Release

**方式 A（推荐，走 CI）**：推送 tag 触发 `.github/workflows/release.yml`，在 CI 里构建通用包、签名、公证并上传。

```bash
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Qingyu/Info.plist)"
git tag "v${VERSION}"
git push origin "v${VERSION}"
gh run list --workflow release.yml --limit 3
gh run watch            # 跟踪最近一次运行
```

CI 需要仓库 Secrets：`DEVELOPER_ID_APP`、`DEVELOPER_ID_APP_CERT_P12_BASE64`、
`DEVELOPER_ID_APP_CERT_PASSWORD`、`KEYCHAIN_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、
`APPLE_APP_PASSWORD`（详见 workflow 顶部注释）。

**方式 B（本机打包并上传）**：需要本机已装 Developer ID 证书与公证凭据。

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export AC_NOTARY_PROFILE="qingyu-notary"        # 或 APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD
./scripts/package-release.sh --upload
```

产物：`dist/Qingyu-<版本>.dmg` 与 `dist/Qingyu-<版本>.dmg.sha256`。脚本会用 `lipo` 校验
同时含 `arm64` 与 `x86_64`。

### 6. 校验发布结果

```bash
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Qingyu/Info.plist)"
gh release view "v${VERSION}"
gh release download "v${VERSION}" --pattern '*.dmg' --dir /tmp/qingyu-release-check
lipo -info /tmp/qingyu-release-check/Qingyu-${VERSION}.dmg 2>/dev/null || true
shasum -a 256 /tmp/qingyu-release-check/Qingyu-${VERSION}.dmg
```

确认：Release 里存在 `Qingyu-<版本>.dmg` 与 `.sha256`；本地下载后能挂载、拖入
`/Applications` 启动；`spctl --assess -vvv --type execute` 通过。

## 环境前置

- Xcode（本项目当前用 Xcode 26）；`xcodebuild` 可用。
- `gh` 已登录：`gh auth status`。
- 本机打包：keychain 里有 Developer ID Application 证书，且公证凭据可用。
- CI 打包：仓库 Secrets 已配置。

## 支持文件

- `references/release-checklist.md`：逐文件描述同步清单 + 人工验收点。
- `scripts/check-release-consistency.sh`：版本三源与文档一致性自动检查。
