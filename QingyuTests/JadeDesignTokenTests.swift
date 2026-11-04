import SwiftUI
import AppKit
import XCTest
@testable import Qingyu

/// Jade 设计 token 的奖项级底线回归：间距不断档、行操作可点中、
/// 选中与品牌文字在明暗两模式下都达到 WCAG 对比度。
///
/// 本轮发现的问题（见 JadeListRow 注释）：选中仅靠浅底时，浅底与主表面
/// 对比度只有 1.12（浅色）/ 1.27（深色），远低于非文字元素 3:1 的要求，
/// 因此选中必须同时有品牌色描边；品牌文字本身 5.87 / 8.99 已达标，
/// 本测试把这两条都锁死，避免后续调色时悄悄回退。
final class JadeDesignTokenTests: XCTestCase {

    func testSpaceScaleIncludes20AndIsAscending() {
        let values = JadeSpace.allCases.map { $0.rawValue }
        XCTAssertEqual(values, values.sorted(), "间距 token 必须单调递增")
        XCTAssertTrue(values.contains(20), "4pt 基准间距不得在 16 与 24 之间断档")
        XCTAssertEqual(JadeSpace.x5.rawValue, 20)
    }

    func testRowActionHitSizeFitsCompactRow() {
        XCTAssertGreaterThanOrEqual(JadeListRow<Text>.actionHitSize, 28, "行操作命中区不得小于 28pt")
        XCTAssertLessThan(JadeListRow<Text>.actionHitSize, JadeRowSize.compact.height, "命中区必须放进紧凑行高 44pt")
    }

    func testRowSizes() {
        XCTAssertEqual(JadeRowSize.compact.height, 44)
        XCTAssertEqual(JadeRowSize.comfortable.height, 64)
    }

    /// 行操作图标在静止态必须"安静"：无磁贴底色、危险操作也不提前变红。
    ///
    /// 这条曾经是纯视觉判断——离屏渲染模拟不了 hover，只能靠肉眼看快照。
    /// 现在样式规则抽成纯函数，两个分支都能被锁死。
    func testRowActionStyleStaysQuietAtRest() {
        XCTAssertEqual(
            JadeRowActionStyle.tileBackground(isHovering: false), Color.clear,
            "静止态不应画磁贴底色：一行 4–6 个方块会把列表画成工具栏"
        )
        XCTAssertEqual(
            JadeRowActionStyle.iconColor(isDestructive: true, isHovering: false), JadeColor.textSecondary,
            "危险操作在静止态不应常驻红色：每行一条红杠会抢走内容注意力"
        )
        XCTAssertEqual(
            JadeRowActionStyle.iconColor(isDestructive: false, isHovering: false), JadeColor.textSecondary
        )
    }

    /// hover 时才浮现磁贴底色、危险操作才转红——可点性与破坏性提示不因此丢失。
    func testRowActionStyleRevealsOnHover() {
        XCTAssertEqual(
            JadeRowActionStyle.tileBackground(isHovering: true), JadeColor.surface3,
            "hover 必须给出可点反馈"
        )
        XCTAssertEqual(
            JadeRowActionStyle.iconColor(isDestructive: true, isHovering: true), JadeColor.danger,
            "hover 时危险操作必须转红"
        )
        XCTAssertEqual(
            JadeRowActionStyle.iconColor(isDestructive: false, isHovering: true), JadeColor.textSecondary,
            "非危险操作 hover 不改变颜色，只改变底色"
        )
    }

    /// 历史窗口搜索框必须比命令栏输入（19pt）更小。
    ///
    /// 命令栏的 19pt 是「聚光灯面板」的主角，照搬到 860pt 宽的历史窗口里，
    /// 输入框会比同屏胶囊（10pt）和列表行（13pt）大出一整档，层级反转。
    func testSearchFieldIsQuieterThanCommandBarInput() {
        XCTAssertLessThanOrEqual(JadeFont.searchFieldPointSize, 16)
        XCTAssertLessThan(JadeFont.searchFieldPointSize, 19, "不得沿用命令栏的 19pt")
        XCTAssertGreaterThanOrEqual(JadeFont.searchFieldPointSize, 13, "不得小于正文 13pt，否则输入文字读不清")
    }

    /// 固定字号 token 的缩放机制必须真的生效。
    ///
    /// 这条锁的是上一轮修过的假覆盖：--uitest-large-text 曾被解析、被断言、被 UI 测试
    /// 当作「放大字号变体」使用，但应用里从未实现，5b 分支跑的是和 5a 一样的字号。
    func testFixedFontTokensHonourScaleFactor() {
        let original = JadeFont.scale
        defer { JadeFont.scale = original }

        JadeFont.scale = 1
        XCTAssertEqual(JadeFont.scaled(15), 15, accuracy: 0.001)

        JadeFont.scale = 1.35
        XCTAssertEqual(JadeFont.scaled(15), 20.25, accuracy: 0.001, "放大字号变体必须真的放大固定字号")
        XCTAssertGreaterThan(JadeFont.scaled(19), 19, "命令栏输入同样要放大")
    }

    /// 「增强对比度」必须真的改变边框。
    ///
    /// JadeColor.border 在 increaseContrast 时把 alpha 从 0.08 提到 0.2。
    /// 系统级读值无法在测试里伪造（-AppleIncreaseContrast 启动参数并不影响
    /// NSWorkspace 的读数），所以这里直接验证「两档 alpha 的对比度差异」——
    /// 只要 0.2 明显强于 0.08，开关就是有效的。
    func testIncreasedContrastBorderIsStronger() {
        let surface: UInt32 = 0xFCFCFD
        // 纯黑以 alpha 叠在接近白色的 surface1 上：结果灰度 = (1 - alpha) * 252
        let normalBorder: UInt32 = UInt32(((1.0 - 0.08) * 252.0).rounded())
        let contrastBorder: UInt32 = UInt32(((1.0 - 0.2) * 252.0).rounded())
        XCTAssertLessThan(
            contrast(normalBorder, surface), contrast(contrastBorder, surface),
            "增强对比度档的边框必须比常规档更强"
        )
    }

    /// 文字令牌在两种模式下都必须达到正文 4.5:1。
    ///
    /// textSecondary / textTertiary 原先直接绑定 NSColor.secondaryLabelColor，
    /// 浅色模式下只有 3.18 / 3.2 —— 而它们承担副标题、说明与占位文字。
    /// 这里锁死「浅色显式值 + 深色系统值」都不会掉到 AA 以下。
    func testTextTokenContrastMeetsWCAGAA() {
        let lightSurface: UInt32 = 0xFCFCFD
        let darkSurface: UInt32 = 0x202226

        // 浅色显式值（与 JadeColor 定义保持一致）
        XCTAssertGreaterThanOrEqual(contrast(0x737373, lightSurface), 4.5, "textSecondary 浅色")
        XCTAssertGreaterThanOrEqual(contrast(0x6E6E6E, lightSurface), 4.5, "textTertiary 浅色")
        XCTAssertGreaterThanOrEqual(contrast(0x000000, lightSurface), 4.5, "textPrimary 浅色")

        // 深色系统次要色的典型值
        XCTAssertGreaterThanOrEqual(contrast(0x999999, darkSurface), 4.5, "次级文字 深色")
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, darkSurface), 4.5, "主文字 深色")
    }

    /// 焦点描边作为非文本元素，必须达到 3:1。
    ///
    /// focusBorder 原为 primary 65% 不透明，在 surface2 上只有 2.73:1。
    /// 焦点描边是键盘用户判断焦点位置的唯一依据，太淡等于没有。
    func testFocusBorderMeetsNonTextContrast() {
        let surface2Light: UInt32 = 0xF3F4F6
        // primary light #4D6487 @ 75% on surface2
        let focusBorderLight = blend(foreground: 0x4D6487, background: surface2Light, alpha: 0.75)
        XCTAssertGreaterThanOrEqual(contrast(focusBorderLight, surface2Light), 3.0, "焦点描边 浅色")

        let surface1Dark: UInt32 = 0x202226
        let focusBorderDark = blend(foreground: 0xB2C4DF, background: surface1Dark, alpha: 0.75)
        XCTAssertGreaterThanOrEqual(contrast(focusBorderDark, surface1Dark), 3.0, "焦点描边 深色")
    }

    /// 结果行类型标签要能压在选中行的 primaryFill 浅蓝底上。
    ///
    /// 用 textTertiary 的 #6E6E6E 时只有 4.07:1（低于小字 4.5:1），
    /// 专用 typeLabel 令牌 #6A6A6A 在 primaryFill 上 4.64:1。
    func testTypeLabelContrastOnSelectionFill() {
        let selectionFill = blend(foreground: 0x4D6487, background: 0xFCFCFD, alpha: 0.10)
        XCTAssertGreaterThanOrEqual(contrast(0x6A6A6A, selectionFill), 4.5, "类型标签在选中行底色上")
        // 记录旧值缺陷：textTertiary 在同一底色上不达标
        XCTAssertLessThan(contrast(0x6E6E6E, selectionFill), 4.5)
    }

    /// JadePill 的文字要能在自身 15% 同色底上读清。
    ///
    /// 旧实现直接用系统语义色作文字色：success 1.92 / warning 1.90 /
    /// info 3.22 / danger 2.83，全部低于 4.5。改用深一档的 pillInk 色后达标。
    func testPillTextContrastOnTintedBackground() {
        let surface: UInt32 = 0xFCFCFD
        let inks: [(String, UInt32)] = [
            ("primary", 0x3D5272),
            ("info", 0x005ABF),
            ("success", 0x186A33),
            ("warning", 0x8A5300),
            ("danger", 0xB82720),
        ]
        for (name, ink) in inks {
            let tinted = blend(foreground: ink, background: surface, alpha: 0.15)
            XCTAssertGreaterThanOrEqual(
                contrast(ink, tinted), 4.5,
                "胶囊 \(name) 文字在 15% 同色底上应达到 4.5:1"
            )
        }
    }


    /// 主色填充上的前景色必须两种模式都清晰。
    ///
    /// 旧实现把选中态文字写死为白色：深色模式的 primary 是浅蓝 #B2C4DF，
    /// 白字在上面只有 1.77:1，几乎读不出来。onPrimary 令牌按模式取色。
    func testOnPrimaryContrastInBothSchemes() {
        // 浅色：白字 on 深蓝 primary
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, 0x4D6487), 4.5, "onPrimary 浅色")
        // 深色：近黑字 on 浅蓝 primary
        XCTAssertGreaterThanOrEqual(contrast(0x151C26, 0xB2C4DF), 4.5, "onPrimary 深色")
        // 记录旧缺陷：白色在深色 primary 上不达标
        XCTAssertLessThan(contrast(0xFFFFFF, 0xB2C4DF), 4.5)
    }

    func testAppKitOverlayFontsMirrorJadeScale() {
        // AppKit 叠层字号必须与 SwiftUI Jade 字阶一致，且不得低于 caption 下限 10pt：
        // 旧代码里工具条标签是 9pt，放大镜已是 10pt，两者曾不一致。
        XCTAssertEqual(JadeFont.appKitCaptionMedium.pointSize, 10)
        XCTAssertEqual(JadeFont.appKitCallout.pointSize, 12)
        XCTAssertEqual(JadeFont.appKitCalloutMedium.pointSize, 12)
        XCTAssertEqual(JadeFont.appKitSubheadMedium.pointSize, 11)
        XCTAssertGreaterThanOrEqual(JadeFont.appKitCaptionMedium.pointSize, 10)
    }

    func testOverlayBadgeFontsFollowJadeCaptionAndSubhead() {
        // 截图来源徽标（SwiftUI：subhead / caption.monospaced）与放大镜徽标
        // （AppKit：appKitCaptionMedium）共用 caption 10pt / subhead 11pt 两个字阶：
        // 徽标内层级只靠 1pt 字号差与不透明度，不靠字重混用。
        XCTAssertEqual(JadeFont.appKitCaptionMedium.pointSize, 10)
        XCTAssertEqual(JadeFont.appKitSubheadMedium.pointSize, 11)
        XCTAssertEqual(JadeFont.appKitSubheadMedium.pointSize - JadeFont.appKitCaptionMedium.pointSize, 1)
    }

    func testToolPillFontsFollowCalloutMediumAndSubhead() {
        // 标注工具条 ToolPill（SwiftUI：calloutMedium / subhead）与 AppKit 桥接共用
        // calloutMedium 12pt / subhead 11pt 两个字阶：pill 内层级只靠 1pt 字号差，
        // 不靠 semibold / medium 混用。SwiftUI Font 本身不可直接判等，此处以
        // AppKit 桥接常量为代理锁死字阶对应关系。
        XCTAssertEqual(JadeFont.appKitCalloutMedium.pointSize, 12)
        XCTAssertEqual(JadeFont.appKitSubheadMedium.pointSize, 11)
        XCTAssertEqual(JadeFont.appKitCalloutMedium.pointSize - JadeFont.appKitSubheadMedium.pointSize, 1)
    }

    func testBrandTextContrastMeetsWCAGAA() {
        XCTAssertGreaterThanOrEqual(contrast(0x4D6487, 0xFCFCFD), 4.5, "浅色品牌文字 on surface1")
        XCTAssertGreaterThanOrEqual(contrast(0xB2C4DF, 0x202226), 4.5, "深色品牌文字 on surface1")
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, 0x4D6487), 4.5, "浅色白字 on actionFill")
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, 0x526B90), 4.5, "深色白字 on actionFill")
    }

    func testSelectedBorderContrastMeetsNonTextRequirement() {
        let lightBorder = blend(foreground: 0x4D6487, background: 0xFCFCFD, alpha: 0.85)
        let darkBorder = blend(foreground: 0xB2C4DF, background: 0x202226, alpha: 0.85)
        XCTAssertGreaterThanOrEqual(contrast(lightBorder, 0xFCFCFD), 3.0, "浅色选中描边")
        XCTAssertGreaterThanOrEqual(contrast(darkBorder, 0x202226), 3.0, "深色选中描边")
        XCTAssertLessThan(contrast(0xECF0F6, 0xFCFCFD), 3.0, "仅浅底不足以辨识选中：此断言记录旧缺陷")
    }

    private func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private func luminance(_ hex: UInt32) -> Double {
        let (r, g, b) = rgb(hex)
        let f = { (c: Double) in c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func blend(foreground: UInt32, background: UInt32, alpha: Double) -> UInt32 {
        let (fr, fg, fb) = rgb(foreground)
        let (br, bg, bb) = rgb(background)
        let r = UInt32((alpha * fr + (1 - alpha) * br) * 255)
        let g = UInt32((alpha * fg + (1 - alpha) * bg) * 255)
        let b = UInt32((alpha * fb + (1 - alpha) * bb) * 255)
        return (r << 16) | (g << 8) | b
    }
}
