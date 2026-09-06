import AppKit
import SwiftUI

/// Unified clipboard history row (P-02). Merges the former `ClipboardItemRow`
/// and `ClipboardHistoryRow` into a single Jade-styled component backed by
/// `ClipboardRecordSnapshot` (Core Data chain).
///
/// Layout: command-search-list-consistent 32×32 radius-md thumbnail (image → thumbnail, rtf/text → glyph or
/// first char, file → system icon), single-line title, caption subtitle
/// (type · size · time). Hover reveals pin / copy / preview / delete actions
/// via `JadeListRow`.
struct JadeClipboardRow: View {
    let item: ClipboardRecordSnapshot
    let selected: Bool
    var thumbnailProvider: (ClipboardRecordSnapshot) async -> Data?
    var onPin: () -> Void
    var onCopy: () -> Void
    var onPreview: () -> Void
    var onDelete: () -> Void

    @State private var thumbnail: NSImage?

    private var actions: [JadeRowAction] {
        [
            JadeRowAction(systemImage: item.isPinned ? "pin.slash.fill" : "pin.fill",
                          label: item.isPinned ? "clipboard.unpin" : "clipboard.pin",
                          action: onPin),
            JadeRowAction(systemImage: "doc.on.doc", label: "clipboard.action.copy", action: onCopy),
            JadeRowAction(systemImage: "eye", label: "preview.open", action: onPreview),
            JadeRowAction(systemImage: "trash", label: "preview.delete", isDestructive: true, action: onDelete)
        ]
    }

    var body: some View {
        JadeListRow(selected: selected, rowSize: .compact, actions: actions) {
            HStack(spacing: JadeSpace.x3.value) {
                thumbnailView

                VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                    HStack(spacing: JadeSpace.x1.value) {
                        Text(primaryText)
                            .font(JadeFont.title3)
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
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(JadeFont.caption)
                                .foregroundStyle(JadeColor.attention)
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
            if item.contentType == .image, let data = await thumbnailProvider(item) {
                thumbnail = NSImage(data: data)
            }
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
        if item.isFavorite { parts.append(L10n.localized("a11y.state.favorite")) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .jadeRadius(.md)
        } else {
            ZStack {
                JadeRadius.md.shape
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                if item.contentType == .text, let ch = firstCharacter {
                    Text(ch)
                        .font(JadeFont.body)
                        .foregroundStyle(typeColor)
                } else {
                    Image(systemName: iconName)
                        .font(JadeFont.body)
                        .foregroundStyle(typeColor)
                }
            }
        }
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
        var parts: [String] = [typeLabel]
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
        case .text: return L10n.localized("content.text")
        case .richText: return L10n.localized("content.richText")
        case .image: return L10n.localized("content.image")
        case .file: return L10n.localized("content.file")
        }
    }

    private var iconName: String {
        switch item.contentType {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var typeColor: Color {
        switch item.contentType {
        case .text: return JadeColor.info
        case .richText: return JadeColor.warning
        case .image: return JadeColor.success
        case .file: return JadeColor.gray
        }
    }
}
