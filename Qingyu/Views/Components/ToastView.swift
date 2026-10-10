import SwiftUI

/// Jade 风格 Toast。契约来源：PRD §9.5 通用组件规范。
///
/// v1.2 T-007 将旧 `ToastView` 重写为统一 `JadeToast`：
/// - 位置：`.bottom` / `.center`。
/// - 变体：`.info` / `.success` / `.error`，各自图标 + 语义色。
/// - 进出动画：slide + fade。
/// - 自动消失：3s(error 变体不自动消失,需外部置空)。
///
/// 兼容性：保留旧 `.toast(message:isShowing:)` modifier 签名,现有调用无需改动,
/// 底层已切换到 `JadeToast`(`.info` / `.bottom`)。
///
/// 全部颜色 / 圆角 / 字号 / 阴影走 Jade token,禁止硬编码。
public struct JadeToast: View {

    public enum Variant: Equatable {
        case info
        case success
        case error

        var tint: Color {
            switch self {
            case .info: return JadeColor.info
            case .success: return JadeColor.success
            case .error: return JadeColor.danger
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        /// error 不自动消失。
        var autoDismiss: Bool { self != .error }
    }

    public enum Position {
        case bottom
        case center
    }

    private let message: String
    private let variant: Variant

    public init(_ message: String, variant: Variant = .info) {
        self.message = message
        self.variant = variant
    }

    public var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            Image(systemName: variant.systemImage)
                .font(JadeFont.body)
                .foregroundStyle(variant.tint)
            Text(message)
                .font(JadeFont.callout.weight(.medium))
                .foregroundStyle(JadeColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.horizontal, JadeSpace.x4.value)
        .padding(.vertical, JadeSpace.x3.value)
        .background(JadeColor.surface1, in: JadeRadius.lg.shape)
        .jadeShadow(.md, radius: .lg)
    }
}

// MARK: - Modifier

/// 完整版 Toast modifier,支持位置 / 变体 / 自动消失。
public struct JadeToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let variant: JadeToast.Variant
    let position: JadeToast.Position

    @State private var dismissTask: DispatchWorkItem?

    public func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                if isShowing {
                    JadeToast(message, variant: variant)
                        .transition(
                            .move(edge: position == .bottom ? .bottom : .top)
                                .combined(with: .opacity)
                        )
                        .padding(.bottom, position == .bottom ? JadeSpace.x8.value : 0)
                }
                if position == .center { Spacer() }
            }
            .allowsHitTesting(false)
            .jadeAnimation(.spring(response: 0.35, dampingFraction: 0.8), value: isShowing)
        }
        .onChange(of: isShowing) { showing in
            dismissTask?.cancel()
            guard showing, variant.autoDismiss else { return }
            let task = DispatchWorkItem { isShowing = false }
            dismissTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
        }
    }
}

extension View {
    /// 完整版 Jade Toast:可指定变体与位置,自动消失(error 除外)。
    public func jadeToast(
        _ message: String,
        isShowing: Binding<Bool>,
        variant: JadeToast.Variant = .info,
        position: JadeToast.Position = .bottom
    ) -> some View {
        modifier(JadeToastModifier(
            isShowing: isShowing,
            message: message,
            variant: variant,
            position: position
        ))
    }

    /// 兼容旧签名:底部、info 变体。现有调用无需修改。
    func toast(message: String, isShowing: Bool) -> some View {
        modifier(JadeToastModifier(
            isShowing: .constant(isShowing),
            message: message,
            variant: .info,
            position: .bottom
        ))
    }
}

// MARK: - Preview

private struct JadeToastGallery: View {
    var body: some View {
        VStack(spacing: JadeSpace.x4.value) {
            JadeToast("已复制到剪贴板", variant: .info)
            JadeToast("保存成功", variant: .success)
            JadeToast("操作失败,请重试", variant: .error)
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 320, height: 260)
        .background(JadeColor.surface2)
    }
}

#Preview("JadeToast · Light") {
    JadeToastGallery()
        .preferredColorScheme(.light)
}

#Preview("JadeToast · Dark") {
    JadeToastGallery()
        .preferredColorScheme(.dark)
}
