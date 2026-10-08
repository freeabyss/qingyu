import XCTest
@testable import Qingyu

@MainActor
final class QuickLaunchPluginTests: XCTestCase {

    private var tempDirectory: URL!
    private var persistence: PersistenceController!
    private var settingsService: SettingsService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickLaunchPluginTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileSystem = AssistantFileSystem(rootDirectory: tempDirectory)
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        settingsService = SettingsService(persistence: persistence)
    }

    override func tearDownWithError() throws {
        settingsService = nil
        persistence = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Test doubles

    private final class SpyCommandExecutor: CommandExecutorProtocol {
        let requiresConfirmationIDs: Set<CommandID>
        private(set) var executions: [(CommandID, Bool)] = []

        init(requiresConfirmationIDs: Set<CommandID> = []) {
            self.requiresConfirmationIDs = requiresConfirmationIDs
        }

        func execute(_ commandID: CommandID, confirmed: Bool) async throws {
            executions.append((commandID, confirmed))
        }

        func requiresConfirmation(_ commandID: CommandID) -> Bool {
            requiresConfirmationIDs.contains(commandID)
        }
    }

    private final class StubConfirmationProvider: CommandConfirmationProviding {
        let result: Bool
        private(set) var requestedCommands: [AssistantCommandDefinition] = []

        init(result: Bool) {
            self.result = result
        }

        func confirm(command: AssistantCommandDefinition) async -> Bool {
            requestedCommands.append(command)
            return result
        }
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

    private func makeQuickLaunchPlugin(
        commandExecutor: CommandExecutorProtocol = SpyCommandExecutor(),
        confirmationProvider: CommandConfirmationProviding = StubConfirmationProvider(result: true)
    ) -> QuickLaunchPlugin {
        QuickLaunchPlugin(
            // Follow the AppSearchSourceTests/FileSearchSourceTests convention:
            // never auto-build indexes in unit tests — background scans of real
            // user directories would churn the process during other tests.
            appSource: AppSearchSource(autoBuildIndex: false, schedulesRefresh: false),
            fileSource: FileSearchSource(autoBuildIndex: false),
            calculatorSource: CalculatorSource(),
            commandSource: SystemCommandSource(),
            settingsService: settingsService,
            commandExecutor: commandExecutor,
            confirmationProvider: confirmationProvider
        )
    }

    // MARK: - Manifest

    func testManifestDeclaresQuickLaunchIDSevenSourcesAndSettingsPage() {
        let plugin = makeQuickLaunchPlugin()

        XCTAssertEqual(plugin.manifest.descriptor.id, .quickLaunch)
        XCTAssertEqual(
            Set(plugin.manifest.searchSources.map(\.id)),
            [.app, .file, .calculator, .command, .settings, .webSearch, .aiChat]
        )
        XCTAssertEqual(plugin.manifest.settingsPage?.id, .quickLaunch)
        XCTAssertEqual(plugin.manifest.descriptor.defaultEnabled, true)
    }

    func testEveryCatalogCommandMapsToStablePluginActionID() {
        let plugin = makeQuickLaunchPlugin()
        let actionIDs = plugin.manifest.actions.map(\.id)

        XCTAssertEqual(actionIDs.count, AssistantCommandCatalog.commands.count)
        for command in AssistantCommandCatalog.commands {
            XCTAssertTrue(
                actionIDs.contains(.quickLaunchCommand(command.id)),
                "Missing plugin action for command \(command.id.rawValue)"
            )
        }
    }

    // MARK: - Action routing

    func testExecutePluginActionRoutesToCommandExecutor() async throws {
        let spy = SpyCommandExecutor()
        let plugin = makeQuickLaunchPlugin(commandExecutor: spy)
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)
        await registry.startAll()

        try await registry.execute(.quickLaunchCommand(.openDownloads))

        XCTAssertEqual(spy.executions.count, 1)
        XCTAssertEqual(spy.executions.first?.0, .openDownloads)
        XCTAssertEqual(spy.executions.first?.1, false)
    }

    func testDangerousCommandActionConfirmsThroughProvider() async throws {
        let spy = SpyCommandExecutor(requiresConfirmationIDs: [.restartDock])
        let confirmation = StubConfirmationProvider(result: true)
        let plugin = makeQuickLaunchPlugin(commandExecutor: spy, confirmationProvider: confirmation)
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)
        await registry.startAll()

        try await registry.execute(.quickLaunchCommand(.restartDock))

        XCTAssertEqual(confirmation.requestedCommands.map(\.id), [.restartDock])
        XCTAssertEqual(spy.executions.count, 1)
        XCTAssertEqual(spy.executions.first?.0, .restartDock)
        XCTAssertEqual(spy.executions.first?.1, true)
    }

    func testDeniedConfirmationPreventsExecution() async throws {
        let spy = SpyCommandExecutor(requiresConfirmationIDs: [.restartFinder])
        let confirmation = StubConfirmationProvider(result: false)
        let plugin = makeQuickLaunchPlugin(commandExecutor: spy, confirmationProvider: confirmation)
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)
        await registry.startAll()

        try await registry.execute(.quickLaunchCommand(.restartFinder))

        XCTAssertTrue(confirmation.requestedCommands.map(\.id).contains(.restartFinder))
        XCTAssertTrue(spy.executions.isEmpty)
    }

    // MARK: - Registry enablement

    func testDisablingPluginHidesAllSevenSourcesAndReenablingRestores() async throws {
        let plugin = makeQuickLaunchPlugin()
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)
        await registry.startAll()

        let enabledSourceIDs = Set(registry.searchSources.map(\.id))
        XCTAssertEqual(enabledSourceIDs, [.app, .file, .calculator, .command, .settings, .webSearch, .aiChat])
        XCTAssertNotNil(registry.settingsPages.first { $0.id == .quickLaunch })

        await registry.setEnabled(false, for: .quickLaunch)
        XCTAssertTrue(registry.searchSources.isEmpty, "禁用插件后七类搜索结果应全部消失")
        XCTAssertTrue(registry.settingsPages.isEmpty)

        await registry.setEnabled(true, for: .quickLaunch)
        XCTAssertEqual(
            Set(registry.searchSources.map(\.id)),
            [.app, .file, .calculator, .command, .settings, .webSearch, .aiChat],
            "重新启用后搜索源应恢复"
        )
    }

    // MARK: - Settings-backed switches

    func testDisabledAppSourceYieldsNoAppResults() async throws {
        try await settingsService.set(false, for: .appSourceEnabled)
        let plugin = makeQuickLaunchPlugin()
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(plugin)

        let appSource = registry.searchSources.first { $0.id == .app }
        let results = await appSource?.search(query: "Settings")

        XCTAssertTrue(results?.isEmpty ?? true, "关闭应用来源开关后不应返回应用结果")
    }
}
