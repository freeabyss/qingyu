import AppKit
import SwiftUI
import XCTest
@testable import Qingyu

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

    // MARK: - 隐藏搜索结果

    /// 没有注入黑名单仓库时，不提供「隐藏」能力。
    func testCanHideIsFalseWithoutRepository() {
        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))
        XCTAssertFalse(viewModel.canHide(Self.makeResult(index: 0)))
    }

    /// 注入仓库后：隐藏该结果会写入黑名单，并重跑当前查询。
    func testHideWritesToBlacklistAndRerunsQuery() async {
        let service = StubPanelSearchService(results: [Self.makeResult(index: 0)])
        let repo = RecordingBlacklistRepository()
        let viewModel = SearchPanelViewModel(searchService: service, searchBlacklist: repo)

        let result = Self.makeResult(index: 0)
        XCTAssertTrue(viewModel.canHide(result))

        viewModel.query = "a"
        await viewModel.searchNow()
        let searchesBefore = await service.searchCount()

        await viewModel.hide(result)

        let hidden = await repo.hiddenResultIDs()
        XCTAssertEqual(hidden, [result.id], "隐藏应把该结果写进黑名单")
        let searchesAfter = await service.searchCount()
        XCTAssertGreaterThan(searchesAfter, searchesBefore, "隐藏后应重跑查询以移除该结果")
    }




    /// 空状态的 CTA 必须跳到文案所说的那个页面。
    /// 「源被各自关掉」时应去快速启动设置，而不是通用页。
    func testOpenQuickLaunchSettingsPostsQuickLaunchRoute() {
        var received: SettingsRoute?
        let token = NotificationCenter.default.addObserver(
            forName: .openManagementCenter,
            object: nil,
            queue: nil
        ) { note in
            received = note.object as? SettingsRoute
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))
        viewModel.openQuickLaunchSettings()

        XCTAssertEqual(received, .quickLaunch)
    }

    /// 空状态要区分三种原因，各自指向不同的设置入口。
    /// - 没有源（插件停用）→ 去「通用 → 插件管理」
    /// - 有源但全被关掉       → 去「快速启动 → 搜索源」
    /// - 只是没匹配           → 换关键词
    func testEmptyReasonDistinguishesNoSourcesFromDisabledSources() async {
        // 1. 一个源都没有
        let empty = SearchPanelViewModel(
            searchService: SearchService(sources: []),
            sourcesEnabledProvider: { true }
        )
        empty.query = "hit"
        await empty.searchNow()
        XCTAssertEqual(empty.emptyReason, .noSources)

        // 2. 有源，但设置里全关掉了：真实情况下被关掉的源在 search() 里直接返回空
        let disabled = SearchPanelViewModel(
            searchService: SearchService(sources: [SilentSource(id: "plugin.a")]),
            sourcesEnabledProvider: { false }
        )
        disabled.query = "hit"
        await disabled.searchNow()
        XCTAssertEqual(disabled.emptyReason, .allSourcesDisabled)

        // 3. 有源且启用，只是没匹配
        let noMatch = SearchPanelViewModel(
            searchService: SearchService(sources: [SilentSource(id: "plugin.b")]),
            sourcesEnabledProvider: { true }
        )
        noMatch.query = "zzz-nothing"
        await noMatch.searchNow()
        XCTAssertEqual(noMatch.emptyReason, .noMatch)
    }

    /// 插件启停后必须能在**本会话内**换掉搜索源。
    ///
    /// 命令栏持有的是启动时的源快照；若停用插件后仍返回其来源的结果，
    /// 就会出现「侧栏页面已消失、结果却还在」的矛盾。
    func testApplySearchSourcesSwapsSourcesForLaterSearches() async {
        let first = StaticSource(id: "plugin.a", title: "A 结果")
        let second = StaticSource(id: "plugin.b", title: "B 结果")
        let service = SearchService(sources: [first])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.query = "hit"
        await viewModel.searchNow()
        XCTAssertTrue(viewModel.visibleResults.contains { $0.title == "A 结果" })

        viewModel.applySearchSources([second])
        await viewModel.searchNow()
        XCTAssertFalse(viewModel.visibleResults.contains { $0.title == "A 结果" }, "停用的源不应再返回结果")
        XCTAssertTrue(viewModel.visibleResults.contains { $0.title == "B 结果" })
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

    /// 只有存在关键词时才显示内容区；空查询（含仅空白字符）保持输入框形态。
    func testQueryPresenceControlsContentArea() async {
        let service = StubPanelSearchService(results: [])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.open()
        XCTAssertFalse(viewModel.hasQuery)

        viewModel.query = "Safari"
        XCTAssertTrue(viewModel.hasQuery)

        viewModel.query = "   "
        XCTAssertFalse(viewModel.hasQuery, "空白查询不得视为有关键词")
    }

    /// 控制器据此驱动面板高度：`$query` 的流值必须直接给出「有关键词」，
    /// 不能重读 `viewModel.query`（`@Published` 在 willSet 发值，会读到旧值）。
    func testQueryPublisherReportsPresenceForTyping() {
        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))
        var received: [Bool] = []
        let cancellable = viewModel.$query
            .map(SearchPanelViewModel.isQueryPresent)
            .removeDuplicates()
            .sink { received.append($0) }

        viewModel.query = "c"
        viewModel.query = "cl"
        viewModel.query = ""
        viewModel.query = "   "

        XCTAssertEqual(received, [false, true, false])
        cancellable.cancel()
    }

    /// 空查询时命令栏只有输入框：没有可导航内容，回车也不执行任何动作。
    func testEmptyQueryShowsNoContentArea() async {
        let service = StubPanelSearchService(results: [Self.makeResult(index: 0)])
        let viewModel = SearchPanelViewModel(searchService: service)

        viewModel.open()
        await viewModel.searchNow()

        XCTAssertFalse(viewModel.hasQuery)
        XCTAssertTrue(viewModel.navigableResults.isEmpty)

        viewModel.confirmSelection()
        let actions = await service.actions()
        XCTAssertTrue(actions.isEmpty, "空查询回车不得执行动作")
    }

    // MARK: - 空结果态不得抢在结果返回之前出现

    /// 防抖窗口内（结果还没回来）不得显示"未找到匹配项"。
    func testNoResultsStateIsSuppressedWhileResultsArePending() async {
        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))

        viewModel.query = "设"
        XCTAssertFalse(viewModel.shouldShowNoResults, "结果未返回前不得显示未找到匹配项")

        await viewModel.searchNow()
        XCTAssertTrue(viewModel.shouldShowNoResults, "搜索完成且确实没有结果时才显示")
    }

    /// 已有空结果后再追加字符，也不得先闪一次空结果态。
    func testNoResultsStateStaysHiddenWhileNextQueryIsPending() async {
        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))

        viewModel.query = "zzz"
        await viewModel.searchNow()
        XCTAssertTrue(viewModel.shouldShowNoResults)

        viewModel.query = "zzzz"
        XCTAssertFalse(viewModel.shouldShowNoResults, "新查询结果未返回前不得显示空结果态")
    }

    // MARK: - 命令栏面板几何（CommandBarMetrics）

    /// 输入文字展示结果时，输入框必须保持不动：收起与展开的输入行顶边一致。
    func testPanelInputRowStaysAnchoredWhenResultsAppear() {
        let frame = NSRect(x: 0, y: 0, width: 2560, height: 1440)

        let collapsedTop = CommandBarMetrics.panelOriginY(
            visibleFrame: frame,
            panelHeight: CommandBarMetrics.inputRowHeight
        ) + CommandBarMetrics.inputRowHeight
        let expandedTop = CommandBarMetrics.panelOriginY(
            visibleFrame: frame,
            panelHeight: CommandBarMetrics.resultsHeight
        ) + CommandBarMetrics.resultsHeight

        XCTAssertEqual(
            collapsedTop,
            expandedTop,
            accuracy: 0.001,
            "展示结果时输入行顶边不得移动（输入框保持不动）"
        )
        // 输入行顶边固定锚点（可见区中心 + inputRowTopOffset）。
        XCTAssertEqual(collapsedTop, frame.midY + CommandBarMetrics.inputRowTopOffset, accuracy: 0.001)
    }

    /// 输入框应在可见区中部偏上，且不贴住可见区顶部。
    func testPanelInputRowSitsHigherThanPreviousAnchor() {
        let frame = NSRect(x: 0, y: 0, width: 2560, height: 1440)

        let top = CommandBarMetrics.panelOriginY(
            visibleFrame: frame,
            panelHeight: CommandBarMetrics.inputRowHeight
        ) + CommandBarMetrics.inputRowHeight

        XCTAssertGreaterThan(top, frame.midY + 200, "输入框应在可见区中心上方")
        XCTAssertLessThan(top, frame.maxY - frame.height / 8, "输入框不应贴住可见区顶部")
        XCTAssertEqual(top, frame.midY + CommandBarMetrics.inputRowTopOffset, accuracy: 0.001)
    }

    /// 可见区偏小时，展开后的面板仍整体落在可见区内。
    func testPanelStaysInsideShortVisibleFrame() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 600)

        let origin = CommandBarMetrics.panelOriginY(
            visibleFrame: frame,
            panelHeight: CommandBarMetrics.resultsHeight
        )

        XCTAssertGreaterThanOrEqual(origin, frame.minY + CommandBarMetrics.minimumScreenMargin)
        XCTAssertLessThanOrEqual(
            origin + CommandBarMetrics.resultsHeight,
            frame.maxY - CommandBarMetrics.minimumScreenMargin
        )
    }

    // MARK: - 命令栏布局：输入框钉在面板顶部

    /// 面板高于自身内容时（收起/展开转场中途），输入框必须钉在面板顶部，
    /// 不得被 SwiftUI 在容器里垂直居中——否则收发文字时输入框会闪动。
    func testCommandBarInputRowPinnedToPanelTop() {
        let heights = [
            CommandBarMetrics.inputRowHeight,
            CommandBarMetrics.resultsHeight / 2,
            CommandBarMetrics.resultsHeight,
        ]

        for height in heights {
            let offset = renderInputRowTopOffset(width: CommandBarMetrics.width, height: height)
            XCTAssertGreaterThanOrEqual(offset, 0, "\(height)pt 高时应渲染出输入行内容")
            XCTAssertLessThan(offset, 60, "\(height)pt 高时输入行应贴在面板顶部，实测偏移 \(offset)pt")
        }
    }

    /// 把命令栏根视图渲染到指定尺寸，返回"输入行内容顶端相对图片顶边的偏移"。
    ///
    /// 检测用「行内相对对比度」而不是绝对暗度：玻璃语言的 `jadeGlassEdge` 会在窗口
    /// 顶部 32% 叠一层白色内高光（浅色外观最浓 α0.60），面板高于输入行时文字被冲淡，
    /// 绝对亮度阈值在 280/560pt 面板上找不到输入行；而文字与底色的相对反差不受影响，
    /// 用它定位同样能区分「钉在顶部」与「被垂直居中」。
    ///
    /// macOS 26+ 真·玻璃路径（NSGlassEffectView）在离屏渲染里不画底——没有桌面
    /// 可折射，行内采样会整行透明而定位失败。这里垫一层不透明白底并固定浅色外观，
    /// 让「输入行位置」断言与玻璃的具体实现解耦：玻璃负责观感，本测试只管布局。
    private func renderInputRowTopOffset(width: CGFloat, height: CGFloat) -> Int {
        let viewModel = SearchPanelViewModel(searchService: StubPanelSearchService(results: []))
        let host = NSHostingView(
            rootView: CommandBarView(viewModel: viewModel)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)

        let w = rep.pixelsWide, h = rep.pixelsHigh
        let scale = Double(w) / Double(width)
        let x0 = Int(Double(w) * 0.2), x1 = Int(Double(w) * 0.8)
        for y in 0..<h {
            // 每行取采样亮度的中位数当「该行底色」，显著更暗的采样视为文字像素。
            var lumas: [Double] = []
            var x = x0
            while x < x1 {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent >= 0.5 {
                    lumas.append(0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent)
                }
                x += 2
            }
            guard !lumas.isEmpty else { continue }
            let sorted = lumas.sorted()
            let base = sorted[sorted.count / 2]
            let dark = lumas.filter { base - $0 > 0.25 }.count
            if dark >= 3 { return Int(Double(y) / scale) }
        }
        return -1
    }
}

actor StubPanelSearchService: SearchServiceProtocol {
    private let stubResults: [SearchResult]
    private(set) var searchWasCalled = false
    private(set) var searchCallCount = 0
    private(set) var executedActions: [SearchAction] = []

    func wasSearchCalled() -> Bool { searchWasCalled }
    func searchCount() -> Int { searchCallCount }
    func actions() -> [SearchAction] { executedActions }

    init(results: [SearchResult]) {
        self.stubResults = results
    }

    func search(query: String) async -> SearchResponse {
        searchWasCalled = true
        searchCallCount += 1
        return SearchResponse(query: query, results: stubResults, elapsed: 0.01)
    }

    func execute(_ action: SearchAction) async throws -> SearchResponse {
        executedActions.append(action)
        return SearchResponse(query: "", results: [], elapsed: 0, shouldCloseSearchPanel: true)
    }

    func recordSelection(_ result: SearchResult) async {}
}

/// 记录隐藏了哪些结果 ID 的黑名单仓库替身，用于验证「隐藏此结果」写入链路。
private actor RecordingBlacklistRepository: SearchBlacklistRepositoryProtocol {
    private var hiddenIDs: [SearchResultID] = []

    func hiddenResultIDs() -> [SearchResultID] { hiddenIDs }

    func add(_ draft: SearchBlacklistDraft) async throws -> SearchBlacklistItemSnapshot {
        hiddenIDs.append(draft.resultID)
        return SearchBlacklistItemSnapshot(id: UUID(), resultID: draft.resultID, sourceID: draft.sourceID, title: draft.title, resultType: draft.resultType, createdAt: Date())
    }

    func add(result: SearchResult) async throws -> SearchBlacklistItemSnapshot {
        try await add(SearchBlacklistDraft(result: result))
    }

    func list() async throws -> [SearchBlacklistItemSnapshot] { [] }
    func remove(id: UUID) async throws {}
    func remove(sourceID: SearchSourceID, resultID: SearchResultID) async throws {}
    func contains(sourceID: SearchSourceID, resultID: SearchResultID) async -> Bool {
        hiddenIDs.contains(resultID)
    }
}

/// 固定返回一条结果的搜索源，用来验证源集合可以在运行期替换。
private final class StaticSource: SearchSource {
    let id: SearchSourceID
    let displayName = "Static"
    let isEnabledInSearch = true
    private let title: String

    init(id: String, title: String) {
        self.id = SearchSourceID(rawValue: id)
        self.title = title
    }

    func canSearch(query: String) -> Bool { true }

    func search(query: String) async -> [SearchResult] {
        [SearchResult(
            id: SearchResultID(rawValue: "\(id.rawValue)-\(title)"),
            sourceID: id,
            title: title,
            subtitle: nil,
            icon: .systemSymbol("doc"),
            typeLabel: "Type",
            baseScore: 100,
            matchScore: 0,
            usageScore: 0,
            primaryAction: .copyText(title),
            secondaryActions: []
        )]
    }
}

/// 永不返回结果的搜索源：模拟「被设置关掉」的源（真实实现同样返回空）。
private final class SilentSource: SearchSource {
    let id: SearchSourceID
    let displayName = "Silent"
    let isEnabledInSearch = true

    init(id: String) {
        self.id = SearchSourceID(rawValue: id)
    }

    func canSearch(query: String) -> Bool { true }
    func search(query: String) async -> [SearchResult] { [] }
}
