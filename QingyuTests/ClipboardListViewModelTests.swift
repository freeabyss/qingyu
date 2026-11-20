import XCTest
@testable import Qingyu

@MainActor
final class ClipboardListViewModelTests: XCTestCase {
    func testLoadHistoryUsesIndexAndFiltersTextOnly() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository(storageUsage: StorageUsage(coreDataBytes: 100, resourceBytes: 250))
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        viewModel.selection = .text
        await viewModel.load()

        // 文本 filter includes both plain text and rich text.
        XCTAssertEqual(viewModel.items.map(\.id), [fixtures.text.id, fixtures.richText.id])
        XCTAssertEqual(viewModel.formattedStorageUsage, ByteCountFormatter.string(fromByteCount: 350, countStyle: .file))
        XCTAssertNil(queryService.historyCalls.last?.filter, "Text selection loads all types then post-filters text+richText.")
    }

    func testSearchUsesDebouncedQueryPathAndImageFilter() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        viewModel.query = "image"
        viewModel.selection = .image
        await viewModel.load()

        XCTAssertEqual(viewModel.items.map(\.id), [fixtures.image.id])
        XCTAssertEqual(queryService.searchCalls.last?.query, "image")
        XCTAssertEqual(queryService.searchCalls.last?.filter, .image)
    }

    func testKeyboardSelectionAndEnterCopySelectedRecord() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let executor = MockClipboardActionExecutor()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: executor,
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        await viewModel.load()
        viewModel.moveSelectionDown()
        await viewModel.copySelectedToPasteboard().value

        XCTAssertEqual(viewModel.selectedItem?.id, fixtures.richText.id)
        XCTAssertEqual(executor.executedActions, [.copyClipboardRecord(fixtures.richText.id)])
    }

    func testTogglePinFavoriteDeleteAndClearAllDelegateToRepositoryChain() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let historyService = MockClipboardHistoryService(repository: repository)
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: historyService,
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        await viewModel.load()
        await viewModel.togglePin(fixtures.text)
        await viewModel.toggleFavorite(fixtures.richText)
        await viewModel.delete(fixtures.image)
        await viewModel.clearAllConfirmed()

        XCTAssertEqual(repository.toggledIDs, [fixtures.text.id])
        XCTAssertEqual(repository.favoritedIDs, [fixtures.richText.id])
        XCTAssertEqual(repository.deletedIDs, [fixtures.image.id])
        XCTAssertEqual(historyService.clearAllConfirmedValues, [true])
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testRevealInFinderToastsWhenRecordedFileIsGone() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )
        await viewModel.load()

        // `fixtures.file` records /tmp/fixture.txt, which does not exist on disk.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtures.file.filePath!.path))
        viewModel.revealInFinder(fixtures.file)

        XCTAssertTrue(viewModel.showToast, "A missing file must surface a toast instead of doing nothing.")
        XCTAssertEqual(viewModel.toastMessage, L10n.localized("toast.fileMissing"))
        XCTAssertEqual(viewModel.toastVariant, .error)
    }

    func testRevealInFinderToastsWhenFileItemHasNoPath() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        viewModel.revealInFinder(fixtures.text)

        XCTAssertTrue(viewModel.showToast)
        XCTAssertEqual(viewModel.toastMessage, L10n.localized("toast.fileMissing"))
    }

    func testCopyAbsolutePathCopiesRecordedPathAsText() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let executor = MockClipboardActionExecutor()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: executor,
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        await viewModel.copyAbsolutePath(fixtures.file)

        XCTAssertEqual(executor.executedActions, [.copyText("/tmp/fixture.txt")])
        XCTAssertTrue(viewModel.showToast)
        XCTAssertEqual(viewModel.toastMessage, L10n.localized("toast.copied"))
    }

    func testCopyAbsolutePathRejectsItemsWithoutFilePath() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let executor = MockClipboardActionExecutor()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: executor,
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        await viewModel.copyAbsolutePath(fixtures.text)

        XCTAssertTrue(executor.executedActions.isEmpty, "A non-file item must not copy a path.")
        XCTAssertEqual(viewModel.toastMessage, L10n.localized("toast.fileMissing"))
        XCTAssertEqual(viewModel.toastVariant, .error)
    }

    func testFileImageDataReadsReferencedFileFromDisk() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qingyu-file-image-\(UUID().uuidString).png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        try bytes.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let fixtures = ClipboardHistoryFixtures()
        let snapshot = fixtures.fileSnapshot(path: tmpURL)
        let queryService = MockClipboardIndexQueryService(items: [], snapshots: [:])
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        let data = await viewModel.fileImageData(for: snapshot)
        XCTAssertEqual(data, bytes, "A file item's image bytes should be read from its path.")
    }

    func testFileImageDataReturnsNilForNonFileItems() async {
        let fixtures = ClipboardHistoryFixtures()
        let queryService = MockClipboardIndexQueryService(items: fixtures.indexItems, snapshots: fixtures.snapshotsByID)
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: queryService,
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        let data = await viewModel.fileImageData(for: fixtures.text)
        XCTAssertNil(data)
    }

    /// 暂停/恢复记录：必须同时驱动真实记录服务与本地状态。
    /// PRD §02-ui-spec 的剪贴板工具栏要求这个控件。
    func testToggleRecordingPauseControlsServiceAndState() {
        let control = MockClipboardRecordingControl()
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: MockClipboardIndexQueryService(items: [], snapshots: [:]),
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService(),
            recordingControl: control
        )

        XCTAssertTrue(viewModel.canToggleRecording)
        XCTAssertFalse(viewModel.isRecordingPaused)

        viewModel.toggleRecordingPause()
        XCTAssertTrue(viewModel.isRecordingPaused, "第一次点击应进入暂停")
        XCTAssertEqual(control.pauseCount, 1, "必须真的调用记录服务的暂停")

        viewModel.toggleRecordingPause()
        XCTAssertFalse(viewModel.isRecordingPaused, "再次点击应恢复")
        XCTAssertEqual(control.resumeCount, 1, "必须真的调用记录服务的恢复")
    }

    /// 没有注入记录控制器时（测试/预览），不提供暂停能力，也不应崩溃。
    func testToggleRecordingPauseIsUnavailableWithoutControl() {
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: MockClipboardIndexQueryService(items: [], snapshots: [:]),
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: MockSettingsService()
        )

        XCTAssertFalse(viewModel.canToggleRecording)
        viewModel.toggleRecordingPause()
        XCTAssertFalse(viewModel.isRecordingPaused)
    }


    /// 插件被停用时，「剪贴板已关闭」态必须出现，且「开启」要能真的恢复。
    ///
    /// 陷阱：插件停用会取消监控任务，只把设置改回 true 不会恢复记录。
    /// 因此 enableClipboard() 必须先恢复插件，否则用户点了「开启」什么都不会发生。
    func testEnableClipboardRestoresDisabledPlugin() async throws {
        final class Flag {
            var pluginEnabled = false
            var enableCalls = 0
        }
        let flag = Flag()
        let settings = MockSettingsService()
        try await settings.set(true, for: .clipboardEnabled)
        let repository = MockClipboardRepository()
        let viewModel = ClipboardListViewModel(
            queryService: MockClipboardIndexQueryService(items: [], snapshots: [:]),
            repository: repository,
            historyService: MockClipboardHistoryService(repository: repository),
            actionExecutor: MockClipboardActionExecutor(),
            resourceStore: MockFileResourceStore(),
            settingsService: settings,
            isPluginEnabled: { flag.pluginEnabled },
            enablePlugin: {
                flag.enableCalls += 1
                flag.pluginEnabled = true
            }
        )

        await viewModel.load()
        XCTAssertFalse(viewModel.clipboardEnabled, "插件停用时应显示关闭态")

        await viewModel.enableClipboard()
        XCTAssertEqual(flag.enableCalls, 1, "必须先恢复插件")
        XCTAssertTrue(viewModel.clipboardEnabled)
    }

    /// 0.4.213 回归：构造剪贴板视图模型前必须注册内置插件。
    ///
    /// 用户报告「剪贴板默认关闭，点开启没反应，容量却一直涨」：引导未完成时
    /// 打开剪贴板窗口，`startFullExperienceServices` 尚未执行、插件未注册——
    /// `isPluginEnabled` 对未注册插件恒为 false（`entries[id]` 缺失返回 false
    /// 而非默认值），窗口落入禁用页；「开启」按钮的 `enablePlugin` 闭包对
    /// 未注册插件又是静默 no-op，按钮永远无效。设置窗口与命令栏工厂都有
    /// `registerBuiltInPlugins()` 前置调用，剪贴板窗口必须同样保证
    /// （入口在 `ClipboardHistoryWindowController.show()`，工厂级兜底在
    /// `AppContainer.makeClipboardListViewModel()`，本测试锁死工厂级那条）。
    @MainActor
    func testMakeClipboardListViewModelRegistersBuiltInPlugins() {
        let container = AppContainer()
        _ = container.makeClipboardListViewModel()
        XCTAssertNotNil(
            container.pluginRegistry.state(of: .clipboard),
            "构造剪贴板视图模型前必须注册内置插件：未注册时 isPluginEnabled 恒为 false，"
                + "窗口呈现禁用页且「开启」按钮无效"
        )
    }
}

private final class ClipboardHistoryFixtures {
    let baseDate = Date(timeIntervalSince1970: 1_000)
    lazy var text = makeSnapshot(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, type: .text, summary: "Alpha", updatedAt: baseDate.addingTimeInterval(30), pinned: true)
    lazy var richText = makeSnapshot(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, type: .richText, summary: "Bold", updatedAt: baseDate.addingTimeInterval(20))
    lazy var image = makeSnapshot(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, type: .image, summary: "Image", updatedAt: baseDate.addingTimeInterval(10))
    lazy var file = makeSnapshot(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, type: .file, summary: "File", updatedAt: baseDate)

    lazy var snapshots = [text, richText, image, file]
    lazy var snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    lazy var indexItems = snapshots.map(SearchIndexItem.init(clipboard:))

    func fileSnapshot(path: URL) -> ClipboardRecordSnapshot {
        ClipboardRecordSnapshot(
            id: UUID(),
            contentType: .file,
            plainText: path.lastPathComponent,
            summary: path.lastPathComponent,
            contentHash: "hash-\(path.lastPathComponent)",
            isPinned: false,
            isFavorite: false,
            createdAt: baseDate,
            updatedAt: baseDate,
            filePath: path,
            fileDisplayName: path.lastPathComponent,
            fileUTI: "public.png",
            fileSize: 6,
            resources: [],
            resourceStatus: .available,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
    }

    private func makeSnapshot(id: UUID, type: ClipboardContentType, summary: String, updatedAt: Date, pinned: Bool = false) -> ClipboardRecordSnapshot {
        let resources: [ClipboardResourceSnapshot]
        if type == .image {
            resources = [
                ClipboardResourceSnapshot(
                    id: id,
                    type: .imageOriginal,
                    relativePath: "Clipboard/Images/\(id.uuidString).png",
                    mimeType: "image/png",
                    byteSize: 128,
                    width: 32,
                    height: 32,
                    isMissing: false
                )
            ]
        } else {
            resources = []
        }
        return ClipboardRecordSnapshot(
            id: id,
            contentType: type,
            plainText: summary,
            summary: summary,
            contentHash: "hash-\(id.uuidString)",
            isPinned: pinned,
            isFavorite: false,
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            filePath: type == .file ? URL(fileURLWithPath: "/tmp/fixture.txt") : nil,
            fileDisplayName: type == .file ? "fixture.txt" : nil,
            fileUTI: type == .file ? "public.text" : nil,
            fileSize: type == .file ? 12 : nil,
            resources: resources,
            resourceStatus: .available,
            sourceAppBundleID: type == .text ? "company.thebrowser.Browser" : nil,
            sourceAppName: type == .text ? "Arc" : nil
        )
    }
}

private final class MockClipboardIndexQueryService: ClipboardIndexQueryServiceProtocol {
    struct HistoryCall: Equatable { let filter: ClipboardContentType?; let limit: Int?; let offset: Int }
    struct SearchCall: Equatable { let query: String; let filter: ClipboardContentType?; let limit: Int? }

    let items: [SearchIndexItem]
    let snapshots: [UUID: ClipboardRecordSnapshot]
    var historyCalls: [HistoryCall] = []
    var searchCalls: [SearchCall] = []

    init(items: [SearchIndexItem], snapshots: [UUID: ClipboardRecordSnapshot]) {
        self.items = items
        self.snapshots = snapshots
    }

    func searchIndex(query: String, filter: ClipboardContentType?, limit: Int?) -> [SearchIndexItem] {
        searchCalls.append(SearchCall(query: query, filter: filter, limit: limit))
        let lowered = query.lowercased()
        let filtered = items.filter { item in
            (filter == nil || item.contentType == filter) && [item.title, item.plainText, item.summary].compactMap { $0?.lowercased() }.joined(separator: " ").contains(lowered)
        }
        guard let limit else { return filtered }
        return Array(filtered.prefix(limit))
    }

    func historyIndex(filter: ClipboardContentType?, limit: Int?, offset: Int) -> [SearchIndexItem] {
        historyCalls.append(HistoryCall(filter: filter, limit: limit, offset: offset))
        let filtered = items.filter { filter == nil || $0.contentType == filter }
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        guard offset < sorted.count else { return [] }
        let sliced = Array(sorted.dropFirst(offset))
        guard let limit else { return sliced }
        return Array(sliced.prefix(limit))
    }

    func loadDetails(for indexItem: SearchIndexItem) async throws -> ClipboardRecordSnapshot? {
        snapshots[indexItem.clipboardRecordID ?? indexItem.id]
    }
}

private final class MockClipboardRepository: ClipboardRepositoryProtocol {
    var toggledIDs: [UUID] = []
    var favoritedIDs: [UUID] = []
    var deletedIDs: [UUID] = []
    var usage: StorageUsage

    init(storageUsage: StorageUsage = StorageUsage(coreDataBytes: 0, resourceBytes: 0)) {
        self.usage = storageUsage
    }

    func upsert(event: AssistantClipboardEvent, resources: [ClipboardResourceDraft]) async throws -> ClipboardRecordSnapshot { throw AssistantClipboardRepositoryError.confirmationRequired }
    func fetch(id: UUID) async throws -> ClipboardRecordSnapshot? { nil }
    func fetchHistory(filter: ClipboardHistoryFilter) async throws -> [ClipboardRecordSnapshot] { [] }
    func delete(id: UUID) async throws { deletedIDs.append(id) }
    func clearAll() async throws {}
    func togglePin(id: UUID) async throws -> ClipboardRecordSnapshot {
        toggledIDs.append(id)
        return Self.snapshot(id: id, pinned: true, favorite: false)
    }
    func toggleFavorite(id: UUID) async throws -> ClipboardRecordSnapshot {
        favoritedIDs.append(id)
        return Self.snapshot(id: id, pinned: false, favorite: true)
    }
    func cleanupExpired(now: Date) async throws -> Int { 0 }
    func storageUsage() async throws -> StorageUsage { usage }
    func touch(id: UUID, at date: Date) async throws -> ClipboardRecordSnapshot? { nil }

    private static func snapshot(id: UUID, pinned: Bool, favorite: Bool) -> ClipboardRecordSnapshot {
        ClipboardRecordSnapshot(
            id: id,
            contentType: .text,
            plainText: "Item",
            summary: "Item",
            contentHash: "hash",
            isPinned: pinned,
            isFavorite: favorite,
            createdAt: Date(),
            updatedAt: Date(),
            filePath: nil,
            fileDisplayName: nil,
            fileUTI: nil,
            fileSize: nil,
            resources: [],
            resourceStatus: .available,
            sourceAppBundleID: nil,
            sourceAppName: nil
        )
    }
}

private final class MockSettingsService: SettingsServiceProtocol {
    var storage: [SettingKey: String] = [
        .clipboardEnabled: "true",
        .clipboardRetention: "30d"
    ]

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        let raw = storage[key] ?? ""
        if type == Bool.self { return (raw == "true") as! T }
        return raw as! T
    }
    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        if let bool = value as? Bool { storage[key] = bool ? "true" : "false" }
        else { storage[key] = "\(value)" }
    }
    func reset(key: SettingKey) async throws {}
    func stringValue(for key: SettingKey) async throws -> String { storage[key] ?? "" }
}

private final class MockClipboardHistoryService: ClipboardHistoryServiceProtocol {
    let repository: ClipboardRepositoryProtocol
    var clearAllConfirmedValues: [Bool] = []

    init(repository: ClipboardRepositoryProtocol) {
        self.repository = repository
    }

    func clearAllConfirmation() -> ClipboardClearAllConfirmation {
        ClipboardClearAllConfirmation(title: "Clear", message: "This action cannot be undone.", destructiveButtonTitle: "Clear All", requiresExplicitConfirmation: true)
    }

    func clearAll(confirmed: Bool) async throws {
        clearAllConfirmedValues.append(confirmed)
        try await repository.clearAll()
    }
}

private final class MockClipboardActionExecutor: SearchActionExecutorProtocol {
    var executedActions: [SearchAction] = []

    func execute(_ action: SearchAction) async throws {
        executedActions.append(action)
    }
}

private final class MockFileResourceStore: FileResourceStoreProtocol {
    func writeImageOriginal(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { FileResourceWriteResult(id: id, relativePath: "", byteSize: Int64(data.count), mimeType: nil) }
    func writeThumbnail(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { FileResourceWriteResult(id: id, relativePath: "", byteSize: Int64(data.count), mimeType: nil) }
    func writeRichTextRTF(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { FileResourceWriteResult(id: id, relativePath: "", byteSize: Int64(data.count), mimeType: nil) }
    func writeRichTextHTML(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { FileResourceWriteResult(id: id, relativePath: "", byteSize: Int64(data.count), mimeType: nil) }
    func read(relativePath: String) async throws -> Data { Data() }
    func delete(relativePath: String) async {}
    func exists(relativePath: String) -> Bool { true }
    func storageUsage() async throws -> Int64 { 0 }
}

private final class MockClipboardRecordingControl: ClipboardServiceProtocol {
    var isRecordingEnabled = true
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    func pauseRecording() {
        pauseCount += 1
        isRecordingEnabled = false
    }

    func resumeRecording() {
        resumeCount += 1
        isRecordingEnabled = true
    }

    func handle(event: AssistantClipboardEvent) async throws -> ClipboardRecordSnapshot? { nil }
}
