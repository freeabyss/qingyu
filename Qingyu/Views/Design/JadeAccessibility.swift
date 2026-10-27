import AppKit
import SwiftUI

/// 系统辅助功能设置桥接（PRD §9.8：尊重「减弱动态效果」「增强对比度」）。
///
/// macOS 通过 `NSWorkspace` 暴露这些系统级偏好。SwiftUI 在 macOS 上对
/// `accessibilityReduceMotion` / `colorSchemeContrast` 的 Environment 支持
/// 不如 iOS 完整，这里统一从 `NSWorkspace.shared` 读取并封装为便捷 API，
/// 供动画降级 / 边框加深使用。
enum JadeAccessibility {

    /// 系统「减弱动态效果」是否开启。
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 系统「增强对比度」是否开启。
    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// 系统「降低透明度」是否开启。
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// 依据「减弱动态效果」返回降级后的动画：
    /// - 正常：传入的动画（通常是 spring / easeInOut）。
    /// - reduce motion：短促无位移的 `.linear(duration: 0.1)`（等价淡入淡出）。
    static func animation(_ standard: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.1) : standard
    }
}

// MARK: - View 扩展

extension View {
    /// 尊重「减弱动态效果」的动画修饰：reduce motion 时降级为 `.linear(0.1)`。
    ///
    /// ```swift
    /// someView.jadeAnimation(.spring(response: 0.35, dampingFraction: 0.8), value: isShowing)
    /// ```
    func jadeAnimation<V: Equatable>(_ standard: Animation, value: V) -> some View {
        animation(JadeAccessibility.animation(standard), value: value)
    }
}

// MARK: - 隐藏快捷键载体

extension View {
    /// 隐藏的键盘快捷键载体：仅保留快捷键响应，视图本身完全不可见。
    ///
    /// 命令栏、剪贴板历史、设置三处的快捷键按钮共用此语义：它们不是视觉元素。
    /// 实现就是原来的 opacity(0)，不引入其他隐藏方式的语义变化；各处原有的
    /// allowsHitTesting / accessibilityHidden / frame(0) 保持不变。
    public func jadeHiddenShortcut() -> some View {
        opacity(0)
    }
}
