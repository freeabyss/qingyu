import CoreData
import Foundation

// MARK: - File resources

protocol FileResourceStoreProtocol {
    func writeImageOriginal(_ data: Data, id: UUID) async throws -> FileResourceWriteResult
    func writeThumbnail(_ data: Data, id: UUID) async throws -> FileResourceWriteResult
    func writeRichTextRTF(_ data: Data, id: UUID) async throws -> FileResourceWriteResult
    func writeRichTextHTML(_ data: Data, id: UUID) async throws -> FileResourceWriteResult
    func read(relativePath: String) async throws -> Data
    func delete(relativePath: String) async
    func exists(relativePath: String) -> Bool
    func storageUsage() async throws -> Int64
}

struct FileResourceWriteResult: Hashable {
    let id: UUID
    let relativePath: String
    let byteSize: Int64
    let mimeType: String?
}

final class FileResourceStore: FileResourceStoreProtocol {
    private let fileSystem: AssistantFileSystem
    private let fileManager: FileManager

    init(fileSystem: AssistantFileSystem = .default, fileManager: FileManager = .default) {
        self.fileSystem = fileSystem
        self.fileManager = fileManager
    }

    func writeImageOriginal(_ data: Data, id: UUID) async throws -> FileResourceWriteResult {
        try await write(data, id: id, type: .imageOriginal)
    }

    func writeThumbnail(_ data: Data, id: UUID) async throws -> FileResourceWriteResult {
        try await write(data, id: id, type: .imageThumbnail)
    }

    func writeRichTextRTF(_ data: Data, id: UUID) async throws -> FileResourceWriteResult {
        try await write(data, id: id, type: .richTextRTF)
    }

    func writeRichTextHTML(_ data: Data, id: UUID) async throws -> FileResourceWriteResult {
        try await write(data, id: id, type: .richTextHTML)
    }

    func read(relativePath: String) async throws -> Data {
        let url = fileSystem.resourceURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AssistantClipboardRepositoryError.resourceMissing(relativePath)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw AssistantClipboardRepositoryError.fileReadFailed(relativePath, error.localizedDescription)
        }
    }

    func delete(relativePath: String) async {
        let url = fileSystem.resourceURL(relativePath: relativePath)
        try? fileManager.removeItem(at: url)
    }

    func exists(relativePath: String) -> Bool {
        fileManager.fileExists(atPath: fileSystem.resourceURL(relativePath: relativePath).path)
    }

    func storageUsage() async throws -> Int64 {
        var total: Int64 = 0
        for directory in [fileSystem.imagesDirectory, fileSystem.thumbnailsDirectory, fileSystem.richTextDirectory] {
            total += try directorySize(directory)
        }
        return total
    }

    private func write(_ data: Data, id: UUID, type: AssistantClipboardResourceType) async throws -> FileResourceWriteResult {
        try fileSystem.ensureDirectoryStructure(fileManager: fileManager)

        let relativePath = fileSystem.resourcePath(for: id, type: type)
        let destinationURL = fileSystem.resourceURL(relativePath: relativePath)
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(id.uuidString).tmp", isDirectory: false)

        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return FileResourceWriteResult(
                id: id,
                relativePath: relativePath,
                byteSize: Int64(data.count),
                mimeType: type.mimeType
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AssistantClipboardRepositoryError.fileWriteFailed(relativePath, error.localizedDescription)
        }
    }

    private func directorySize(_ directory: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: Array(resourceKeys)) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - Clipboard domain models

protocol ClipboardRepositoryProtocol {
    func upsert(event: AssistantClipboardEvent, resources: [ClipboardResourceDraft]) async throws -> ClipboardRecordSnapshot
    func fetch(id: UUID) async throws -> ClipboardRecordSnapshot?
    func fetchHistory(filter: ClipboardHistoryFilter) async throws -> [ClipboardRecordSnapshot]
    func delete(id: UUID) async throws
    func clearAll() async throws
    func togglePin(id: UUID) async throws -> ClipboardRecordSnapshot
    func toggleFavorite(id: UUID) async throws -> ClipboardRecordSnapshot
    func cleanupExpired(now: Date) async throws -> Int
    func storageUsage() async throws -> StorageUsage
}

struct AssistantClipboardEvent: Hashable {
    let payload: ClipboardPayload
    let contentHash: String
    let capturedAt: Date
    let sourceAppBundleID: String?
    let sourceAppName: String?

    init(
        payload: ClipboardPayload,
        capturedAt: Date = Date(),
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.payload = payload
        self.contentHash = ClipboardContentHasher.hash(payload)
        self.capturedAt = capturedAt
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }

    init(
        payload: ClipboardPayload,
        contentHash: String,
        capturedAt: Date = Date(),
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.payload = payload
        self.contentHash = contentHash
        self.capturedAt = capturedAt
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }
}

enum ClipboardPayload: Hashable {
    case plainText(String)
    case richText(plainText: String, rtfData: Data?, htmlData: Data?)
    case image(data: Data)
    case files([FileClipboardItem])
}

struct FileClipboardItem: Hashable, Codable {
    let path: URL
    let displayName: String
    let uti: String?
    let fileSize: Int64?

    init(path: URL, displayName: String? = nil, uti: String? = nil, fileSize: Int64? = nil) {
        self.path = path
        self.displayName = displayName ?? path.lastPathComponent
        self.uti = uti
        self.fileSize = fileSize
    }
}

struct ClipboardResourceDraft: Hashable {
    let id: UUID
    let type: ClipboardResourceType
    let relativePath: String
    let mimeType: String?
    let byteSize: Int64
    let width: Int?
    let height: Int?

    init(
        id: UUID,
        type: ClipboardResourceType,
        relativePath: String,
        mimeType: String?,
        byteSize: Int64,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.width = width
        self.height = height
    }

    init(_ writeResult: FileResourceWriteResult, type: ClipboardResourceType, width: Int? = nil, height: Int? = nil) {
        self.init(
            id: writeResult.id,
            type: type,
            relativePath: writeResult.relativePath,
            mimeType: writeResult.mimeType,
            byteSize: writeResult.byteSize,
            width: width,
            height: height
        )
    }
}

struct ClipboardHistoryFilter: Hashable {
    var query: String?
    var contentType: ClipboardContentType?
    var includePinned: Bool = true

    init(query: String? = nil, contentType: ClipboardContentType? = nil, includePinned: Bool = true) {
        self.query = query
        self.contentType = contentType
        self.includePinned = includePinned
    }
}

struct ClipboardRecordSnapshot: Identifiable, Hashable {
    let id: UUID
    let contentType: ClipboardContentType
    let plainText: String?
    let summary: String?
    let contentHash: String
    let isPinned: Bool
    let isFavorite: Bool
    let createdAt: Date
    let updatedAt: Date
    let filePath: URL?
    let fileDisplayName: String?
    let fileUTI: String?
    let fileSize: Int64?
    let resources: [ClipboardResourceSnapshot]
    let resourceStatus: ClipboardResourceStatus
    /// App that produced this clipboard content (Arc, Safari, …).
    let sourceAppBundleID: String?
    let sourceAppName: String?

    var failureReason: String? {
        resourceStatus.failureReason
    }
}

enum ClipboardContentType: String, Codable, CaseIterable, Hashable {
    case text
    case richText
    case image
    case file
}

struct ClipboardResourceSnapshot: Identifiable, Hashable {
    let id: UUID
    let type: ClipboardResourceType
    let relativePath: String
    let mimeType: String?
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let isMissing: Bool
}

enum ClipboardResourceType: String, Codable, CaseIterable, Hashable {
    case imageOriginal
    case imageThumbnail
    case richTextRTF
    case richTextHTML

    var assistantFileSystemType: AssistantClipboardResourceType {
        switch self {
        case .imageOriginal:
            return .imageOriginal
        case .imageThumbnail:
            return .imageThumbnail
        case .richTextRTF:
            return .richTextRTF
        case .richTextHTML:
            return .richTextHTML
        }
    }
}

struct ClipboardResourceStatus: Hashable {
    let missingResourcePaths: [String]
    let missingFileReference: URL?

    var isAvailable: Bool {
        missingResourcePaths.isEmpty && missingFileReference == nil
    }

    var failureReason: String? {
        guard !isAvailable else { return nil }
        var parts: [String] = []
        if !missingResourcePaths.isEmpty {
            parts.append("Missing clipboard resource: \(missingResourcePaths.joined(separator: ", "))")
        }
        if let missingFileReference {
            parts.append("Referenced file is missing: \(missingFileReference.path)")
        }
        return parts.joined(separator: "; ")
    }

    static let available = ClipboardResourceStatus(missingResourcePaths: [], missingFileReference: nil)
}

struct StorageUsage: Hashable {
    let coreDataBytes: Int64
    let resourceBytes: Int64

    var totalBytes: Int64 {
        coreDataBytes + resourceBytes
    }
}

struct ClipboardClearAllConfirmation: Hashable {
    let title: String
    let message: String
    let destructiveButtonTitle: String
    let requiresExplicitConfirmation: Bool
}

protocol ClipboardHistoryServiceProtocol {
    func clearAllConfirmation() -> ClipboardClearAllConfirmation
    func clearAll(confirmed: Bool) async throws
}

final class ClipboardHistoryService: ClipboardHistoryServiceProtocol {
    private let repository: ClipboardRepositoryProtocol

    init(repository: ClipboardRepositoryProtocol) {
        self.repository = repository
    }

    func clearAllConfirmation() -> ClipboardClearAllConfirmation {
        ClipboardClearAllConfirmation(
            title: "Clear Clipboard History",
            message: "This action cannot be undone.",
            destructiveButtonTitle: "Clear All",
            requiresExplicitConfirmation: true
        )
    }

    func clearAll(confirmed: Bool) async throws {
        guard confirmed else {
            throw AssistantClipboardRepositoryError.confirmationRequired
        }
        try await repository.clearAll()
    }
}

// MARK: - Hashing

enum ClipboardContentHasher {
    static func hash(_ payload: ClipboardPayload) -> String {
        switch payload {
        case .plainText(let text):
            return CryptoHelper.sha256("text:\(normalizeText(text))")
        case .richText(let plainText, let rtfData, let htmlData):
            let plainHash = CryptoHelper.sha256(normalizeText(plainText))
            let rtfHash = rtfData.map(CryptoHelper.sha256) ?? "nil"
            let htmlHash = htmlData.map(CryptoHelper.sha256) ?? "nil"
            return CryptoHelper.sha256("richText:\(plainHash):\(rtfHash):\(htmlHash)")
        case .image(let data):
            return CryptoHelper.sha256("image:\(CryptoHelper.sha256(data))")
        case .files(let files):
            let joinedPaths = files
                .map { $0.path.standardizedFileURL.path }
                .sorted()
                .joined(separator: "\n")
            return CryptoHelper.sha256("file:\(joinedPaths)")
        }
    }

    static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Repository implementation

final class ClipboardRepository: @unchecked Sendable, ClipboardRepositoryProtocol {
    private let persistence: PersistenceController
    private let resourceStore: FileResourceStoreProtocol
    private let fileSystem: AssistantFileSystem
    private let fileManager: FileManager

    init(
        persistence: PersistenceController = .shared,
        resourceStore: FileResourceStoreProtocol? = nil,
        fileManager: FileManager = .default
    ) {
        self.persistence = persistence
        self.fileSystem = persistence.fileSystem
        self.resourceStore = resourceStore ?? FileResourceStore(fileSystem: persistence.fileSystem, fileManager: fileManager)
        self.fileManager = fileManager
    }

    func upsert(event: AssistantClipboardEvent, resources: [ClipboardResourceDraft] = []) async throws -> ClipboardRecordSnapshot {
        let context = persistence.viewContext
        return try await context.perform {
            let now = event.capturedAt
            if let existing = try self.fetchRecord(contentHash: event.contentHash, in: context) {
                existing.updatedAt = now
                self.applyPayload(event.payload, to: existing, preservingCreationDate: true)
                try context.saveIfNeeded()
                return try self.makeSnapshot(from: existing)
            }

            let record = CDClipboardRecord(context: context)
            record.id = UUID()
            record.contentHash = event.contentHash
            record.isPinned = false
            record.createdAt = now
            record.updatedAt = now
            record.fileSize = 0
            record.sourceAppBundleID = event.sourceAppBundleID
            record.sourceAppName = event.sourceAppName
            self.applyPayload(event.payload, to: record, preservingCreationDate: false)

            for draft in resources {
                let resource = CDClipboardResource(context: context)
                resource.id = draft.id
                resource.resourceType = draft.type.rawValue
                resource.relativePath = draft.relativePath
                resource.mimeType = draft.mimeType
                resource.byteSize = draft.byteSize
                resource.width = Int32(draft.width ?? 0)
                resource.height = Int32(draft.height ?? 0)
                resource.createdAt = now
                resource.record = record
            }

            do {
                try context.saveIfNeeded()
            } catch {
                for draft in resources {
                    Task { await self.resourceStore.delete(relativePath: draft.relativePath) }
                }
                throw error
            }
            return try self.makeSnapshot(from: record)
        }
    }

    func fetch(id: UUID) async throws -> ClipboardRecordSnapshot? {
        let context = persistence.viewContext
        return try await context.perform {
            guard let record = try self.fetchRecord(id: id, in: context) else { return nil }
            return try self.makeSnapshot(from: record)
        }
    }

    func fetchHistory(filter: ClipboardHistoryFilter = ClipboardHistoryFilter()) async throws -> [ClipboardRecordSnapshot] {
        let context = persistence.viewContext
        return try await context.perform {
            let request = CDClipboardRecord.fetchRequest()
            var predicates: [NSPredicate] = []
            if let contentType = filter.contentType {
                predicates.append(NSPredicate(format: "contentType == %@", contentType.rawValue))
            }
            if !filter.includePinned {
                predicates.append(NSPredicate(format: "isPinned == NO"))
            }
            if let query = filter.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                predicates.append(NSPredicate(format: "plainText CONTAINS[cd] %@ OR summary CONTAINS[cd] %@ OR fileDisplayName CONTAINS[cd] %@ OR filePath CONTAINS[cd] %@", query, query, query, query))
            }
            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            return try context.fetch(request).map { try self.makeSnapshot(from: $0) }
        }
    }

    func delete(id: UUID) async throws {
        let context = persistence.viewContext
        let relativePaths = try await context.perform {
            guard let record = try self.fetchRecord(id: id, in: context) else { return [String]() }
            let paths = record.resources.map(\.relativePath)
            context.delete(record)
            try context.saveIfNeeded()
            return paths
        }
        for relativePath in relativePaths {
            await resourceStore.delete(relativePath: relativePath)
        }
    }

    func clearAll() async throws {
        let context = persistence.viewContext
        let relativePaths = try await context.perform {
            let records = try context.fetch(CDClipboardRecord.fetchRequest())
            let paths = records.flatMap { $0.resources.map(\.relativePath) }
            for record in records {
                context.delete(record)
            }
            try context.saveIfNeeded()
            return paths
        }
        for relativePath in relativePaths {
            await resourceStore.delete(relativePath: relativePath)
        }
    }

    func togglePin(id: UUID) async throws -> ClipboardRecordSnapshot {
        let context = persistence.viewContext
        return try await context.perform {
            guard let record = try self.fetchRecord(id: id, in: context) else {
                throw AssistantClipboardRepositoryError.recordNotFound(id)
            }
            record.isPinned.toggle()
            record.updatedAt = Date()
            try context.saveIfNeeded()
            return try self.makeSnapshot(from: record)
        }
    }

    func toggleFavorite(id: UUID) async throws -> ClipboardRecordSnapshot {
        let context = persistence.viewContext
        return try await context.perform {
            guard let record = try self.fetchRecord(id: id, in: context) else {
                throw AssistantClipboardRepositoryError.recordNotFound(id)
            }
            record.isFavorite.toggle()
            try context.saveIfNeeded()
            return try self.makeSnapshot(from: record)
        }
    }

    func cleanupExpired(now: Date = Date()) async throws -> Int {
        let retention = try await retentionSettingDays()
        guard let retention else { return 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retention, to: now) ?? now
        let context = persistence.viewContext
        let cleanupResult = try await context.perform {
            let request = CDClipboardRecord.fetchRequest()
            request.predicate = NSPredicate(format: "isPinned == NO AND isFavorite == NO AND updatedAt < %@", cutoff as NSDate)
            let records = try context.fetch(request)
            let paths = records.flatMap { $0.resources.map(\.relativePath) }
            let deletedCount = records.count
            for record in records {
                context.delete(record)
            }
            try context.saveIfNeeded()
            return (deletedCount, paths)
        }
        for relativePath in cleanupResult.1 {
            await resourceStore.delete(relativePath: relativePath)
        }
        return cleanupResult.0
    }

    func storageUsage() async throws -> StorageUsage {
        let resourceBytes = try await resourceStore.storageUsage()
        let storeBytes = try coreDataStoreUsage()
        return StorageUsage(coreDataBytes: storeBytes, resourceBytes: resourceBytes)
    }

    private func applyPayload(_ payload: ClipboardPayload, to record: CDClipboardRecord, preservingCreationDate: Bool) {
        switch payload {
        case .plainText(let text):
            record.contentType = ClipboardContentType.text.rawValue
            record.plainText = text
            record.summary = makeSummary(from: text)
            record.filePath = nil
            record.fileDisplayName = nil
            record.fileUTI = nil
            record.fileSize = 0
        case .richText(let plainText, _, _):
            record.contentType = ClipboardContentType.richText.rawValue
            record.plainText = plainText
            record.summary = makeSummary(from: plainText)
            record.filePath = nil
            record.fileDisplayName = nil
            record.fileUTI = nil
            record.fileSize = 0
        case .image:
            record.contentType = ClipboardContentType.image.rawValue
            record.plainText = nil
            record.summary = "Image"
            record.filePath = nil
            record.fileDisplayName = nil
            record.fileUTI = nil
            record.fileSize = 0
        case .files(let files):
            record.contentType = ClipboardContentType.file.rawValue
            let paths = files.map { $0.path.standardizedFileURL.path }
            record.plainText = paths.joined(separator: "\n")
            record.summary = files.map(\.displayName).joined(separator: ", ")
            let first = files.first
            record.filePath = first?.path.standardizedFileURL.path
            record.fileDisplayName = first?.displayName
            record.fileUTI = first?.uti
            record.fileSize = first?.fileSize ?? 0
        }

        if !preservingCreationDate, record.createdAt == .distantPast {
            record.createdAt = Date()
        }
    }

    private func makeSummary(from text: String, limit: Int = 200) -> String {
        let normalized = ClipboardContentHasher.normalizeText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= limit { return normalized }
        return String(normalized.prefix(limit))
    }

    private func makeSnapshot(from record: CDClipboardRecord) throws -> ClipboardRecordSnapshot {
        guard let contentType = ClipboardContentType(rawValue: record.contentType) else {
            throw AssistantClipboardRepositoryError.invalidContentType(record.contentType)
        }

        let resourceSnapshots = record.resources
            .sorted { $0.createdAt < $1.createdAt }
            .map { resource in
                let type = ClipboardResourceType(rawValue: resource.resourceType) ?? .imageOriginal
                let missing = !resourceStore.exists(relativePath: resource.relativePath)
                return ClipboardResourceSnapshot(
                    id: resource.id,
                    type: type,
                    relativePath: resource.relativePath,
                    mimeType: resource.mimeType,
                    byteSize: resource.byteSize,
                    width: resource.width > 0 ? Int(resource.width) : nil,
                    height: resource.height > 0 ? Int(resource.height) : nil,
                    isMissing: missing
                )
            }

        let fileURL = record.filePath.map { URL(fileURLWithPath: $0) }
        let missingFile: URL?
        if contentType == .file, let fileURL, !fileManager.fileExists(atPath: fileURL.path) {
            missingFile = fileURL
        } else {
            missingFile = nil
        }

        let missingPaths = resourceSnapshots
            .filter(\.isMissing)
            .map(\.relativePath)
        let status = ClipboardResourceStatus(missingResourcePaths: missingPaths, missingFileReference: missingFile)

        return ClipboardRecordSnapshot(
            id: record.id,
            contentType: contentType,
            plainText: record.plainText,
            summary: record.summary,
            contentHash: record.contentHash,
            isPinned: record.isPinned,
            isFavorite: record.isFavorite,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            filePath: fileURL,
            fileDisplayName: record.fileDisplayName,
            fileUTI: record.fileUTI,
            fileSize: record.fileSize,
            resources: resourceSnapshots,
            resourceStatus: status,
            sourceAppBundleID: record.sourceAppBundleID,
            sourceAppName: record.sourceAppName
        )
    }

    private func fetchRecord(id: UUID, in context: NSManagedObjectContext) throws -> CDClipboardRecord? {
        let request = CDClipboardRecord.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func fetchRecord(contentHash: String, in context: NSManagedObjectContext) throws -> CDClipboardRecord? {
        let request = CDClipboardRecord.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "contentHash == %@", contentHash)
        return try context.fetch(request).first
    }

    private func retentionSettingDays() async throws -> Int? {
        let context = persistence.viewContext
        return try await context.perform {
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", "clipboard.retention")
            let value = try context.fetch(request).first?.value ?? AssistantSettingDefaults.values["clipboard.retention"] ?? "30d"
            switch value {
            case "7d": return 7
            case "30d": return 30
            case "90d": return 90
            case "forever": return nil
            default: return 30
            }
        }
    }

    private func coreDataStoreUsage() throws -> Int64 {
        let storeURL = fileSystem.storeURL
        let urls = [
            storeURL,
            storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"),
            storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
        ]

        var total: Int64 = 0
        for url in urls where fileManager.fileExists(atPath: url.path) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            total += attributes[.size] as? Int64 ?? Int64(attributes[.size] as? Int ?? 0)
        }
        return total
    }
}

// MARK: - Errors and helpers

enum AssistantClipboardRepositoryError: LocalizedError, Equatable {
    case recordNotFound(UUID)
    case resourceMissing(String)
    case fileWriteFailed(String, String)
    case fileReadFailed(String, String)
    case invalidContentType(String)
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .recordNotFound(let id):
            return "Clipboard record not found: \(id.uuidString)"
        case .resourceMissing(let relativePath):
            return "Clipboard resource is missing: \(relativePath)"
        case .fileWriteFailed(let relativePath, let reason):
            return "Failed to write clipboard resource \(relativePath): \(reason)"
        case .fileReadFailed(let relativePath, let reason):
            return "Failed to read clipboard resource \(relativePath): \(reason)"
        case .invalidContentType(let value):
            return "Invalid clipboard content type: \(value)"
        case .confirmationRequired:
            return "Clear all clipboard history requires explicit confirmation."
        }
    }
}

private extension NSManagedObjectContext {
    func saveIfNeeded() throws {
        if hasChanges {
            try save()
        }
    }
}
