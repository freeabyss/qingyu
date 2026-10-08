/// 产品特性开关。1.0.0 暂不开启截图相关功能；后续版本置为 true 即恢复全部入口。
///
/// 所有截图相关入口（菜单项、搜索命令、全局快捷键、设置页、欢迎向导屏幕录制段）
/// 均以 `FeatureGate.screenshotEnabled` 判断：关闭时代码保留不删，仅不再暴露入口。
enum FeatureGate {
    static let screenshotEnabled = false
}
