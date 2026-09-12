import CoreData
import Foundation
import os.log

/// Core Data stack for the Assistant MVP data layer.
///
/// The model is created in code so the data layer can be exercised from both
/// SwiftPM and the Xcode app target without relying on a generated .xcdatamodel
/// during the MVP migration away from the legacy GRDB store.
final class PersistenceController {
    /// Shared instance used throughout the app. In DEBUG builds a test override
    /// (set via `setDebugShared` before first access) takes precedence, enabling
    /// `--uitest-data-dir` data isolation. In Release the override mechanism is
    /// compiled out and `shared` always returns the default singleton.
    static var shared: PersistenceController {
        #if DEBUG
        if let override = _debugOverride {
            return override
        }
        #endif
        return _defaultShared
    }

    private static let _defaultShared = PersistenceController()

    #if DEBUG
    /// DEBUG-only override for UITest data isolation. Must be set before any code
    /// accesses `shared` (i.e. at the very start of `applicationDidFinishLaunching`).
    private static var _debugOverride: PersistenceController?

    /// Replace the shared instance for `--uitest-data-dir` data isolation (DEBUG only).
    static func setDebugShared(_ controller: PersistenceController) {
        _debugOverride = controller
    }
    #endif

    let container: NSPersistentContainer
    let fileSystem: AssistantFileSystem

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private static let managedObjectModel: NSManagedObjectModel = makeManagedObjectModel()

    convenience init() {
        self.init(storeConfiguration: .persistent(), fileSystem: .default)
    }

    init(storeConfiguration: StoreConfiguration, fileSystem: AssistantFileSystem) {
        self.fileSystem = fileSystem
        self.container = NSPersistentContainer(name: "Qingniao", managedObjectModel: Self.managedObjectModel)

        let description = NSPersistentStoreDescription()
        switch storeConfiguration {
        case .persistent(let storeURL):
            description.type = NSSQLiteStoreType
            description.url = storeURL ?? fileSystem.storeURL
        case .temporary:
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Loads the persistent store, creates required Application Support
    /// directories, and inserts default AppSetting rows if they are missing.
    func load() throws {
        try fileSystem.ensureDirectoryStructure()

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        try initializeDefaultSettings(in: viewContext)
    }

    /// Creates all default AppSetting rows without overwriting existing user values.
    func initializeDefaultSettings(in context: NSManagedObjectContext) throws {
        for (key, value) in AssistantSettingDefaults.values {
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
            if try context.count(for: request) == 0 {
                let setting = CDAppSetting(context: context)
                setting.key = key
                setting.value = value
                setting.updatedAt = Date()
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let clipboardRecord = NSEntityDescription()
        clipboardRecord.name = "ClipboardRecord"
        clipboardRecord.managedObjectClassName = NSStringFromClass(CDClipboardRecord.self)

        let clipboardResource = NSEntityDescription()
        clipboardResource.name = "ClipboardResource"
        clipboardResource.managedObjectClassName = NSStringFromClass(CDClipboardResource.self)

        let blacklistItem = NSEntityDescription()
        blacklistItem.name = "SearchBlacklistItem"
        blacklistItem.managedObjectClassName = NSStringFromClass(CDSearchBlacklistItem.self)

        let usageStat = NSEntityDescription()
        usageStat.name = "UsageStat"
        usageStat.managedObjectClassName = NSStringFromClass(CDUsageStat.self)

        let appSetting = NSEntityDescription()
        appSetting.name = "AppSetting"
        appSetting.managedObjectClassName = NSStringFromClass(CDAppSetting.self)

        clipboardRecord.properties = [
            attribute("id", .UUIDAttributeType, isOptional: false),
            attribute("contentType", .stringAttributeType, isOptional: false),
            attribute("plainText", .stringAttributeType),
            attribute("summary", .stringAttributeType),
            attribute("contentHash", .stringAttributeType, isOptional: false),
            attribute("isPinned", .booleanAttributeType, isOptional: false, defaultValue: false),
            attribute("isFavorite", .booleanAttributeType, isOptional: false, defaultValue: false),
            attribute("createdAt", .dateAttributeType, isOptional: false),
            attribute("updatedAt", .dateAttributeType, isOptional: false),
            attribute("filePath", .stringAttributeType),
            attribute("fileDisplayName", .stringAttributeType),
            attribute("fileUTI", .stringAttributeType),
            attribute("fileSize", .integer64AttributeType, isOptional: false, defaultValue: 0)
        ]
        clipboardRecord.uniquenessConstraints = [["contentHash"]]

        clipboardResource.properties = [
            attribute("id", .UUIDAttributeType, isOptional: false),
            attribute("resourceType", .stringAttributeType, isOptional: false),
            attribute("relativePath", .stringAttributeType, isOptional: false),
            attribute("mimeType", .stringAttributeType),
            attribute("byteSize", .integer64AttributeType, isOptional: false, defaultValue: 0),
            attribute("width", .integer32AttributeType, isOptional: false, defaultValue: 0),
            attribute("height", .integer32AttributeType, isOptional: false, defaultValue: 0),
            attribute("createdAt", .dateAttributeType, isOptional: false)
        ]

        blacklistItem.properties = [
            attribute("id", .UUIDAttributeType, isOptional: false),
            attribute("resultID", .stringAttributeType, isOptional: false),
            attribute("sourceID", .stringAttributeType, isOptional: false),
            attribute("title", .stringAttributeType, isOptional: false),
            attribute("resultType", .stringAttributeType, isOptional: false),
            attribute("createdAt", .dateAttributeType, isOptional: false)
        ]
        blacklistItem.uniquenessConstraints = [["sourceID", "resultID"]]

        usageStat.properties = [
            attribute("id", .UUIDAttributeType, isOptional: false),
            attribute("targetID", .stringAttributeType, isOptional: false),
            attribute("targetType", .stringAttributeType, isOptional: false),
            attribute("useCount", .integer64AttributeType, isOptional: false, defaultValue: 0),
            attribute("lastUsedAt", .dateAttributeType),
            attribute("createdAt", .dateAttributeType, isOptional: false),
            attribute("updatedAt", .dateAttributeType, isOptional: false)
        ]
        usageStat.uniquenessConstraints = [["targetType", "targetID"]]

        appSetting.properties = [
            attribute("key", .stringAttributeType, isOptional: false),
            attribute("value", .stringAttributeType, isOptional: false),
            attribute("updatedAt", .dateAttributeType, isOptional: false)
        ]
        appSetting.uniquenessConstraints = [["key"]]

        let recordResources = NSRelationshipDescription()
        recordResources.name = "resources"
        recordResources.destinationEntity = clipboardResource
        recordResources.minCount = 0
        recordResources.maxCount = 0
        recordResources.deleteRule = .cascadeDeleteRule
        recordResources.isOptional = true

        let resourceRecord = NSRelationshipDescription()
        resourceRecord.name = "record"
        resourceRecord.destinationEntity = clipboardRecord
        resourceRecord.minCount = 0
        resourceRecord.maxCount = 1
        resourceRecord.deleteRule = .nullifyDeleteRule
        resourceRecord.isOptional = true

        recordResources.inverseRelationship = resourceRecord
        resourceRecord.inverseRelationship = recordResources

        clipboardRecord.properties.append(recordResources)
        clipboardResource.properties.append(resourceRecord)

        model.entities = [
            clipboardRecord,
            clipboardResource,
            blacklistItem,
            usageStat,
            appSetting
        ]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        isOptional: Bool = true,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = isOptional
        description.defaultValue = defaultValue
        return description
    }
}

extension PersistenceController {
    enum StoreConfiguration {
        case persistent(storeURL: URL? = nil)
        case temporary
    }
}

@objc(CDClipboardRecord)
final class CDClipboardRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var contentType: String
    @NSManaged var plainText: String?
    @NSManaged var summary: String?
    @NSManaged var contentHash: String
    @NSManaged var isPinned: Bool
    @NSManaged var isFavorite: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var filePath: String?
    @NSManaged var fileDisplayName: String?
    @NSManaged var fileUTI: String?
    @NSManaged var fileSize: Int64
    @NSManaged var resources: Set<CDClipboardResource>
}

extension CDClipboardRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDClipboardRecord> {
        NSFetchRequest<CDClipboardRecord>(entityName: "ClipboardRecord")
    }
}

@objc(CDClipboardResource)
final class CDClipboardResource: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var resourceType: String
    @NSManaged var relativePath: String
    @NSManaged var mimeType: String?
    @NSManaged var byteSize: Int64
    @NSManaged var width: Int32
    @NSManaged var height: Int32
    @NSManaged var createdAt: Date
    @NSManaged var record: CDClipboardRecord?
}

extension CDClipboardResource {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDClipboardResource> {
        NSFetchRequest<CDClipboardResource>(entityName: "ClipboardResource")
    }
}

@objc(CDSearchBlacklistItem)
final class CDSearchBlacklistItem: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var resultID: String
    @NSManaged var sourceID: String
    @NSManaged var title: String
    @NSManaged var resultType: String
    @NSManaged var createdAt: Date
}

extension CDSearchBlacklistItem {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDSearchBlacklistItem> {
        NSFetchRequest<CDSearchBlacklistItem>(entityName: "SearchBlacklistItem")
    }
}

@objc(CDUsageStat)
final class CDUsageStat: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var targetID: String
    @NSManaged var targetType: String
    @NSManaged var useCount: Int64
    @NSManaged var lastUsedAt: Date?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

extension CDUsageStat {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDUsageStat> {
        NSFetchRequest<CDUsageStat>(entityName: "UsageStat")
    }
}

@objc(CDAppSetting)
final class CDAppSetting: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var value: String
    @NSManaged var updatedAt: Date
}

extension CDAppSetting {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDAppSetting> {
        NSFetchRequest<CDAppSetting>(entityName: "AppSetting")
    }
}

struct AssistantSettingDefaults {
    static let values: [String: String] = [
        // Legacy onboarding boolean retained for the current onboarding gating
        // (AppDelegate/OnboardingViewModel). The onboarding gating rewire to
        // `onboarding.completedAt` is out of scope for T-003.
        "onboarding.completed": "false",
        // v1.2 (db.md §8.3): `onboarding.completedAt` (Date?, empty string == nil).
        // Non-empty means completed/skipped. Added now; gating switch is deferred.
        "onboarding.completedAt": "",
        "hotkey.search": "option+space",
        // v1.2: screenshot capture hotkey defaults (mirror KeyboardShortcuts.Name defaults).
        "hotkey.capture.region": "shift+ctrl+cmd+4",
        "hotkey.capture.window": "shift+ctrl+cmd+5",
        "hotkey.capture.fullscreen": "ctrl+option+cmd+3",
        "launchAtLogin.enabled": "true",
        "clipboard.enabled": "true",
        "clipboard.showInSearch": "true",
        "clipboard.retention": "30d",
        "search.source.app.enabled": "true",
        "search.source.command.enabled": "true",
        "search.source.calculator.enabled": "true",
        "search.source.settings.enabled": "true",
        // v1.2: FileSearchSource display toggle.
        "search.source.file.enabled": "true",
        "screenshot.saveDirectory": "~/Desktop",
        // Task 007: quick-save target directory for the completion coordinator.
        "screenshot.quickSaveDirectory": "~/Desktop",
        // Task 008: pin (贴图) defaults — file-path→image on first pin, restore queue of 1.
        "pin.filePathToImage": "true",
        "pin.restoreCapacity": "1",
        // v1.2: appearance mode (system/light/dark).
        "appearance.mode": "system",
        // v1.2: security-scoped bookmark for a user-chosen data/screenshot directory (nil by default).
        "data.folderBookmark": "",
        "language.mode": "system"
    ]
}
