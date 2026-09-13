import SwiftUI

/// 字体 Design Token（SF Pro / 系统字体）。契约来源：PRD §9.2.5。
///
/// PRD §9.8 要求正文类字号跟随系统「字体大小」设置动态缩放（body 支持到 15pt）。
/// SwiftUI 的 `Font.system(size:)` 是固定字号、**不**参与 Dynamic Type；而语义
/// `Font.system(_:design:weight:)`（`.body` / `.headline` …）会随系统字体大小缩放。
///
/// macOS 各语义 TextStyle 的默认点值恰好与多数 Jade 字号一一对应
/// （headline/body=13、callout=12、subheadline=11、caption=10、title2=17、title=22），
/// 因此正文/说明/徽章/卡片标题等**阅读文本**改用语义字体：默认档位尺寸不变、
/// 放大系统字号时等比缩放，避免大字号破版。
///
/// 大号 logo（display 40）、窗口大标题（title1 28）、命令栏输入（20，固定 48px 行高）
/// 保持固定字号，以免缩放时破坏既有版式（PRD「不 redesign UI」）。
public enum JadeFont {

    /// 启动页 / Onboarding 大 logo:40pt bold（固定,装饰性）
    public static let display = Font.system(size: 40, weight: .bold)

    /// 窗口标题:28pt semibold（固定）
    public static let title1 = Font.system(size: 28, weight: .semibold)

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

    /// 命令栏输入框:20pt regular（固定,配合 48px 输入行高）
    public static let commandBarInput = Font.system(size: 20, weight: .regular)
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
