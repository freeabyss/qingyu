import SwiftUI

/// 系统字体层级。阅读文字使用语义样式，页标题与搜索输入保持克制。
/// 视觉规范见 docs/prd/02-ui-spec.md；保持既有 API，避免各视图独立硬编码。
public enum JadeFont {

    /// 启动页 / Onboarding 大 logo:32pt semibold（固定,装饰性）
    public static let display = Font.system(size: 32, weight: .semibold)

    /// 窗口标题:26pt semibold（固定）
    public static let title1 = Font.system(size: 26, weight: .semibold)

    /// section 大标题:≈22pt semibold（随 title 缩放）
    public static let title2 = Font.system(.title, design: .default, weight: .semibold)

    /// 卡片标题 / 结果首行:≈17pt semibold（随 title2 缩放）
    public static let title3 = Font.system(.title2, design: .default, weight: .semibold)

    /// 小节标题（设置卡片外标题 / 分组标题）:≈13pt semibold（随 headline 缩放）
    public static let headline = Font.system(.headline, design: .default, weight: .semibold)

    /// 主阅读正文:≈13pt regular（随 body 缩放,PRD §9.8 到 15pt）
    public static let body = Font.system(.body, design: .default, weight: .regular)

    /// 辅助说明:≈12pt regular（随 callout 缩放）
    public static let callout = Font.system(.callout, design: .default, weight: .regular)

    /// 副标题 / 元信息 / breadcrumb:≈11pt medium（随 subheadline 缩放）
    public static let subhead = Font.system(.subheadline, design: .default, weight: .medium)

    /// 快捷键提示 / 徽章 / tab 计数:≈10pt medium（随 caption 缩放）
    public static let caption = Font.system(.caption, design: .default, weight: .medium)

    /// 命令栏输入框:19pt regular（固定,配合 48px 输入行高）
    public static let commandBarInput = Font.system(size: 19, weight: .regular)
}

// MARK: - Preview

#Preview("JadeFont") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("display · 40 bold").font(JadeFont.display)
                Text("title1 · 28 semibold").font(JadeFont.title1)
                Text("title2 · 22 semibold").font(JadeFont.title2)
                Text("title3 · 17 semibold").font(JadeFont.title3)
                Text("body · 13 regular").font(JadeFont.body)
                Text("callout · 12 regular").font(JadeFont.callout)
                Text("subhead · 11 medium").font(JadeFont.subhead)
                Text("caption · 10 medium").font(JadeFont.caption)
                Text("commandBarInput · 20 regular").font(JadeFont.commandBarInput)
            }
            .foregroundStyle(JadeColor.textPrimary)
        }
        .padding(24)
    }
    .frame(width: 360, height: 420)
}
