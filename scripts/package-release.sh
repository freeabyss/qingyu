#!/usr/bin/env bash
#
# 生成可分发的通用二进制（Apple 芯片 + Intel）DMG 安装包：
#   编译 Release → 签名 → 公证（可选）→ 装订票据 → 制作 DMG → 可选上传 GitHub Release
#
# 两种签名模式：
#   1) Developer ID（正式分发）：需要 DEVELOPER_ID_APP，并配置公证凭据。
#   2) ad-hoc（无证书，--adhoc）：用 `codesign -s -` 签名，跳过公证。
#      Apple 芯片可运行，但未公证；其他 Mac 首次打开需在
#      「系统设置 → 隐私与安全性」点「仍要打开」。
#
# 需要的环境变量：
#   Developer ID 模式： DEVELOPER_ID_APP（证书名）
#   公证二选一：       AC_NOTARY_PROFILE
#                      或 APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD
#
# 可选：
#   DERIVED_DATA_DIR   构建目录（默认 <repo>/DerivedData）
#   OUTPUT_DIR         产物目录（默认 <repo>/dist）
#   GITHUB_TOKEN       `gh` 上传 Release 所需的令牌（环境已登录时可省略）
#   RELEASE_TAG        自定义 Release tag（默认 v<版本号>）
#
# 用法：
#   ./scripts/package-release.sh                      # Developer ID 签名 + 公证 + DMG
#   ./scripts/package-release.sh --adhoc              # 无证书：ad-hoc 签名 + DMG（不公证）
#   ./scripts/package-release.sh --adhoc --upload     # 生成后上传 GitHub Release（标记为预发布）
#   ./scripts/package-release.sh --skip-notarize      # 签名但不公证
#   ./scripts/package-release.sh --upload             # 生成后上传 GitHub Release
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
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --adhoc)          ADHOC=1; SKIP_NOTARIZE=1 ;;
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

# 解析签名身份
if [[ "${ADHOC}" -eq 1 ]]; then
    SIGN_IDENTITY="-"
    SIGN_DESCRIPTION="ad-hoc（无证书，未公证）"
    log_warn "ad-hoc 模式：产物未公证，其他 Mac 首次打开需手动放行（隐私与安全性 → 仍要打开）"
else
    if [[ -z "${DEVELOPER_ID_APP:-}" ]]; then
        log_error "缺少环境变量 DEVELOPER_ID_APP（Developer ID Application 证书名）"
        echo '  示例: export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"'
        echo '  无证书时可用: ./scripts/package-release.sh --adhoc'
        exit 1
    fi
    SIGN_IDENTITY="${DEVELOPER_ID_APP}"
    SIGN_DESCRIPTION="Developer ID（${DEVELOPER_ID_APP}）"
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

log_info "构建 ${PROJECT_NAME} ${VERSION} (${BUILD}) 通用二进制（arm64 + x86_64），签名方式：${SIGN_DESCRIPTION}"
rm -rf "${DERIVED_DATA_DIR}/Build/Products/Release"
if [[ "${ADHOC}" -eq 1 ]]; then
    # ad-hoc：先构建未签名产物，构建后再用 `codesign -s -` 统一 ad-hoc 签名。
    xcodebuild \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        -derivedDataPath "${DERIVED_DATA_DIR}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        clean build \
        || { log_error "Release 编译失败"; exit 1; }
else
    xcodebuild \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        -derivedDataPath "${DERIVED_DATA_DIR}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        clean build \
        || { log_error "Release 编译失败"; exit 1; }
fi

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

# 签名
mkdir -p "${OUTPUT_DIR}"
if [[ "${ADHOC}" -eq 1 ]]; then
    log_info "ad-hoc 签名（entitlements 保留，不启用 Hardened Runtime 公证链）..."
    codesign --force --deep --timestamp=none \
        --entitlements "${ENTITLEMENTS}" \
        --sign - \
        "${APP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
else
    log_info "Developer ID 签名（Hardened Runtime + entitlements）..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

# 公证 App（仅 Developer ID 模式）
if [[ "${SKIP_NOTARIZE}" -eq 1 ]]; then
    log_warn "跳过公证（ad-hoc 或按要求）"
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

log_info "签名 DMG..."
if [[ "${ADHOC}" -eq 1 ]]; then
    codesign --force --sign - "${DMG_PATH}"
else
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi
codesign --verify --verbose=2 "${DMG_PATH}" || true

if [[ "${SKIP_NOTARIZE}" -eq 0 ]] && resolve_notary; then
    log_info "提交 DMG 公证..."
    xcrun notarytool submit "${DMG_PATH}" "${notary_args[@]}" --wait
    xcrun stapler staple "${DMG_PATH}"
    spctl --assess -vvv --type open --context context:primary-signature "${DMG_PATH}" || \
        log_warn "spctl 评估未通过，请检查签名/公证"
fi

shasum -a 256 "${DMG_PATH}" | tee "${DMG_PATH}.sha256"
log_ok "安装包已生成: ${DMG_PATH}（${SIGN_DESCRIPTION}）"

# 上传到 GitHub Release（可选）
if [[ "${UPLOAD}" -eq 1 ]]; then
    log_info "上传到 GitHub Release ${TAG}..."
    if ! command -v gh >/dev/null 2>&1; then
        log_error "未安装 gh CLI，无法上传"
        exit 1
    fi
    if [[ "${ADHOC}" -eq 1 ]]; then
        release_notes="ad-hoc 签名、**未公证**的测试版本。首次打开可能被 macOS 拦截，请在「系统设置 → 隐私与安全性」点「仍要打开」。正式分发请使用 Developer ID 签名 + 公证版本。"
    else
        release_notes="见 [CHANGELOG.md](https://github.com/freeabyss/qingyu/blob/main/CHANGELOG.md)。"
    fi
    if gh release view "${TAG}" >/dev/null 2>&1; then
        gh release upload "${TAG}" "${DMG_PATH}" "${DMG_PATH}.sha256" --clobber
        if [[ "${ADHOC}" -eq 1 ]]; then
            gh release edit "${TAG}" --prerelease --notes "${release_notes}"
        fi
    elif [[ "${ADHOC}" -eq 1 ]]; then
        gh release create "${TAG}" \
            "${DMG_PATH}" "${DMG_PATH}.sha256" \
            --title "清羽 Qingyu ${VERSION}" \
            --notes "${release_notes}" \
            --prerelease
    else
        gh release create "${TAG}" \
            "${DMG_PATH}" "${DMG_PATH}.sha256" \
            --title "清羽 Qingyu ${VERSION}" \
            --notes "${release_notes}"
    fi
    log_ok "已上传 Release: ${TAG}"
fi
