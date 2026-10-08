import AppKit
import SwiftUI

/// Unified clipboard history row (P-02).
///
/// Layout: thumbnail + title/subtitle on the left; pin / copy / delete icons
/// always visible on the right (same symbols as detail-free list actions).
struct JadeClipboardRow: View {
    let item: ClipboardRecordSnapshot
    let selected: Bool
    var thumbnailProvider: (ClipboardRecordSnapshot) async -> Data?
    var onPin: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    /// File clipboard items only: reveal the file’s folder in Finder.
    var onRevealInFinder: (() -> Void)? = nil

    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?

    private var actions: [JadeRowAction] {
        var items: [JadeRowAction] = [
            JadeRowAction(systemImage: item.isPinned ? "pin.slash.fill" : "pin.fill",
                          label: item.isPinned ? "clipboard.unpin" : "clipboard.pin",
                          action: onPin),
            JadeRowAction(systemImage: "doc.on.doc", label: "clipboard.action.copy", action: onCopy)
        ]
        if item.contentType == .file, let onRevealInFinder, item.filePath != nil {
            items.append(
                JadeRowAction(
                    systemImage: "folder",
                    label: "preview.showInFinder",
                    action: onRevealInFinder
                )
            )
        }
        items.append(
            JadeRowAction(systemImage: "trash", label: "preview.delete", isDestructive: true, action: onDelete)
        )
        return items
    }

    var body: some View {
        JadeListRow(
            selected: selected,
            rowSize: .comfortable,
            actions: actions,
            alwaysShowsActions: true
        ) {
            HStack(spacing: JadeSpace.x3.value) {
                thumbnailView

                VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                    HStack(spacing: JadeSpace.x1.value) {
                        Text(primaryText)
                            .font(JadeFont.body)
                            .fontWeight(.medium)
                            .foregroundStyle(JadeColor.textPrimary)
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(JadeFont.caption)
                                .foregroundStyle(JadeColor.primary)
                                .rotationEffect(.degrees(45))
                                .accessibilityHidden(true)
                        }
                        if item.failureReason != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(JadeFont.caption)
                                .foregroundStyle(JadeColor.warning)
                                .accessibilityHidden(true)
                        }
                    }

                    Text(subtitleText)
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .lineLimit(1)
                }
            }
            // VoiceOver：合并成单个可读元素（内容 + 类型/大小/时间 + 置顶/收藏状态)。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabelText))
            .accessibilityValue(Text(accessibilityStateText))
        }
        .task(id: item.id) {
            thumbnail = nil
            sourceAppIcon = nil
            if item.contentType == .image, let data = await thumbnailProvider(item) {
                thumbnail = NSImage(data: data)
            }
            sourceAppIcon = Self.loadSourceAppIcon(bundleID: item.sourceAppBundleID)
        }
    }

    /// "内容摘要, 类型 · 大小 · 时间" 的可读串。
    private var accessibilityLabelText: String {
        "\(primaryText), \(subtitleText)"
    }

    /// 置顶 / 收藏状态拼成 value。
    private var accessibilityStateText: String {
        var parts: [String] = []
        if item.isPinned { parts.append(L10n.localized("a11y.state.pinned")) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Thumbnail

    /// Prefer the **source application** icon (Arc / Safari / …). Fall back to
    /// image thumbnail, then content-type glyph.
    @ViewBuilder
    private var thumbnailView: some View {
        if let sourceAppIcon {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .jadeRadius(.sm)
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .jadeRadius(.sm)
        } else {
            ZStack {
                JadeRadius.sm.shape
                    .fill(selected ? JadeColor.primaryFill : JadeColor.surface2)
                    .frame(width: 36, height: 36)
                if item.contentType == .text || item.contentType == .richText, let ch = firstCharacter {
                    Text(ch)
                        .font(JadeFont.body)
                        .foregroundStyle(selected ? JadeColor.primary : JadeColor.textSecondary)
                } else if item.contentType == .image && item.failureReason != nil {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.warning)
                } else {
                    Image(systemName: iconName)
                        .font(JadeFont.body)
                        .foregroundStyle(selected ? JadeColor.primary : JadeColor.textSecondary)
                }
            }
        }
    }

    private static func loadSourceAppIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
            .flatMap { $0.icon }
    }

    private var firstCharacter: String? {
        let source = item.summary ?? item.plainText ?? ""
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first)
    }

    // MARK: - Text

    private var primaryText: String {
        switch item.contentType {
        case .text, .richText:
            return item.summary ?? item.plainText ?? L10n.localized("preview.empty")
        case .image:
            return item.summary ?? L10n.localized("content.image")
        case .file:
            return item.fileDisplayName ?? item.filePath?.lastPathComponent ?? L10n.localized("content.file")
        }
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let sourceAppName = item.sourceAppName, !sourceAppName.isEmpty {
            parts.append(sourceAppName)
        }
        parts.append(typeLabel)
        if let size = sizeText {
            parts.append(size)
        }
        parts.append(L10n.relativeTime(from: item.updatedAt))
        return parts.joined(separator: " · ")
    }

    private var sizeText: String? {
        switch item.contentType {
        case .image:
            if let original = item.resources.first(where: { $0.type == .imageOriginal }) {
                if let width = original.width, let height = original.height {
                    return "\(width)×\(height)"
                }
                return ByteCountFormatter.string(fromByteCount: original.byteSize, countStyle: .file)
            }
            return nil
        case .file:
            guard let size = item.fileSize, size > 0 else { return nil }
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        case .text, .richText:
            return nil
        }
    }

    private var typeLabel: String {
        switch item.contentType {
        case .text, .richText:
            // Product: 富文本 is presented as 文本.
            return L10n.localized("clipboard.filter.text")
        case .image:
            return L10n.localized("content.image")
        case .file:
            return L10n.localized("content.file")
        }
    }

    private var iconName: String {
        switch item.contentType {
        case .text, .richText: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

}
