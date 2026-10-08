import Cocoa
import SwiftUI

// MARK: - Top toolbar (floating pill · tool selection)

/// P-05 顶部悬浮工具 pill：矩形 / 箭头 / 文字 / 马赛克 + blur（禁用，v1.3）。
struct AnnotationTopToolbar: View {
    @ObservedObject var state: AnnotationCanvasState

    var body: some View {
        HStack(spacing: JadeSpace.x1.value) {
            ForEach(AnnotationTool.allCases) { tool in
                ToolPill(tool: tool, selected: state.tool == tool) {
                    state.tool = tool
                }
            }

            Divider().frame(height: 24)

            // blur 工具：v1.3 支持，本版禁用（opacity 0.4 + tooltip）。
            DisabledToolPill(
                systemImage: "drop.fill",
                label: L10n.localized("annotation.tool.blur"),
                tooltip: L10n.localized("annotation.tool.blur.soon")
            )
        }
        .padding(JadeSpace.x2.value)
        .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: 1))
        .jadeShadow(.md, radius: .xl)
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

    var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            IconButton(systemName: "arrow.uturn.backward", tooltip: L10n.localized("annotation.undo.help"), disabled: !state.canUndo, action: onUndo)
            IconButton(systemName: "arrow.uturn.forward", tooltip: L10n.localized("annotation.redo.help"), disabled: !state.canRedo, action: onRedo)

            Divider().frame(height: 24)

            HStack(spacing: JadeSpace.x2.value) {
                ForEach(AnnotationColor.allCases) { color in
                    ColorSwatch(color: color, selected: state.style.color == color) {
                        state.style.color = color
                    }
                }
            }

            Divider().frame(height: 24)

            Picker("", selection: Binding(get: { state.style.lineWidth }, set: { state.style.lineWidth = $0 })) {
                ForEach(AnnotationLineWidth.allCases) { width in
                    Text(width.displayName).tag(width)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .help(L10n.localized("annotation.lineWidth.help"))

            Divider().frame(height: 24)

            IconTextButton(label: L10n.localized("annotation.cancel"), tint: JadeColor.danger, action: onCancel)
            IconTextButton(label: L10n.localized("annotation.copy"), action: onCopy)
            IconTextButton(label: L10n.localized("annotation.save"), tint: JadeColor.primary, prominent: true, action: onSave)
        }
        .padding(JadeSpace.x2.value)
        .background(JadeMaterial.pill.material, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(JadeColor.border, lineWidth: 1))
        .jadeShadow(.md, radius: .xl)
    }
}

// MARK: - Components

private struct ToolPill: View {
    let tool: AnnotationTool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: JadeSpace.x1.value) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(tool.displayName)
                    .font(JadeFont.subhead)
            }
            .foregroundColor(selected ? .white : JadeColor.textPrimary)
            .padding(.horizontal, JadeSpace.x2.value)
            .padding(.vertical, JadeSpace.x1.value + 1)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? JadeColor.primary : (hovering ? JadeColor.surface3 : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
        .accessibilityLabel(Text(tool.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
    }
}

private struct DisabledToolPill: View {
    let systemImage: String
    let label: String
    let tooltip: String

    var body: some View {
        HStack(spacing: JadeSpace.x1.value) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(JadeFont.subhead)
        }
        .foregroundColor(JadeColor.textPrimary)
        .padding(.horizontal, JadeSpace.x2.value)
        .padding(.vertical, JadeSpace.x1.value + 1)
        .opacity(0.4)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(tooltip))
    }
}

private struct ColorSwatch: View {
    let color: AnnotationColor
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(JadeColor.border, lineWidth: color == .white ? 1 : 0))
                // 选中态：Jade 2pt 色环，直径 26pt。
                .overlay(Circle().stroke(selected ? JadeColor.primary : Color.clear, lineWidth: 2).frame(width: 26, height: 26))
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.12), radius: hovering ? 3 : 1)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .help(color.displayName)
        .accessibilityLabel(Text(color.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
    }
}

private struct IconButton: View {
    let systemName: String
    let tooltip: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
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
    }
}

private struct IconTextButton: View {
    let label: String
    var tint: Color = JadeColor.textPrimary
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(JadeFont.subhead)
                .foregroundColor(prominent ? .white : tint)
                .padding(.horizontal, JadeSpace.x3.value)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(prominent ? JadeColor.primary : (hovering ? JadeColor.surface3 : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hovering = $0 }
    }
}
