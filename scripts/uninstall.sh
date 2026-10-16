#!/bin/bash

# Qingyu 彻底卸载脚本
#
# 唯一功能：**彻底卸载** Qingyu。不提供子命令，也不需要确认 —— 安装脚本
# （scripts/install.sh）会在安装前直接调用本脚本，交互确认会打断自动化流程。
#
# 执行顺序（顺序本身有约束，不要调换）：
#   1) 退出正在运行的 Qingyu
#   2) 重置系统权限授权（TCC）—— 必须在移除 App **之前**：tccutil 依赖
#      LaunchServices 解析 bundle id，App 一旦被移除就只能得到 -10814，
#      表现为「重置了但系统设置里条目还在」
#   3) 移除已安装的 Qingyu.app（/Applications 与 ~/Applications，移入废纸篓，可恢复）
#   4) 删除用户数据与偏好（数据库、剪贴板资源、偏好 plist、缓存、日志、保存状态）
#   5) 清理本地构建产物（DerivedData 下的 Build 与 Logs；--deep 时连同缓存/索引与 dist/）
#
# 用法: ./scripts/uninstall.sh [选项]
#
# 选项:
#   -n, --dry-run   只列出将删除/重置的内容，不做任何修改
#   --deep          连 DerivedData 缓存/索引与 dist/ 安装包一起清理
#   -h, --help      显示此帮助信息
#
# 注意:
#   - 本脚本**不询问**，执行即删除，且用户数据不可恢复。
#   - 「系统设置 → 通用 → 登录项」中的 Qingyu 由系统（SMAppService）托管，
#     没有 plist 可删；需在应用内关闭「开机启动」或手动移除。

set -euo pipefail  # 遇到错误立即退出；管道中任一命令失败即失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_NAME="Qingyu"
BUNDLE_IDENTIFIER="com.freeabyss.qingyu"

# 本地构建产物（与 install.sh 保持一致）
DERIVED_DATA_PATH="${PROJECT_DIR}/DerivedData"
DEBUG_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/${PROJECT_NAME}.app"
RELEASE_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${PROJECT_NAME}.app"
DIST_DIR="${PROJECT_DIR}/dist"

# 安装位置与用户数据
# 同时覆盖 DMG「正式安装」与 install.sh 脚本安装的副本。
INSTALLED_APP_PATHS=(
    "/Applications/${PROJECT_NAME}.app"
    "${HOME}/Applications/${PROJECT_NAME}.app"
)
SUPPORT_DIR="${HOME}/Library/Application Support"
DATA_DIR="${SUPPORT_DIR}/${PROJECT_NAME}"
PREFERENCES_PLIST="${HOME}/Library/Preferences/${BUNDLE_IDENTIFIER}.plist"
SAVED_STATE_DIR="${HOME}/Library/Saved Application State/${BUNDLE_IDENTIFIER}.savedState"
CACHE_DIR="${HOME}/Library/Caches/${BUNDLE_IDENTIFIER}"
HTTP_STORAGE_DIR="${HOME}/Library/HTTPStorages/${BUNDLE_IDENTIFIER}"
WEBKIT_DIR="${HOME}/Library/WebKit/${BUNDLE_IDENTIFIER}"
CONTAINER_DIR="${HOME}/Library/Containers/${BUNDLE_IDENTIFIER}"
APP_SCRIPTS_DIR="${HOME}/Library/Application Scripts/${BUNDLE_IDENTIFIER}"
LOG_DIR="${HOME}/Library/Logs/${PROJECT_NAME}"

# 旧版本命名（目录 + 主库文件），仅当确实属于本应用时才删除
LEGACY_DATA_DIRS=("${SUPPORT_DIR}/Qingniao:Qingniao.sqlite" "${SUPPORT_DIR}/Assistant:Assistant.sqlite")
# 选项
DRY_RUN=0
DEEP=0

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

# 人类可读的占用大小
path_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || true
}

# 删除前统一做路径安全校验：只允许删除 HOME 或项目目录之下的路径
assert_safe_path() {
    local target="$1"
    case "${target}" in
        "${HOME}"/*|"${PROJECT_DIR}"/*) return 0 ;;
        *)
            log_error "安全检查失败，拒绝删除预期之外路径: ${target}"
            return 1
            ;;
    esac
}

# 删除本地路径（不存在则跳过；dry-run 只打印）
remove_path() {
    local target="$1"
    local label="${2:-}"

    if [ ! -e "${target}" ]; then
        return 0
    fi

    assert_safe_path "${target}" || return 1

    local size
    size="$(path_size "${target}")"

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[dry-run] 将删除${label:+（${label}）}: ${target}${size:+ (${size})}"
        return 0
    fi

    log_info "删除${label:+（${label}）}: ${target}"
    if ! rm -rf "${target}"; then
        log_error "删除失败: ${target}"
        return 1
    fi
    log_success "已删除: ${target}"
}

# 退出已运行的应用，避免删除时文件被占用（逻辑与 install.sh 对齐）
quit_running_app() {
    if ! pgrep -x "${PROJECT_NAME}" > /dev/null; then
        log_info "${PROJECT_NAME} 未在运行"
        return 0
    fi

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[dry-run] 将退出正在运行的 ${PROJECT_NAME}"
        return 0
    fi

    log_info "正在退出 ${PROJECT_NAME}..."
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
        log_error "无法退出已运行的 ${PROJECT_NAME}"
        return 1
    fi

    log_success "已退出 ${PROJECT_NAME}"
}

# 1) 清理本地构建产物
clean_build() {
    if [ "${DEEP}" -eq 1 ]; then
        remove_path "${DERIVED_DATA_PATH}" "构建目录"
        remove_path "${DIST_DIR}" "发版产物（DMG）"
    else
        # 与 install.sh clean 对称：只删构建产物与日志，保留 SPM 缓存与索引
        log_info "清理构建产物（保留 SPM 缓存与索引）..."
        remove_path "${DERIVED_DATA_PATH}/Build" "构建产物"
        remove_path "${DERIVED_DATA_PATH}/Logs" "构建日志"
    fi
}

# 2) 移除已安装的应用（移入废纸篓，可恢复）
#    覆盖 /Applications（DMG 正式安装 / install.sh 安装）与 ~/Applications 两个位置。
remove_installed_app() {
    local found=0
    local app_path

    for app_path in "${INSTALLED_APP_PATHS[@]}"; do
        if [ ! -d "${app_path}" ]; then
            continue
        fi
        found=1

        if [ "${DRY_RUN}" -eq 1 ]; then
            log_info "[dry-run] 将把 ${app_path} 移入废纸篓"
            continue
        fi

        log_info "移除已安装的 App: ${app_path}"
        remove_installed_app_at "${app_path}"
    done

    if [ "${found}" -eq 0 ]; then
        log_info "未发现已安装的 ${PROJECT_NAME}.app，跳过"
    fi
}

# 移除单个已安装的 App 副本
remove_installed_app_at() {
    local app_path="$1"

    # 优先使用系统 trash，失败再退回 Finder（都是移入废纸篓而非硬删除）
    if command -v trash > /dev/null 2>&1 && trash "${app_path}" > /dev/null 2>&1; then
        log_success "已移入废纸篓: ${app_path}（可从废纸篓恢复）"
        return 0
    fi

    if osascript -e "tell application \"Finder\" to delete POSIX file \"${app_path}\"" > /dev/null 2>&1; then
        log_success "已移入废纸篓: ${app_path}（可从废纸篓恢复）"
        return 0
    fi

    log_warn "移入废纸篓失败（可能被占用），改为直接删除"
    rm -rf "${app_path}"
    log_success "已删除: ${app_path}"
}

# 3) 删除用户数据与偏好
remove_user_data() {
    # 先让 cfprefsd 忘记该域，再删 plist，避免偏好被缓存重新写回
    if [ "${DRY_RUN}" -eq 0 ]; then
        defaults delete "${BUNDLE_IDENTIFIER}" > /dev/null 2>&1 || true
    fi

    remove_path "${DATA_DIR}" "应用数据（数据库 + 剪贴板资源 + 日志）"
    remove_path "${PREFERENCES_PLIST}" "偏好设置"
    remove_path "${SAVED_STATE_DIR}" "保存的窗口状态"
    remove_path "${CACHE_DIR}" "缓存"
    remove_path "${HTTP_STORAGE_DIR}" "网络存储"
    remove_path "${WEBKIT_DIR}" "WebKit 数据"
    remove_path "${CONTAINER_DIR}" "沙盒容器（历史遗留）"
    remove_path "${APP_SCRIPTS_DIR}" "应用脚本目录（历史遗留）"
    remove_path "${LOG_DIR}" "日志"

    # 旧版本命名目录：仅当内部存在对应主库文件（确认属于本应用）时才删除
    local entry dir store
    for entry in "${LEGACY_DATA_DIRS[@]}"; do
        dir="${entry%%:*}"
        store="${entry##*:}"
        if [ -d "${dir}" ] && [ -f "${dir}/${store}" ]; then
            log_warn "发现旧版本数据目录（${store}）"
            remove_path "${dir}" "旧版本数据"
        fi
    done

    log_success "用户数据与偏好清理完成"
}

# 4) 重置系统权限授权（TCC）
#
# 关键约束：tccutil 通过 **LaunchServices** 解析 bundle id，App 被移除后会报
# `-10814 No such bundle identifier`，重置**静默失败**。因此重置必须发生在
# 「移除已安装的 App」**之前**（见 main 中的执行顺序）。
TCC_SERVICES=(ScreenCapture Accessibility AppleEvents)

reset_permissions() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        local dry_service
        for dry_service in "${TCC_SERVICES[@]}"; do
            log_info "[dry-run] 将执行: tccutil reset ${dry_service} ${BUNDLE_IDENTIFIER}"
        done
        return 0
    fi

    if ! command -v tccutil > /dev/null 2>&1; then
        log_warn "未找到 tccutil，跳过权限重置"
        return 0
    fi

    log_info "重置系统权限授权..."
    local service output status
    local reset_failures=0
    local bundle_unknown=0

    for service in "${TCC_SERVICES[@]}"; do
        set +e
        output="$(tccutil reset "${service}" "${BUNDLE_IDENTIFIER}" 2>&1)"
        status=$?
        set -e

        if [ "${status}" -eq 0 ]; then
            log_success "已重置 ${service} 授权"
            continue
        fi

        reset_failures=$((reset_failures + 1))
        # -10814 / No such bundle identifier：App 已不在 LaunchServices 里，
        # 只能说明重置来得太晚，或者本就未安装过。
        case "${output}" in
            *"-10814"*|*"No such bundle identifier"*)
                bundle_unknown=1
                log_warn "${service}: 系统已不认识 ${BUNDLE_IDENTIFIER}（App 已移除或从未安装），无法重置"
                ;;
            *)
                log_warn "${service}: 重置失败（退出码 ${status}）：${output}"
                ;;
        esac
    done

    if [ "${reset_failures}" -eq 0 ]; then
        log_success "已重置系统权限授权"
    elif [ "${bundle_unknown}" -eq 1 ]; then
        log_warn "部分服务未能重置：请在「系统设置 → 隐私与安全性」中手动移除 Qingyu 条目"
    else
        log_warn "部分服务重置失败，可能需要更高权限，可手动执行："
        for service in "${TCC_SERVICES[@]}"; do
            echo "    sudo tccutil reset ${service} ${BUNDLE_IDENTIFIER}"
        done
    fi

    log_info "提示：系统设置界面可能仍显示旧条目，退出并重新打开「系统设置」即可刷新。"
    log_info "提示：「系统设置 → 通用 → 登录项」中的 Qingyu 由系统托管，需在应用内关闭「开机启动」或手动移除。"
}

# 显示帮助信息
show_help() {
    sed -n '3,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | sed '/^set -euo/d'
}

# 主函数：唯一流程 = 彻底卸载
main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=1 ;;
            --deep)       DEEP=1 ;;
            -h|--help)    show_help; exit 0 ;;
            *)
                log_error "未知参数: $1（本脚本只做彻底卸载，无子命令）"
                show_help
                exit 2
                ;;
        esac
        shift
    done

    cd "${PROJECT_DIR}"

    [ "${DRY_RUN}" -eq 1 ] && log_warn "dry-run 模式：只预览，不做任何修改"

    log_info "彻底卸载 ${PROJECT_NAME}..."
    quit_running_app
    # 顺序约束：必须在 remove_installed_app 之前重置权限（见文件头说明）
    reset_permissions
    remove_installed_app
    remove_user_data
    clean_build

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_success "dry-run 完成（未做任何修改）"
    else
        log_success "${PROJECT_NAME} 已彻底卸载"
    fi
}

# 执行主函数
main "$@"
