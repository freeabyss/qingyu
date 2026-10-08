import CoreData
import Foundation

// MARK: - Search source identifiers

struct SearchSourceID: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SearchSourceID {
    static let app = SearchSourceID(rawValue: "app")
    static let clipboard = SearchSourceID(rawValue: "clipboard")
    static let command = SearchSourceID(rawValue: "command")
    static let calculator = SearchSourceID(rawValue: "calculator")
    static let settings = SearchSourceID(rawValue: "settings")
    static let file = SearchSourceID(rawValue: "file")
    /// 关键词触发的外部跳转（`google <文字>` / `chatgpt <文字>`）。
    static let webSearch = SearchSourceID(rawValue: "webSearch")
    static let aiChat = SearchSourceID(rawValue: "aiChat")
}

// MARK: - Index model

struct SearchIndexItem: Identifiable, Hashable {
    let id: UUID
    let sourceID: SearchSourceID
    let recordID: UUID?
    let title: String
    let plainText: String?
    let summary: String?
    let contentType: ClipboardContentType?
    let pinyin: String?
    let initials: String?
    let updatedAt: Date
    let isPinned: Bool
    let isFavorite: Bool
    let contentHash: String?
    let resourceReferences: [UUID]
    let usageCount: Int
    let lastUsedAt: Date?

    var clipboardRecordID: UUID? {
        guard sourceID == .clipboard else { return nil }
        return recordID ?? id
    }
}

extension SearchIndexItem {
    init(clipboard snapshot: ClipboardRecordSnapshot) {
        let title: String
        switch snapshot.contentType {
        case .text, .richText:
            title = snapshot.summary ?? snapshot.plainText ?? "Clipboard Text"
        case .image:
            title = snapshot.summary ?? "Image"
        case .file:
            title = snapshot.fileDisplayName ?? snapshot.summary ?? snapshot.filePath?.lastPathComponent ?? "File"
        }

        self.init(
            id: snapshot.id,
            sourceID: .clipboard,
            recordID: snapshot.id,
            title: title,
            plainText: snapshot.plainText,
            summary: snapshot.summary,
            contentType: snapshot.contentType,
            pinyin: nil,
            initials: nil,
            updatedAt: snapshot.updatedAt,
            isPinned: snapshot.isPinned,
            isFavorite: snapshot.isFavorite,
            contentHash: snapshot.contentHash,
            resourceReferences: snapshot.resources.map(\.id),
            usageCount: 0,
            lastUsedAt: nil
        )
    }
}

struct ClipboardIndexSearchOptions: Hashable {
    var query: String?
    var filter: ClipboardContentType?
    var limit: Int?
    var offset: Int

    init(query: String? = nil, filter: ClipboardContentType? = nil, limit: Int? = nil, offset: Int = 0) {
        self.query = query
        self.filter = filter
        self.limit = limit
        self.offset = max(0, offset)
    }
}

// MARK: - In-memory index

protocol InMemorySearchIndexProtocol: AnyObject {
    func rebuild(from records: [SearchIndexItem])
    func upsert(_ item: SearchIndexItem)
    func remove(id: UUID)
    func removeAll(sourceID: SearchSourceID)
    func searchClipboard(query: String, filter: ClipboardContentType?) -> [SearchIndexItem]
    func historyClipboard(filter: ClipboardContentType?, limit: Int?, offset: Int) -> [SearchIndexItem]
    func item(id: UUID) -> SearchIndexItem?
    var count: Int { get }
}

final class InMemorySearchIndex: InMemorySearchIndexProtocol {
    private struct StoredItem {
        let item: SearchIndexItem
        let searchableText: String
    }

    private let lock = NSLock()
    private var itemsByID: [UUID: StoredItem] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return itemsByID.count
    }

    func rebuild(from records: [SearchIndexItem]) {
        let rebuilt = Dictionary(uniqueKeysWithValues: records.map { ($0.id, StoredItem(item: $0, searchableText: Self.makeSearchableText(for: $0))) })
        lock.lock()
        itemsByID = rebuilt
        lock.unlock()
    }

    func upsert(_ item: SearchIndexItem) {
        lock.lock()
        itemsByID[item.id] = StoredItem(item: item, searchableText: Self.makeSearchableText(for: item))
        lock.unlock()
    }

    func remove(id: UUID) {
        lock.lock()
        itemsByID.removeValue(forKey: id)
        lock.unlock()
    }

    func removeAll(sourceID: SearchSourceID) {
        lock.lock()
        itemsByID = itemsByID.filter { $0.value.item.sourceID != sourceID }
        lock.unlock()
    }

    func item(id: UUID) -> SearchIndexItem? {
        lock.lock()
        defer { lock.unlock() }
        return itemsByID[id]?.item
    }

    func historyClipboard(filter: ClipboardContentType? = nil, limit: Int? = nil, offset: Int = 0) -> [SearchIndexItem] {
        let candidates = clipboardCandidates(filter: filter)
        return Self.page(Self.sortForHistory(candidates.map(\.item)), limit: limit, offset: offset)
    }

    func searchClipboard(query: String, filter: ClipboardContentType? = nil) -> [SearchIndexItem] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return historyClipboard(filter: filter, limit: nil, offset: 0)
        }

        let terms = normalizedQuery.split(separator: " ").map(String.init)
        let matches = clipboardCandidates(filter: filter).compactMap { stored -> (SearchIndexItem, Double)? in
            let score = Self.matchScore(searchableText: stored.searchableText, title: stored.item.title, terms: terms, normalizedQuery: normalizedQuery)
            guard score > 0 else { return nil }
            return (stored.item, score)
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.0.isPinned != rhs.0.isPinned { return lhs.0.isPinned && !rhs.0.isPinned }
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
    }

    private func clipboardCandidates(filter: ClipboardContentType?) -> [StoredItem] {
        lock.lock()
        let values = Array(itemsByID.values)
        lock.unlock()

        return values.filter { stored in
            stored.item.sourceID == .clipboard && (filter == nil || stored.item.contentType == filter)
        }
    }

    private static func sortForHistory(_ items: [SearchIndexItem]) -> [SearchIndexItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func page(_ items: [SearchIndexItem], limit: Int?, offset: Int) -> [SearchIndexItem] {
        guard offset < items.count else { return [] }
        let sliced = Array(items.dropFirst(offset))
        guard let limit, limit >= 0 else { return sliced }
        return Array(sliced.prefix(limit))
    }

    private static func makeSearchableText(for item: SearchIndexItem) -> String {
        normalize([
            item.title,
            item.plainText,
            item.summary,
            item.contentHash,
            item.pinyin,
            item.initials
        ].compactMap { $0 }.joined(separator: "\n"))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchScore(searchableText: String, title: String, terms: [String], normalizedQuery: String) -> Double {
        guard terms.allSatisfy({ searchableText.contains($0) }) else { return 0 }

        let normalizedTitle = normalize(title)
        if normalizedTitle == normalizedQuery { return 100 }
        if normalizedTitle.hasPrefix(normalizedQuery) { return 80 }
        if normalizedTitle.contains(normalizedQuery) { return 60 }
        if searchableText.contains(normalizedQuery) { return 45 }
        return Double(terms.count) * 10
    }
}

// MARK: - Core Data rebuild

protocol ClipboardSearchIndexLoaderProtocol {
    func rebuildFromPersistentStore() async throws
}

final class ClipboardSearchIndexLoader: ClipboardSearchIndexLoaderProtocol {
    private let persistence: PersistenceController
    private let index: InMemorySearchIndexProtocol

    init(persistence: PersistenceController = .shared, index: InMemorySearchIndexProtocol) {
        self.persistence = persistence
        self.index = index
    }

    func rebuildFromPersistentStore() async throws {
        let context = persistence.viewContext
        let items = try await context.perform {
            let request = CDClipboardRecord.fetchRequest()
            request.relationshipKeyPathsForPrefetching = ["resources"]
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).map(Self.makeIndexItem(from:))
        }
        index.rebuild(from: items)
    }

    private static func makeIndexItem(from record: CDClipboardRecord) -> SearchIndexItem {
        let contentType = ClipboardContentType(rawValue: record.contentType)
        let resourceReferences = record.resources.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let title: String
        switch contentType {
        case .text, .richText:
            title = record.summary ?? record.plainText ?? "Clipboard Text"
        case .image:
            title = record.summary ?? "Image"
        case .file:
            title = record.fileDisplayName ?? record.summary ?? record.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File"
        case nil:
            title = record.summary ?? record.plainText ?? "Clipboard Item"
        }

        return SearchIndexItem(
            id: record.id,
            sourceID: .clipboard,
            recordID: record.id,
            title: title,
            plainText: record.plainText,
            summary: record.summary,
            contentType: contentType,
            pinyin: nil,
            initials: nil,
            updatedAt: record.updatedAt,
            isPinned: record.isPinned,
            isFavorite: record.isFavorite,
            contentHash: record.contentHash,
            resourceReferences: resourceReferences,
            usageCount: 0,
            lastUsedAt: nil
        )
    }
}

// MARK: - Query service and repository synchronization

protocol ClipboardIndexQueryServiceProtocol {
    func searchIndex(query: String, filter: ClipboardContentType?, limit: Int?) -> [SearchIndexItem]
    func historyIndex(filter: ClipboardContentType?, limit: Int?, offset: Int) -> [SearchIndexItem]
    func loadDetails(for indexItem: SearchIndexItem) async throws -> ClipboardRecordSnapshot?
}

final class ClipboardIndexQueryService: ClipboardIndexQueryServiceProtocol {
    private let index: InMemorySearchIndexProtocol
    private let repository: ClipboardRepositoryProtocol

    init(index: InMemorySearchIndexProtocol, repository: ClipboardRepositoryProtocol) {
        self.index = index
        self.repository = repository
    }

    func searchIndex(query: String, filter: ClipboardContentType? = nil, limit: Int? = nil) -> [SearchIndexItem] {
        let results = index.searchClipboard(query: query, filter: filter)
        guard let limit else { return results }
        return Array(results.prefix(limit))
    }

    func historyIndex(filter: ClipboardContentType? = nil, limit: Int? = nil, offset: Int = 0) -> [SearchIndexItem] {
        index.historyClipboard(filter: filter, limit: limit, offset: offset)
    }

    func loadDetails(for indexItem: SearchIndexItem) async throws -> ClipboardRecordSnapshot? {
        guard let recordID = indexItem.clipboardRecordID else { return nil }
        return try await repository.fetch(id: recordID)
    }
}

final class IndexingClipboardRepository: ClipboardRepositoryProtocol {
    private let base: ClipboardRepositoryProtocol
    private let index: InMemorySearchIndexProtocol
    private let loader: ClipboardSearchIndexLoaderProtocol?

    init(base: ClipboardRepositoryProtocol, index: InMemorySearchIndexProtocol, loader: ClipboardSearchIndexLoaderProtocol? = nil) {
        self.base = base
        self.index = index
        self.loader = loader
    }

    func upsert(event: AssistantClipboardEvent, resources: [ClipboardResourceDraft]) async throws -> ClipboardRecordSnapshot {
        let snapshot = try await base.upsert(event: event, resources: resources)
        index.upsert(SearchIndexItem(clipboard: snapshot))
        return snapshot
    }

    func fetch(id: UUID) async throws -> ClipboardRecordSnapshot? {
        try await base.fetch(id: id)
    }

    func fetchHistory(filter: ClipboardHistoryFilter) async throws -> [ClipboardRecordSnapshot] {
        try await base.fetchHistory(filter: filter)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
        index.remove(id: id)
    }

    func clearAll() async throws {
        try await base.clearAll()
        index.removeAll(sourceID: .clipboard)
    }

    func togglePin(id: UUID) async throws -> ClipboardRecordSnapshot {
        let snapshot = try await base.togglePin(id: id)
        index.upsert(SearchIndexItem(clipboard: snapshot))
        return snapshot
    }

    func toggleFavorite(id: UUID) async throws -> ClipboardRecordSnapshot {
        let snapshot = try await base.toggleFavorite(id: id)
        index.upsert(SearchIndexItem(clipboard: snapshot))
        return snapshot
    }

    func cleanupExpired(now: Date) async throws -> Int {
        let deletedCount = try await base.cleanupExpired(now: now)
        if deletedCount > 0 {
            try await loader?.rebuildFromPersistentStore()
        }
        return deletedCount
    }

    func storageUsage() async throws -> StorageUsage {
        try await base.storageUsage()
    }
}
