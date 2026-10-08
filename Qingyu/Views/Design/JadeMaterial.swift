import SwiftUI

/// 材质 Design Token。契约来源：PRD §9.2.7。
///
/// - Command Bar：`.ultraThinMaterial`（HUD 毛玻璃）
/// - 工具条 / pill：`.ultraThinMaterial`
/// - Sheet / 弹窗：`.thinMaterial`
/// - 管理窗口：默认 `windowBackground`，此处不封装
/// - 全屏遮罩：见 `JadeColor.overlay`
public enum JadeMaterial: CaseIterable {
    /// 命令栏
    case commandBar
    /// 工具条 / pill
    case pill
    /// Sheet / 弹窗
    case sheet

    /// 映射到 SwiftUI `Material`。
    public var material: Material {
        switch self {
        case .commandBar: return .ultraThinMaterial
        case .pill: return .ultraThinMaterial
        case .sheet: return .thinMaterial
        }
    }
}

// MARK: - View 扩展

extension View {
    /// 以指定材质 token 作为背景，并按 token 圆角裁剪。
    ///
    /// ```swift
    /// commandBar.jadeMaterial(.commandBar, radius: .xxl)
    /// ```
    public func jadeMaterial(_ material: JadeMaterial,
                             radius: JadeRadius? = nil) -> some View {
        modifier(JadeMaterialModifier(material: material, radius: radius))
    }

    /// Window chrome: the solid `surface1` panel surface.
    @ViewBuilder
    func jadeWindowSurface(radius: JadeRadius? = nil) -> some View {
        if let radius {
            background(JadeColor.surface1, in: radius.shape)
        } else {
            background(JadeColor.surface1)
        }
    }
}

private struct JadeMaterialModifier: ViewModifier {
    let material: JadeMaterial
    let radius: JadeRadius?

    func body(content: Content) -> some View {
        if let radius {
            content.background(material.material, in: radius.shape)
        } else {
            content.background(material.material)
        }
    }
}

// MARK: - Preview

#Preview("JadeMaterial") {
    ZStack {
        LinearGradient(
            colors: [JadeColor.jade500, JadeColor.jade600],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            ForEach(JadeMaterial.allCases, id: \.self) { m in
                Text(String(describing: m))
                    .font(JadeFont.title3)
                    .foregroundStyle(JadeColor.textPrimary)
                    .frame(width: 200, height: 56)
                    .jadeMaterial(m, radius: .xl)
            }
        }
    }
    .frame(width: 300, height: 320)
}
