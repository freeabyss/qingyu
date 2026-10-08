import CoreData
import Foundation

// MARK: - Search blacklist domain models

struct SearchBlacklistItemSnapshot: Identifiable, Hashable {
    let id: UUID
    let resultID: SearchResultID
    let sourceID: SearchSourceID
    let title: String
    let resultType: String
    let createdAt: Date
}

struct SearchBlacklistDraft: Hashable {
    let resultID: SearchResultID
    let sourceID: SearchSourceID
    let title: String
    let resultType: String

    init(resultID: SearchResultID, sourceID: SearchSourceID, title: String, resultType: String) {
        self.resultID = resultID
        self.sourceID = sourceID
        self.title = title
        self.resultType = resultType
    }

    init(result: SearchResult) {
        self.init(
            resultID: result.id,
            sourceID: result.sourceID,
            title: result.title,
            resultType: result.typeLabel
        )
    }
}

protocol SearchBlacklistRepositoryProtocol: SearchBlacklistCheckingProtocol {
    func add(_ draft: SearchBlacklistDraft) async throws -> SearchBlacklistItemSnapshot
    func add(result: SearchResult) async throws -> SearchBlacklistItemSnapshot
    func list() async throws -> [SearchBlacklistItemSnapshot]
    func remove(id: UUID) async throws
    func remove(sourceID: SearchSourceID, resultID: SearchResultID) async throws
}

/// Core Data backed repository for hiding concrete search results.
///
/// This repository deliberately stores stable `(sourceID, resultID)` pairs only.
/// It does not implement keyword/path/source rules, preserving the MVP boundary
/// that the blacklist hides concrete results and nothing broader.
final class SearchBlacklistRepository: SearchBlacklistRepositoryProtocol, @unchecked Sendable {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func add(_ draft: SearchBlacklistDraft) async throws -> SearchBlacklistItemSnapshot {
        let context = persistence.viewContext
        return try await context.perform {
            if let existing = try self.fetch(sourceID: draft.sourceID, resultID: draft.resultID, in: context) {
                existing.title = draft.title
                existing.resultType = draft.resultType
                try context.saveIfNeeded()
                return Self.snapshot(from: existing)
            }

            let item = CDSearchBlacklistItem(context: context)
            item.id = UUID()
            item.resultID = draft.resultID.rawValue
            item.sourceID = draft.sourceID.rawValue
            item.title = draft.title
            item.resultType = draft.resultType
            item.createdAt = Date()
            try context.saveIfNeeded()
            return Self.snapshot(from: item)
        }
    }

    func add(result: SearchResult) async throws -> SearchBlacklistItemSnapshot {
        try await add(SearchBlacklistDraft(result: result))
    }

    func list() async throws -> [SearchBlacklistItemSnapshot] {
        let context = persistence.viewContext
        return try await context.perform {
            let request = CDSearchBlacklistItem.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try context.fetch(request).map(Self.snapshot(from:))
        }
    }

    func remove(id: UUID) async throws {
        let context = persistence.viewContext
        try await context.perform {
            let request = CDSearchBlacklistItem.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let item = try context.fetch(request).first {
                context.delete(item)
                try context.saveIfNeeded()
            }
        }
    }

    func remove(sourceID: SearchSourceID, resultID: SearchResultID) async throws {
        let context = persistence.viewContext
        try await context.perform {
            if let item = try self.fetch(sourceID: sourceID, resultID: resultID, in: context) {
                context.delete(item)
                try context.saveIfNeeded()
            }
        }
    }

    func contains(sourceID: SearchSourceID, resultID: SearchResultID) async -> Bool {
        let context = persistence.viewContext
        return await context.perform {
            do {
                let request = CDSearchBlacklistItem.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(
                    format: "sourceID == %@ AND resultID == %@",
                    sourceID.rawValue,
                    resultID.rawValue
                )
                return try context.count(for: request) > 0
            } catch {
                return false
            }
        }
    }

    private func fetch(sourceID: SearchSourceID, resultID: SearchResultID, in context: NSManagedObjectContext) throws -> CDSearchBlacklistItem? {
        let request = CDSearchBlacklistItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "sourceID == %@ AND resultID == %@",
            sourceID.rawValue,
            resultID.rawValue
        )
        return try context.fetch(request).first
    }

    private static func snapshot(from item: CDSearchBlacklistItem) -> SearchBlacklistItemSnapshot {
        SearchBlacklistItemSnapshot(
            id: item.id,
            resultID: SearchResultID(rawValue: item.resultID),
            sourceID: SearchSourceID(rawValue: item.sourceID),
            title: item.title,
            resultType: item.resultType,
            createdAt: item.createdAt
        )
    }
}

private extension NSManagedObjectContext {
    func saveIfNeeded() throws {
        if hasChanges {
            try save()
        }
    }
}
