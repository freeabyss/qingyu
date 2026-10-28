import Cocoa
import SwiftUI

// MARK: - Top toolbar (floating pill · tool selection)

/// P-05 顶部悬浮工具 pill：矩形 / 箭头 / 文字 / 马赛克 + blur（禁用，v1.3）。
struct AnnotationTopToolbar: View {
    @ObservedObject var state: AnnotationCanvasState

    /// 悬浮 pill 边框线宽：1pt，仅用于顶部工具栏悬浮 pill 的描边；不并入 JadeSpace，那是间距档位，不是线宽。
    private static let pillBorderLineWidth: CGFloat = 1

    var body: some View {
        HStack(spacing: JadeSpace.x1.value) {
            // 一个按钮对应一组工具：矩形/椭圆、马赛克/高斯模糊共用按钮，重复点击在组内切换。
            ForEach(Array(AnnotationTool.toolbarGroups.enumerated()), id: \.offset) { _, group in
                ToolPill(
                    tool: displayedTool(in: group),
                    selected: group.contains(state.tool),
                    showsCycleHint: group.count > 1
                ) {
                    state.tool = AnnotationTool.next(in: group, after: state.tool)
                }
            }
        }
        .jadePadding(.x2)
        .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: Self.pillBorderLineWidth))
        .jadeShadow(.md, radius: .xl)
    }

    /// 按钮展示的图标与名称：组内当前选中的工具优先，否则展示组内第一个。
    private func displayedTool(in group: [AnnotationTool]) -> AnnotationTool {
        group.contains(state.tool) ? state.tool : (group.first ?? state.tool)
    }
}

// MARK: - Bottom toolbar (floating pill · undo/redo · colors · width · actions)

struct AnnotationBottomToolbar: View {
    @ObservedObject var state: AnnotationCanvasState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    /// 分组分隔线高度：24pt，仅用于底部工具栏的分组分隔线；不并入 JadeSpace，那是间距档位，不是分隔线高度。
    private static let dividerHeight: CGFloat = 24

    /// 线宽选择器宽度：132pt，仅用于底部工具栏的线宽分段选择器；不并入 JadeSpace，那是间距档位，不是控件宽度。
    private static let lineWidthPickerWidth: CGFloat = 132

    /// 悬浮 pill 边框线宽：1pt，仅用于底部工具栏悬浮 pill 的描边；不并入 JadeSpace，那是间距档位，不是线宽。
    private static let pillBorderLineWidth: CGFloat = 1

    var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            IconButton(systemName: "arrow.uturn.backward", tooltip: L10n.localized("annotation.undo.help"), disabled: !state.canUndo, action: onUndo)
            IconButton(systemName: "arrow.uturn.forward", tooltip: L10n.localized("annotation.redo.help"), disabled: !state.canRedo, action: onRedo)

            Divider().frame(height: Self.dividerHeight)

            HStack(spacing: JadeSpace.x2.value) {
                ForEach(AnnotationColor.allCases) { color in
                    ColorSwatch(color: color, selected: state.style.color == color) {
                        state.style.color = color
                    }
                }
            }

            Divider().frame(height: Self.dividerHeight)

            Picker("", selection: Binding(get: { state.style.lineWidth }, set: { state.style.lineWidth = $0 })) {
                ForEach(AnnotationLineWidth.allCases) { width in
                    Text(width.displayName).tag(width)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: Self.lineWidthPickerWidth)
            .help(L10n.localized("annotation.lineWidth.help"))

            Divider().frame(height: Self.dividerHeight)

            IconTextButton(label: L10n.localized("annotation.cancel"), tint: JadeColor.danger, action: onCancel)
            IconTextButton(label: L10n.localized("annotation.copy"), action: onCopy)
            IconTextButton(label: L10n.localized("annotation.save"), tint: JadeColor.primary, prominent: true, action: onSave)
        }
        .jadePadding(.x2)
        .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: Self.pillBorderLineWidth))
        .jadeShadow(.md, radius: .xl)
    }
}

// MARK: - Components

private struct ToolPill: View {
    let tool: AnnotationTool
    let selected: Bool
    var showsCycleHint: Bool = false
    let action: () -> Void
    @State private var hovering = false

    private var tooltip: String {
        showsCycleHint
            ? "\(tool.displayName) · \(L10n.localized("annotation.tool.cycleHint"))"
            : tool.displayName
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: JadeSpace.x1.value) {
                // 工具图标只用 medium 一种字重：图标 12pt、名称 11pt，层级靠 1pt 字号差，不再混用 semibold / medium。
                Image(systemName: tool.systemImage)
                    .font(JadeFont.calloutMedium)
                    .accessibilityHidden(true)
                Text(tool.displayName)
                    .font(JadeFont.subhead)
            }
            .foregroundColor(selected ? .white : JadeColor.textPrimary)
            .jadePadding(.horizontal, .x2)
            .jadePadding(.vertical, .x2)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? JadeColor.primary : (hovering ? JadeColor.surface3 : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(Text(tool.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
        .jadeAnimation(.easeInOut(duration: 0.12), value: hovering)
    }
}

private struct ColorSwatch: View {
    let color: AnnotationColor
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    /// 色块直径：24pt，仅用于颜色色块本身的圆形；不并入 JadeSpace，那是间距档位，不是色块尺寸，且与外圈 30pt 角色不同。
    private static let swatchSize: CGFloat = 24

    /// 磁贴边长：30pt 正方形，按钮外框与选中色环共用同一外框尺寸，色环贴着磁贴边缘；不并入 JadeSpace，那是间距档位，不是磁贴尺寸。
    private static let tileSize: CGFloat = 30

    /// 选中色环线宽：2pt，仅用于颜色色块的选中态色环；不并入 JadeSpace，那是间距档位，不是线宽。
    private static let selectedRingLineWidth: CGFloat = 2

    /// 白色色块边框线宽：1pt，仅用于白色色块在浅色背景上可见的描边，非白色色块无描边；不并入 JadeSpace，那是间距档位，不是线宽。
    private static let whiteSwatchBorderLineWidth: CGFloat = 1

    /// 色块悬停阴影不透明度：0.35，仅用于颜色色块悬停时的阴影加深；与未悬停 0.12 角色不同，不合并；与 JadeShadow 各档的通用阴影角色不同，不并入。
    private static let hoverShadowOpacity: Double = 0.35

    /// 色块未悬停阴影不透明度：0.12，仅用于颜色色块常态下的轻微阴影；与悬停 0.35 角色不同，不合并。
    private static let restingShadowOpacity: Double = 0.12

    /// 色块悬停阴影半径：3pt，仅用于颜色色块悬停时的阴影扩散；与未悬停 1pt 角色不同，不合并。
    private static let hoverShadowRadius: CGFloat = 3

    /// 色块未悬停阴影半径：1pt，仅用于颜色色块常态下的轻微阴影扩散；与悬停 3pt 角色不同，不合并。
    private static let restingShadowRadius: CGFloat = 1

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay(Circle().stroke(JadeColor.border, lineWidth: color == .white ? Self.whiteSwatchBorderLineWidth : 0))
                // 选中态：Jade 2pt 色环，直径 30pt。
                .overlay(Circle().stroke(selected ? JadeColor.primary : Color.clear, lineWidth: Self.selectedRingLineWidth).frame(width: Self.tileSize, height: Self.tileSize))
                .shadow(color: .black.opacity(hovering ? Self.hoverShadowOpacity : Self.restingShadowOpacity), radius: hovering ? Self.hoverShadowRadius : Self.restingShadowRadius)
        }
        .buttonStyle(.plain)
        .frame(width: Self.tileSize, height: Self.tileSize)
        .help(color.displayName)
        .accessibilityLabel(Text(color.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
        .jadeAnimation(.easeInOut(duration: 0.12), value: hovering)
    }
}

private struct IconButton: View {
    let systemName: String
    let tooltip: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    /// 图标磁贴边长：30pt 正方形，仅用于标注工具栏的图标按钮；不并入 JadeSpace，那是间距档位，不是磁贴尺寸。
    private static let tileSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(JadeFont.toolbarIcon)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .foregroundColor(disabled ? JadeColor.textTertiary : JadeColor.textPrimary)
                .background(
                    Circle().fill(hovering && !disabled ? JadeColor.surface3 : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
        .onHover { hovering = $0 }
        .jadeAnimation(.easeInOut(duration: 0.12), value: hovering)
    }
}

private struct IconTextButton: View {
    let label: String
    var tint: Color = JadeColor.textPrimary
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    /// 按钮高度：30pt，仅用于标注工具栏的文字按钮；只定高，宽度由文字与水平内边距决定，与正方形磁贴的 tileSize 角色不同。
    private static let buttonHeight: CGFloat = 30

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(JadeFont.subhead)
                .foregroundColor(prominent ? .white : tint)
                .jadePadding(.horizontal, .x3)
                .frame(height: Self.buttonHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(prominent ? JadeColor.primary : (hovering ? JadeColor.surface3 : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hovering = $0 }
        .jadeAnimation(.easeInOut(duration: 0.12), value: hovering)
    }
}
