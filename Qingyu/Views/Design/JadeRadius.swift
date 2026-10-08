import SwiftUI

/// 圆角 Design Token。契约来源：PRD §9.2.3。
///
/// 所有圆角统一使用 `.continuous`（苹果连续曲率），不使用直角矩形圆角。
public enum JadeRadius: CGFloat, CaseIterable {
    /// 小徽章 / 小按钮
    case sm = 6
    /// 按钮 / 输入框 / chip
    case md = 8
    /// 卡片 / 行项
    case lg = 10
    /// 窗口 / panel
    case xl = 12
    /// command bar / overlay pill（PRD radius-2xl）
    case xxl = 16

    /// 圆角数值（point）
    public var value: CGFloat { rawValue }

    /// 对应的连续曲率 `RoundedRectangle` 形状。
    public var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: value, style: .continuous)
    }
}

// MARK: - View 扩展

extension View {
    /// 以指定 token 裁剪为连续曲率圆角。
    ///
    /// ```swift
    /// SomeView().jadeRadius(.lg)
    /// ```
    public func jadeRadius(_ radius: JadeRadius) -> some View {
        clipShape(radius.shape)
    }

    /// 以指定 token 描边（连续曲率）。
    public func jadeRadiusBorder(_ radius: JadeRadius,
                                 color: Color = JadeColor.border,
                                 lineWidth: CGFloat = 1) -> some View {
        overlay(radius.shape.strokeBorder(color, lineWidth: lineWidth))
    }
}

// MARK: - Preview

#Preview("JadeRadius") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(JadeRadius.allCases, id: \.rawValue) { r in
            HStack(spacing: 12) {
                JadeColor.jade500
                    .frame(width: 80, height: 48)
                    .jadeRadius(r)
                Text(".\(String(describing: r)) = \(Int(r.value))pt")
                    .font(.system(size: 13))
                    .foregroundStyle(JadeColor.textSecondary)
            }
        }
    }
    .padding(24)
    .frame(width: 280)
}
