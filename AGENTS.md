# 项目协作约束

## 版本管理

- 应用版本从 `0.2.0` 开始，主版本固定为 `0`；代码变更提交时只递增后两位版本号，并同步递增构建号。
- 版本单一事实来源为 `Qingniao/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`；`Qingniao.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 必须保持一致。
- 每次修改版本号时，必须同步确认“关于”页面、更新页面和反馈邮件读取并显示当前 Bundle 版本与构建号。不得在 UI、文案、测试或文档中硬编码应用版本。
- 提交前运行 `plutil -lint Qingniao/Info.plist`，并确认 `MARKETING_VERSION` 等于 `CFBundleShortVersionString`。
