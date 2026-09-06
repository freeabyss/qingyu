import XCTest
@testable import Qingniao

final class SearchServiceCoreTests: XCTestCase {
    func testEmptyInputReturnsNoRecommendations() async {
        let source = MockSearchSource(sourceID: .app, minimumLength: 1, results: [
            .mock(id: "app:notes", sourceID: .app, title: "Notes", baseScore: 100, matchScore: 20)
        ])
        let service = SearchService(sources: [source])

        let response = await service.search(query: "   ")

        XCTAssertTrue(response.results.isEmpty)
        XCTAssertEqual(source.searchCallCount, 0)
    }

    func testPerSourceTriggerRules() async {
        let app = MockSearchSource(sourceID: .app, minimumLength: 1)
        let command = MockSearchSource(sourceID: .command, minimumLength: 1)
        let settings = MockSearchSource(sourceID: .settings, minimumLength: 1)
        let clipboard = MockSearchSource(sourceID: .clipboard, minimumLength: 2)
        let calculator = MockPatternSource(sourceID: .calculator, matches: { $0.contains("+") || $0.contains(" to ") })
        let service = SearchService(sources: [app, command, settings, clipboard, calculator])

        _ = await service.search(query: "a")
        XCTAssertEqual(app.searchCallCount, 1)
        XCTAssertEqual(command.searchCallCount, 1)
        XCTAssertEqual(settings.searchCallCount, 1)
        XCTAssertEqual(clipboard.searchCallCount, 0)
        XCTAssertEqual(calculator.searchCallCount, 0)

        _ = await service.search(query: "ab")
        XCTAssertEqual(clipboard.searchCallCount, 1)

        _ = await service.search(query: "1+2")
        XCTAssertEqual(calculator.searchCallCount, 1)
    }

    func testSortingUsesSourcePriorityTextMatchAndRecentUsage() async {
        let appID = SearchResultID(rawValue: "app:notes")
        let app = MockSearchSource(sourceID: .app, minimumLength: 1, results: [
            .mock(id: appID.rawValue, sourceID: .app, title: "Notes", baseScore: 100, matchScore: 1)
        ])
        let command = MockSearchSource(sourceID: .command, minimumLength: 1, results: [
            .mock(id: "command:note", sourceID: .command, title: "New Note", baseScore: 90, matchScore: 30)
        ])
        let clipboard = MockSearchSource(sourceID: .clipboard, minimumLength: 1, results: [
            .mock(id: "clipboard:note", sourceID: .clipboard, title: "note text", baseScore: 70, matchScore: 5)
        ])
        let usage = MockUsageStore(boosts: [appID: 25])
        let service = SearchService(sources: [clipboard, command, app], usageStore: usage)

        let response = await service.search(query: "note")

        XCTAssertEqual(response.results.map(\.id.rawValue), ["app:notes", "command:note", "clipboard:note"])
        XCTAssertGreaterThan(response.results[0].usageScore, 0)
    }

    func testApplicationNameMatchAlwaysRanksAheadOfOtherSources() async {
        let app = MockSearchSource(sourceID: .app, minimumLength: 1, results: [
            .mock(id: "app:weak", sourceID: .app, title: "Weak App Match", baseScore: 1, matchScore: 1)
        ])
        let command = MockSearchSource(sourceID: .command, minimumLength: 1, results: [
            .mock(id: "command:strong", sourceID: .command, title: "Exact Match", baseScore: 1_000, matchScore: 1_000)
        ])
        let service = SearchService(sources: [command, app])

        let response = await service.search(query: "match")

        XCTAssertEqual(response.results.first?.sourceID, .app)
    }

    func testTotalResultLimitIsTwelveWithApplicationsPrioritized() async {
        let appResults = (0..<10).map { SearchResult.mock(id: "app:\($0)", sourceID: .app, title: "App \($0)", baseScore: 100, matchScore: Double($0)) }
        let commandResults = (0..<10).map { SearchResult.mock(id: "command:\($0)", sourceID: .command, title: "Command \($0)", baseScore: 90, matchScore: Double(20 - $0)) }
        let service = SearchService(sources: [
            MockSearchSource(sourceID: .app, minimumLength: 1, results: appResults),
            MockSearchSource(sourceID: .command, minimumLength: 1, results: commandResults)
        ])

        let response = await service.search(query: "a")

        XCTAssertEqual(response.results.count, 12)
        XCTAssertTrue(response.results.contains { $0.sourceID == .app })
        XCTAssertTrue(response.results.contains { $0.sourceID == .command })
        XCTAssertTrue(response.results.prefix(10).allSatisfy { $0.sourceID == .app })
        XCTAssertEqual(
            response.results.filter { $0.sourceID == .app }.map(\.id),
            response.results.filter { $0.sourceID == .app }.sorted { $0.finalScore > $1.finalScore }.map(\.id)
        )
    }

    func testResultCarriesIconTypeLabelAndPrimaryActionClosesSearchPanel() async throws {
        let executor = MockActionExecutor()
        let service = SearchService(sources: [], actionExecutor: executor)
        let action = SearchAction.openSettings(.general)
        let result = SearchResult.mock(
            id: "setting:general",
            sourceID: .settings,
            title: "Settings",
            icon: .systemSymbol("gearshape"),
            typeLabel: "Settings",
            primaryAction: action
        )

        XCTAssertEqual(result.icon, .systemSymbol("gearshape"))
        XCTAssertEqual(result.typeLabel, "Settings")
        XCTAssertEqual(result.primaryAction, action)

        let response = try await service.execute(result.primaryAction)

        XCTAssertEqual(executor.executedActions, [action])
        XCTAssertTrue(response.shouldCloseSearchPanel)
    }

    func testRecordSelectionFeedsRecentUsageBoost() async {
        let result = SearchResult.mock(id: "command:test", sourceID: .command, title: "Test Command", baseScore: 90, matchScore: 0)
        let source = MockSearchSource(sourceID: .command, minimumLength: 1, results: [result])
        let usageStore = InMemorySearchUsageStore(now: { Date(timeIntervalSince1970: 1_000) })
        let service = SearchService(sources: [source], usageStore: usageStore)

        let before = await service.search(query: "t")
        await service.recordSelection(result)
        let after = await service.search(query: "t")

        XCTAssertGreaterThan(after.results.first?.usageScore ?? 0, before.results.first?.usageScore ?? 0)
    }

    func testSettingsBackedSearchSourceImmediatelyHidesAndRestoresResults() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsBackedSearchSourceTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: AssistantFileSystem(rootDirectory: tempDirectory))
        try persistence.load()
        let settings = SettingsService(persistence: persistence)
        let result = SearchResult.mock(id: "app:notes", sourceID: .app, title: "Notes", baseScore: 100, matchScore: 20)
        let source = MockSearchSource(sourceID: .app, minimumLength: 1, results: [result])
        let wrapped = SettingsBackedSearchSource(source: source, settingsService: settings, settingKey: .appSourceEnabled)
        let service = SearchService(sources: [wrapped])

        let visible = await service.search(query: "n")
        XCTAssertEqual(visible.results.map(\.id.rawValue), ["app:notes"])

        try await settings.set(false, for: .appSourceEnabled)
        let hidden = await service.search(query: "n")
        XCTAssertTrue(hidden.results.isEmpty)

        try await settings.set(true, for: .appSourceEnabled)
        let restored = await service.search(query: "n")
        XCTAssertEqual(restored.results.map(\.id.rawValue), ["app:notes"])
    }
}

private final class MockSearchSource: SearchSource {
    let id: SearchSourceID
    let displayName: String
    let isEnabledInSearch: Bool
    let minimumLength: Int
    let results: [SearchResult]
    private let lock = NSLock()
    private var _searchCallCount = 0

    var searchCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _searchCallCount
    }

    init(
        sourceID: SearchSourceID,
        displayName: String = "Mock",
        isEnabledInSearch: Bool = true,
        minimumLength: Int,
        results: [SearchResult] = []
    ) {
        self.id = sourceID
        self.displayName = displayName
        self.isEnabledInSearch = isEnabledInSearch
        self.minimumLength = minimumLength
        self.results = results
    }

    func canSearch(query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumLength
    }

    func search(query: String) async -> [SearchResult] {
        lock.withLock {
            _searchCallCount += 1
        }
        return results
    }
}

private final class MockPatternSource: SearchSource {
    let id: SearchSourceID
    let displayName = "Pattern"
    let isEnabledInSearch = true
    let matches: (String) -> Bool
    private let lock = NSLock()
    private var _searchCallCount = 0

    var searchCallCount: Int {
        lock.withLock { _searchCallCount }
    }

    init(sourceID: SearchSourceID, matches: @escaping (String) -> Bool) {
        self.id = sourceID
        self.matches = matches
    }

    func canSearch(query: String) -> Bool {
        matches(query)
    }

    func search(query: String) async -> [SearchResult] {
        lock.withLock {
            _searchCallCount += 1
        }
        return []
    }
}

private actor MockUsageStore: SearchUsageStoreProtocol {
    let boosts: [SearchResultID: Double]
    private var recorded: [SearchResultID] = []

    init(boosts: [SearchResultID: Double]) {
        self.boosts = boosts
    }

    func usageBoost(for resultID: SearchResultID, sourceID: SearchSourceID) async -> Double {
        boosts[resultID] ?? 0
    }

    func recordSelection(resultID: SearchResultID, sourceID: SearchSourceID) async {
        recorded.append(resultID)
    }
}

private final class MockActionExecutor: SearchActionExecutorProtocol {
    private(set) var executedActions: [SearchAction] = []

    func execute(_ action: SearchAction) async throws {
        executedActions.append(action)
    }
}

private extension SearchResult {
    static func mock(
        id: String,
        sourceID: SearchSourceID,
        title: String,
        subtitle: String? = nil,
        icon: SearchResultIcon = .systemSymbol("sparkles"),
        typeLabel: String = "Mock",
        baseScore: Double = 0,
        matchScore: Double = 0,
        usageScore: Double = 0,
        primaryAction: SearchAction = .copyText("mock"),
        secondaryActions: [SearchAction] = []
    ) -> SearchResult {
        SearchResult(
            id: SearchResultID(rawValue: id),
            sourceID: sourceID,
            title: title,
            subtitle: subtitle,
            icon: icon,
            typeLabel: typeLabel,
            baseScore: baseScore,
            matchScore: matchScore,
            usageScore: usageScore,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions
        )
    }
}
