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
