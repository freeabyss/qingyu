import SwiftUI

/// 统一危险操作确认弹窗 helper。契约来源：PRD §9.5 通用组件规范。
///
/// 封装系统 `confirmationDialog`，统一为「红色 destructive 主按钮 + Cancel」的
/// 二选一样式，避免各处重复搭建。不重复造轮子，仅提供统一 API。
///
/// 用法：
/// ```swift
/// someView
///     .jadeConfirmationDialog(
///         "确认删除该条目？",
///         isPresented: $showConfirm,
///         confirmTitle: "删除"
///     ) { viewModel.delete() }
/// ```
extension View {
    /// 展示统一样式的危险操作确认弹窗。
    ///
    /// - Parameters:
    ///   - title: 弹窗标题(本地化 key)。
    ///   - isPresented: 控制展示的绑定。
    ///   - confirmTitle: destructive 主按钮文案(本地化 key)。
    ///   - cancelTitle: 取消按钮文案，默认「取消」。
    ///   - message: 可选补充说明。
    ///   - onConfirm: 用户确认后的回调。
    public func jadeConfirmationDialog(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        confirmTitle: LocalizedStringKey,
        cancelTitle: LocalizedStringKey = "取消",
        message: LocalizedStringKey? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(role: .destructive) {
                onConfirm()
            } label: {
                Text(confirmTitle)
            }
            Button(role: .cancel) {} label: {
                Text(cancelTitle)
            }
        } message: {
            if let message {
                Text(message)
            }
        }
    }
}

// MARK: - Preview

private struct JadeConfirmationDialogGallery: View {
    @State private var showDialog = false

    var body: some View {
        VStack(spacing: JadeSpace.x4.value) {
            Text("jadeConfirmationDialog")
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
            Button("删除全部历史") { showDialog = true }
                .buttonStyle(.jadeDestructive)
        }
        .padding(JadeSpace.x8.value)
        .frame(width: 320, height: 220)
        .background(JadeColor.surface1)
        .jadeConfirmationDialog(
            "确认删除全部历史记录？",
            isPresented: $showDialog,
            confirmTitle: "删除",
            message: "此操作不可撤销。"
        ) {}
    }
}

#Preview("JadeConfirmationDialog · Light") {
    JadeConfirmationDialogGallery()
        .preferredColorScheme(.light)
}

#Preview("JadeConfirmationDialog · Dark") {
    JadeConfirmationDialogGallery()
        .preferredColorScheme(.dark)
}
