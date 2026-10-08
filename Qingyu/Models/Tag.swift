import Foundation
import GRDB

/// A user-defined tag for categorizing clipboard items.
struct Tag: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tags"

    var id: Int64?
    var name: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case name
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Junction record linking clipboard items and tags (many-to-many).
struct ItemTag: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "item_tags"

    var itemId: Int64
    var tagId: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case itemId = "item_id"
        case tagId = "tag_id"
    }
}
