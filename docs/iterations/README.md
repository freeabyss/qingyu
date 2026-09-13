# 迭代总览

| 版本 | 主题 | Issue | PR | 状态 | 当前节点 | 开始 | 上线 |
|------|------|-------|-----|------|---------|------|------|
| v1.2.1 | 欢迎页面路由 bug + 关闭按钮 | #7 | #8 | released | ⑥ 已上线 | 2026-07-07 | 2026-08-11 |
| v1.2.0 | 青鸟 Qingniao —— 产品全面审视 + 品牌改名 | #5 | #6 | released | ⑥ 已上线 | 2026-07-03 | 2026-07-07 |
| v1.1.0 | Onboarding 死锁修复：权限申请 + 跳过向导 | #3 | #4 | released | ⑥ 已上线 | 2026-07-02 | 2026-07-03 |
| v1.0.1 | 修复启动时 Sparkle updater 弹窗 | #1 | #2 | released | ⑥ 已上线 | 2026-07-02 | 2026-07-02 |
| v1.0.0 | Mac Super Assistant MVP | -（追溯迭代） | -（直接合入 main） | released | ⑥ 已上线 | 2026-06-11 | 2026-07-02 |

## v1.2.1（已上线）
- 目标：修复 v1.2.0 上线后两个 bug —— ① 所有功能入口（搜索/剪贴板/截图/设置）都错误路由到欢迎页面（P0 阻塞）；② 欢迎页面缺少「开始使用/关闭」按钮，用户无法离开（P1）
- 关联 issue：[#7](https://github.com/freeabyss/qingniao/issues/7)
- 关联 PR：[#8](https://github.com/freeabyss/qingniao/pull/8)（merged 2026-08-11）
- 分支：v1.2.1
- 当前节点：⑥ 已上线。移除 onboarding 功能入口门禁、欢迎页改 ScrollView 布局；XCUITest 扩展代码就绪（target+hook+a11y+22 条用例），UI 测试实际跑通待一次性 GUI 授权（已知限制）
- 开始日期：2026-07-07
- 上线日期：2026-08-11
- 详见 [v1.2.1/README.md](v1.2.1/README.md)

## v1.2.0（已上线）
- 目标：正式确立产品名「青鸟 / Qingniao」并全面改名（工程、target、源码目录、显示名、文案）；从①需求→②产品→③架构→④评审全流程重新审视现有产品不足，直接修订 docs/ 全局文件
- 关联 issue：[#5](https://github.com/freeabyss/qingniao/issues/5)
- 关联 PR：[#6](https://github.com/freeabyss/qingniao/pull/6)（merged 2026-07-07）
- 分支：v1.2.0
- 当前节点：⑥ 已上线
- 开始日期：2026-07-03
- 上线日期：2026-07-07
- 详见 [v1.2.0/README.md](v1.2.0/README.md)

## v1.1.0（已上线）
- 目标：修复 onboarding 屏幕录制权限申请断点 + 增加跳过向导入口，解开用户"权限拿不到 + 无法跳过"死锁
- 关联 issue：[#3](https://github.com/freeabyss/qingniao/issues/3)
- 关联 PR：[#4](https://github.com/freeabyss/qingniao/pull/4)（merged 2026-07-03）
- 分支：v1.1.0
- 上线日期：2026-07-03
- 详见 [v1.1.0/README.md](v1.1.0/README.md)

## v1.0.1（已上线）
- 目标：修复启动时"无法启动更新程序"弹窗
- 关联 issue：[#1](https://github.com/freeabyss/qingniao/issues/1)
- 关联 PR：[#2](https://github.com/freeabyss/qingniao/pull/2)（merged 2026-07-02）
- 分支：v1.0.1
- 上线日期：2026-07-02
- 详见 [v1.0.1/README.md](v1.0.1/README.md)

## v1.0.0（已上线）
- 目标：Mac Super Assistant public-beta-ready MVP（22 个用户故事）
- 关联 issue：无（追溯迭代）
- 关联 PR：无（代码已合入 main）
- 分支：main
- 上线日期：2026-07-02
- 详见 [v1.0.0/README.md](v1.0.0/README.md)
