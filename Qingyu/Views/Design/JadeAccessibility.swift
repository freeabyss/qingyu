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
