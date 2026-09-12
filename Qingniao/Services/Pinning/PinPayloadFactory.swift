import AppKit
import Foundation

// MARK: - Pin payload factory (Task 008)

enum PinPayloadFactoryError: LocalizedError, Equatable {
    case emptyPasteboard
    case imageDecodeFailed
    case htmlParseFailed

    var errorDescription: String? {
        switch self {
        case .emptyPasteboard:
            return L10n.localized("pin.error.emptyPasteboard")
        case .imageDecodeFailed:
            return L10n.localized("pin.error.imageDecodeFailed")
        case .htmlParseFailed:
            return L10n.localized("pin.error.htmlParseFailed")
        }
    }
}

/// 剪贴板 → 贴图载荷。解析顺序：图像、颜色、HTML、纯文本、文件路径。
///
/// - 颜色：`#RRGGBB`（大小写不限）或 `R, G, B`（与取色输出一致）；
/// - HTML：仅本地富文本渲染——剥离脚本与远程资源，只保留文本与内联样式；
/// - 文件路径：同一进程内首次 → 尝试转图片预览，再次 → 纯文本。
@MainActor
final class PinPayloadFactory {
    /// 文件路径首贴转图片开关（设置页可改）。
    var filePathToImage: Bool
    /// 本进程内已按「文件路径→图片」贴过的路径；重复出现时按纯文本处理。
    private var pinnedFilePaths: Set<String> = []

    init(filePathToImage: Bool = true) {
        self.filePathToImage = filePathToImage
    }

    func makePayload(from pasteboard: NSPasteboard) throws -> PinPayload {
        if let image = try imagePayload(from: pasteboard) {
            return image
        }
        if let color = colorPayload(from: pasteboard) {
            return color
        }
        if let attributed = try htmlPayload(from: pasteboard) {
            return attributed
        }
        // 纯文本/文件路径分支无空剪贴板时必然成功，否则向上抛 emptyPasteboard。
        return try textOrFilePathPayload(from: pasteboard)
    }

    // MARK: - Image

    private func imagePayload(from pasteboard: NSPasteboard) throws -> PinPayload? {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in types {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard NSImage(data: data) != nil else {
                throw PinPayloadFactoryError.imageDecodeFailed
            }
            return .image(data)
        }
        return nil
    }

    // MARK: - Color

    static func parseColor(_ text: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("#"), trimmed.count == 7,
           let value = UInt32(trimmed.dropFirst(), radix: 16) {
            let red = UInt8((value >> 16) & 0xFF)
            let green = UInt8((value >> 8) & 0xFF)
            let blue = UInt8(value & 0xFF)
            return (red, green, blue)
        }

        let components = trimmed
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        if components.count == 3 {
            return (components[0], components[1], components[2])
        }
        return nil
    }

    private func colorPayload(from pasteboard: NSPasteboard) -> PinPayload? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        guard let color = Self.parseColor(text) else { return nil }
        return .color(red: color.red, green: color.green, blue: color.blue)
    }

    // MARK: - HTML (local rich text only)

    private func htmlPayload(from pasteboard: NSPasteboard) throws -> PinPayload? {
        guard let html = pasteboard.data(forType: .html) ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.html")) else {
            return nil
        }
        guard let attributed = Self.sanitizeHTML(html) else {
            throw PinPayloadFactoryError.htmlParseFailed
        }
        return .attributedText(attributed)
    }

    /// HTML → 本地富文本：`<script>` 被解析器丢弃；再剥离附件（远程图片等）
    /// 与链接属性，确保只保留本地文本与内联样式。
    static func sanitizeHTML(_ html: Data) -> NSAttributedString? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let raw = try? NSAttributedString(html: html, options: options, documentAttributes: nil) else {
            return nil
        }
        let full = NSMutableAttributedString(attributedString: raw)
        full.enumerateAttribute(.attachment, in: NSRange(location: 0, length: full.length)) { value, range, _ in
            if value is NSTextAttachment {
                full.removeAttribute(.attachment, range: range)
            }
        }
        full.removeAttribute(.link, range: NSRange(location: 0, length: full.length))
        return full
    }

    // MARK: - Plain text / file path

    private func textOrFilePathPayload(from pasteboard: NSPasteboard) throws -> PinPayload {
        guard let text = pasteboard.string(forType: .string) else {
            throw PinPayloadFactoryError.emptyPasteboard
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PinPayloadFactoryError.emptyPasteboard
        }

        // 文件路径：首次（且开关开启）→ 图片载荷；再次 → 纯文本。
        if filePathToImage,
           trimmed.hasPrefix("/"),
           FileManager.default.fileExists(atPath: trimmed) {
            if let imageData = Self.imageDataIfDecodable(fileURL: URL(fileURLWithPath: trimmed)),
               !pinnedFilePaths.contains(trimmed) {
                pinnedFilePaths.insert(trimmed)
                return .image(imageData)
            }
        }
        return .text(trimmed)
    }

    private static func imageDataIfDecodable(fileURL: URL) -> Data? {
        guard let image = NSImage(contentsOf: fileURL),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
