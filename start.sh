#!/bin/bash

# Qingyu 构建并启动脚本
# 用法: ./start.sh [clean|build|run|all|release|help]

set -euo pipefail  # 遇到错误立即退出；管道中任一命令失败即失败

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Qingyu"
SCHEME_NAME="Qingyu"
DERIVED_DATA_PATH="${PROJECT_DIR}/DerivedData"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/Qingyu.app"
BUNDLE_IDENTIFIER="com.freeabyss.qingyu"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清理构建目录
clean_build() {
    log_info "清理构建产物（保留 SPM 缓存）..."
    local build_dir="${DERIVED_DATA_PATH}/Build"
    if [ -d "${build_dir}" ]; then
        rm -rf "${build_dir}"
        log_success "已清理构建产物（SPM 缓存保留）"
    else
        log_info "无需清理"
    fi
}

# 退出已运行的应用，避免新构建与旧实例并存。
quit_running_app() {
    if ! pgrep -x "${PROJECT_NAME}" > /dev/null; then
        return 0
    fi

    log_info "正在退出已启动的 ${PROJECT_NAME}..."
    osascript -e "tell application id \"${BUNDLE_IDENTIFIER}\" to quit" > /dev/null 2>&1 || true

    local attempts=0
    while pgrep -x "${PROJECT_NAME}" > /dev/null && [ "${attempts}" -lt 20 ]; do
        sleep 0.25
        attempts=$((attempts + 1))
    done

    if pgrep -x "${PROJECT_NAME}" > /dev/null; then
        log_warn "${PROJECT_NAME} 未在 5 秒内正常退出，正在终止进程..."
        pkill -TERM -x "${PROJECT_NAME}" > /dev/null 2>&1 || true
        sleep 0.5
    fi

    if pgrep -x "${PROJECT_NAME}" > /dev/null; then
        log_error "无法退出已启动的 ${PROJECT_NAME}"
        return 1
    fi

    log_success "已退出已启动的 ${PROJECT_NAME}"
}

# 编译项目
build_project() {
    log_info "开始编译 ${PROJECT_NAME}..."

    # 检查 Xcode 是否安装
    if ! command -v xcodebuild &> /dev/null; then
        log_error "未找到 xcodebuild，请确保已安装 Xcode"
        exit 1
    fi

    # xcodebuild 的 shim 即使只有 Command Line Tools 也存在，必须确认
    # developer 目录指向完整 Xcode，否则会报 “requires Xcode” 而非许可证问题。
    local developer_dir
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ "${developer_dir}" != *"Xcode.app/Contents/Developer"* ]]; then
        log_error "当前 developer 目录不是完整 Xcode: ${developer_dir:-<未设置>}"
        log_info "请安装 Xcode 后执行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    # 检查 Xcode 许可证状态
    if ! xcodebuild -license check &> /dev/null; then
        log_warn "Xcode 许可证可能未接受，尝试编译..."
    fi

    # 纯命令行构建机可能未安装 Mac Development 证书；此时退回 ad-hoc 本地
    # 签名，让 Debug 构建/运行仍可用。有证书的机器行为保持不变。
    local sign_args=""
    if [ -z "$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*\([0-9][0-9]*\) valid identities found.*/\1/p' | grep -v '^0$')" ]; then
        log_warn "未发现可用签名身份，Debug 构建使用 ad-hoc 本地签名"
        sign_args="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO"
    fi

    local log_file
    log_file="$(mktemp -t qingyu-xcodebuild.XXXXXX)"

    local status=0
    # 明确 macOS destination，避免 arm64/x86_64 多匹配告警；
    # 日志写入临时文件后过滤展示，便于用 xcodebuild 退出码判定成败
    # （管道 + while 会吞掉 xcodebuild 的退出码）。
    xcodebuild \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Debug \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        ${sign_args} \
        -quiet \
        >"${log_file}" 2>&1 || status=$?

    # 过滤并高亮重要信息（忽略 Xcode 插件/CoreSimulator 环境噪声与
    # Xcode 27 的「exit code 0 but produced no further output」空输出提示）
    grep -v -E 'DVTPlugIn|DVTDevice|CoreDevice|CoreSimulator|iOSSimulator|DVTErrorPresenter|DVTAssertions|Please file a bug|knownDeviceLocators|Recovery Suggestion|Failure Reason|^Method:|^Thread:|^Object:|Domain: DVT|the following command failed with exit code 0|SwiftCompile normal arm64|^Code:|^--$|^$' \
        "${log_file}" || true

    if [ "${status}" -ne 0 ]; then
        log_error "编译失败（xcodebuild 退出码 ${status}）"
        log_info "完整日志: ${log_file}"
        return "${status}"
    fi

    if [ ! -d "${APP_PATH}" ]; then
        log_error "xcodebuild 报告成功但未找到产物: ${APP_PATH}"
        log_info "完整日志: ${log_file}"
        return 1
    fi

    rm -f "${log_file}"
    log_success "编译成功完成: ${APP_PATH}"
    return 0
}

# 启动应用
run_app() {
    # 检查 .app 文件是否存在
    if [ ! -d "${APP_PATH}" ]; then
        log_error "未找到编译后的应用: ${APP_PATH}"
        log_info "请先运行编译: $0 build"
        exit 1
    fi

    if ! quit_running_app; then
        exit 1
    fi

    log_info "启动 ${PROJECT_NAME}..."

    # 使用 open 命令启动应用
    open "${APP_PATH}"

    # 等待应用启动
    sleep 2

    # 检查应用是否正在运行
    if pgrep -x "${PROJECT_NAME}" > /dev/null; then
        log_success "${PROJECT_NAME} 已启动"
    else
        log_warn "${PROJECT_NAME} 可能未正确启动，请检查控制台日志"
    fi
}

# Release 构建 + 签名 + 公证 + 装订（Developer ID 分发）
#
# 需要的环境变量：
#   DEVELOPER_ID_APP   Developer ID Application 证书名（如
#                      "Developer ID Application: Your Name (TEAMID)"）
#   AC_NOTARY_PROFILE  notarytool 已保存的 keychain profile 名
#                      （由 `xcrun notarytool store-credentials` 预先创建）
# 可选：
#   RELEASE_APP_PATH   输出 .app 路径（默认 Release 产物）
build_for_release() {
    local release_derived="${PROJECT_DIR}/DerivedData"
    local release_app="${RELEASE_APP_PATH:-${release_derived}/Build/Products/Release/${PROJECT_NAME}.app}"
    local entitlements="${PROJECT_DIR}/${PROJECT_NAME}/${PROJECT_NAME}.entitlements"
    local developer_id="${DEVELOPER_ID_APP:-}"
    local notary_profile="${AC_NOTARY_PROFILE:-}"

    if [ -z "${developer_id}" ]; then
        log_error "缺少环境变量 DEVELOPER_ID_APP（Developer ID Application 证书名）"
        log_info "示例: export DEVELOPER_ID_APP=\"Developer ID Application: Your Name (TEAMID)\""
        return 1
    fi

    log_info "编译 Release 配置（通用二进制：arm64 + x86_64）..."
    xcodebuild \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        -derivedDataPath "${release_derived}" \
        clean build \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${developer_id}" \
        || { log_error "Release 编译失败"; return 1; }

    if [ ! -d "${release_app}" ]; then
        log_error "未找到 Release 产物: ${release_app}"
        return 1
    fi

    # 深度签名（Hardened Runtime + entitlements + secure timestamp）
    log_info "使用 Developer ID 签名并启用 Hardened Runtime..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "${entitlements}" \
        --sign "${developer_id}" \
        "${release_app}" \
        || { log_error "codesign 失败"; return 1; }

    codesign --verify --deep --strict --verbose=2 "${release_app}" \
        || { log_error "签名校验失败"; return 1; }
    log_success "签名完成"

    # 公证（需 notarytool profile）
    if [ -z "${notary_profile}" ]; then
        log_warn "未设置 AC_NOTARY_PROFILE，跳过公证与装订（仅完成签名）"
        log_info "配置方法: xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID> --password <app-specific-pwd>"
        return 0
    fi

    local zip_path="${release_derived}/${PROJECT_NAME}-notarize.zip"
    log_info "打包并提交公证..."
    /usr/bin/ditto -c -k --keepParent "${release_app}" "${zip_path}" \
        || { log_error "打包 zip 失败"; return 1; }

    xcrun notarytool submit "${zip_path}" \
        --keychain-profile "${notary_profile}" \
        --wait \
        || { log_error "notarytool 公证失败"; return 1; }

    # 装订票据
    log_info "装订公证票据..."
    xcrun stapler staple "${release_app}" \
        || { log_error "stapler 装订失败"; return 1; }

    # Gatekeeper 评估
    spctl --assess -vvv --type execute "${release_app}" \
        || log_warn "spctl 评估未通过，请检查签名/公证"

    log_success "Release 签名 + 公证 + 装订完成: ${release_app}"
}

# 显示帮助信息
show_help() {
    echo "Qingyu 构建并启动脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  clean    清理构建目录"
    echo "  build    编译项目"
    echo "  run      启动应用（需要先编译）"
    echo "  all      清理、编译并启动（默认）"
    echo "  release  Release 编译 + Developer ID 签名 + 公证 + 装订"
    echo "  package  Release 签名 + 公证 + 生成通用二进制 DMG（scripts/package-release.sh）"
    echo "  help     显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0          # 清理、编译并启动"
    echo "  $0 build    # 仅编译"
    echo "  $0 run      # 仅启动"
    echo "  $0 clean    # 仅清理"
    echo "  $0 release  # 分发构建（需 DEVELOPER_ID_APP / AC_NOTARY_PROFILE）"
}

# 主函数
main() {
    cd "${PROJECT_DIR}"

    case "${1:-all}" in
        clean)
            clean_build
            ;;
        build)
            build_project
            ;;
        run)
            run_app
            ;;
        release)
            build_for_release
            ;;
        package)
            "${PROJECT_DIR}/scripts/package-release.sh"
            ;;
        all)
            clean_build
            if build_project; then
                run_app
            else
                log_error "编译失败，无法启动应用"
                exit 1
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
