import Foundation
import GRDB

/// Content type of a clipboard item.
enum ContentType: String, Codable, CaseIterable, Identifiable {
    case text
    case rtf
    case image
    case file

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return L10n.localized("content.text")
        case .rtf: return L10n.localized("content.richText")
        case .image: return L10n.localized("content.image")
        case .file: return L10n.localized("content.file")
        }
    }

    var iconName: String {
        switch self {
        case .text: return "doc.text"
        case .rtf: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

/// Core data model for a clipboard history record.
/// Maps to the `clipboard_items` database table.
struct ClipboardItem: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clipboard_items"

    var id: Int64?
    var contentType: ContentType
    var textContent: String?
    var rtfContent: String?
    var imageData: Data?
    var filePath: String?
    var ocrText: String?
    var contentHash: String
    var isPinned: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Column Mapping

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case contentType = "content_type"
        case textContent = "text_content"
        case rtfContent = "rtf_content"
        case imageData = "image_data"
        case filePath = "file_path"
        case ocrText = "ocr_text"
        case contentHash = "content_hash"
        case isPinned = "is_pinned"
        case isFavorite = "is_favorite"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - GRDB

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Codable (backward-compatible decoding)

    /// Custom decoder that tolerates legacy JSON exports missing `is_favorite`.
    /// Older export files (US-011 era) don't have the field; default to false.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.contentType = try container.decode(ContentType.self, forKey: .contentType)
        self.textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        self.rtfContent = try container.decodeIfPresent(String.self, forKey: .rtfContent)
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        self.contentHash = try container.decode(String.self, forKey: .contentHash)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    // MARK: - Convenience Initializer

    /// Create a new clipboard item (not yet saved, id is nil).
    init(
        contentType: ContentType,
        textContent: String? = nil,
        rtfContent: String? = nil,
        imageData: Data? = nil,
        filePath: String? = nil,
        ocrText: String? = nil,
        contentHash: String,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = nil
        self.contentType = contentType
        self.textContent = textContent
        self.rtfContent = rtfContent
        self.imageData = imageData
        self.filePath = filePath
        self.ocrText = ocrText
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Fetch Requests

    /// FTS5 association for full-text search.
    static let fts = hasOne(ClipboardItemFTS.self)
}

/// FTS5 virtual table record (read-only, writes handled by triggers).
struct ClipboardItemFTS: Decodable, TableRecord, FetchableRecord {
    static let databaseTableName = "clipboard_items_fts"

    var rowid: Int64
    var textContent: String?
    var ocrText: String?

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case rowid
        case textContent = "text_content"
        case ocrText = "ocr_text"
    }
}
