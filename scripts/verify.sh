#!/usr/bin/env bash
# 每次代码修改提交前的标准检查（docs/test/cases.md「测试门禁」）：
#   1. git diff --check（空白错误 / 冲突标记）
#   2. 测试文件登记检查（孤儿文件里的用例不会被执行）
#   3. 全量单元测试 QingyuTests（含截图会话生命周期回归 SHOT-LIFE 组）
# 用法：./scripts/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> git diff --check"
git diff --check
echo "    OK"

# 第 2 步的由来：`QingyuTests/PermissionServiceProtocolConformanceTests.swift`（4 条用例）
# 与 `QingyuTests/ScreenshotOverlayAppearanceTests.swift`（6 条用例）都曾**从未登记进测试目标**，
# 文件在仓库里、测试全绿，用例却一条也没跑过 —— 「全绿」因此具有欺骗性。
# 这里把「测试目录里的每个 .swift 都出现在 project.pbxproj 中」变成硬门禁。
echo "==> 测试文件登记检查"
orphans=""
while IFS= read -r file; do
  # 登记方式在新旧文件间不一致（`path = QingyuTests/Foo.swift` + SOURCE_ROOT
  # 与 `path = Foo.swift` + group），因此按**文件名**匹配 Sources 阶段条目，
  # 并容忍注释里带不带 `QingyuTests/` 前缀两种写法。
  name="$(basename "$file")"
  if ! grep -qE "/\* (QingyuTests/)?$name in Sources \*/" Qingyu.xcodeproj/project.pbxproj; then
    orphans="$orphans QingyuTests/$file"
  fi
done < <(cd QingyuTests && find . -name '*.swift' | sed 's|^\./||' | sort)
if [ -n "$orphans" ]; then
  echo "    FAILED：以下文件未登记进测试目标，其用例不会被执行："
  for file in $orphans; do echo "      $file"; done
  echo "    请把它们加入 Qingyu.xcodeproj 的 QingyuTests 目标（PBXFileReference + Sources）"
  exit 1
fi
echo "    OK"

# 纯命令行构建机可能未安装 Mac Development 证书；此时退回 ad-hoc 本地签名，
# 让单元测试仍能运行（含 TEST_HOST 宿主应用）。有证书的机器行为完全不变，
# Release 分发签名不受影响。
sign_args=""
if [ -z "$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*\([0-9][0-9]*\) valid identities found.*/\1/p' | grep -v '^0$')" ]; then
  echo "    [i] 未发现可用签名身份，使用 ad-hoc 本地签名"
  sign_args="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO"
fi

log="/tmp/qingyu-verify-$$.log"
echo "==> xcodebuild test (QingyuTests)，日志：$log"
set +e
xcodebuild test \
  -project Qingyu.xcodeproj \
  -scheme Qingyu \
  -destination 'platform=macOS' \
  -only-testing:QingyuTests \
  ${sign_args} \
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
