import Foundation

// MARK: - Pin shortcut hints (Task 017 / 04)

/// 贴图窗口悬停时的快捷键提示文案（纯函数，便于单测）。
///
/// 提示刻意保持「一行、克制」：过长会盖住贴图内容本身。
enum PinShortcutHints {
    /// 最多展示的提示项数（超出截断）。
    static let maximumItems = 6

    struct Item: Equatable {
        /// 动作名（已本地化）。
        let action: String
        /// 键位描述（如 `⌘W`）；为空表示未绑定，该项被跳过。
        let keys: String

        init(action: String, keys: String) {
            self.action = action
            self.keys = keys
        }
    }

    /// 组装一行提示：跳过未绑定项、截断到上限、以 ` · ` 分隔。
    static func text(_ items: [Item]) -> String {
        items
            .filter { !$0.keys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(maximumItems)
            .map { "\($0.keys) \($0.action)" }
            .joined(separator: " · ")
    }
}
