import AppKit
import XCTest
@testable import Qingniao

@MainActor
final class SearchPanelViewModelTests: XCTestCase {
    func testEmptyInputShowsNoResults() async {
        let service = StubPanelSearchService(results: [Self.makeResult(index: 0)])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "   "
        await viewModel.searchNow()

        let wasSearchCalled = await service.wasSearchCalled()
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(wasSearchCalled)
    }

    func testResultsAreCappedAtTwelveAndSelectionMoves() async {
        let service = StubPanelSearchService(results: (0..<20).map(Self.makeResult(index:)))
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "a"
        await viewModel.searchNow()

        XCTAssertEqual(viewModel.results.count, 12)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        viewModel.moveUp()
        XCTAssertEqual(viewModel.selectedIndex, 11)
        viewModel.moveDown()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testConfirmSelectionExecutesAndClosesPanel() async {
        let service = StubPanelSearchService(results: [Self.makeResult(index: 0)])
        var didClose = false
        let viewModel = SearchPanelViewModel(searchService: service, onClose: {
            didClose = true
        })

        viewModel.query = "a"
        await viewModel.searchNow()
        viewModel.confirmSelection()
        try? await Task.sleep(nanoseconds: 80_000_000)

        let executedActions = await service.actions()
        XCTAssertEqual(executedActions, [.copyText("0")])
        XCTAssertTrue(didClose)
    }

    private static func makeResult(index: Int) -> SearchResult {
        SearchResult(
            id: SearchResultID(rawValue: "test:\(index)"),
            sourceID: .settings,
            title: "Result \(index)",
            subtitle: "Subtitle",
            icon: .systemSymbol("gearshape"),
            typeLabel: "Settings",
            baseScore: 80,
            matchScore: Double(index),
            usageScore: 0,
            primaryAction: .copyText("\(index)"),
            secondaryActions: []
        )
    }

    // MARK: - T-011 command bar

    private static func makeResult(
        source: SearchSourceID,
        id: String,
        title: String,
        action: SearchAction
    ) -> SearchResult {
        SearchResult(
            id: SearchResultID(rawValue: id),
            sourceID: source,
            title: title,
            subtitle: nil,
            icon: .systemSymbol("app"),
            typeLabel: "Type",
            baseScore: 100,
            matchScore: 0,
            usageScore: 0,
            primaryAction: action,
            secondaryActions: []
        )
    }

    func testActiveSourceFiltersVisibleResults() async {
        let mixed = [
            Self.makeResult(source: .app, id: "app:1", title: "Safari", action: .copyText("safari")),
            Self.makeResult(source: .command, id: "command:x", title: "Restart Dock", action: .copyText("dock")),
            Self.makeResult(source: .file, id: "file:1", title: "notes.txt", action: .copyText("notes"))
        ]
        let service = StubPanelSearchService(results: mixed)
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "x"
        await viewModel.searchNow()
        XCTAssertEqual(viewModel.visibleResults.count, 3)

        viewModel.selectSource(.app)
        XCTAssertEqual(viewModel.visibleResults.map { $0.title }, ["Safari"])

        viewModel.selectSource(.file)
        XCTAssertEqual(viewModel.visibleResults.map { $0.title }, ["notes.txt"])

        viewModel.selectSource(.all)
        XCTAssertEqual(viewModel.visibleResults.count, 3)
    }

    func testDangerousCommandRoutesToConfirmationInsteadOfExecuting() async {
        let dangerResult = Self.makeResult(
            source: .command,
            id: "command:restartDock",
            title: "Restart Dock",
            action: .runCommand(CommandID(rawValue: "restartDock"))
        )
        let service = StubPanelSearchService(results: [dangerResult])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "dock"
        await viewModel.searchNow()
        XCTAssertTrue(viewModel.isDangerous(dangerResult))

        viewModel.confirmSelection()
        try? await Task.sleep(nanoseconds: 40_000_000)
        // Pending confirmation, nothing executed yet.
        XCTAssertNotNil(viewModel.pendingDangerResult)
        let before = await service.actions()
        XCTAssertTrue(before.isEmpty)

        viewModel.confirmPendingDanger()
        try? await Task.sleep(nanoseconds: 60_000_000)
        let after = await service.actions()
        XCTAssertEqual(after, [.runCommand(CommandID(rawValue: "restartDock"))])
        XCTAssertNil(viewModel.pendingDangerResult)
    }

    func testCopyCurrentValueCopiesTextWithoutExecuting() async {
        let result = Self.makeResult(source: .app, id: "app:1", title: "Safari", action: .copyText("hello world"))
        let service = StubPanelSearchService(results: [result])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "safari"
        await viewModel.searchNow()

        NSPasteboard.general.clearContents()
        viewModel.copyCurrentValue()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello world")
        let actions = await service.actions()
        XCTAssertTrue(actions.isEmpty)
    }

    func testCalculatorResultIsTopHighlighted() async {
        let calc = SearchResult(
            id: SearchResultID(rawValue: "calculator:1"),
            sourceID: .calculator,
            title: "= 4",
            subtitle: "2+2",
            icon: .systemSymbol("function"),
            typeLabel: "Calculator",
            baseScore: 85,
            matchScore: 30,
            usageScore: 0,
            primaryAction: .copyText("4"),
            secondaryActions: []
        )
        let other = Self.makeResult(source: .app, id: "app:1", title: "Calc App", action: .copyText("x"))
        let service = StubPanelSearchService(results: [calc, other])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "2+2"
        await viewModel.searchNow()
        XCTAssertTrue(viewModel.isCalculatorTopResult(calc))
        XCTAssertFalse(viewModel.isCalculatorTopResult(other))
    }

    func testHomeContentLoadsFromProvider() async {
        let recents = [Self.makeResult(source: .app, id: "app:1", title: "Safari", action: .copyText("s"))]
        let favorites = [Self.makeResult(source: .clipboard, id: "clipboard:1", title: "pinned", action: .copyText("p"))]
        let provider = StubHomeProvider(recents: recents, favorites: favorites)
        let service = StubPanelSearchService(results: [])
        let viewModel = SearchPanelViewModel(searchService: service, homeProvider: provider)

        await viewModel.loadHomeContent()
        XCTAssertEqual(viewModel.recentResults.map { $0.title }, ["Safari"])
        XCTAssertEqual(viewModel.favoriteResults.map { $0.title }, ["pinned"])
        XCTAssertTrue(viewModel.hasHomeContent)
    }

    func testPanelExpandsForQuickActionsQueryOrHomeContent() async {
        let service = StubPanelSearchService(results: [])
        let viewModel = SearchPanelViewModel(searchService: service)
        XCTAssertTrue(viewModel.shouldExpandPanel)

        viewModel.query = "Safari"
        XCTAssertTrue(viewModel.shouldExpandPanel)

        viewModel.query = ""
        let homeResult = Self.makeResult(source: .app, id: "app:1", title: "Safari", action: .copyText("s"))
        let homeProvider = StubHomeProvider(recents: [homeResult], favorites: [])
        let homeViewModel = SearchPanelViewModel(searchService: service, homeProvider: homeProvider)
        await homeViewModel.loadHomeContent()
        XCTAssertTrue(homeViewModel.shouldExpandPanel)
    }

    /// 1.0.0 FeatureGate 关闭：空查询快捷操作只保留剪贴板历史，不出现截图命令。
    func testHomeQuickActionsExcludeScreenshotWhileGateOff() {
        XCTAssertFalse(FeatureGate.screenshotEnabled)
        let service = StubPanelSearchService(results: [])
        let viewModel = SearchPanelViewModel(searchService: service)
        let commandIDs = viewModel.homeQuickActions.compactMap { result -> CommandID? in
            result.primaryAction.commandID
        }

        XCTAssertEqual(commandIDs, [.openClipboardHistory])
    }
}

struct StubHomeProvider: CommandBarHomeProviding {
    let recents: [SearchResult]
    let favorites: [SearchResult]

    func recentResults(limit: Int) async -> [SearchResult] { Array(recents.prefix(limit)) }
    func favoriteResults(limit: Int) async -> [SearchResult] { Array(favorites.prefix(limit)) }
}

actor StubPanelSearchService: SearchServiceProtocol {
    private let stubResults: [SearchResult]
    private(set) var searchWasCalled = false
    private(set) var executedActions: [SearchAction] = []

    func wasSearchCalled() -> Bool { searchWasCalled }
    func actions() -> [SearchAction] { executedActions }

    init(results: [SearchResult]) {
        self.stubResults = results
    }

    func search(query: String) async -> SearchResponse {
        searchWasCalled = true
        return SearchResponse(query: query, results: stubResults, elapsed: 0.01)
    }

    func execute(_ action: SearchAction) async throws -> SearchResponse {
        executedActions.append(action)
        return SearchResponse(query: "", results: [], elapsed: 0, shouldCloseSearchPanel: true)
    }

    func recordSelection(_ result: SearchResult) async {}
}
