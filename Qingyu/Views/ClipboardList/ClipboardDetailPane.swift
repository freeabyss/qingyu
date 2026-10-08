import AppKit
import SwiftUI

/// Right-hand clipboard detail pane — content only (no action buttons).
///
/// Pin / copy / delete live on the list rows and stay always visible there.
/// Header top-right can maximize into a large preview sheet for long content.
struct ClipboardDetailPane: View {
    let item: ClipboardRecordSnapshot?
    var imageProvider: (ClipboardRecordSnapshot) async -> Data?
    var richTextProvider: (ClipboardRecordSnapshot) async -> NSAttributedString?
    /// File items only: reveal the recorded path in Finder. The owner is
    /// responsible for surfacing a toast when the path is gone.
    var onRevealInFinder: (ClipboardRecordSnapshot) -> Void = { _ in }
    /// Show the maximize control (disabled inside the maximized sheet itself).
    var allowsMaximize: Bool = true

    @State private var image: NSImage?
    @State private var rtfAttributed: NSAttributedString?
    @State private var isRichTextLoading = false
    @State private var imageLoadFinished = false
    @State private var isMaximized = false

    var body: some View {
        Group {
            if let item {
                detail(for: item)
                    .id(item.id)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JadeColor.surface1)
        .frame(minWidth: 280)
        .sheet(isPresented: $isMaximized) {
            maximizedPreview(for: item)
        }
    }

    // MARK: - Maximized preview

    @ViewBuilder
    private func maximizedPreview(for item: ClipboardRecordSnapshot?) -> some View {
        if let item {
            VStack(spacing: 0) {
                HStack(spacing: JadeSpace.x2.value) {
                    Image(systemName: iconName(for: item.contentType))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textSecondary)
                    Text(typeLabel(for: item.contentType))
                        .font(JadeFont.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(JadeColor.textPrimary)
                    Spacer()
                    Text(L10n.relativeTime(from: item.updatedAt))
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textTertiary)
                    Button {
                        isMaximized = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(JadeColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("a11y.commandBar.clear"))
                }
                .padding(.horizontal, JadeSpace.x4.value)
                .padding(.vertical, JadeSpace.x3.value)

                Divider().overlay(JadeColor.border)

                // Large scrolling body — same content rendering as the side pane.
                ScrollView {
                    content(for: item)
                        .padding(JadeSpace.x6.value)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 880, minHeight: 640)
            .background(JadeColor.surface1)
            .overlay(
                Button(action: { isMaximized = false }) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            )
        } else {
            Color.clear.frame(width: 320, height: 240)
        }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(JadeColor.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.localized("clipboard.detail.empty"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(JadeSpace.x6.value)
    }

    // MARK: - Detail

    private func detail(for item: ClipboardRecordSnapshot) -> some View {
        VStack(spacing: 0) {
            header(for: item)
                .frame(height: 44)
            Divider().overlay(JadeColor.border)
            ScrollView {
                content(for: item)
                    .padding(JadeSpace.x4.value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            image = nil
            rtfAttributed = nil
            isRichTextLoading = false
            imageLoadFinished = false
            if item.contentType == .image {
                if let data = await imageProvider(item) {
                    image = NSImage(data: data)
                }
                imageLoadFinished = true
            } else if item.contentType == .richText {
                isRichTextLoading = true
                rtfAttributed = await richTextProvider(item)
                isRichTextLoading = false
            }
        }
    }

    private func header(for item: ClipboardRecordSnapshot) -> some View {
        HStack(spacing: JadeSpace.x2.value) {
            Image(systemName: iconName(for: item.contentType))
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textSecondary)
            Text(typeLabel(for: item.contentType))
                .font(JadeFont.callout)
                .fontWeight(.semibold)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer()
            Text(L10n.relativeTime(from: item.updatedAt))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textTertiary)

            if allowsMaximize {
                Button {
                    isMaximized = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(JadeColor.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(JadeColor.surface2)
                        .jadeRadius(.sm)
                }
                .buttonStyle(.plain)
                .help(L10n.localized("clipboard.detail.maximize"))
                .accessibilityLabel(Text(L10n.localized("clipboard.detail.maximize")))
                .accessibilityIdentifier("clipboard.detail.maximize")
            }
        }
        .padding(.horizontal, JadeSpace.x4.value)
        .padding(.vertical, JadeSpace.x3.value)
    }

    @ViewBuilder
    private func content(for item: ClipboardRecordSnapshot) -> some View {
        switch item.contentType {
        case .text:
            plainTextContent(item)
        case .richText:
            richTextContent(for: item)
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                    .jadeRadius(.md)
            } else if imageLoadFinished {
                // Load finished without data → file missing / unreadable.
                missingImagePlaceholder
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        case .file:
            fileContent(for: item)
        }
    }

    private func plainTextContent(_ item: ClipboardRecordSnapshot) -> some View {
        Text(item.plainText ?? item.summary ?? L10n.localized("preview.empty"))
            .font(JadeFont.body)
            .lineSpacing(5)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x3.value)
            .background(JadeColor.surface2)
            .jadeRadius(.md)
    }

    private var missingImagePlaceholder: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(JadeColor.warning)
                .accessibilityHidden(true)
            Text(L10n.localized("preview.imageNotAvailable"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(JadeSpace.x4.value)
        .background(JadeColor.surface2)
        .jadeRadius(.md)
    }

    @ViewBuilder
    private func richTextContent(for item: ClipboardRecordSnapshot) -> some View {
        if let rtfAttributed {
            RTFTextView(attributedString: rtfAttributed)
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(JadeSpace.x3.value)
        } else if isRichTextLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            // Parse failed or resources missing — still show plain text as 文本.
            plainTextContent(item)
        }
    }

    private func fileContent(for item: ClipboardRecordSnapshot) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
            if let fileURL = item.filePath {
                let path = fileURL.path
                let displayName = item.fileDisplayName ?? fileURL.lastPathComponent

                HStack(alignment: .top, spacing: JadeSpace.x3.value) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                        Text(displayName)
                            .font(JadeFont.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(JadeColor.textPrimary)
                            .lineLimit(2)
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(JadeColor.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    onRevealInFinder(item)
                } label: {
                    Label(L10n.localized("preview.showInFinder"), systemImage: "folder")
                }
                .buttonStyle(.jadeSecondary)
                .accessibilityIdentifier("clipboard.detail.showInFinder")
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 40))
                    .foregroundStyle(JadeColor.textSecondary)
                Text(item.summary ?? item.plainText ?? L10n.localized("preview.fileNotAvailable"))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(JadeSpace.x3.value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JadeColor.surface2)
        .overlay(JadeRadius.md.shape.strokeBorder(JadeColor.border, lineWidth: 1))
        .jadeRadius(.md)
    }

    private func iconName(for type: ClipboardContentType) -> String {
        switch type {
        case .text, .richText: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private func typeLabel(for type: ClipboardContentType) -> String {
        switch type {
        case .text, .richText: return L10n.localized("clipboard.filter.text")
        case .image: return L10n.localized("clipboard.filter.image")
        case .file: return L10n.localized("clipboard.filter.file")
        }
    }
}
