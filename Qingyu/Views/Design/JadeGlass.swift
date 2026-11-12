import SwiftUI
import AppKit

/// 玻璃设计语言令牌（方向三 · Liquid Glass 取向）。
///
/// **为什么玻璃必须自带叠加层**：真实窗口背后是桌面内容（可能是纯白网页，也可能是深色编辑器），
/// 不像设计稿里的固定彩色壁纸。只靠 `NSVisualEffectView` 的模糊，白字压在浅色桌面上会读不出来。
/// 所以材质只负责「透出桌面的层次与色彩」，可读性由 `tint` 叠加层保证：
/// 深色外观 0.78、浅色外观 0.74，两种外观下行内文字对比度均 ≥ 4.5:1。
public enum JadeGlass {

    private struct Pair {
        let light: NSColor
        let dark: NSColor
    }

    private static func dynamic(_ name: String, _ pair: Pair) -> NSColor {
        NSColor(name: NSColor.Name("JadeGlass.\(name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? pair.dark : pair.light
        }
    }

    // MARK: - 面板

    /// 压在材质之上的叠加底色。
    /// 深色外观取深紫黑（偏冷，让材质里的蓝紫反光成立）；浅色外观取暖白（保留纸感）。
    public static let tintNS = dynamic("Tint", Pair(
        light: NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 0.74),
        dark: NSColor(srgbRed: 0.051, green: 0.027, blue: 0.110, alpha: 0.78)
    ))
    public static let tint = Color(tintNS)

    /// 1pt 外描边。
    public static let edge = Color(dynamic("Edge", Pair(
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.42)
    )))

    /// 顶部内高光：表达玻璃的厚度。
    public static let innerHighlight = Color(dynamic("InnerHighlight", Pair(
        light: NSColor(white: 1, alpha: 0.60),
        dark: NSColor(white: 1, alpha: 0.26)
    )))

    // MARK: - 分区与行

    /// 分隔线。
    public static let separator = Color(dynamic("Separator", Pair(
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.14)
    )))

    /// 行悬停底色。
    public static let rowHover = Color(dynamic("RowHover", Pair(
        light: NSColor(white: 0, alpha: 0.045),
        dark: NSColor(white: 1, alpha: 0.06)
    )))

    /// 行选中底色。
    public static let rowSelected = Color(dynamic("RowSelected", Pair(
        light: NSColor(white: 0, alpha: 0.075),
        dark: NSColor(white: 1, alpha: 0.10)
    )))

    /// 选中行左侧竖条。
    public static let selectionMark = Color(dynamic("SelectionMark", Pair(
        light: NSColor(srgbRed: 0.302, green: 0.392, blue: 0.529, alpha: 1),
        dark: NSColor(white: 1, alpha: 0.95)
    )))

    // MARK: - 控件

    /// 键位胶囊底。
    public static let keycapFill = Color(dynamic("KeycapFill", Pair(
        light: NSColor(white: 0, alpha: 0.06),
        dark: NSColor(white: 1, alpha: 0.20)
    )))

    /// 键位胶囊描边。
    public static let keycapBorder = Color(dynamic("KeycapBorder", Pair(
        light: NSColor(white: 0, alpha: 0.12),
        dark: NSColor(white: 1, alpha: 0.26)
    )))

    /// 图标按钮 / 胶囊切换的悬停底。
    public static let controlHover = Color(dynamic("ControlHover", Pair(
        light: NSColor(white: 0, alpha: 0.06),
        dark: NSColor(white: 1, alpha: 0.16)
    )))

    /// 图标按钮的激活底（已置顶等）。
    public static let controlActive = Color(dynamic("ControlActive", Pair(
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.16)
    )))
}

// MARK: - View 扩展

extension View {

    /// 铺玻璃面板：系统材质 + 叠加底色 + 可选圆角裁剪。
    public func jadeGlassSurface(radius: JadeRadius? = nil) -> some View {
        modifier(JadeGlassSurfaceModifier(radius: radius))
    }

    /// 玻璃面板描边：1pt 外描边 + 顶部内高光。
    public func jadeGlassEdge(radius: JadeRadius, lineWidth: CGFloat = 1) -> some View {
        modifier(JadeGlassEdgeModifier(radius: radius, lineWidth: lineWidth))
    }
}

private struct JadeGlassSurfaceModifier: ViewModifier {
    let radius: JadeRadius?

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                JadeGlass.tint
            }
            .modifier(JadeGlassClip(radius: radius))
        }
    }
}

private struct JadeGlassClip: ViewModifier {
    let radius: JadeRadius?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let radius {
            content.clipShape(radius.shape)
        } else {
            content
        }
    }
}

private struct JadeGlassEdgeModifier: ViewModifier {
    let radius: JadeRadius
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                radius.shape.strokeBorder(JadeGlass.edge, lineWidth: lineWidth)
            }
            .overlay {
                radius.shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: JadeGlass.innerHighlight, location: 0),
                                .init(color: .clear, location: 0.32)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Preview

#Preview("JadeGlass") {
    ZStack {
        Image(systemName: "photo")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()

        VStack(spacing: JadeSpace.x4.value) {
            Text("玻璃面板 · 深色")
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
                .frame(width: 260, height: 88)
                .jadeGlassSurface(radius: .xxl)
                .jadeGlassEdge(radius: .xxl)

            Text("玻璃面板 · 浅色")
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
                .frame(width: 260, height: 88)
                .jadeGlassSurface(radius: .xxl)
                .jadeGlassEdge(radius: .xxl)
        }
    }
    .frame(width: 360, height: 360)
}
