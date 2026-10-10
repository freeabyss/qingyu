#!/usr/bin/env bash
#
# 生成可分发的通用二进制（Apple 芯片 + Intel）DMG 安装包：
#   编译 Release → 签名 → 公证（可选）→ 制作 DMG → 可选上传 GitHub Release
#
# 签名模式（二选一）：
#   1. Developer ID 正式签名（推荐，可公证）：
#        DEVELOPER_ID_APP  Developer ID Application 证书名，例如
#                          "Developer ID Application: Your Name (TEAMID)"
#   2. ad-hoc 免费签名（无需任何证书，不公证）：
#        不提供 DEVELOPER_ID_APP，或显式传 --adhoc。
#        用户首次打开需右键 →「打开」，或执行：
#          xattr -dr com.apple.quarantine /Applications/Qingyu.app
#
# 公证（仅 Developer ID 模式可用）二选一：
#   AC_NOTARY_PROFILE  `xcrun notarytool store-credentials` 保存的 keychain profile
#   或同时提供：APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD（app-specific password）
#
# 可选：
#   DERIVED_DATA_DIR   构建目录（默认 <repo>/DerivedData）
#   OUTPUT_DIR         产物目录（默认 <repo>/dist）
#   GITHUB_TOKEN       `gh` 上传 Release 所需的令牌
#   RELEASE_TAG        自定义 Release tag（默认 v<版本号>）
#
# 用法：
#   ./scripts/package-release.sh                 # 有证书则签名+公证；无证书则自动 ad-hoc
#   ./scripts/package-release.sh --adhoc         # 强制 ad-hoc（免费、不公证）
#   ./scripts/package-release.sh --skip-notarize # 仅签名 + 生成 DMG
#   ./scripts/package-release.sh --upload        # 生成后上传到 GitHub Release
#   ./scripts/package-release.sh --help
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="Qingyu"
SCHEME_NAME="Qingyu"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-${PROJECT_DIR}/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_DIR}/dist}"
ENTITLEMENTS="${PROJECT_DIR}/${PROJECT_NAME}/${PROJECT_NAME}.entitlements"

SKIP_NOTARIZE=0
UPLOAD=0
REQUIRE_NOTARIZE=0
ADHOC=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

usage() {
    sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --adhoc)          ADHOC=1 ;;
        --skip-notarize)  SKIP_NOTARIZE=1 ;;
        --upload)         UPLOAD=1 ;;
        --require-notarize) REQUIRE_NOTARIZE=1 ;;
        --help|-h)        usage; exit 0 ;;
        *) log_error "未知参数: $arg"; usage; exit 2 ;;
    esac
done

plist_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PROJECT_DIR}/${PROJECT_NAME}/Info.plist"
}
plist_build() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${PROJECT_DIR}/${PROJECT_NAME}/Info.plist"
}

VERSION="$(plist_version)"
BUILD="$(plist_build)"
TAG="${RELEASE_TAG:-v${VERSION}}"
DMG_NAME="${PROJECT_NAME}-${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/${PROJECT_NAME}.app"

# 解析签名模式：显式 --adhoc，或缺少证书时自动回退 ad-hoc（免费、不公证）。
if [[ "${ADHOC}" -eq 1 ]]; then
    ADHOC_SIGNING=1
elif [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    ADHOC_SIGNING=0
else
    ADHOC_SIGNING=1
    log_warn "未提供 DEVELOPER_ID_APP，自动使用 ad-hoc 签名（免费、不公证）"
fi

if [[ "${ADHOC_SIGNING}" -eq 1 ]]; then
    SIGN_IDENTITY="-"
    if [[ "${REQUIRE_NOTARIZE}" -eq 1 ]]; then
        log_error "已要求必须公证，但 ad-hoc 模式无法公证（公证需要 Developer ID 证书）"
        exit 1
    fi
else
    SIGN_IDENTITY="${DEVELOPER_ID_APP}"
fi

notary_args=()
resolve_notary() {
    if [[ -n "${AC_NOTARY_PROFILE:-}" ]]; then
        notary_args=(--keychain-profile "${AC_NOTARY_PROFILE}")
        return 0
    fi
    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
        notary_args=(--apple-id "${APPLE_ID}" --team-id "${APPLE_TEAM_ID}" --password "${APPLE_APP_PASSWORD}")
        return 0
    fi
    return 1
}

log_info "构建 ${PROJECT_NAME} ${VERSION} (${BUILD}) 通用二进制（arm64 + x86_64）..."
rm -rf "${DERIVED_DATA_DIR}/Build/Products/Release"
build_sign_args=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=${SIGN_IDENTITY}")
if [[ "${ADHOC_SIGNING}" -eq 0 ]]; then
    build_sign_args+=(OTHER_CODE_SIGN_FLAGS="--timestamp")
fi
xcodebuild \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    "${build_sign_args[@]}" \
    clean build \
    || { log_error "Release 编译失败"; exit 1; }

[[ -d "${APP_PATH}" ]] || { log_error "未找到产物: ${APP_PATH}"; exit 1; }

# 校验通用二进制确实包含两个架构
log_info "校验二进制架构..."
lipo -info "${APP_PATH}/Contents/MacOS/${PROJECT_NAME}" || true
if ! lipo -info "${APP_PATH}/Contents/MacOS/${PROJECT_NAME}" | grep -q "x86_64"; then
    log_error "产物缺少 x86_64 架构，无法支持 Intel 芯片"
    exit 1
fi
if ! lipo -info "${APP_PATH}/Contents/MacOS/${PROJECT_NAME}" | grep -q "arm64"; then
    log_error "产物缺少 arm64 架构，无法支持 Apple 芯片"
    exit 1
fi

# Xcode 会签名，这里再显式深度签名一次，确保 entitlements 生效。
if [[ "${ADHOC_SIGNING}" -eq 1 ]]; then
    log_info "ad-hoc 签名（entitlements，不公证）..."
    codesign --force --deep \
        --entitlements "${ENTITLEMENTS}" \
        --sign - \
        "${APP_PATH}"
else
    log_info "Developer ID 签名（Hardened Runtime + entitlements）..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

# 公证 App（可选）
mkdir -p "${OUTPUT_DIR}"

if [[ "${ADHOC_SIGNING}" -eq 1 ]]; then
    log_warn "ad-hoc 模式：跳过公证（免费版本，用户首次打开需手动放行）"
elif [[ "${SKIP_NOTARIZE}" -eq 1 ]]; then
    log_warn "按要求跳过公证"
elif resolve_notary; then
    log_info "提交 App 公证..."
    app_zip="${DERIVED_DATA_DIR}/${PROJECT_NAME}-notarize.zip"
    rm -f "${app_zip}"
    /usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${app_zip}"
    xcrun notarytool submit "${app_zip}" "${notary_args[@]}" --wait
    xcrun stapler staple "${APP_PATH}"
else
    log_warn "未配置公证凭据（AC_NOTARY_PROFILE 或 APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD），跳过公证"
    if [[ "${REQUIRE_NOTARIZE}" -eq 1 ]]; then
        log_error "已要求必须公证，缺少凭据"
        exit 1
    fi
fi

# 制作 DMG（拖拽到「应用程序」安装）
log_info "制作 DMG..."
staging="$(mktemp -d)"
trap 'rm -rf "${staging:-}"' EXIT
cp -R "${APP_PATH}" "${staging}/"
ln -s /Applications "${staging}/Applications"
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "清羽 ${PROJECT_NAME}" \
    -srcfolder "${staging}" \
    -ov -format UDZO \
    "${DMG_PATH}"

if [[ "${ADHOC_SIGNING}" -eq 1 ]]; then
    log_info "ad-hoc 签名 DMG..."
    codesign --force --sign - "${DMG_PATH}"
else
    log_info "签名 DMG..."
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi
codesign --verify --verbose=2 "${DMG_PATH}"

if [[ "${ADHOC_SIGNING}" -eq 0 && "${SKIP_NOTARIZE}" -eq 0 ]] && resolve_notary; then
    log_info "提交 DMG 公证..."
    xcrun notarytool submit "${DMG_PATH}" "${notary_args[@]}" --wait
    xcrun stapler staple "${DMG_PATH}"
    spctl --assess -vvv --type open --context context:primary-signature "${DMG_PATH}" || \
        log_warn "spctl 评估未通过，请检查签名/公证"
fi

shasum -a 256 "${DMG_PATH}" | tee "${DMG_PATH}.sha256"
log_ok "安装包已生成: ${DMG_PATH}"
if [[ "${ADHOC_SIGNING}" -eq 1 ]]; then
    log_warn "这是 ad-hoc 未公证版本：用户首次打开需右键 →「打开」，或执行："
    echo "        xattr -dr com.apple.quarantine /Applications/${PROJECT_NAME}.app"
fi

# 上传到 GitHub Release（可选）
if [[ "${UPLOAD}" -eq 1 ]]; then
    log_info "上传到 GitHub Release ${TAG}..."
    if ! command -v gh >/dev/null 2>&1; then
        log_error "未安装 gh CLI，无法上传"
        exit 1
    fi
    if gh release view "${TAG}" >/dev/null 2>&1; then
        gh release upload "${TAG}" "${DMG_PATH}" "${DMG_PATH}.sha256" --clobber
    else
        gh release create "${TAG}" \
            "${DMG_PATH}" "${DMG_PATH}.sha256" \
            --title "清羽 Qingyu ${VERSION}" \
            --notes "见 [CHANGELOG.md](https://github.com/freeabyss/qingyu/blob/main/CHANGELOG.md)。"
    fi
    log_ok "已上传 Release: ${TAG}"
fi
