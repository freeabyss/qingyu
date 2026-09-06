# Qingniao 构建与运行指南

## 快速开始

### 使用构建脚本（推荐）

项目根目录下提供了 `build_and_run.sh` 脚本，用于编译和启动 Qingniao 应用。

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
DerivedData/Build/Products/Debug/Qingniao.app
```

## 手动构建

### 使用 Xcode

1. 打开项目文件：
   ```bash
   open Qingniao.xcodeproj
   ```

2. 在 Xcode 中选择 "My Mac" 作为目标设备

3. 按 `Cmd + R` 编译并运行

### 使用 xcodebuild 命令行

```bash
# 编译项目
xcodebuild -project Qingniao.xcodeproj -scheme Qingniao -configuration Debug

# 清理构建
xcodebuild -project Qingniao.xcodeproj -scheme Qingniao clean
```

## 依赖项

项目使用 Swift Package Manager 管理依赖：

- **GRDB** ~> 7.0: SQLite 数据库封装（遗留依赖）
- **KeyboardShortcuts** ~> 2.0: 全局快捷键支持

依赖项会在首次编译时自动下载。

## 系统要求

- macOS 13.0+
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
   - 删除 `~/Library/Application Support/Qingniao/`
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
log stream --process Qingniao --level debug
```

### 重置应用数据

```bash
# 删除应用数据（包括数据库和设置）
rm -rf ~/Library/Application\ Support/Qingniao/

# 删除应用偏好设置
defaults delete com.assistant.app
```

## 发布构建

Qingniao 采用 Developer ID 签名 + 公证的方式分发（不再使用 App Sandbox）。

### 生成 Release 版本

```bash
# 使用 Release 配置编译
xcodebuild -project Qingniao.xcodeproj -scheme Qingniao -configuration Release

# 归档
xcodebuild -project Qingniao.xcodeproj -scheme Qingniao -configuration Release archivePath=./build/Qingniao.xcarchive archive
```

`build_and_run.sh` 中的 `build_for_release` 函数封装了 codesign + notarytool + staple 流程
（使用环境变量中的 Developer ID 证书），签名后可用 `spctl --assess -vvv Qingniao.app` 验证。

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
