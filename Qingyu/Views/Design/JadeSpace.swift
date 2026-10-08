import SwiftUI

/// 间距 Design Token（4px 基准）。契约来源：PRD §9.2.4。
public enum JadeSpace: CGFloat, CaseIterable {
    /// 4px
    case x1 = 4
    /// 8px
    case x2 = 8
    /// 12px
    case x3 = 12
    /// 16px
    case x4 = 16
    /// 24px
    case x6 = 24
    /// 32px
    case x8 = 32

    /// 间距数值（point）
    public var value: CGFloat { rawValue }
}

// MARK: - View 扩展

extension View {
    /// 四周使用统一 token 内边距。
    ///
    /// ```swift
    /// SomeView().jadePadding(.x3)
    /// ```
    public func jadePadding(_ space: JadeSpace) -> some View {
        padding(space.value)
    }

    /// 指定边使用 token 内边距。
    public func jadePadding(_ edges: Edge.Set, _ space: JadeSpace) -> some View {
        padding(edges, space.value)
    }
}

// MARK: - Preview

#Preview("JadeSpace") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(JadeSpace.allCases, id: \.rawValue) { s in
            HStack(spacing: 12) {
                Rectangle()
                    .fill(JadeColor.jade500)
                    .frame(width: s.value, height: 20)
                Text(".\(String(describing: s)) = \(Int(s.value))px")
                    .font(.system(size: 13))
                    .foregroundStyle(JadeColor.textSecondary)
            }
        }
    }
    .padding(24)
    .frame(width: 240)
}
