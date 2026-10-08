import SwiftUI

/// 权限未授予时的占位 / 引导组件。契约来源：PRD §9.5 通用组件规范。
///
/// 图标 + 标题 + 描述 + 引导按钮，用于空权限态(如辅助功能 / 屏幕录制未授权)。
///
/// 全部尺寸 / 颜色 / 圆角 / 字号走 Jade token，禁止硬编码。
public struct PermissionGate: View {

    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let actionTitle: LocalizedStringKey
    private let action: () -> Void

    /// - Parameters:
    ///   - systemImage: SF Symbol 名称。
    ///   - title: 标题(本地化 key)。
    ///   - message: 描述文案(本地化 key)。
    ///   - actionTitle: 引导按钮文案(本地化 key)。
    ///   - action: 按钮点击回调。
    public init(systemImage: String,
                title: LocalizedStringKey,
                message: LocalizedStringKey,
                actionTitle: LocalizedStringKey,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: JadeSpace.x3.value) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(JadeColor.textTertiary)

            Text(title)
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(actionTitle)
            }
            .buttonStyle(.jadePrimary)
            .padding(.top, JadeSpace.x1.value)
        }
        .padding(JadeSpace.x8.value)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JadeColor.surface1)
    }
}

// MARK: - Preview

private struct PermissionGateGallery: View {
    var body: some View {
        PermissionGate(
            systemImage: "lock.shield",
            title: "需要屏幕录制权限",
            message: "清羽需要屏幕录制权限才能截取屏幕内容。请在系统设置中开启后重试。",
            actionTitle: "打开系统设置"
        ) {}
        .frame(width: 360, height: 340)
    }
}

#Preview("PermissionGate · Light") {
    PermissionGateGallery()
        .preferredColorScheme(.light)
}

#Preview("PermissionGate · Dark") {
    PermissionGateGallery()
        .preferredColorScheme(.dark)
}
