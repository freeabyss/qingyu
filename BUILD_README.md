# Qingyu 构建与运行指南

## 快速开始

### 使用构建脚本（推荐）

项目根目录下提供了 `build_and_run.sh` 脚本，用于编译和启动 Qingyu 应用。

```bash
# 赋予脚本执行权限（首次使用）
chmod +x build_and_run.sh

# 清理、编译并启动应用（默认）
./build_and_run.sh

# 仅编译
./build_and_run.sh build

# 仅启动（需要先编译）
./build_and_run.sh run

# 仅清理构建目录
./build_and_run.sh clean

# 显示帮助信息
./build_and_run.sh help
```

### 脚本功能说明

- **clean**: 清理 `DerivedData/` 构建目录
- **build**: 使用 `xcodebuild` 编译项目（Debug 配置）
- **run**: 启动编译后的 `.app` 应用
- **all**: 依次执行 clean → build → run（默认命令）

### 编译输出

编译成功后，应用位于：
```
DerivedData/Build/Products/Debug/Qingyu.app
```

## 手动构建

### 使用 Xcode

1. 打开项目文件：
   ```bash
   open Qingyu.xcodeproj
   ```

2. 在 Xcode 中选择 "My Mac" 作为目标设备

3. 按 `Cmd + R` 编译并运行

### 使用 xcodebuild 命令行

```bash
# 编译项目
xcodebuild -project Qingyu.xcodeproj -scheme Qingyu -configuration Debug

# 清理构建
xcodebuild -project Qingyu.xcodeproj -scheme Qingyu clean
```

## 依赖项

项目使用 Swift Package Manager 管理依赖：

- **GRDB** ~> 7.0: SQLite 数据库封装（遗留依赖）
- **KeyboardShortcuts** ~> 2.0: 全局快捷键支持

依赖项会在首次编译时自动下载。

## 系统要求

- macOS 12.0+
- Xcode 15.0+
- Swift 5.9+

## 故障排除

### 编译错误

1. **Xcode 许可证未接受**：
   ```bash
   sudo xcodebuild -license accept
   ```

2. **依赖下载失败**：
   ```bash
   # 清理 SPM 缓存
   rm -rf .build
   rm -rf .swiftpm
   # 重新编译
   ./build_and_run.sh build
   ```

3. **权限问题**：
   ```bash
   # 确保脚本有执行权限
   chmod +x build_and_run.sh
   ```

### 运行时问题

1. **应用无法启动**：
   - 检查 Console.app 中的日志
   - 确认 macOS 版本符合要求

2. **数据库错误**：
   - 删除 `~/Library/Application Support/Qingyu/`
   - 重新启动应用

## 开发模式

### 自动版本号

提交包含 Swift 源码、字符串资源或 Xcode 工程配置的改动时，Git 钩子会自动递增修订号，
并将版本文件加入同一次提交。版本从 `0.2.0` 起，主版本固定为 `0`，自动递增序列为
`0.2.1`、`0.2.2`……；构建号也会同步递增。

首次克隆仓库后执行一次：

```bash
git config core.hooksPath .githooks
```

如需重新初始化版本，可运行：

```bash
./scripts/bump-version.sh --set 0.2.0 200
```

### 启用调试日志

在 Xcode 中运行时，调试日志会自动显示在控制台。命令行运行时：

```bash
# 查看实时日志
log stream --process Qingyu --level debug
```

### 重置应用数据

```bash
# 删除应用数据（包括数据库和设置）
rm -rf ~/Library/Application\ Support/Qingyu/

# 删除应用偏好设置
defaults delete com.freeabyss.qingyu
```

## 发布构建

Qingyu 采用 Developer ID 签名 + 公证的方式分发（不再使用 App Sandbox）。
发行包为**通用二进制**（`arm64` + `x86_64`），以 `.dmg` 形式提供，最低支持
macOS 12 Monterey。

### 生成 DMG 安装包（推荐）

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
# 公证凭据二选一：
export AC_NOTARY_PROFILE="qingyu-notary"   # xcrun notarytool store-credentials 保存的 profile
# 或：export APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=...

./scripts/package-release.sh              # 编译（通用）+ 签名 + 公证 + 生成 dist/Qingyu-<版本>.dmg
./scripts/package-release.sh --upload     # 生成后上传到 GitHub Release
./scripts/package-release.sh --skip-notarize   # 仅签名并生成 DMG（本地联调）
```

脚本会用 `lipo` 确认产物同时包含 `arm64` 与 `x86_64`，并对 App 与 DMG 分别签名、
公证、装订票据（`codesign` / `notarytool` / `stapler`）。

### 自动发布（GitHub Actions）

推送形如 `v0.3.40` 的 tag，或在 Actions 中手动触发 `Release` workflow，即会
构建通用二进制、签名、公证并创建 GitHub Release。所需 Secrets 见
[`.github/workflows/release.yml`](.github/workflows/release.yml) 顶部注释。

### 手动签名与校验

```bash
codesign --verify --deep --strict --verbose=2 dist/Qingyu.app
spctl --assess -vvv --type execute dist/Qingyu.app
xcrun stapler validate dist/Qingyu-<版本>.dmg
```

### 代码签名

发布前需要配置代码签名：

1. 在 Xcode 中打开项目设置
2. 选择 "Signing & Capabilities"
3. 配置 Developer ID 证书，启用 Hardened Runtime

## 脚本自定义

### 修改编译配置

编辑 `build_and_run.sh` 中的变量：

```bash
# 修改编译配置（Debug/Release）
CONFIGURATION="Debug"

# 修改 DerivedData 路径
DERIVED_DATA_PATH="${PROJECT_DIR}/DerivedData"

# 添加额外的 xcodebuild 参数
XCODEBUILD_ARGS="-jobs 8"  # 使用 8 个并行任务
```

### 添加自定义命令

可以在脚本中添加新函数，例如：

```bash
# 运行测试
run_tests() {
    xcodebuild test \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -derivedDataPath "${DERIVED_DATA_PATH}"
}
```

## 相关文档

- [项目架构](docs/architecture/design.md)
- [需求文档](docs/prd.md)
- [测试用例](docs/test/cases.md)
</content>
