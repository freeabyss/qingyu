import CoreData
import Foundation
import GRDB

/// Legacy GRDB application settings stored as key-value pairs in the old database.
///
/// Assistant MVP settings are persisted through `SettingsService` and `CDAppSetting`.
/// This type remains only for legacy services that still read the old GRDB store while
/// the project is being migrated task-by-task.
struct AppSetting: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "app_settings"

    var key: String
    var value: String

    var id: String { key }
}

/// Legacy GRDB setting keys kept for compatibility with pre-MVP services.
enum LegacySettingKey {
    static let retentionDays = "retention_days"
    static let maxStorageMB = "max_storage_mb"
    static let ocrEnabled = "ocr_enabled"
    static let pollIntervalMs = "poll_interval_ms"
    static let searchProvider = "search_provider"
    static let launchAtLoginEnabled = "launch_at_login_enabled"

    static let defaults: [String: String] = [
        retentionDays: "30",
        maxStorageMB: "500",
        ocrEnabled: "1",
        pollIntervalMs: "500",
        searchProvider: "fts",
        launchAtLoginEnabled: "1"
    ]
}

/// Assistant MVP strongly typed setting keys backed by Core Data `CDAppSetting` rows.
enum SettingKey: String, CaseIterable, Codable {
    case onboardingCompleted = "onboarding.completed"
    case onboardingCompletedAt = "onboarding.completedAt"
    case searchHotkey = "hotkey.search"
    case launchAtLoginEnabled = "launchAtLogin.enabled"
    case clipboardEnabled = "clipboard.enabled"
    case clipboardShowInSearch = "clipboard.showInSearch"
    case clipboardRetention = "clipboard.retention"
    case appSourceEnabled = "search.source.app.enabled"
    case commandSourceEnabled = "search.source.command.enabled"
    case calculatorSourceEnabled = "search.source.calculator.enabled"
    case settingsSourceEnabled = "search.source.settings.enabled"
    case fileSourceEnabled = "search.source.file.enabled"
    case screenshotSaveDirectory = "screenshot.saveDirectory"
    case screenshotQuickSaveDirectory = "screenshot.quickSaveDirectory"
    // Task 008: pin (贴图) settings.
    case pinFilePathToImage = "pin.filePathToImage"
    case pinRestoreCapacity = "pin.restoreCapacity"
    case appearanceMode = "appearance.mode"
    case dataFolderBookmark = "data.folderBookmark"
    case languageMode = "language.mode"
    /// 关键词跳转的用户定制（改写关键词 / 自定义条目），值为 JSON。
    case keywordLaunchCustomization = "search.keywordLaunch"
}

enum ClipboardRetention: String, Codable, CaseIterable, Hashable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case forever = "forever"

    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .forever: return nil
        }
    }
}

enum LanguageMode: String, Codable, CaseIterable, Hashable, Sendable {
    case followSystem = "system"
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .followSystem: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// v1.2: appearance override (system / light / dark). Backed by `appearance.mode`.
enum AppearanceMode: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark
}

protocol SettingsServiceProtocol {
    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T
    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws
    func reset(key: SettingKey) async throws
    func stringValue(for key: SettingKey) async throws -> String
}

actor SettingsService: SettingsServiceProtocol {
    private let persistence: PersistenceController
    private let context: NSManagedObjectContext
    private let now: () -> Date

    init(
        persistence: PersistenceController = .shared,
        context: NSManagedObjectContext? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.context = context ?? persistence.viewContext
        self.now = now
    }

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        let rawValue = try await stringValue(for: key)
        return try decode(rawValue, as: type)
    }

    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        let encoded = try encode(value)
        try await context.perform { [context, now] in
            let setting = try Self.fetchOrInsert(key: key, in: context)
            setting.value = encoded
            setting.updatedAt = now()
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func reset(key: SettingKey) async throws {
        guard let defaultValue = AssistantSettingDefaults.values[key.rawValue] else {
            throw SettingsServiceError.missingDefault(key.rawValue)
        }
        try await context.perform { [context, now] in
            let setting = try Self.fetchOrInsert(key: key, in: context)
            setting.value = defaultValue
            setting.updatedAt = now()
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func stringValue(for key: SettingKey) async throws -> String {
        try await context.perform { [context] in
            let request = CDAppSetting.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key.rawValue)

            if let setting = try context.fetch(request).first {
                return setting.value
            }

            guard let defaultValue = AssistantSettingDefaults.values[key.rawValue] else {
                throw SettingsServiceError.missingDefault(key.rawValue)
            }

            let setting = CDAppSetting(context: context)
            setting.key = key.rawValue
            setting.value = defaultValue
            setting.updatedAt = Date()
            try context.save()
            return defaultValue
        }
    }

    private static func fetchOrInsert(key: SettingKey, in context: NSManagedObjectContext) throws -> CDAppSetting {
        let request = CDAppSetting.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "key == %@", key.rawValue)
        if let existing = try context.fetch(request).first {
            return existing
        }

        let setting = CDAppSetting(context: context)
        setting.key = key.rawValue
        setting.value = AssistantSettingDefaults.values[key.rawValue] ?? ""
        setting.updatedAt = Date()
        return setting
    }

    private func decode<T: Decodable>(_ rawValue: String, as type: T.Type) throws -> T {
        if type == String.self, let value = rawValue as? T { return value }
        if type == Bool.self, let value = Self.parseBool(rawValue) as? T { return value }
        if type == Int.self, let value = Int(rawValue) as? T { return value }
        if type == URL.self, let value = URL(fileURLWithPath: Self.expandTilde(rawValue)) as? T { return value }
        if type == ClipboardRetention.self, let value = ClipboardRetention(rawValue: rawValue) as? T { return value }
        if type == LanguageMode.self, let value = LanguageMode(rawValue: rawValue) as? T { return value }
        if type == AppearanceMode.self, let value = AppearanceMode(rawValue: rawValue) as? T { return value }

        let data = Data(rawValue.utf8)
        return try JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let url as URL:
            return url.path
        case let retention as ClipboardRetention:
            return retention.rawValue
        case let language as LanguageMode:
            return language.rawValue
        case let appearance as AppearanceMode:
            return appearance.rawValue
        default:
            let data = try JSONEncoder().encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw SettingsServiceError.encodingFailed
            }
            return string
        }
    }

    private static func parseBool(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on": return true
        default: return false
        }
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

enum SettingsServiceError: LocalizedError, Equatable {
    case missingDefault(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingDefault(let key):
            return "Missing default value for setting key: \(key)"
        case .encodingFailed:
            return "Failed to encode setting value as UTF-8 string."
        }
    }
}
