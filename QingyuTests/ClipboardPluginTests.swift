import XCTest
@testable import Qingyu

@MainActor
final class ClipboardPluginTests: XCTestCase {

    private var tempDirectory: URL!
    private var persistence: PersistenceController!
    private var repository: IndexingClipboardRepository!
    private var settingsService: SettingsService!
    private var monitor: FakeClipboardMonitor!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPluginTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        let resourceStore = FileResourceStore(fileSystem: fileSystem)
        let index = InMemorySearchIndex()
        let baseRepository = ClipboardRepository(persistence: persistence, resourceStore: resourceStore)
        repository = IndexingClipboardRepository(base: baseRepository, index: index)
        settingsService = SettingsService(persistence: persistence)
        monitor = FakeClipboardMonitor()
    }

    override func tearDownWithError() throws {
        monitor.finishStream()
        monitor = nil
        repository = nil
        settingsService = nil
        persistence = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Test doubles

    private final class FakeClipboardMonitor: ClipboardMonitorProtocol {
        private(set) var startCallCount = 0
        private(set) var stopCallCount = 0
        // Mirrors the real ClipboardMonitor: every `events` access hands out a
        // fresh stream whose continuation is retained for yielding.
        private var continuation: AsyncStream<AssistantClipboardEvent>.Continuation?

        init() {}

        var events: AsyncStream<AssistantClipboardEvent> {
            AsyncStream { continuation in
                self.continuation = continuation
            }
        }

        func start() { startCallCount += 1 }
        func stop() { stopCallCount += 1 }
        func pollNow() async {}
        func yield(_ event: AssistantClipboardEvent) { continuation?.yield(event) }
        func finishStream() { continuation?.finish() }
    }

    private final class InMemoryEnablementStore: PluginEnablementStore {
        var overrides: [PluginID: Bool] = [:]

        func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool {
            overrides[id] ?? defaultValue
        }

        func setEnabled(_ enabled: Bool, for id: PluginID) {
            overrides[id] = enabled
        }
    }

    private func makePlugin(openHistoryWindow: @escaping @MainActor () -> Void = {}) -> ClipboardPlugin {
        ClipboardPlugin(
            monitor: monitor,
            index: InMemorySearchIndex(),
            repository: repository,
            resourceStore: FileResourceStore(fileSystem: AssistantFileSystem(rootDirectory: tempDirectory)),
            settingsService: settingsService,
            openHistoryWindow: openHistoryWindow
        )
    }

    private func waitForRepositoryCount(_ count: Int, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let records = try await repository.fetchHistory(filter: ClipboardHistoryFilter())
            if records.count == count { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let records = try await repository.fetchHistory(filter: ClipboardHistoryFilter())
        XCTAssertEqual(records.count, count, "Timed out waiting for \(count) records")
    }

    // MARK: - Manifest

    func testManifestDeclaresClipboardSourceActionsAndSettingsPage() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.manifest.descriptor.id, .clipboard)
        XCTAssertEqual(plugin.manifest.searchSources.map(\.id), [.clipboard])
        XCTAssertEqual(plugin.manifest.settingsPage?.id, .clipboard)
        XCTAssertEqual(
            Set(plugin.manifest.actions.map(\.id)),
            [.openClipboardHistory, .toggleClipboardRecording, .clearClipboardHistory]
        )
    }

    // MARK: - Lifecycle (idempotent)

    func testStartIsIdempotentAndStopCallsMonitorOnce() async throws {
        let plugin = makePlugin()

        try await plugin.start()
        try await plugin.start()
        XCTAssertEqual(monitor.startCallCount, 1)

        await plugin.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)

        await plugin.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    func testRestartAfterStopRestoresMonitoring() async throws {
        let plugin = makePlugin()

        try await plugin.start()
        await plugin.stop()
        try await plugin.start()

        XCTAssertEqual(monitor.startCallCount, 2)
        XCTAssertEqual(monitor.stopCallCount, 1)

        monitor.yield(AssistantClipboardEvent(payload: .plainText("after restart")))
        try await waitForRepositoryCount(1)
    }

    // MARK: - Event processing

    func testStartedPluginProcessesMonitorEvents() async throws {
        let plugin = makePlugin()
        try await plugin.start()

        monitor.yield(AssistantClipboardEvent(payload: .plainText("hello clipboard")))
        try await waitForRepositoryCount(1)
    }

    func testStoppedPluginDoesNotProcessNewEvents() async throws {
        let plugin = makePlugin()
        try await plugin.start()
        await plugin.stop()

        monitor.yield(AssistantClipboardEvent(payload: .plainText("ignored")))
        try await Task.sleep(nanoseconds: 120_000_000)
        try await waitForRepositoryCount(0)
    }

    // MARK: - Actions

    func testOpenHistoryActionInvokesInjectedWindowAction() async throws {
        var openCount = 0
        let plugin = makePlugin(openHistoryWindow: { openCount += 1 })

        try await plugin.manifest.actions.first { $0.id == .openClipboardHistory }?.perform()

        XCTAssertEqual(openCount, 1)
    }

    func testToggleRecordingActionFlipsPersistedSetting() async throws {
        let plugin = makePlugin()

        try await plugin.manifest.actions.first { $0.id == .toggleClipboardRecording }?.perform()

        let enabled = try await settingsService.value(for: .clipboardEnabled, as: Bool.self)
        XCTAssertFalse(enabled, "默认开启时执行 toggle 后应为关闭")
    }

    func testClearHistoryActionRemovesRecords() async throws {
        let plugin = makePlugin()
        _ = try await repository.upsert(
            event: AssistantClipboardEvent(payload: .plainText("to be cleared")),
            resources: []
        )

        try await plugin.manifest.actions.first { $0.id == .clearClipboardHistory }?.perform()

        let records = try await repository.fetchHistory(filter: ClipboardHistoryFilter())
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Registry integration

    func testRegistryEnablementControlsMonitoringAndContributions() async throws {
        let plugin = makePlugin()
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)

        await registry.startAll()
        XCTAssertEqual(monitor.startCallCount, 1, "启用插件应恰好创建一个监听任务")
        XCTAssertEqual(registry.searchSources.map(\.id), [.clipboard])

        await registry.setEnabled(false, for: .clipboard)
        XCTAssertEqual(monitor.stopCallCount, 1, "停用插件应停止监听")
        XCTAssertTrue(registry.searchSources.isEmpty)

        await registry.setEnabled(true, for: .clipboard)
        XCTAssertEqual(monitor.startCallCount, 2)
        XCTAssertEqual(registry.searchSources.map(\.id), [.clipboard])
    }
}
