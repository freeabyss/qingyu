import XCTest
@testable import Qingyu

final class SettingsSourceTests: XCTestCase {
    private var tempDirectory: URL!
    private var persistence: PersistenceController!
    private var settingsService: SettingsService!

    override func tearDownWithError() throws {
        settingsService = nil
        persistence = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testChinesePinyinMatchesSettingsRoute() async {
        let source = SettingsSource()

        let results = await source.search(query: "jiantieban")

        XCTAssertTrue(results.contains { $0.id.rawValue == "setting:\(SettingsRoute.clipboard.rawValue)" })
    }

    func testInitialsMatchesSettingsRoute() async {
        let source = SettingsSource()

        let results = await source.search(query: "kjj")

        XCTAssertTrue(results.contains { $0.id.rawValue == "setting:\(SettingsRoute.quickLaunch.rawValue)" })
    }

    func testEnglishAliasMatchesRegardlessOfInterfaceLanguage() async {
        let source = SettingsSource()

        let results = await source.search(query: "privacy")

        XCTAssertTrue(results.contains { $0.id.rawValue == "setting:\(SettingsRoute.general.rawValue)" })
    }

    func testDefaultRoutesCoverPageAndSettingSectionEntrypoints() {
        let routes = Set(SettingsSource.defaultRoutes.map(\.id))

        XCTAssertEqual(routes, Set([
            .general,
            .quickLaunch,
            .clipboard,
            .screenshot,
            .about
        ]))
    }

    func testSettingsSearchResultsOnlyOpenRoutesAndDoNotToggleSettings() async {
        let source = SettingsSource()

        let results = await source.search(query: "搜索源开关")

        XCTAssertTrue(results.contains { $0.id.rawValue == "setting:\(SettingsRoute.quickLaunch.rawValue)" })
        XCTAssertTrue(results.allSatisfy { result in
            if case .openSettings = result.primaryAction {
                return result.secondaryActions.isEmpty
            }
            return false
        })
    }

    @MainActor
    func testManagementCenterLanguageSelectionWritesAppleLanguagesAndRelaunches() async throws {
        let suiteName = "AssistantUS019LanguageTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected suite-scoped UserDefaults")
            return
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = InMemoryManagementSettingsService()
        var relaunchCount = 0
        let viewModel = SettingsViewModel(
            settingsService: settings,
            blacklistRepository: EmptyBlacklistRepository(),
            permissionService: StaticPermissionService(),
            launchAtLoginService: NoopLaunchAtLoginService(),
            notificationCenter: NotificationCenter(),
            userDefaults: userDefaults,
            relaunch: { relaunchCount += 1 }
        )

        // 未改语言时保存（例如只动了剪贴板开关）不得重启应用。
        await viewModel.saveSettings()
        XCTAssertNil(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(relaunchCount, 0)

        viewModel.languageMode = .simplifiedChinese
        await viewModel.saveSettings()
        XCTAssertEqual(userDefaults.array(forKey: "AppleLanguages") as? [String], ["zh-Hans"])
        XCTAssertEqual(relaunchCount, 1)

        viewModel.languageMode = .traditionalChinese
        await viewModel.saveSettings()
        XCTAssertEqual(userDefaults.array(forKey: "AppleLanguages") as? [String], ["zh-Hant"])
        XCTAssertEqual(relaunchCount, 2)

        viewModel.languageMode = .japanese
        await viewModel.saveSettings()
        XCTAssertEqual(userDefaults.array(forKey: "AppleLanguages") as? [String], ["ja"])
        XCTAssertEqual(relaunchCount, 3)

        viewModel.languageMode = .french
        await viewModel.saveSettings()
        XCTAssertEqual(userDefaults.array(forKey: "AppleLanguages") as? [String], ["fr"])
        XCTAssertEqual(relaunchCount, 4)

        viewModel.languageMode = .english
        await viewModel.saveSettings()
        XCTAssertEqual(userDefaults.array(forKey: "AppleLanguages") as? [String], ["en"])
        XCTAssertEqual(relaunchCount, 5)

        viewModel.languageMode = .followSystem
        await viewModel.saveSettings()
        XCTAssertNil(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(relaunchCount, 6)
    }

    func testSettingsSourceCanBeHiddenByPersistentSearchSourceSwitch() async throws {
        try makeTemporarySettingsService()
        try await settingsService.set(false, for: .settingsSourceEnabled)
        let source = SettingsSource(settingsService: settingsService)

        let hiddenResults = await source.search(query: "settings")
        XCTAssertTrue(hiddenResults.isEmpty)

        try await settingsService.set(true, for: .settingsSourceEnabled)
        let visibleResults = await source.search(query: "settings")
        XCTAssertFalse(visibleResults.isEmpty)
    }

    private func makeTemporarySettingsService() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantSettingsSourceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        settingsService = SettingsService(persistence: persistence)
    }
}

private actor InMemoryManagementSettingsService: SettingsServiceProtocol {
    private var values = AssistantSettingDefaults.values

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        let raw = try await stringValue(for: key)
        if type == Bool.self, let value = (["true", "1", "yes", "on"].contains(raw.lowercased())) as? T { return value }
        if type == String.self, let value = raw as? T { return value }
        if type == URL.self, let value = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath) as? T { return value }
        if type == ClipboardRetention.self, let value = ClipboardRetention(rawValue: raw) as? T { return value }
        if type == LanguageMode.self, let value = LanguageMode(rawValue: raw) as? T { return value }
        return try JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        switch value {
        case let bool as Bool:
            values[key.rawValue] = bool ? "true" : "false"
        case let string as String:
            values[key.rawValue] = string
        case let url as URL:
            values[key.rawValue] = url.path
        case let retention as ClipboardRetention:
            values[key.rawValue] = retention.rawValue
        case let language as LanguageMode:
            values[key.rawValue] = language.rawValue
        default:
            let data = try JSONEncoder().encode(value)
            values[key.rawValue] = String(data: data, encoding: .utf8)
        }
    }

    func reset(key: SettingKey) async throws {
        values[key.rawValue] = AssistantSettingDefaults.values[key.rawValue]
    }

    func stringValue(for key: SettingKey) async throws -> String {
        values[key.rawValue] ?? ""
    }
}

private final class EmptyBlacklistRepository: SearchBlacklistRepositoryProtocol {
    func add(_ draft: SearchBlacklistDraft) async throws -> SearchBlacklistItemSnapshot {
        SearchBlacklistItemSnapshot(id: UUID(), resultID: draft.resultID, sourceID: draft.sourceID, title: draft.title, resultType: draft.resultType, createdAt: Date())
    }

    func add(result: SearchResult) async throws -> SearchBlacklistItemSnapshot {
        try await add(SearchBlacklistDraft(result: result))
    }

    func list() async throws -> [SearchBlacklistItemSnapshot] { [] }
    func remove(id: UUID) async throws {}
    func remove(sourceID: SearchSourceID, resultID: SearchResultID) async throws {}
    func contains(sourceID: SearchSourceID, resultID: SearchResultID) async -> Bool { false }
}

final class StaticPermissionService: PermissionServiceProtocol {
    func status(for permission: PermissionKind) -> PermissionStatus { .authorized }
    func openSystemSettings(for permission: PermissionKind) {}
    func refreshStatuses() async -> [PermissionKind: PermissionStatus] {
        Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, .authorized) })
    }
    func requestScreenRecordingPrompt() -> Bool { true }
    func onDemandAccessibilityCheck() -> Bool { true }
}

private final class NoopLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool { true }
    func setEnabled(_ enabled: Bool) throws {}
}
