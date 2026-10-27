import SwiftUI
import AppKit

/// 系统字体层级。阅读文字使用语义样式，页标题与搜索输入保持克制。
/// 视觉规范见 docs/prd/02-ui-spec.md；保持既有 API，避免各视图独立硬编码。
///
/// 语义样式统一用 `Font.<style>.weight(_:)`（macOS 11 起可用），
/// 而非 `Font.system(_:design:weight:)`（macOS 13 起可用），以维持 macOS 12 支持。
public enum JadeFont {

    /// 启动页 / Onboarding 大 logo:32pt semibold（固定,装饰性）
    public static let display = Font.system(size: 32, weight: .semibold)

    /// 窗口标题:26pt semibold（固定）
    public static let title1 = Font.system(size: 26, weight: .semibold)

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
    public static let toolbarIcon = Font.system(size: 14, weight: .medium)

    /// 带标签图标按钮：15pt medium（固定），用于截图预览工具条图标加 caption 标签的竖排单元格，与 30pt 独立图标按钮区分。
    public static let toolbarIconLabeled = Font.system(size: 15, weight: .medium)

    /// 副标题 / 元信息 / breadcrumb:≈11pt medium（随 subheadline 缩放）
    public static let subhead = Font.subheadline.weight(.medium)

    /// 快捷键提示 / 徽章 / tab 计数:≈10pt medium（随 caption 缩放）
    public static let caption = Font.caption.weight(.medium)

    /// 命令栏输入框:19pt regular（固定,配合 48px 输入行高）
    public static let commandBarInput = Font.system(size: 19, weight: .regular)
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
                Text("commandBarInput · 19 regular").font(JadeFont.commandBarInput)
            }
            .foregroundStyle(JadeColor.textPrimary)
        }
        .padding(24)
    }
    .frame(width: 360, height: 420)
}
