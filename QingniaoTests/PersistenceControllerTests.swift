import CoreData
import XCTest
@testable import Qingniao

final class PersistenceControllerTests: XCTestCase {
    private var tempDirectory: URL!
    private var persistence: PersistenceController!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantCoreDataTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
    }

    override func tearDownWithError() throws {
        persistence = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testCreatesAssistantDirectoryStructure() throws {
        let fileSystem = persistence.fileSystem

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileSystem.rootDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileSystem.imagesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileSystem.thumbnailsDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileSystem.richTextDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileSystem.logsDirectory.path))
        XCTAssertEqual(fileSystem.storeURL.lastPathComponent, "Qingniao.sqlite")
    }

    func testUUIDResourcePathsAreRelativeToApplicationSupport() {
        let imageID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let htmlID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            persistence.fileSystem.resourcePath(for: imageID, type: .imageOriginal),
            "Clipboard/Images/00000000-0000-0000-0000-000000000001.png"
        )
        XCTAssertEqual(
            persistence.fileSystem.resourcePath(for: htmlID, type: .richTextHTML),
            "Clipboard/RichText/00000000-0000-0000-0000-000000000002.html"
        )
    }

    func testInitializesDefaultAppSettingsWithoutOverwritingExistingValues() throws {
        let context = persistence.viewContext
        let request = CDAppSetting.fetchRequest()
        let settings = try context.fetch(request)
        let dictionary = Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0.value) })

        XCTAssertEqual(dictionary["onboarding.completed"], "false")
        XCTAssertEqual(dictionary["hotkey.search"], "option+space")
        XCTAssertEqual(dictionary["clipboard.enabled"], "true")
        XCTAssertEqual(dictionary["clipboard.retention"], "30d")
        XCTAssertEqual(dictionary["language.mode"], "system")
        XCTAssertEqual(settings.count, AssistantSettingDefaults.values.count)

        let retentionRequest = CDAppSetting.fetchRequest()
        retentionRequest.predicate = NSPredicate(format: "key == %@", "clipboard.retention")
        let retention = try XCTUnwrap(context.fetch(retentionRequest).first)
        retention.value = "90d"
        try context.save()

        try persistence.initializeDefaultSettings(in: context)
        let reloaded = try XCTUnwrap(context.fetch(retentionRequest).first)
        XCTAssertEqual(reloaded.value, "90d")
    }

    func testClipboardRecordResourceCRUDInTemporaryStore() throws {
        let context = persistence.viewContext
        let recordID = UUID()
        let resourceID = UUID()
        let now = Date()

        let record = CDClipboardRecord(context: context)
        record.id = recordID
        record.contentType = "image"
        record.plainText = nil
        record.summary = "Screenshot"
        record.contentHash = "image:abc123"
        record.isPinned = false
        record.createdAt = now
        record.updatedAt = now
        record.fileSize = 0

        let resource = CDClipboardResource(context: context)
        resource.id = resourceID
        resource.resourceType = AssistantClipboardResourceType.imageOriginal.rawValue
        resource.relativePath = persistence.fileSystem.resourcePath(for: resourceID, type: .imageOriginal)
        resource.mimeType = AssistantClipboardResourceType.imageOriginal.mimeType
        resource.byteSize = 12
        resource.width = 100
        resource.height = 80
        resource.createdAt = now
        resource.record = record

        try context.save()

        let fetch = CDClipboardRecord.fetchRequest()
        fetch.predicate = NSPredicate(format: "id == %@", recordID as CVarArg)
        let fetched = try XCTUnwrap(context.fetch(fetch).first)
        XCTAssertEqual(fetched.contentHash, "image:abc123")
        XCTAssertEqual(fetched.resources.count, 1)
        XCTAssertEqual(fetched.resources.first?.relativePath.hasPrefix("Clipboard/Images/"), true)

        fetched.isPinned = true
        fetched.summary = "Updated Screenshot"
        try context.save()

        let updated = try XCTUnwrap(context.fetch(fetch).first)
        XCTAssertTrue(updated.isPinned)
        XCTAssertEqual(updated.summary, "Updated Screenshot")

        context.delete(updated)
        try context.save()

        XCTAssertEqual(try context.count(for: fetch), 0)
        XCTAssertEqual(try context.count(for: CDClipboardResource.fetchRequest()), 0)
    }

    func testCoreEntitiesCanCreateQueryUpdateDelete() throws {
        let context = persistence.viewContext
        let now = Date()

        let blacklist = CDSearchBlacklistItem(context: context)
        blacklist.id = UUID()
        blacklist.sourceID = "app"
        blacklist.resultID = "app:com.apple.TextEdit"
        blacklist.title = "TextEdit"
        blacklist.resultType = "application"
        blacklist.createdAt = now

        let usage = CDUsageStat(context: context)
        usage.id = UUID()
        usage.targetID = "command:captureScreenshot"
        usage.targetType = "command"
        usage.useCount = 1
        usage.lastUsedAt = now
        usage.createdAt = now
        usage.updatedAt = now

        let setting = CDAppSetting(context: context)
        setting.key = "test.setting"
        setting.value = "before"
        setting.updatedAt = now

        try context.save()

        let blacklistRequest = CDSearchBlacklistItem.fetchRequest()
        blacklistRequest.predicate = NSPredicate(format: "sourceID == %@ AND resultID == %@", "app", "app:com.apple.TextEdit")
        XCTAssertEqual(try context.count(for: blacklistRequest), 1)

        let usageRequest = CDUsageStat.fetchRequest()
        usageRequest.predicate = NSPredicate(format: "targetType == %@", "command")
        let fetchedUsage = try XCTUnwrap(context.fetch(usageRequest).first)
        fetchedUsage.useCount += 1
        try context.save()
        XCTAssertEqual(try XCTUnwrap(context.fetch(usageRequest).first).useCount, 2)

        let settingRequest = CDAppSetting.fetchRequest()
        settingRequest.predicate = NSPredicate(format: "key == %@", "test.setting")
        let fetchedSetting = try XCTUnwrap(context.fetch(settingRequest).first)
        fetchedSetting.value = "after"
        try context.save()
        XCTAssertEqual(try XCTUnwrap(context.fetch(settingRequest).first).value, "after")

        context.delete(try XCTUnwrap(context.fetch(blacklistRequest).first))
        context.delete(try XCTUnwrap(context.fetch(usageRequest).first))
        context.delete(try XCTUnwrap(context.fetch(settingRequest).first))
        try context.save()

        XCTAssertEqual(try context.count(for: blacklistRequest), 0)
        XCTAssertEqual(try context.count(for: usageRequest), 0)
        XCTAssertEqual(try context.count(for: settingRequest), 0)
    }

    func testContentHashUniquenessConstraintAndMergePolicyDeduplicateClipboardRecords() throws {
        let entity = try XCTUnwrap(PersistenceController.makeManagedObjectModel().entitiesByName["ClipboardRecord"])
        XCTAssertEqual(entity.uniquenessConstraints as? [[String]], [["contentHash"]])

        let context = persistence.viewContext
        let first = makeRecord(context: context, contentHash: "text:duplicate")
        let second = makeRecord(context: context, contentHash: "text:duplicate")
        first.summary = "first"
        second.summary = "second"

        try context.save()

        let request = CDClipboardRecord.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", "text:duplicate")
        let records = try context.fetch(request)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.contentHash, "text:duplicate")
    }

    private func makeRecord(context: NSManagedObjectContext, contentHash: String) -> CDClipboardRecord {
        let record = CDClipboardRecord(context: context)
        record.id = UUID()
        record.contentType = "text"
        record.plainText = "hello"
        record.summary = "hello"
        record.contentHash = contentHash
        record.isPinned = false
        record.createdAt = Date()
        record.updatedAt = Date()
        record.fileSize = 0
        return record
    }
}
