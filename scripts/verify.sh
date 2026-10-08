#!/usr/bin/env bash
# 每次代码修改提交前的标准检查（docs/test/cases.md「测试门禁」）：
#   1. git diff --check（空白错误 / 冲突标记）
#   2. 全量单元测试 QingyuTests（含截图会话生命周期回归 SHOT-LIFE 组）
# 用法：./scripts/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> git diff --check"
git diff --check
echo "    OK"

log="/tmp/qingyu-verify-$$.log"
echo "==> xcodebuild test (QingyuTests)，日志：$log"
set +e
xcodebuild test \
  -project Qingyu.xcodeproj \
  -scheme Qingyu \
  -destination 'platform=macOS' \
  -only-testing:QingyuTests \
  >"$log" 2>&1
build_status=$?
set -e

grep -E "Executed [0-9]+ tests" "$log" | tail -2 || true
if [ "$build_status" -ne 0 ] || ! grep -q '\*\* TEST SUCCEEDED \*\*' "$log"; then
  echo "    FAILED（日志尾部摘要如下）"
  tail -40 "$log"
  exit 1
fi
echo "    TEST SUCCEEDED"
