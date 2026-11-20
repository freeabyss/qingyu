import CoreData
import XCTest
@testable import Qingyu

final class AssistantClipboardRepositoryTests: XCTestCase {
    private var tempDirectory: URL!
    private var persistence: PersistenceController!
    private var fileSystem: AssistantFileSystem!
    private var resourceStore: FileResourceStore!
    private var repository: ClipboardRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantClipboardRepositoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        resourceStore = FileResourceStore(fileSystem: fileSystem)
        repository = ClipboardRepository(persistence: persistence, resourceStore: resourceStore)
    }

    override func tearDownWithError() throws {
        repository = nil
        resourceStore = nil
        persistence = nil
        fileSystem = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testFileResourceStoreWritesReadsDeletesAndMeasuresAllResourceTypes() async throws {
        let imageID = UUID()
        let thumbnailID = UUID()
        let rtfID = UUID()
        let htmlID = UUID()

        let image = try await resourceStore.writeImageOriginal(Data([0, 1, 2, 3]), id: imageID)
        let thumbnail = try await resourceStore.writeThumbnail(Data([4, 5]), id: thumbnailID)
        let rtf = try await resourceStore.writeRichTextRTF(Data("{\\rtf1 hello}".utf8), id: rtfID)
        let html = try await resourceStore.writeRichTextHTML(Data("<b>hello</b>".utf8), id: htmlID)

        XCTAssertEqual(image.relativePath, "Clipboard/Images/\(imageID.uuidString).png")
        XCTAssertEqual(thumbnail.relativePath, "Clipboard/Thumbnails/\(thumbnailID.uuidString).png")
        XCTAssertEqual(rtf.relativePath, "Clipboard/RichText/\(rtfID.uuidString).rtf")
        XCTAssertEqual(html.relativePath, "Clipboard/RichText/\(htmlID.uuidString).html")
        let imageData = try await resourceStore.read(relativePath: image.relativePath)
        let storageUsage = try await resourceStore.storageUsage()
        XCTAssertEqual(imageData, Data([0, 1, 2, 3]))
        XCTAssertEqual(storageUsage, 4 + 2 + Int64("{\\rtf1 hello}".utf8.count) + Int64("<b>hello</b>".utf8.count))

        await resourceStore.delete(relativePath: image.relativePath)
        XCTAssertFalse(resourceStore.exists(relativePath: image.relativePath))
        await XCTAssertThrowsErrorAsync {
            _ = try await resourceStore.read(relativePath: image.relativePath)
        }
    }

    func testContentHashStrategiesAreStableAndTypeScoped() {
        let textA = ClipboardContentHasher.hash(.plainText("Hello\r\nWorld"))
        let textB = ClipboardContentHasher.hash(.plainText("Hello\nWorld"))
        let textCase = ClipboardContentHasher.hash(.plainText("hello\nWorld"))
        XCTAssertEqual(textA, textB)
        XCTAssertNotEqual(textA, textCase)

        let richA = ClipboardContentHasher.hash(.richText(plainText: "Hello", rtfData: Data([1]), htmlData: Data([2])))
        let richB = ClipboardContentHasher.hash(.richText(plainText: "Hello", rtfData: Data([1]), htmlData: Data([3])))
        XCTAssertNotEqual(richA, richB)
        XCTAssertNotEqual(richA, ClipboardContentHasher.hash(.plainText("Hello")))

        XCTAssertEqual(
            ClipboardContentHasher.hash(.image(data: Data([9, 8, 7]))),
            ClipboardContentHasher.hash(.image(data: Data([9, 8, 7])))
        )

        let fileA = FileClipboardItem(path: URL(fileURLWithPath: "/tmp/b.txt"))
        let fileB = FileClipboardItem(path: URL(fileURLWithPath: "/tmp/a.txt"))
        XCTAssertEqual(
            ClipboardContentHasher.hash(.files([fileA, fileB])),
            ClipboardContentHasher.hash(.files([fileB, fileA]))
        )
    }

    func testRepositoryUpsertsTextAndDeduplicatesByUpdatingTimeOnly() async throws {
        let initialDate = Date(timeIntervalSince1970: 100)
        let laterDate = Date(timeIntervalSince1970: 200)
        let first = AssistantClipboardEvent(payload: .plainText("Hello"), capturedAt: initialDate)
        let inserted = try await repository.upsert(event: first, resources: [])

        let duplicate = AssistantClipboardEvent(payload: .plainText("Hello"), capturedAt: laterDate)
        let updated = try await repository.upsert(event: duplicate, resources: [])
        let history = try await repository.fetchHistory(filter: ClipboardHistoryFilter())

        XCTAssertEqual(inserted.id, updated.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(updated.createdAt, initialDate)
        XCTAssertEqual(updated.updatedAt, laterDate)
        XCTAssertFalse(updated.isPinned)
        XCTAssertEqual(updated.contentType, .text)
        XCTAssertEqual(updated.plainText, "Hello")
    }

    func testPinnedDuplicateCopyUpdatesTimeAndKeepsPinned() async throws {
        let event = AssistantClipboardEvent(payload: .plainText("Pinned"), capturedAt: Date(timeIntervalSince1970: 10))
        let inserted = try await repository.upsert(event: event, resources: [])
        let pinned = try await repository.togglePin(id: inserted.id)
        XCTAssertTrue(pinned.isPinned)

        let updated = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("Pinned"), capturedAt: Date(timeIntervalSince1970: 30)),
            resources: []
        )

        XCTAssertEqual(updated.id, inserted.id)
        XCTAssertTrue(updated.isPinned)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 30))
    }

    func testRepositoryStoresRichTextImageAndFileSnapshots() async throws {
        let rtf = try await resourceStore.writeRichTextRTF(Data("{\\rtf1 rich}".utf8), id: UUID())
        let html = try await resourceStore.writeRichTextHTML(Data("<p>rich</p>".utf8), id: UUID())
        let rich = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .richText(plainText: "Rich text", rtfData: Data("{\\rtf1 rich}".utf8), htmlData: Data("<p>rich</p>".utf8))),
            resources: [ClipboardResourceDraft(rtf, type: .richTextRTF), ClipboardResourceDraft(html, type: .richTextHTML)]
        )
        XCTAssertEqual(rich.contentType, .richText)
        XCTAssertEqual(rich.resources.map(\.type).sorted { $0.rawValue < $1.rawValue }, [.richTextHTML, .richTextRTF])
        XCTAssertTrue(rich.resourceStatus.isAvailable)

        let original = try await resourceStore.writeImageOriginal(Data([1, 2, 3]), id: UUID())
        let thumb = try await resourceStore.writeThumbnail(Data([4]), id: UUID())
        let image = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([1, 2, 3]))),
            resources: [ClipboardResourceDraft(original, type: .imageOriginal, width: 10, height: 20), ClipboardResourceDraft(thumb, type: .imageThumbnail, width: 2, height: 4)]
        )
        XCTAssertEqual(image.contentType, .image)
        XCTAssertEqual(image.resources.count, 2)
        XCTAssertEqual(image.resources.first(where: { $0.type == .imageOriginal })?.width, 10)

        let fileURL = tempDirectory.appendingPathComponent("source.txt")
        try Data("file".utf8).write(to: fileURL)
        let file = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .files([FileClipboardItem(path: fileURL, uti: "public.text", fileSize: 4)])),
            resources: []
        )
        XCTAssertEqual(file.contentType, .file)
        XCTAssertEqual(file.filePath, fileURL.standardizedFileURL)
        XCTAssertEqual(file.fileDisplayName, "source.txt")
        XCTAssertEqual(file.fileUTI, "public.text")
        XCTAssertEqual(file.fileSize, 4)
        XCTAssertTrue(file.resourceStatus.isAvailable)
    }

    func testFetchHistoryFiltersByQueryTypeAndPinnedInDefaultOrder() async throws {
        let olderPinned = try await repository.upsert(event: AssistantClipboardEvent(payload: .plainText("alpha"), capturedAt: Date(timeIntervalSince1970: 1)), resources: [])
        _ = try await repository.togglePin(id: olderPinned.id)
        _ = try await repository.upsert(event: AssistantClipboardEvent(payload: .image(data: Data([1])), capturedAt: Date(timeIntervalSince1970: 3)), resources: [])
        let newerText = try await repository.upsert(event: AssistantClipboardEvent(payload: .plainText("beta keyword"), capturedAt: Date(timeIntervalSince1970: 5)), resources: [])

        let all = try await repository.fetchHistory(filter: ClipboardHistoryFilter())
        XCTAssertEqual(all.map(\.id).prefix(2), [olderPinned.id, newerText.id])

        let textOnly = try await repository.fetchHistory(filter: ClipboardHistoryFilter(contentType: .text))
        XCTAssertEqual(Set(textOnly.map(\.contentType)), [.text])

        let query = try await repository.fetchHistory(filter: ClipboardHistoryFilter(query: "keyword"))
        XCTAssertEqual(query.map(\.id), [newerText.id])

        let withoutPinned = try await repository.fetchHistory(filter: ClipboardHistoryFilter(includePinned: false))
        XCTAssertFalse(withoutPinned.contains { $0.id == olderPinned.id })
    }

    func testMissingResourceAndMissingFileReferencesAreRepresentedInSnapshots() async throws {
        let imageResult = try await resourceStore.writeImageOriginal(Data([7, 7]), id: UUID())
        let image = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([7, 7]))),
            resources: [ClipboardResourceDraft(imageResult, type: .imageOriginal)]
        )
        await resourceStore.delete(relativePath: imageResult.relativePath)
        let fetchedMissingImage = try await repository.fetch(id: image.id)
        let missingImage = try XCTUnwrap(fetchedMissingImage)
        XCTAssertFalse(missingImage.resourceStatus.isAvailable)
        XCTAssertEqual(missingImage.resources.first?.isMissing, true)
        // 原因文案已本地化，断言不再绑死英文措辞：只要求非空且带上出问题的资源路径。
        let imageReason = try XCTUnwrap(missingImage.failureReason)
        XCTAssertFalse(imageReason.isEmpty)
        XCTAssertTrue(imageReason.contains("Clipboard/Images"), "原因里应带出缺失的资源路径：\(imageReason)")

        let fileURL = tempDirectory.appendingPathComponent("deleted.txt")
        try Data("gone".utf8).write(to: fileURL)
        let file = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .files([FileClipboardItem(path: fileURL)])),
            resources: []
        )
        try FileManager.default.removeItem(at: fileURL)
        let fetchedMissingFile = try await repository.fetch(id: file.id)
        let missingFile = try XCTUnwrap(fetchedMissingFile)
        XCTAssertFalse(missingFile.resourceStatus.isAvailable)
        let fileReason = try XCTUnwrap(missingFile.failureReason)
        XCTAssertTrue(fileReason.contains("deleted.txt"), "原因里应带出缺失的文件路径：\(fileReason)")
    }

    func testCleanupExpiredDeletesOnlyUnpinnedRecordsAndResources() async throws {
        try await setRetention("7d")
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 + 10 * 24 * 60 * 60)

        let deletableResource = try await resourceStore.writeImageOriginal(Data([1]), id: UUID())
        let deletable = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([1])), capturedAt: oldDate),
            resources: [ClipboardResourceDraft(deletableResource, type: .imageOriginal)]
        )
        let pinned = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("old pinned"), capturedAt: oldDate),
            resources: []
        )
        _ = try await repository.togglePin(id: pinned.id)

        let deleted = try await repository.cleanupExpired(now: now)
        XCTAssertEqual(deleted, 1)
        let deletedRecord = try await repository.fetch(id: deletable.id)
        let pinnedRecord = try await repository.fetch(id: pinned.id)
        XCTAssertNil(deletedRecord)
        XCTAssertNotNil(pinnedRecord)
        XCTAssertFalse(resourceStore.exists(relativePath: deletableResource.relativePath))
    }

    func testStorageUsageIncludesCoreDataAndResources() async throws {
        let image = try await resourceStore.writeImageOriginal(Data([1, 2, 3, 4, 5]), id: UUID())
        _ = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([1, 2, 3, 4, 5]))),
            resources: [ClipboardResourceDraft(image, type: .imageOriginal)]
        )

        let usage = try await repository.storageUsage()
        XCTAssertGreaterThanOrEqual(usage.resourceBytes, 5)
        XCTAssertGreaterThanOrEqual(usage.totalBytes, usage.resourceBytes)
    }

    func testClearAllRequiresServiceConfirmationAndDeletesHistoryAndResources() async throws {
        let service = ClipboardHistoryService(repository: repository)
        let confirmation = service.clearAllConfirmation()
        XCTAssertTrue(confirmation.requiresExplicitConfirmation)
        // 断言与语言无关：直接对照本地化键，避免把英文措辞写死在测试里。
        XCTAssertEqual(confirmation.message, L10n.localized("clipboard.clearAll.message"))
        XCTAssertEqual(confirmation.title, L10n.localized("clipboard.clearAll.title"))
        XCTAssertEqual(confirmation.destructiveButtonTitle, L10n.localized("clipboard.clearAll.button"))

        let resource = try await resourceStore.writeImageOriginal(Data([1]), id: UUID())
        _ = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .image(data: Data([1]))),
            resources: [ClipboardResourceDraft(resource, type: .imageOriginal)]
        )
        await XCTAssertThrowsErrorAsync {
            try await service.clearAll(confirmed: false)
        }

        try await service.clearAll(confirmed: true)
        let remainingHistory = try await repository.fetchHistory(filter: ClipboardHistoryFilter())
        XCTAssertEqual(remainingHistory.count, 0)
        XCTAssertFalse(resourceStore.exists(relativePath: resource.relativePath))
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

    // MARK: - 复制置顶（touch 排序键）

    /// 「复制即重新复制」：touch 只刷新排序键 updatedAt，
    /// createdAt（首次复制时间）与内容一律不动；记录不存在返回 nil。
    func testTouchBumpsSortKeyWithoutChangingCreationDate() async throws {
        let captured = Date(timeIntervalSinceNow: -3600)
        let snapshot = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("hello"), capturedAt: captured),
            resources: []
        )

        let bumped = Date()
        let touched = try await repository.touch(id: snapshot.id, at: bumped)
        XCTAssertEqual(touched?.updatedAt, bumped, "排序键应刷新为 touch 时间")
        XCTAssertEqual(touched?.createdAt, captured, "createdAt 是「首次复制时间」，touch 不得改动")
        XCTAssertEqual(touched?.plainText, "hello", "touch 不得改动内容")

        let missing = try await repository.touch(id: UUID(), at: bumped)
        XCTAssertNil(missing, "不存在的记录返回 nil，不抛错（顺序是次级收益）")
    }

    /// 索引包装层必须把 touch 同步进内存索引：否则历史排序仍旧序，
    /// 「复制置顶」要等重启才可见。
    func testTouchReordersInMemoryHistoryIndex() async throws {
        let index = InMemorySearchIndex()
        let indexing = IndexingClipboardRepository(base: repository, index: index)
        let older = try await indexing.upsert(
            event: AssistantClipboardEvent(payload: .plainText("older"), capturedAt: Date(timeIntervalSinceNow: -600)),
            resources: []
        )
        let newer = try await indexing.upsert(
            event: AssistantClipboardEvent(payload: .plainText("newer"), capturedAt: Date(timeIntervalSinceNow: -60)),
            resources: []
        )

        let firstBefore = index.historyClipboard(filter: nil, limit: nil, offset: 0).first?.clipboardRecordID
        XCTAssertEqual(firstBefore, newer.id, "touch 前更新的记录应在最前")

        _ = try await indexing.touch(id: older.id)
        let firstAfter = index.historyClipboard(filter: nil, limit: nil, offset: 0).first?.clipboardRecordID
        XCTAssertEqual(firstAfter, older.id, "touch 后该条应顶到历史最前（像重新复制一样）")
    }

    // MARK: - 内容大小（人类友好格式）

    /// 行/详情展示的大小口径：文本 = UTF-8 字节，富文本 = RTF+HTML 资源字节和
    /// （资源缺失回退纯文本），图片 = 原图字节（缩略图不计），文件 = 记录大小；
    /// 无可计量内容时为 nil（UI 不显示「0 bytes」）。
    func testContentByteCountsByType() {
        XCTAssertEqual(Self.snapshot(type: .text, plainText: "hello").contentByteCount, 5)
        XCTAssertEqual(Self.snapshot(type: .text, plainText: "你好").contentByteCount, 6, "中文按 UTF-8 字节数计")
        // 富文本：RTF 100 + HTML 50 = 150；缩略图/原图不是富文本资源，不参与。
        XCTAssertEqual(
            Self.snapshot(
                type: .richText,
                plainText: "fallback",
                resources: [
                    Self.resource(type: .richTextRTF, byteSize: 100),
                    Self.resource(type: .richTextHTML, byteSize: 50),
                ]
            ).contentByteCount,
            150
        )
        // 富文本资源全缺失：回退纯文本字节。
        XCTAssertEqual(Self.snapshot(type: .richText, plainText: "fallback").contentByteCount, 8)
        // 图片：只取原图。
        XCTAssertEqual(
            Self.snapshot(
                type: .image,
                resources: [
                    Self.resource(type: .imageOriginal, byteSize: 2048),
                    Self.resource(type: .imageThumbnail, byteSize: 30),
                ]
            ).contentByteCount,
            2048
        )
        XCTAssertEqual(Self.snapshot(type: .file, fileSize: 1024 * 1024).contentByteCount, 1_048_576)
        XCTAssertNil(Self.snapshot(type: .text, plainText: nil).contentByteCount)
        XCTAssertNil(Self.snapshot(type: .file, fileSize: nil).contentByteCount)
    }

    /// 人类友好格式：ByteCountFormatter(.file) 输出「xx bytes / xx KB / xx MB」量级。
    func testFormattedContentSizeIsHumanReadable() {
        // ByteCountFormatter(.file) 随系统语言输出（en「5 bytes」/ zh「5 字节」），
        // 期望值用同一格式化器构造，锁口径不锁语言。
        XCTAssertEqual(
            Self.snapshot(type: .text, plainText: "hello").formattedContentSize,
            ByteCountFormatter.string(fromByteCount: 5, countStyle: .file)
        )
        XCTAssertEqual(
            Self.snapshot(type: .file, fileSize: 2048).formattedContentSize,
            ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file)
        )
        XCTAssertNil(Self.snapshot(type: .text, plainText: nil).formattedContentSize, "无可计量内容不显示，不给「0 bytes」")
    }

    private static func snapshot(
        type: ClipboardContentType,
        plainText: String? = nil,
        resources: [ClipboardResourceSnapshot] = [],
        fileSize: Int64? = nil
    ) -> ClipboardRecordSnapshot {
        ClipboardRecordSnapshot(
            id: UUID(),
            contentType: type,
            plainText: plainText,
            summary: nil,
            contentHash: "hash-\(UUID().uuidString)",
            isPinned: false,
            isFavorite: false,
            createdAt: Date(timeIntervalSinceNow: -60),
            updatedAt: Date(timeIntervalSinceNow: -60),
            filePath: nil,
            fileDisplayName: nil,
            fileUTI: nil,
            fileSize: fileSize,
            resources: resources,
            resourceStatus: .available,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
    }

    private static func resource(type: ClipboardResourceType, byteSize: Int64) -> ClipboardResourceSnapshot {
        ClipboardResourceSnapshot(
            id: UUID(),
            type: type,
            relativePath: "rel/\(type.rawValue)",
            mimeType: nil,
            byteSize: byteSize,
            width: nil,
            height: nil,
            isMissing: false
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        // Expected path.
    }
}
