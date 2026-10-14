/// 产品特性开关。截图相关功能自本版起**开放**；如需临时下线，置为 false 即可隐藏全部入口。
///
/// 所有截图相关入口（菜单项、搜索命令、全局快捷键、设置页、欢迎向导屏幕录制段）
/// 均以 `FeatureGate.screenshotEnabled` 判断：关闭时代码保留不删，仅不再暴露入口。
enum FeatureGate {
    static let screenshotEnabled = true
}
