---
name: qingyu-release
description: 清羽（Qingyu）发布流程：版本递增、changelog 归档、打包上传 GitHub Release、同步 HomePage 产品说明。用户要求「发布 / 发版 / 出包 / release」清羽新版本时使用。
---

# 清羽发布流程

> 目标：一条龙完成 版本递增 → changelog 归档 → 出包上传 GitHub Release → HomePage 产品说明同步。
> 版本号查询：`plutil -extract CFBundleShortVersionString raw Qingyu/Info.plist`（构建号把 key 换成 `CFBundleVersion`）。

## 0. 前置检查

```bash
cd /Users/abyss/workspace/my/qingyu
git status --short          # 工作树必须干净：所有功能提交已入 main
git log --oneline -5        # 确认要发布的提交都在
./scripts/verify.sh         # 必须全绿（git diff --check + xcstrings JSON + 测试登记 + 全量单测）
```

- 版本规则：主版本固定 `0`，发布只递增 `0.MINOR.PATCH`，构建号同步 +1（例 `0.4.215/615` → `0.4.216/616`）。
- 版本单一事实来源是 `Qingyu/Info.plist`；`project.pbxproj` 必须同步（「关于」页、更新页、反馈邮件都从 Bundle 读，禁止硬编码）。

## 1. 归档 changelog

`docs/guides/changelog.md`：

1. 把 `## [Unreleased]` 下已写好的条目归档成 `## [0.MINOR.PATCH] - YYYY-MM-DD`（Keep a Changelog 格式，Added/Changed/Fixed 小节保留）。
2. 在其上新建空的 `## [Unreleased]` 节，供下个周期累计。

## 2. 递增版本

```bash
./scripts/bump-version.sh --set 0.MINOR.PATCH BUILD   # 例 --set 0.4.216 616
plutil -lint Qingyu/Info.plist
grep -m1 MARKETING_VERSION Qingyu.xcodeproj/project.pbxproj   # 必须等于 CFBundleShortVersionString
```

注意：`.githooks/pre-commit` 对 Swift/工程文件的提交会**自动**再递增一次；发布提交因为已暂存 Info.plist 变更会跳过自动递增（钩子幂等），所以版本只加一次，不要手动多 bump。

## 3. 提交发布变更

```bash
git add -A
git commit -m "chore(release): 发布 0.MINOR.PATCH（构建 BUILD）

- 归档 changelog：<一句话>
- 版本 0.4.OLD/OLD_BUILD → 0.MINOR.PATCH/BUILD
- 验证：./scripts/verify.sh 全绿"
```

## 4. 出包与发布（二选一）

**A. 走 CI（推荐，产物有 Developer ID 签名 + 公证）**

```bash
git tag vX.Y.Z            # 例 v0.4.216，与 CFBundleShortVersionString 一致
git push origin main --tags
# .github/workflows/release.yml 由 v* tag 触发：构建通用二进制 → 签名 → 公证 → DMG → 创建 GitHub Release
```

**B. 本地出包**

```bash
./scripts/package-release.sh --adhoc --upload            # 无证书：ad-hoc 签名 + DMG + 上传（预发布加 --prerelease）
./scripts/package-release.sh                              # 有 Developer ID：正式签名 + 公证 + DMG
# 产物在 dist/，RELEASE_TAG 默认 v<版本号>；需要 GITHUB_TOKEN 或 gh 已登录
```

## 5. HomePage 产品说明同步（必须执行）

仓库：`~/workspace/my/HomePage`（Next.js 站点）。**涉及清羽的地方只有一处**：

| 项 | 内容 |
|---|---|
| 文件 | `app/page.tsx` |
| 位置 | Products 区（`<section id="products">`），搜「`Qingyu 清羽`」定位卡片（约 L169–186） |
| 结构 | `feature-icon` 🪶 → `feature-card-title`「Qingyu 清羽」→ `feature-card-desc`（英文描述段）→ GitHub 链接 `https://github.com/freeabyss/qingyu` |

修改规则：

1. **只在功能面变化时改文案**：新增/移除主打功能、设计语言变化、平台要求变化（例：0.4.211 接入系统 Liquid Glass、0.4.214 改为完全磁盘访问模式、0.4.215 选区可鼠标调整——这些都值得反映）。纯 bug 修复版本可跳过文案，但仍要**检查**一遍。
2. 描述是**英文**，写用户可感知的能力，不写实现细节；长度对齐同区其它卡片（3–4 行）。
3. 卡片**没有版本号、没有直链 DMG**，GitHub 仓库链接永远有效，不用动。
4. `public/` 目前没有清羽截图；若将来加了产品图，发布时同步换成新版本截图。
5. 该仓库常有用户未提交的改动（`app/page.tsx` 可能是脏的）：**只动 Qingyu 卡片那一段**，改完在 HomePage 仓库提交（`git -C ~/workspace/my/HomePage commit`）即可。
6. **部署不归本流程管**：HomePage 按**它自己的部署方案**自行上线（其仓库/平台自身的流程负责），qingyu 发布侧不代为部署、不代为推送——提交完本步骤即结束。

## 6. 发布后验证

```bash
gh release view vX.Y.Z --repo freeabyss/qingyu    # DMG 已挂上
```

- 安装 DMG 后：「关于」页版本 = 新版本；首次启动会把 `~/Downloads`、`~/Desktop` 的 `Qingyu-*.dmg` 移进废纸篓（安装包自清理，按版本执行一次）。
- HomePage 上线与验证由其自身部署方案负责，本流程不包含该步骤。
