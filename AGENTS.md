# 项目协作约束

## 版本管理

- 应用版本从 `0.2.0` 开始，主版本固定为 `0`；代码变更提交时只递增后两位版本号，并同步递增构建号。
- 版本单一事实来源为 `Qingyu/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`；`Qingyu.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 必须保持一致。
- 每次修改版本号时，必须同步确认“关于”页面、更新页面和反馈邮件读取并显示当前 Bundle 版本与构建号。不得在 UI、文案、测试或文档中硬编码应用版本。
- 提交前运行 `plutil -lint Qingyu/Info.plist`，并确认 `MARKETING_VERSION` 等于 `CFBundleShortVersionString`。
- 每次修改完毕后，提交当前修改

## 测试门禁

- 每次代码修改完毕、提交之前，必须运行 `./scripts/verify.sh`（`git diff --check` + `Localizable.xcstrings` JSON 检查 + 测试文件登记检查 + 全量单元测试）；失败时必须修复后才能提交，不得跳过或删测试应付。
- 涉及窗口、会话或悬浮层生命周期的改动，必须保留或新增对应回归用例；回归用例目录见 `docs/test/cases.md`（「截图会话生命周期回归」一节）。
- 新增测试文件后，必须把它登记进 `Qingyu.xcodeproj` 的 `QingyuTests` 目标（`PBXFileReference` + 分组 children + Sources 阶段）；只把文件放进 `QingyuTests/` 目录**不会**让它被执行。`./scripts/verify.sh` 已把「测试目录里每个 `.swift` 都出现在 Sources 阶段」设为硬门禁（该缺陷已发生过两次：`PermissionServiceProtocolConformanceTests` 4 条、`ScreenshotOverlayAppearanceTests` 6 条用例长期未被执行，而测试报告始终全绿）。

## 子代理模型

- 派发子代理（CreateSession 子会话、`.zcode/agents/*.md` 自定义 agent）时优先使用免费（Idle 计划）模型：常规子任务用 `account:bigmodel-offpeak-idle-plan/GLM-5.3-Flash`，重型综合任务用 `account:bigmodel-offpeak-idle-plan/GLM-5.3`；账户名可能变化，以派发时 `ListModels` 列出的 Idle/免费计划为准。
- 免费容量耗尽或派发报配额错误时，回退到付费计划模型（当前为 Individual Coding Plan 的 GLM-5.3 / GLM-5.3-Flash），不得让任务阻塞。
- 内置 Agent 类型的模型由各自定义锁定、无法逐次覆盖；需要钉住免费模型时，用自定义 agent 定义（frontmatter）或 CreateSession 的 `model` 字段。
