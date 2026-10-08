import AppKit
import XCTest
@testable import Qingyu

final class ClipboardMonitorTests: XCTestCase {
    func testPollEmitsPlainTextEventAndDeduplicatesRecentHashes() async throws {
        let pasteboard = FakePasteboardReader(changeCount: 1)
        let monitor = ClipboardMonitor(pasteboard: pasteboard, idleDowngradeAfter: 60)
        let probe = EventProbe(stream: monitor.events)

        pasteboard.setString("Hello", for: .string)
        pasteboard.bumpChangeCount()
        await monitor.pollNow()

        let event = try await probe.nextRequired()
        XCTAssertEqual(event.payload, .plainText("Hello"))
        XCTAssertEqual(event.contentHash, ClipboardContentHasher.hash(.plainText("Hello")))

        pasteboard.bumpChangeCount()
        await monitor.pollNow()
        let duplicate = await probe.next(timeout: 0.1)
        XCTAssertNil(duplicate)
    }

    func testPollEmitsRichTextWithPlainTextRTFAndHTML() async throws {
        let pasteboard = FakePasteboardReader(changeCount: 1)
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let probe = EventProbe(stream: monitor.events)
        let rtf = Data("{\\rtf1\\ansi Rich}".utf8)
        let html = Data("<b>Rich</b>".utf8)

        pasteboard.setString("Rich", for: .string)
        pasteboard.setData(rtf, for: .rtf)
        pasteboard.setData(html, for: .html)
        pasteboard.bumpChangeCount()
        await monitor.pollNow()

        let event = try await probe.nextRequired()
        guard case .richText(let plainText, let rtfData, let htmlData) = event.payload else {
            return XCTFail("Expected rich text payload")
        }
        XCTAssertEqual(plainText, "Rich")
        XCTAssertEqual(rtfData, rtf)
        XCTAssertEqual(htmlData, html)
    }

    func testFilePayloadOnlyStoresReferencesAndMetadata() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMonitorTests-\(UUID().uuidString).txt")
        try Data("source file content".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let pasteboard = FakePasteboardReader(changeCount: 1)
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let probe = EventProbe(stream: monitor.events)

        pasteboard.fileURLValues = [tempFile]
        pasteboard.bumpChangeCount()
        await monitor.pollNow()

        let event = try await probe.nextRequired()
        guard case .files(let files) = event.payload else {
            return XCTFail("Expected file payload")
        }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, tempFile)
        XCTAssertEqual(files[0].displayName, tempFile.lastPathComponent)
        XCTAssertEqual(files[0].fileSize, Int64("source file content".utf8.count))
        XCTAssertTrue(files[0].uti?.contains("text") == true || files[0].uti == nil)
    }

    func testAdaptivePollingDowngradesAfterIdleAndRestoresAfterChange() async {
        let clock = ManualClock(Date(timeIntervalSince1970: 100))
        let pasteboard = FakePasteboardReader(changeCount: 1)
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            activePollInterval: 0.5,
            idlePollInterval: 2.0,
            idleDowngradeAfter: 1.0,
            now: { clock.date }
        )
        monitor.start()
        XCTAssertEqual(monitor.currentPollInterval, 0.5, accuracy: 0.001)

        clock.date = Date(timeIntervalSince1970: 102)
        await monitor.pollNow()
        XCTAssertEqual(monitor.currentPollInterval, 2.0, accuracy: 0.001)

        pasteboard.setString("Wake up", for: .string)
        pasteboard.bumpChangeCount()
        await monitor.pollNow()
        XCTAssertEqual(monitor.currentPollInterval, 0.5, accuracy: 0.001)
        monitor.stop()
    }

    func testClipboardServiceStoresRichTextImageThumbnailFileAndUpdatesIndex() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        let persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        let resourceStore = FileResourceStore(fileSystem: fileSystem)
        let index = InMemorySearchIndex()
        let baseRepository = ClipboardRepository(persistence: persistence, resourceStore: resourceStore)
        let repository = IndexingClipboardRepository(base: baseRepository, index: index)
        let service = ClipboardService(repository: repository, resourceStore: resourceStore)

        let richEvent = AssistantClipboardEvent(payload: .richText(
            plainText: "Rich Body",
            rtfData: Data("{\\rtf1 Rich Body}".utf8),
            htmlData: Data("<strong>Rich Body</strong>".utf8)
        ))
        let rich = try await XCTUnwrapAsync(try await service.handle(event: richEvent))
        XCTAssertEqual(rich.contentType, .richText)
        XCTAssertEqual(Set(rich.resources.map(\.type)), [.richTextRTF, .richTextHTML])
        XCTAssertNotNil(index.item(id: rich.id))

        let imageData = try XCTUnwrap(makePNG(width: 400, height: 200))
        let imageEvent = AssistantClipboardEvent(payload: .image(data: imageData))
        let image = try await XCTUnwrapAsync(try await service.handle(event: imageEvent))
        XCTAssertEqual(image.contentType, .image)
        let original = try XCTUnwrap(image.resources.first { $0.type == .imageOriginal })
        let thumbnail = try XCTUnwrap(image.resources.first { $0.type == .imageThumbnail })
        XCTAssertTrue(resourceStore.exists(relativePath: original.relativePath))
        XCTAssertTrue(resourceStore.exists(relativePath: thumbnail.relativePath))
        XCTAssertLessThanOrEqual(thumbnail.width ?? 9999, 256)
        XCTAssertLessThanOrEqual(thumbnail.height ?? 9999, 256)

        let sourceFile = tempDirectory.appendingPathComponent("referenced.txt")
        try Data("do not copy me".utf8).write(to: sourceFile)
        let fileEvent = AssistantClipboardEvent(payload: .files([FileClipboardItem(path: sourceFile)]))
        let file = try await XCTUnwrapAsync(try await service.handle(event: fileEvent))
        XCTAssertEqual(file.contentType, .file)
        XCTAssertEqual(file.filePath, sourceFile.standardizedFileURL)
        XCTAssertTrue(file.resources.isEmpty)

        let allResourcesUsage = try await resourceStore.storageUsage()
        XCTAssertGreaterThan(allResourcesUsage, 0)
        XCTAssertEqual(index.historyClipboard(filter: nil, limit: nil, offset: 0).count, 3)
    }

    private func makePNG(width: Int, height: Int) -> Data? {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image.pngData()
    }
}

private actor EventInbox {
    private var events: [AssistantClipboardEvent] = []

    func append(_ event: AssistantClipboardEvent) {
        events.append(event)
    }

    func popFirst() -> AssistantClipboardEvent? {
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }
}

private final class EventProbe {
    private let inbox = EventInbox()
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<AssistantClipboardEvent>) {
        task = Task { [inbox] in
            for await event in stream {
                await inbox.append(event)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    func next(timeout: TimeInterval = 0.5) async -> AssistantClipboardEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = await inbox.popFirst() {
                return event
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await inbox.popFirst()
    }

    func nextRequired(
        timeout: TimeInterval = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AssistantClipboardEvent {
        guard let event = await next(timeout: timeout) else {
            XCTFail("Timed out waiting for clipboard event", file: file, line: line)
            throw TestError.timeout
        }
        return event
    }
}

private final class FakePasteboardReader: PasteboardReading {
    var changeCount: Int
    var storedStrings: [NSPasteboard.PasteboardType: String] = [:]
    var storedData: [NSPasteboard.PasteboardType: Data] = [:]
    var fileURLValues: [URL] = []

    init(changeCount: Int = 0) {
        self.changeCount = changeCount
    }

    var types: [NSPasteboard.PasteboardType] {
        Array(Set(storedStrings.keys).union(storedData.keys).union(fileURLValues.isEmpty ? [] : [.fileURL]))
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        storedStrings[type]
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        storedData[type]
    }

    func fileURLs() -> [URL] {
        fileURLValues
    }

    func setString(_ value: String, for type: NSPasteboard.PasteboardType) {
        storedStrings[type] = value
    }

    func setData(_ value: Data, for type: NSPasteboard.PasteboardType) {
        storedData[type] = value
    }

    func bumpChangeCount() {
        changeCount += 1
    }
}

private final class ManualClock {
    var date: Date
    init(_ date: Date) {
        self.date = date
    }
}

private enum TestError: Error {
    case timeout
}

private func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?) async throws -> T {
    guard let value = try await expression() else {
        throw TestError.timeout
    }
    return value
}
