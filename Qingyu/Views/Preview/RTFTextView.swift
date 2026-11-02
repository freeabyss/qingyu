import SwiftUI
import AppKit

// MARK: - RTF Text View (NSViewRepresentable for full RTF rendering with selection)

/// Wraps NSTextView to render attributed string with text selection support.
///
/// 供剪贴板详情面板（ClipboardDetailPane）渲染 RTF 富文本使用。
/// 历史：此类型原先定义在 PreviewPanel.swift 里——那个面板的职责后来
/// 被 ClipboardDetailPane.maximizedPreview 取代并删除，但 RTFTextView 仍被
/// 详情面板复用，因此单独保留成这个文件。
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
