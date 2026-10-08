import SwiftUI

/// Jade 风格文本输入框。契约来源：PRD §9.5 通用组件规范。
///
/// 特性：
/// - 可选左侧前缀图标（`Image?`）。
/// - 右侧 `xmark.circle.fill` 清空按钮（仅在有内容时出现）。
/// - focus 时 1.5pt `JadeColor.primary` 边框；未 focus 时 1pt `JadeColor.border`。
/// - `JadeRadius.md` 连续曲率圆角、`JadeFont.body`、内边 12×9。
/// - `@FocusState` 驱动焦点态，支持 `@Binding<String>` 与 `LocalizedStringKey` placeholder。
///
/// 全部尺寸 / 颜色 / 圆角 / 字号走 Jade token，禁止硬编码。
public struct JadeTextField: View {

    @Binding private var text: String
    private let placeholder: LocalizedStringKey
    private let icon: Image?

    @FocusState private var isFocused: Bool

    /// - Parameters:
    ///   - placeholder: 占位文案（本地化 key）。
    ///   - text: 绑定的文本。
    ///   - icon: 可选左侧前缀图标。
    public init(_ placeholder: LocalizedStringKey,
                text: Binding<String>,
                icon: Image? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            if let icon {
                icon
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textSecondary)
                    .accessibilityHidden(true)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)
                .focused($isFocused)
                .accessibilityLabel(Text(placeholder))

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("a11y.commandBar.clear"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(JadeColor.surface2)
        .jadeRadius(.md)
        .overlay(
            JadeRadius.md.shape
                .strokeBorder(
                    isFocused ? JadeColor.primary : JadeColor.border,
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .animation(JadeAccessibility.animation(.easeInOut(duration: 0.12)), value: isFocused)
        .contentShape(JadeRadius.md.shape)
        .onTapGesture { isFocused = true }
    }
}

// MARK: - Preview

private struct JadeTextFieldGallery: View {
    @State private var empty = ""
    @State private var filled = "搜索关键词"
    @State private var iconField = "clipboard.item"

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x4.value) {
            JadeTextField("搜索…", text: $empty)
            JadeTextField("搜索…", text: $filled)
            JadeTextField("搜索…", text: $iconField,
                          icon: Image(systemName: "magnifyingglass"))
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 320)
        .background(JadeColor.surface2)
    }
}

#Preview("JadeTextField · Light") {
    JadeTextFieldGallery()
        .preferredColorScheme(.light)
}

#Preview("JadeTextField · Dark") {
    JadeTextFieldGallery()
        .preferredColorScheme(.dark)
}
