import CoreData
import XCTest
@testable import Qingyu

final class InMemorySearchIndexTests: XCTestCase {
    private var tempDirectory: URL!
    private var persistence: PersistenceController!
    private var fileSystem: AssistantFileSystem!
    private var resourceStore: FileResourceStore!
    private var baseRepository: ClipboardRepository!
    private var index: InMemorySearchIndex!
    private var indexingRepository: IndexingClipboardRepository!
    private var loader: ClipboardSearchIndexLoader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InMemorySearchIndexTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        resourceStore = FileResourceStore(fileSystem: fileSystem)
        baseRepository = ClipboardRepository(persistence: persistence, resourceStore: resourceStore)
        index = InMemorySearchIndex()
        loader = ClipboardSearchIndexLoader(persistence: persistence, index: index)
        indexingRepository = IndexingClipboardRepository(base: baseRepository, index: index, loader: loader)
    }

    override func tearDownWithError() throws {
        indexingRepository = nil
        loader = nil
        index = nil
        baseRepository = nil
        resourceStore = nil
        persistence = nil
        fileSystem = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testRebuildFromCoreDataLoadsOnlyLightweightIndexFieldsAndResourceIDs() async throws {
        let rtfData = Data(String(repeating: "{\\rtf1 rich payload}", count: 256).utf8)
        let htmlData = Data(String(repeating: "<strong>rich payload</strong>", count: 256).utf8)
        let rtf = try await resourceStore.writeRichTextRTF(rtfData, id: UUID())
        let html = try await resourceStore.writeRichTextHTML(htmlData, id: UUID())
        let rich = try await baseRepository.upsert(
            event: AssistantClipboardEvent(payload: .richText(plainText: "Quarterly Plan", rtfData: rtfData, htmlData: htmlData), capturedAt: Date(timeIntervalSince1970: 100)),
            resources: [ClipboardResourceDraft(rtf, type: .richTextRTF), ClipboardResourceDraft(html, type: .richTextHTML)]
        )

        let imageBytes = Data(repeating: 7, count: 4096)
        let original = try await resourceStore.writeImageOriginal(imageBytes, id: UUID())
        let thumbnail = try await resourceStore.writeThumbnail(Data([1, 2, 3]), id: UUID())
        let image = try await baseRepository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: imageBytes), capturedAt: Date(timeIntervalSince1970: 200)),
            resources: [ClipboardResourceDraft(original, type: .imageOriginal, width: 80, height: 60), ClipboardResourceDraft(thumbnail, type: .imageThumbnail, width: 8, height: 6)]
        )

        try await loader.rebuildFromPersistentStore()

        XCTAssertEqual(index.count, 2)
        let richIndex = try XCTUnwrap(index.item(id: rich.id))
        XCTAssertEqual(richIndex.sourceID, .clipboard)
        XCTAssertEqual(richIndex.recordID, rich.id)
        XCTAssertEqual(richIndex.plainText, "Quarterly Plan")
        XCTAssertEqual(Set(richIndex.resourceReferences), Set(rich.resources.map(\.id)))
        XCTAssertFalse(richIndex.title.contains("rtf1 rich payload"), "Index title must not contain raw RTF data")
        XCTAssertFalse(richIndex.title.contains("<strong>"), "Index title must not contain raw HTML data")

        let imageIndex = try XCTUnwrap(index.item(id: image.id))
        XCTAssertEqual(imageIndex.contentType, .image)
        XCTAssertNil(imageIndex.plainText)
        XCTAssertEqual(Set(imageIndex.resourceReferences), Set(image.resources.map(\.id)))
        XCTAssertFalse(imageIndex.title.contains(String(decoding: imageBytes, as: UTF8.self)), "Index must not load image original bytes")
    }

    func testSearchAndHistoryQueriesSortPinnedMatchScoreAndUpdatedAt() async throws {
        let olderPinned = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("alpha keyword"), capturedAt: Date(timeIntervalSince1970: 10)),
            resources: []
        )
        _ = try await indexingRepository.togglePin(id: olderPinned.id)
        let newerMatch = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("keyword beta"), capturedAt: Date(timeIntervalSince1970: 50)),
            resources: []
        )
        _ = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([9])), capturedAt: Date(timeIntervalSince1970: 90)),
            resources: []
        )

        let searchResults = index.searchClipboard(query: "keyword", filter: .text)
        XCTAssertEqual(searchResults.map(\.id), [olderPinned.id, newerMatch.id])

        let history = index.historyClipboard(filter: nil, limit: nil, offset: 0)
        XCTAssertEqual(history.first?.id, olderPinned.id)
        XCTAssertEqual(history.count, 3)

        let pagedText = index.historyClipboard(filter: .text, limit: 1, offset: 1)
        XCTAssertEqual(pagedText.map(\.id), [newerMatch.id])
    }

    func testIndexSynchronizesUpsertDuplicateDeleteClearAndPinChanges() async throws {
        let inserted = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("sync target"), capturedAt: Date(timeIntervalSince1970: 1)),
            resources: []
        )
        XCTAssertEqual(index.item(id: inserted.id)?.updatedAt, Date(timeIntervalSince1970: 1))

        let duplicate = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("sync target"), capturedAt: Date(timeIntervalSince1970: 5)),
            resources: []
        )
        XCTAssertEqual(duplicate.id, inserted.id)
        XCTAssertEqual(index.item(id: inserted.id)?.updatedAt, Date(timeIntervalSince1970: 5))

        let pinned = try await indexingRepository.togglePin(id: inserted.id)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(index.item(id: inserted.id)?.isPinned, true)

        try await indexingRepository.delete(id: inserted.id)
        XCTAssertNil(index.item(id: inserted.id))

        _ = try await indexingRepository.upsert(event: AssistantClipboardEvent(payload: .plainText("one")), resources: [])
        _ = try await indexingRepository.upsert(event: AssistantClipboardEvent(payload: .plainText("two")), resources: [])
        XCTAssertEqual(index.count, 2)
        try await indexingRepository.clearAll()
        XCTAssertEqual(index.count, 0)
    }

    func testCleanupRebuildsIndexFromPersistentStore() async throws {
        try await setRetention("7d")
        let old = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("old removable"), capturedAt: Date(timeIntervalSince1970: 1_000)),
            resources: []
        )
        let oldPinned = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("old pinned"), capturedAt: Date(timeIntervalSince1970: 1_001)),
            resources: []
        )
        _ = try await indexingRepository.togglePin(id: oldPinned.id)
        let fresh = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("fresh"), capturedAt: Date(timeIntervalSince1970: 1_000 + 9 * 24 * 60 * 60)),
            resources: []
        )

        let deleted = try await indexingRepository.cleanupExpired(now: Date(timeIntervalSince1970: 1_000 + 10 * 24 * 60 * 60))

        XCTAssertEqual(deleted, 1)
        XCTAssertNil(index.item(id: old.id))
        XCTAssertNotNil(index.item(id: oldPinned.id))
        XCTAssertNotNil(index.item(id: fresh.id))
        XCTAssertEqual(index.count, 2)
    }

    func testQueryServiceReturnsIndexHitsAndLoadsDetailsOnDemand() async throws {
        let inserted = try await indexingRepository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("detail lookup text"), capturedAt: Date(timeIntervalSince1970: 123)),
            resources: []
        )
        let service = ClipboardIndexQueryService(index: index, repository: indexingRepository)

        let hits = service.searchIndex(query: "lookup", filter: .text, limit: 5)
        XCTAssertEqual(hits.map(\.id), [inserted.id])
        XCTAssertEqual(hits.first?.plainText, "detail lookup text")

        let detail = try await service.loadDetails(for: try XCTUnwrap(hits.first))
        XCTAssertEqual(detail?.id, inserted.id)
        XCTAssertEqual(detail?.plainText, "detail lookup text")
    }

    private func setRetention(_ value: String) async throws {
        let context = persistence.viewContext
        try await context.perform {
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", "clipboard.retention")
            let setting = try XCTUnwrap(context.fetch(request).first)
            setting.value = value
            setting.updatedAt = Date()
            try context.save()
        }
    }
}
