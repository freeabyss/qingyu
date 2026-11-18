import SwiftUI
import AppKit

/// 玻璃设计语言令牌（方向三 · Liquid Glass 取向）。
///
/// **两条渲染路径**（`jadeGlassSurface` 内部自动选择，调用方无感知）：
/// - macOS 26+：系统级 Liquid Glass（`NSGlassEffectView`）。折射、明暗适配、边缘高光、
///   文字可读性全部由系统实时处理，`liquidTint*` 只负责把玻璃染向品牌色相（低透明度）。
/// - macOS 12–25：`NSVisualEffectView(.hudWindow)` + `tint` 叠加层回退。
///   **为什么回退路径必须自带叠加层**：真实窗口背后是桌面内容（可能是纯白网页，也可能是
///   深色编辑器），不像设计稿里的固定彩色壁纸。只靠材质模糊，白字压在浅色桌面上会读不出来；
///   旧系统没有自适应玻璃，可读性只能由 `tint` 保证（深 0.62 / 浅 0.60）。
///
/// **历史教训（0.4.211 修复）**：曾把回退思路原样搬到唯一路径——tint 叠到 α0.78~0.90，
/// 四个界面全部变成实心深色面板，「玻璃化」名存实亡；且离屏截图（cacheDisplay）渲染不出
/// behind-window 模糊，当时的「双外观验证」全绿却看不到真实效果。玻璃本身必须透，
/// 可读性交给系统玻璃（26+）或适度 tint（回退），不得再用高不透明度叠加层把材质盖死。
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

    /// 回退路径（macOS < 26）压在材质之上的叠加底色。
    /// 深色外观取深紫黑（偏冷，让材质里的蓝紫反光成立）；浅色外观取暖白（保留纸感）。
    public static let tintNS = dynamic("Tint", Pair(
        light: NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 0.60),
        dark: NSColor(srgbRed: 0.051, green: 0.027, blue: 0.110, alpha: 0.62)
    ))
    public static let tint = Color(tintNS)

    /// 回退路径里长时阅读窗口（设置、引导）的叠加底：比 `tint` 稍不透明，
    /// 桌面内容只透出层次、不干扰正文。
    public static let tintOpaqueNS = dynamic("TintOpaque", Pair(
        light: NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 0.78),
        dark: NSColor(srgbRed: 0.051, green: 0.027, blue: 0.110, alpha: 0.74)
    ))
    public static let tintOpaque = Color(tintOpaqueNS)

    /// macOS 26+ 真·Liquid Glass 的染色：玻璃自身负责折射/明暗/可读性，
    /// 这里只把色相拉向品牌（深色偏冷紫黑、浅色偏暖白），透明度必须保持低——
    /// 一旦叠高就把系统玻璃盖死，重蹈 0.4.211 之前的覆辙。
    public static let liquidTintNS = dynamic("LiquidTint", Pair(
        light: NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 0.20),
        dark: NSColor(srgbRed: 0.051, green: 0.027, blue: 0.110, alpha: 0.18)
    ))

    /// macOS 26+ 长时阅读窗口（设置、引导、详情）的玻璃染色：同色相、略深一档。
    public static let liquidReadingTintNS = dynamic("LiquidReadingTint", Pair(
        light: NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 0.38),
        dark: NSColor(srgbRed: 0.051, green: 0.027, blue: 0.110, alpha: 0.32)
    ))


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

    /// 设置卡片底：叠在玻璃之上的一层半透明浮层，比窗口 `tint` 亮/深一档，
    /// 表达「这是从面板上抬起来的内容组」。替换旧的不透明 `settingsCard`。
    public static let cardFill = Color(dynamic("CardFill", Pair(
        light: NSColor(white: 1, alpha: 0.55),
        dark: NSColor(white: 1, alpha: 0.08)
    )))


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

/// 玻璃面板的用途，决定染色的深浅：标准浮层 vs 长时阅读窗口（设置、引导、详情）。
public enum JadeGlassTintKind {
    case standard
    case reading
}

/// `jadeGlassSurface` 当前实际使用的渲染后端。
/// 暴露出来是为了让测试能锁死「macOS 26+ 必须走真玻璃」这条契约，
/// 防止后续改动悄悄退回材质叠加层路径。
public enum JadeGlassSurfaceBackend: String, Equatable {
    case liquidGlass
    case materialFallback

    public static var current: JadeGlassSurfaceBackend {
        if #available(macOS 26.0, *) {
            return .liquidGlass
        }
        return .materialFallback
    }
}

extension View {

    /// 铺玻璃面板：macOS 26+ 走系统 Liquid Glass（`NSGlassEffectView`），
    /// 旧系统回退到「材质 + 叠加底 + 圆角裁剪」。
    /// 长时阅读窗口传 `tint: .reading`，玻璃略深一档以稳住正文。
    public func jadeGlassSurface(radius: JadeRadius? = nil, tint kind: JadeGlassTintKind = .standard) -> some View {
        modifier(JadeGlassSurfaceModifier(radius: radius, kind: kind))
    }

    /// 玻璃面板描边：1pt 外描边 + 顶部内高光。
    /// macOS 26+ 为 no-op：系统玻璃自带边缘高光，再叠一层就是双描边。
    public func jadeGlassEdge(radius: JadeRadius, lineWidth: CGFloat = 1) -> some View {
        modifier(JadeGlassEdgeModifier(radius: radius, lineWidth: lineWidth))
    }
}

private struct JadeGlassSurfaceModifier: ViewModifier {
    let radius: JadeRadius?
    let kind: JadeGlassTintKind

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background(
                LiquidGlassView(
                    cornerRadius: radius?.value ?? 0,
                    tintColor: kind == .reading ? JadeGlass.liquidReadingTintNS : JadeGlass.liquidTintNS
                )
            )
        } else {
            content.background {
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    kind == .reading ? JadeGlass.tintOpaque : JadeGlass.tint
                }
                .modifier(JadeGlassClip(radius: radius))
            }
        }
    }
}

/// macOS 26+ 系统 Liquid Glass 的 AppKit 桥接。
///
/// 作为 SwiftUI 内容的 `.background` 使用：玻璃在自身 bounds 内渲染完整效果
/// （含圆角与边缘高光），SwiftUI 内容绘制其上。`tintColor` 只染品牌色相，
/// 可读性由系统玻璃的明暗自适应处理。
@available(macOS 26.0, *)
private struct LiquidGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tintColor: NSColor

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
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
        if #available(macOS 26.0, *) {
            // 系统 Liquid Glass 自带边缘高光与描边；手工再叠会双描边。
            content
        } else {
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
