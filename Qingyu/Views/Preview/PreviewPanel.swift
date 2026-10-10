import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Content preview panel shown as a sheet when a clipboard item is opened
/// (space / ⌘Y / eye action). Backed by `ClipboardRecordSnapshot` (Core Data
/// chain); image / RTF payloads are loaded lazily via async providers.
///
/// Supports text selection, RTF rendering, image zoom (0.5–5x magnification)
/// and file info display. Delete / copy actions use Jade button styling.
struct PreviewPanel: View {
    let item: ClipboardRecordSnapshot
    var imageProvider: (ClipboardRecordSnapshot) async -> Data?
    var richTextProvider: (ClipboardRecordSnapshot) async -> Data?
    var onCopy: () -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var imageScale: CGFloat = 1.0
    @State private var image: NSImage?
    @State private var rtfAttributed: NSAttributedString?
    /// Toast state for action failures (e.g. the recorded file is gone).
    @State private var toastMessage = ""
    @State private var toastVariant: JadeToast.Variant = .error
    @State private var isShowingToast = false
    @State private var toastDismissTask: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ScrollView {
                contentArea
                    .padding(JadeSpace.x4.value)
            }

            Divider()

            actionBar
        }
        .frame(minWidth: 450, minHeight: 400)
        .background(JadeColor.surface1)
        .jadeToast(toastMessage, isShowing: $isShowingToast, variant: toastVariant)
        // ESC to close: hidden button with .cancelAction keyboard shortcut (macOS 13+)
        .overlay(
            Button(action: { dismiss() }) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
        .task(id: item.id) {
            if item.contentType == .image {
                if let data = await imageProvider(item) { image = NSImage(data: data) }
            } else if item.contentType == .richText {
                if let data = await richTextProvider(item) {
                    rtfAttributed = try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: iconName)
                .font(JadeFont.body)
                .foregroundStyle(typeColor)

            Text(typeLabel)
                .font(JadeFont.body.weight(.semibold))
                .foregroundStyle(JadeColor.textPrimary)

            Spacer()

            Text(L10n.relativeTime(from: item.updatedAt))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(JadeColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, JadeSpace.x4.value)
        .padding(.vertical, JadeSpace.x3.value)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch item.contentType {
        case .text:
            textPreview
        case .richText:
            rtfPreview
        case .image:
            imagePreview
        case .file:
            filePreview
        }
    }

    private var textPreview: some View {
        Text(item.plainText ?? item.summary ?? L10n.localized("preview.empty"))
            .font(.system(size: 14, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x3.value)
            .background(Color(NSColor.textBackgroundColor))
            .jadeRadius(.md)
            .jadeRadiusBorder(.md)
    }

    @ViewBuilder
    private var rtfPreview: some View {
        if let rtfAttributed {
            RTFTextView(attributedString: rtfAttributed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(JadeSpace.x3.value)
                .background(Color(NSColor.textBackgroundColor))
                .jadeRadius(.md)
                .jadeRadiusBorder(.md)
        } else {
            Text(item.plainText ?? item.summary ?? L10n.localized("preview.empty"))
                .font(JadeFont.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(JadeSpace.x3.value)
                .background(Color(NSColor.textBackgroundColor))
                .jadeRadius(.md)
        }
    }

    private var imagePreview: some View {
        VStack(spacing: JadeSpace.x3.value) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(imageScale)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .background(Color(NSColor.textBackgroundColor))
                    .jadeRadius(.md)
                    .jadeRadiusBorder(.md)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                imageScale = max(0.5, min(value, 5.0))
                            }
                    )

                HStack(spacing: JadeSpace.x4.value) {
                    Label("\(Int(image.size.width)) x \(Int(image.size.height))", systemImage: "aspectratio")
                    if let rep = image.representations.first {
                        Label("\(rep.pixelsWide) x \(rep.pixelsHigh) px", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
            } else {
                VStack(spacing: JadeSpace.x2.value) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(JadeColor.textSecondary)
                    Text(L10n.localized("preview.imageNotAvailable"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filePreview: some View {
        VStack(spacing: JadeSpace.x4.value) {
            if let fileURL = item.filePath {
                let path = fileURL.path
                let icon = NSWorkspace.shared.icon(forFile: path)

                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(spacing: JadeSpace.x2.value) {
                    fileInfoRow(label: L10n.localized("preview.fileName"), value: fileURL.lastPathComponent)
                    fileInfoRow(label: L10n.localized("preview.filePath"), value: path)
                    if let size = fileSizeString(path: path) {
                        fileInfoRow(label: L10n.localized("preview.fileSize"), value: size)
                    }
                    if let type = fileType(path: path) {
                        fileInfoRow(label: L10n.localized("preview.fileType"), value: type)
                    }
                }
                .padding(JadeSpace.x3.value)
                .background(Color(NSColor.textBackgroundColor))
                .jadeRadius(.md)
                .jadeRadiusBorder(.md)

                Button {
                    revealInFinder(path: path)
                } label: {
                    Label(L10n.localized("preview.showInFinder"), systemImage: "folder")
                }
                .buttonStyle(.jadeSecondary)
            } else {
                VStack(spacing: JadeSpace.x2.value) {
                    Image(systemName: "doc")
                        .font(.system(size: 40))
                        .foregroundStyle(JadeColor.textSecondary)
                    Text(L10n.localized("preview.fileNotAvailable"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Reveal in Finder

    /// Reveals the recorded file path in Finder; a path that no longer exists is
    /// reported with a toast rather than silently doing nothing.
    private func revealInFinder(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            showToast(message: L10n.localized("toast.fileMissing"))
            return
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    /// `JadeToastModifier` cannot auto-dismiss the `.error` variant (fixed at the
    /// modifier level), so the panel clears it on its own longer timer.
    private func showToast(message: String) {
        toastMessage = message
        toastVariant = .error
        isShowingToast = true
        toastDismissTask?.cancel()
        let task = DispatchWorkItem {
            if isShowingToast { isShowingToast = false }
        }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: task)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: JadeSpace.x3.value) {
            Spacer()

            Button {
                onDelete()
                dismiss()
            } label: {
                Label(L10n.localized("preview.delete"), systemImage: "trash")
            }
            .buttonStyle(.jadeDestructive)

            Button {
                onCopy()
                dismiss()
            } label: {
                Label(L10n.localized("preview.copy"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.jadePrimary)
        }
        .padding(.horizontal, JadeSpace.x4.value)
        .padding(.vertical, JadeSpace.x3.value)
    }

    // MARK: - Helpers

    private var typeColor: Color {
        switch item.contentType {
        case .text: return JadeColor.info
        case .richText: return JadeColor.warning
        case .image: return JadeColor.success
        case .file: return JadeColor.gray
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

    private var typeLabel: String {
        switch item.contentType {
        case .text: return L10n.localized("content.text")
        case .richText: return L10n.localized("content.richText")
        case .image: return L10n.localized("content.image")
        case .file: return L10n.localized("content.file")
        }
    }

    private func fileInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(JadeFont.callout.weight(.medium))
                .foregroundStyle(JadeColor.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fileSizeString(path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func fileType(path: String) -> String? {
        guard let uti = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier else { return nil }
        return UTType(uti)?.localizedDescription ?? uti
    }
}

// MARK: - RTF Text View (NSViewRepresentable for full RTF rendering with selection)

/// Wraps NSTextView to render attributed string with text selection support.
struct RTFTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            // scrollableTextView() always vends an NSTextView; guard instead of
            // force-cast so an unexpected AppKit change degrades gracefully.
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
    }
}

#Preview {
    PreviewPanel(
        item: ClipboardRecordSnapshot(
            id: UUID(),
            contentType: .text,
            plainText: "Hello World\nThis is a preview of the clipboard content.\nLine 3 here.",
            summary: "Hello World",
            contentHash: "preview1",
            isPinned: false,
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date(),
            filePath: nil,
            fileDisplayName: nil,
            fileUTI: nil,
            fileSize: nil,
            resources: [],
            resourceStatus: .available,
            sourceAppBundleID: nil,
            sourceAppName: nil
        ),
        imageProvider: { _ in nil },
        richTextProvider: { _ in nil },
        onCopy: {},
        onDelete: {}
    )
}
