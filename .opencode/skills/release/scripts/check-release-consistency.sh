#!/usr/bin/env bash
#
# 清羽 Qingyu 发布一致性检查
#
# 校验：
#   1. 版本单一事实来源：Info.plist 与 project.pbxproj 的版本/构建号一致；
#   2. Info.plist 语法正确；
#   3. README / 网站 / BUILD_README 标明的 macOS 版本与部署目标一致；
#   4. 分发描述包含 DMG + GitHub Releases；
#   5. CHANGELOG 含当前版本或 [Unreleased]；
#   6. 未见过期文案（旧口号、旧系统版本）；
#   7. README / 网站未硬编码应用版本号。
#
# 用法：
#   bash .opencode/skills/release/scripts/check-release-consistency.sh
#   QINGYU_ROOT=/path/to/repo bash .../check-release-consistency.sh
#
# 退出码：0 全部通过（可能含 WARN）；1 存在 FAIL。
set -uo pipefail

ROOT="${QINGYU_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"

fail=0
warn=0
pass()  { printf '\033[0;32m[ OK ]\033[0m %s\n' "$1"; }
info()  { printf '\033[0;34m[INFO]\033[0m %s\n' "$1"; }
bad()   { printf '\033[0;31m[FAIL]\033[0m %s\n' "$1"; fail=$((fail + 1)); }
warnf() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; warn=$((warn + 1)); }

PLIST="$ROOT/Qingyu/Info.plist"
PBXPROJ="$ROOT/Qingyu.xcodeproj/project.pbxproj"

for required in "$PLIST" "$PBXPROJ"; do
    [[ -f "$required" ]] || { bad "缺少文件：$required"; echo; info "结果：$fail 项失败，$warn 项警告"; exit 1; }
done

read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

VERSION="$(read_plist CFBundleShortVersionString)"
BUILD="$(read_plist CFBundleVersion)"
MARKETING="$(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | head -1 | awk '{print $3}')"
CURRENT="$(grep -o 'CURRENT_PROJECT_VERSION = [^;]*' "$PBXPROJ" | head -1 | awk '{print $3}')"
TARGET="$(grep -o 'MACOSX_DEPLOYMENT_TARGET = [^;]*' "$PBXPROJ" | head -1 | awk '{print $3}')"
TARGET_MAJOR="${TARGET%%.*}"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    bad "无法从 Info.plist 读取版本/构建号"
    echo
    info "结果：$fail 项失败，$warn 项警告"
    exit 1
fi

info "仓库：$ROOT"
info "版本：Info.plist=$VERSION ($BUILD) / 工程 MARKETING=$MARKETING CURRENT=$CURRENT"
info "部署目标：macOS $TARGET"

# 1. 版本三源一致
[[ "$VERSION" == "$MARKETING" ]] \
    && pass "MARKETING_VERSION 与 CFBundleShortVersionString 一致" \
    || bad "版本不一致：CFBundleShortVersionString=$VERSION vs MARKETING_VERSION=$MARKETING"
[[ "$BUILD" == "$CURRENT" ]] \
    && pass "CURRENT_PROJECT_VERSION 与 CFBundleVersion 一致" \
    || bad "构建号不一致：CFBundleVersion=$BUILD vs CURRENT_PROJECT_VERSION=$CURRENT"

# 2. plist 语法
if plutil -lint "$PLIST" >/dev/null 2>&1; then
    pass "Info.plist 语法正确"
else
    bad "Info.plist 语法错误（plutil -lint 失败）"
fi

# 3. 文档标明的系统版本
for f in README.md README.zh-CN.md website/qingyu.html BUILD_README.md; do
    path="$ROOT/$f"
    if [[ ! -f "$path" ]]; then
        bad "缺少文件 $f"
        continue
    fi
    if grep -q "macOS $TARGET_MAJOR" "$path"; then
        pass "$f 标明 macOS $TARGET_MAJOR"
    else
        bad "$f 未标明 macOS ${TARGET_MAJOR}（系统要求可能过期）"
    fi
done

# 4. 分发描述
for f in README.md README.zh-CN.md; do
    path="$ROOT/$f"
    [[ -f "$path" ]] || continue
    grep -q '\.dmg' "$path" \
        && pass "$f 描述 DMG 分发" \
        || bad "$f 未描述 DMG 分发"
    grep -qi 'GitHub Releases' "$path" \
        && pass "$f 提及 GitHub Releases" \
        || warnf "$f 未提及 GitHub Releases"
done

# 5. CHANGELOG
if [[ -f "$ROOT/CHANGELOG.md" ]]; then
    if grep -qE "^## \[($VERSION|Unreleased)\]" "$ROOT/CHANGELOG.md"; then
        pass "CHANGELOG 含 [$VERSION] 或 [Unreleased]"
    else
        warnf "CHANGELOG 未包含 [$VERSION] 或 [Unreleased] 条目"
    fi
else
    bad "缺少 CHANGELOG.md"
fi

# 6. 过期文案
stale_patterns=(
    "没有账号，没有云同步，没有埋点"
    "No accounts, no cloud sync, no analytics"
    "macOS 13 Ventura"
)
for pat in "${stale_patterns[@]}"; do
    hits="$(grep -rlF "$pat" "$ROOT/README.md" "$ROOT/README.zh-CN.md" "$ROOT/BUILD_README.md" "$ROOT/website" 2>/dev/null)"
    if [[ -n "$hits" ]]; then
        warnf "存在疑似过期文案「${pat}」：$(echo "$hits" | tr '\n' ' ')"
    else
        pass "未发现过期文案「${pat}」"
    fi
done

# 7. 文档不得硬编码应用版本
for f in README.md README.zh-CN.md website/qingyu.html; do
    path="$ROOT/$f"
    [[ -f "$path" ]] || continue
    if grep -qF "$VERSION" "$path"; then
        warnf "$f 硬编码了版本号 ${VERSION}（AGENTS.md 禁止在文案中硬编码版本）"
    else
        pass "$f 未硬编码版本号"
    fi
done

echo
info "结果：$fail 项失败，$warn 项警告"
[[ "$fail" -eq 0 ]]
