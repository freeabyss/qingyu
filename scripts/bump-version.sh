#!/usr/bin/env bash
# Keeps the marketing and build versions used by Xcode in sync.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist_path="$project_root/Qingniao/Info.plist"
project_path="$project_root/Qingniao.xcodeproj/project.pbxproj"

usage() {
    echo "Usage: $0 --set 0.MINOR.PATCH [BUILD] | --bump" >&2
    exit 2
}

set_version() {
    local version="$1"
    local build_number="$2"

    if [[ ! "$version" =~ ^0\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "Version must use the 0.MINOR.PATCH format; major version 0 is fixed." >&2
        exit 1
    fi
    if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
        echo "Build number must be a positive integer." >&2
        exit 1
    fi

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist_path"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist_path"

    perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_path"

    echo "Version updated to $version (build $build_number)."
}

case "${1:-}" in
    --set)
        [[ $# -eq 3 ]] || usage
        set_version "$2" "$3"
        ;;
    --bump)
        [[ $# -eq 1 ]] || usage
        current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist_path")"
        current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist_path")"
        if [[ ! "$current_version" =~ ^0\.([0-9]+)\.([0-9]+)$ ]]; then
            echo "Current version must use the 0.MINOR.PATCH format; found: $current_version" >&2
            exit 1
        fi
        current_minor="${BASH_REMATCH[1]}"
        current_patch="${BASH_REMATCH[2]}"
        if [[ ! "$current_build" =~ ^[1-9][0-9]*$ ]]; then
            echo "Current build number must be a positive integer; found: $current_build" >&2
            exit 1
        fi
        set_version "0.${current_minor}.$((current_patch + 1))" "$((current_build + 1))"
        ;;
    *)
        usage
        ;;
esac
