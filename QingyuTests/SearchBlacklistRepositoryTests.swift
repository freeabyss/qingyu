import XCTest
@testable import Qingyu

final class SearchBlacklistRepositoryTests: XCTestCase {
    func testAddListContainsAndRemoveConcreteResult() async throws {
        let persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: AssistantFileSystem(rootDirectory: Self.makeTemporaryDirectory()))
        try persistence.load()
        let repository = SearchBlacklistRepository(persistence: persistence)
        let resultID = SearchResultID(rawValue: "command:openSystemSettings")
        let sourceID = SearchSourceID.command

        let containsBeforeAdd = await repository.contains(sourceID: sourceID, resultID: resultID)
        XCTAssertFalse(containsBeforeAdd)

        let added = try await repository.add(SearchBlacklistDraft(
            resultID: resultID,
            sourceID: sourceID,
            title: "Open System Settings",
            resultType: "Command"
        ))

        XCTAssertEqual(added.resultID, resultID)
        XCTAssertEqual(added.sourceID, sourceID)
        let containsAfterAdd = await repository.contains(sourceID: sourceID, resultID: resultID)
        XCTAssertTrue(containsAfterAdd)
        let listed = try await repository.list()
        XCTAssertEqual(listed.map { $0.resultID }, [resultID])

        try await repository.remove(sourceID: sourceID, resultID: resultID)

        let containsAfterRemove = await repository.contains(sourceID: sourceID, resultID: resultID)
        let remaining = try await repository.list()
        XCTAssertFalse(containsAfterRemove)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSearchServiceFiltersOnlyBlacklistedConcreteResultAndRestoresAfterRemoval() async throws {
        let persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: AssistantFileSystem(rootDirectory: Self.makeTemporaryDirectory()))
        try persistence.load()
        let repository = SearchBlacklistRepository(persistence: persistence)
        let hidden = SearchResult.mock(id: "command:hidden", sourceID: .command, title: "Hidden Command", baseScore: 90, matchScore: 20)
        let visible = SearchResult.mock(id: "command:visible", sourceID: .command, title: "Visible Command", baseScore: 90, matchScore: 19)
        let source = MockBlacklistSearchSource(sourceID: .command, results: [hidden, visible])
        let service = SearchService(sources: [source], blacklistChecker: repository)

        _ = try await repository.add(result: hidden)
        let filtered = await service.search(query: "command")

        XCTAssertEqual(filtered.results.map { $0.id }, [visible.id])

        try await repository.remove(sourceID: hidden.sourceID, resultID: hidden.id)
        let restored = await service.search(query: "command")

        XCTAssertEqual(restored.results.map { $0.id }, [hidden.id, visible.id])
    }

    private static func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchBlacklistRepositoryTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class MockBlacklistSearchSource: SearchSource {
    let id: SearchSourceID
    let displayName = "Mock"
    let isEnabledInSearch = true
    let results: [SearchResult]

    init(sourceID: SearchSourceID, results: [SearchResult]) {
        self.id = sourceID
        self.results = results
    }

    func canSearch(query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search(query: String) async -> [SearchResult] {
        results
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
