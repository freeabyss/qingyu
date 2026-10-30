import SwiftUI
import AppKit

/// 系统字体层级。阅读文字使用语义样式，页标题与搜索输入保持克制。
/// 视觉规范见 docs/prd/02-ui-spec.md；保持既有 API，避免各视图独立硬编码。
///
/// 语义样式统一用 `Font.<style>.weight(_:)`（macOS 11 起可用），
/// 而非 `Font.system(_:design:weight:)`（macOS 13 起可用），以维持 macOS 12 支持。
public enum JadeFont {

    /// 全局字号缩放因子：默认 1。
    ///
    /// 设计 token 里大量使用固定字号（Font.system(size:)）——它们不随系统字号变化，
    /// 这是为了版式稳定；代价是「放大字号」这种可访问性诉求无从验证。
    /// --uitest-large-text 会把它设为 1.35，用来真实检验放大字号下布局是否还站得住
    /// （此前该参数只被解析、从未生效，对应的 UI 测试等于在跑同样字号）。
    public static var scale: CGFloat = 1

    /// 固定字号统一乘以缩放因子。
    private static func scaled(_ size: CGFloat) -> CGFloat { size * scale }


    /// 启动页 / Onboarding 大 logo:32pt semibold（固定,装饰性）
    public static var display: Font { .system(size: scaled(32), weight: .semibold) }

    /// 窗口标题:26pt semibold（固定）
    public static var title1: Font { .system(size: scaled(26), weight: .semibold) }

    /// section 大标题:≈22pt semibold（随 title 缩放）
    public static let title2 = Font.title.weight(.semibold)

    /// 卡片标题 / 结果首行:≈17pt semibold（随 title2 缩放）
    public static let title3 = Font.title2.weight(.semibold)

    /// 小节标题（设置卡片外标题 / 分组标题）:≈13pt semibold（随 headline 缩放）
    public static let headline = Font.headline.weight(.semibold)

    /// 主阅读正文:≈13pt regular（随 body 缩放,PRD §9.8 到 15pt）
    public static let body = Font.body.weight(.regular)

    /// 辅助说明:≈12pt regular（随 callout 缩放）
    public static let callout = Font.callout.weight(.regular)

    /// 工具图标 / 快捷键提示：≈12pt medium（随 callout 缩放），与 AppKit appKitCalloutMedium 对应。
    public static let calloutMedium = Font.callout.weight(.medium)

    /// 独立图标按钮：14pt medium（固定），用于 30pt 命中区的单图标按钮（标注 IconButton、截图紧凑工具条）。
    public static var toolbarIcon: Font { .system(size: scaled(14), weight: .medium) }

    /// 带标签图标按钮：15pt medium（固定），用于截图预览工具条图标加 caption 标签的竖排单元格，与 30pt 独立图标按钮区分。
    public static var toolbarIconLabeled: Font { .system(size: scaled(15), weight: .medium) }

    /// 副标题 / 元信息 / breadcrumb:≈11pt medium（随 subheadline 缩放）
    public static let subhead = Font.subheadline.weight(.medium)

    /// 快捷键提示 / 徽章 / tab 计数:≈10pt medium（随 caption 缩放）
    public static let caption = Font.caption.weight(.medium)

    /// 全幅占位插图：40pt regular（固定），用于空态、禁用、不可用与权限引导的大图标，颜色仍由各处自定。
    public static var placeholderIcon: Font { .system(size: scaled(40), weight: .regular) }

    /// 命令栏输入框:19pt regular（固定,配合 48px 输入行高）
    /// 清除 / 关闭图标：18pt regular（固定），用于 xmark.circle.fill 清除与关闭按钮（命令栏、剪贴板搜索、详情最大化关闭），颜色仍由各处自定。
    public static var dismissIcon: Font { .system(size: scaled(18), weight: .regular) }

    /// 文件元信息值：12pt 等宽（固定），用于文件路径、大小、类型等文件系统值的展示，与正文区分，颜色仍由各处自定。
    public static var fileValueMono: Font { .system(size: scaled(12), design: .monospaced) }

    /// 小尺寸图标：12pt semibold（固定），用于 12pt 级小图标，保证小字号下笔画可辨，颜色仍由各处自定。
    public static var smallIconSemibold: Font { .system(size: scaled(12), weight: .semibold) }

    /// 预览纯文本正文：14pt 等宽（固定），用于预览面板纯文本内容的可选文本展示，与 12pt 等宽的文件元信息值区分。
    public static var previewTextMono: Font { .system(size: scaled(14), design: .monospaced) }

    /// 命令栏结果贴片图标：15pt semibold（固定），用于 32x32 结果贴片内的符号图标，与 15pt medium 的 toolbarIconLabeled 区分，颜色仍由各处自定。
    public static var resultTileIcon: Font { .system(size: scaled(15), weight: .semibold) }

    /// 设置侧栏图标：14pt medium（固定），用于设置侧栏 18x18 图标，与 30pt 命中区的 toolbarIcon 区分，颜色仍由各处自定。
    public static var settingsSidebarIcon: Font { .system(size: scaled(14), weight: .medium) }

    /// 设置页首图标：18pt semibold（固定），用于设置页首 28x28 标题辅助图标，颜色仍由各处自定。
    public static var settingsHeaderIcon: Font { .system(size: scaled(18), weight: .semibold) }

    /// 引导页首 Logo 图标：28pt light（固定），用于引导页首 56x56 叶形图标贴片，颜色仍由各处自定。
    public static var onboardingLogoIcon: Font { .system(size: scaled(28), weight: .light) }

    /// 引导卡片标签图标：18pt medium（固定），用于引导卡片标签 24 宽图标，与 18pt semibold 的 settingsHeaderIcon 和 18pt regular 的 dismissIcon 区分，颜色仍由各处自定。
    public static var onboardingCardIcon: Font { .system(size: scaled(18), weight: .medium) }

    /// 命令栏无结果图标：30pt regular（固定），用于命令栏无结果状态的 questionmark.circle 图标，与 40pt 的 placeholderIcon 及详情 32/36pt 占位图标区分，颜色仍由各处自定。
    public static var commandBarNoResultsIcon: Font { .system(size: scaled(30), weight: .regular) }

    /// 详情空态图标：32pt regular（固定），用于详情页空态占位 doc.on.clipboard 图标，颜色仍由各处自定。
    public static var detailEmptyIcon: Font { .system(size: scaled(32), weight: .regular) }

    /// 详情缺图图标：36pt regular（固定），用于详情页缺图占位 photo.badge.exclamationmark 图标，与 32pt 空态图标区分，颜色仍由各处自定。
    public static var detailMissingImageIcon: Font { .system(size: scaled(36), weight: .regular) }

    public static var commandBarInput: Font { .system(size: scaled(19), weight: .regular) }

    /// 剪贴板历史搜索框：15pt regular（固定）。
    ///
    /// 命令栏的 19pt 输入是「聚光灯式」面板的主角，那是刻意的；但把它照搬到
    /// 860pt 宽的历史窗口里，输入框比同屏的胶囊（10pt）和列表行（13pt）大出一整档，
    /// 层级被反转——输入框看起来像窗口标题，真正的内容退成了注释。
    public static let searchFieldPointSize: CGFloat = 15
    public static var searchField: Font { .system(size: scaled(searchFieldPointSize), weight: .regular) }
}

// MARK: - AppKit bridge

/// AppKit 叠层文字与 SwiftUI Jade 字阶一一对应：叠层用 NSView/NSAttributedString
/// 绘制，无法直接用 SwiftUI Font，之前各处各自硬编码字号，甚至出现低于
/// Jade 最小字阶 caption（10pt）的 9pt 工具条标签。桥接常量锁死字号，
/// 让叠层文字随 Jade 字阶一起审查，不再悄悄漂移。
extension JadeFont {
    /// 工具条字段标签：对应 JadeFont.caption（10pt medium）。
    public static let appKitCaptionMedium = NSFont.systemFont(ofSize: 10, weight: .medium)
    /// 预设选择器与内联提示：对应 JadeFont.callout（12pt regular）。
    public static let appKitCallout = NSFont.systemFont(ofSize: 12)
    /// 快捷键提示胶囊：对应 callout 字号、medium 字重。
    public static let appKitCalloutMedium = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// 选区尺寸标注：对应 JadeFont.subhead（11pt medium）。
    public static let appKitSubheadMedium = NSFont.systemFont(ofSize: 11, weight: .medium)
}

// MARK: - Preview

#Preview("JadeFont") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("display · 32 semibold").font(JadeFont.display)
                Text("title1 · 26 semibold").font(JadeFont.title1)
                Text("title2 · 22 semibold").font(JadeFont.title2)
                Text("title3 · 17 semibold").font(JadeFont.title3)
                Text("body · 13 regular").font(JadeFont.body)
                Text("callout · 12 regular").font(JadeFont.callout)
                Text("calloutMedium · 12 medium").font(JadeFont.calloutMedium)
                Text("toolbarIcon · 14 medium").font(JadeFont.toolbarIcon)
                Text("toolbarIconLabeled · 15 medium").font(JadeFont.toolbarIconLabeled)
                Text("subhead · 11 medium").font(JadeFont.subhead)
                Text("caption · 10 medium").font(JadeFont.caption)
                Text("placeholderIcon · 40 regular").font(JadeFont.placeholderIcon)
                Text("dismissIcon · 18 regular").font(JadeFont.dismissIcon)
                Text("fileValueMono · 12 monospaced").font(JadeFont.fileValueMono)
                Text("smallIconSemibold · 12 semibold").font(JadeFont.smallIconSemibold)
                Text("previewTextMono · 14 monospaced").font(JadeFont.previewTextMono)
                Text("resultTileIcon · 15 semibold").font(JadeFont.resultTileIcon)
                Text("settingsSidebarIcon · 14 medium").font(JadeFont.settingsSidebarIcon)
                Text("settingsHeaderIcon · 18 semibold").font(JadeFont.settingsHeaderIcon)
                Text("onboardingLogoIcon · 28 light").font(JadeFont.onboardingLogoIcon)
                Text("onboardingCardIcon · 18 medium").font(JadeFont.onboardingCardIcon)
                Text("commandBarNoResultsIcon · 30 regular").font(JadeFont.commandBarNoResultsIcon)
                Text("detailEmptyIcon · 32 regular").font(JadeFont.detailEmptyIcon)
                Text("detailMissingImageIcon · 36 regular").font(JadeFont.detailMissingImageIcon)
                Text("commandBarInput · 19 regular").font(JadeFont.commandBarInput)
            }
            .foregroundStyle(JadeColor.textPrimary)
        }
        .padding(JadeSpace.x6.value)
    }
    .frame(width: 360, height: 420)
}
