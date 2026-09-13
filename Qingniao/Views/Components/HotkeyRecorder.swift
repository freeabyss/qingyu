import SwiftUI
import KeyboardShortcuts

/// Jade 风格快捷键录制器。契约来源：PRD §9.5 通用组件规范。
///
/// 将 `KeyboardShortcuts.Recorder` 包装为统一外观：
/// - `JadeRadius.md` 连续曲率圆角、未 focus 时 `JadeColor.border` 描边。
/// - focus 时 `JadeColor.primary` 高亮描边。
/// - 冲突时行内红色警告文案 + `exclamationmark.triangle`。
///
/// - Important: 冲突检测本身是 T-008 的职责。本组件**不做**任何检测逻辑，
///   仅暴露 `isConflicting` / `conflictMessage` 由外部传入并负责渲染。
public struct HotkeyRecorder: View {

    private let name: KeyboardShortcuts.Name
    @Binding private var isConflicting: Bool
    @Binding private var conflictMessage: String?

    @State private var isFocused = false

    /// - Parameters:
    ///   - name: `KeyboardShortcuts.Name` 绑定的快捷键。
    ///   - isConflicting: 是否存在冲突（外部检测后传入）。
    ///   - conflictMessage: 冲突提示文案（外部提供）。
    public init(for name: KeyboardShortcuts.Name,
                isConflicting: Binding<Bool> = .constant(false),
                conflictMessage: Binding<String?> = .constant(nil)) {
        self.name = name
        self._isConflicting = isConflicting
        self._conflictMessage = conflictMessage
    }

    private var borderColor: Color {
        if isConflicting { return JadeColor.danger }
        return isFocused ? JadeColor.primary : JadeColor.border
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
            KeyboardShortcuts.Recorder(for: name) { _ in
                // 录制结果变更由外部（T-008）监听并更新冲突态；此处不处理。
            }
            .padding(.horizontal, JadeSpace.x2.value)
            .padding(.vertical, JadeSpace.x1.value)
            .background(JadeColor.surface1)
            .jadeRadius(.md)
            .overlay(
                JadeRadius.md.shape
                    .strokeBorder(borderColor, lineWidth: isFocused || isConflicting ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.12), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: isConflicting)
            .onHover { hovering in
                // Recorder 无直接 focus 回调，用 hover 近似高亮反馈。
                isFocused = hovering
            }

            if isConflicting, let conflictMessage {
                Label {
                    Text(conflictMessage)
                        .font(JadeFont.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(JadeFont.caption)
                }
                .foregroundStyle(JadeColor.danger)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Preview

private struct HotkeyRecorderGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x4.value) {
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text("正常")
                    .font(JadeFont.subhead)
                    .foregroundStyle(JadeColor.textSecondary)
                HotkeyRecorder(for: .togglePanel)
            }

            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text("冲突")
                    .font(JadeFont.subhead)
                    .foregroundStyle(JadeColor.textSecondary)
                HotkeyRecorder(
                    for: .startScreenshot,
                    isConflicting: .constant(true),
                    conflictMessage: .constant("与系统截图快捷键冲突")
                )
            }
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 320)
        .background(JadeColor.surface1)
    }
}

#Preview("HotkeyRecorder · Light") {
    HotkeyRecorderGallery()
        .preferredColorScheme(.light)
}

#Preview("HotkeyRecorder · Dark") {
    HotkeyRecorderGallery()
        .preferredColorScheme(.dark)
}
