import XCTest
import SwiftUI
@testable import Qingniao

@MainActor
final class PluginRegistryTests: XCTestCase {

    private struct StubStartError: Error {}

    /// Minimal SearchSource double; the registry only aggregates references.
    private final class NullSearchSource: SearchSource {
        let id = SearchSourceID(rawValue: "plugin.test.source")
        let displayName = "Test Source"
        let isEnabledInSearch = true

        func canSearch(query: String) -> Bool { false }
        func search(query: String) async -> [SearchResult] { [] }
    }

    /// In-memory enablement store so tests never touch real UserDefaults.
    private final class InMemoryEnablementStore: PluginEnablementStore {
        var overrides: [PluginID: Bool] = [:]

        func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool {
            overrides[id] ?? defaultValue
        }

        func setEnabled(_ enabled: Bool, for id: PluginID) {
            overrides[id] = enabled
        }
    }

    private final class TestPlugin: QingniaoPlugin {
        private final class Counter {
            var count = 0
        }

        let manifest: PluginManifest
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private let actionCounter: Counter
        private let startError: Error?

        var actionRunCount: Int { actionCounter.count }

        init(
            id: PluginID,
            settingsOrder: Int? = nil,
            actionID: PluginActionID? = nil,
            defaultEnabled: Bool = true,
            startError: Error? = nil
        ) {
            let counter = Counter()
            var actions: [PluginAction] = []
            if let actionID {
                actions = [PluginAction(id: actionID) {
                    counter.count += 1
                }]
            }
            self.startError = startError
            self.manifest = PluginManifest(
                descriptor: PluginDescriptor(
                    id: id,
                    displayNameKey: "plugin.\(id.rawValue).name",
                    version: "1.0.0",
                    defaultEnabled: defaultEnabled
                ),
                searchSources: [NullSearchSource()],
                actions: actions,
                settingsPage: settingsOrder.map { order in
                    PluginSettingsPageDescriptor(
                        id: id,
                        titleKey: "plugin.\(id.rawValue).settings",
                        systemImageName: "gearshape",
                        order: order,
                        makeView: { AnyView(EmptyView()) }
                    )
                },
                menuItems: [],
                shortcuts: [],
                requiredPermissions: []
            )
            self.actionCounter = counter
        }

        func start() async throws {
            startCount += 1
            if let startError {
                throw startError
            }
        }

        func stop() async {
            stopCount += 1
        }
    }

    private func expectActionUnavailable(_ actionID: PluginActionID, in registry: PluginRegistry) async {
        do {
            try await registry.execute(actionID)
            XCTFail("Expected execute(\(actionID.rawValue)) to throw")
        } catch {
            // expected: action not available
        }
    }

    // MARK: - Registration

    func testSettingsPagesSortedByOrderAndDuplicateIDRejected() {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try? registry.register(TestPlugin(id: PluginID(rawValue: "one"), settingsOrder: 20))
        try? registry.register(TestPlugin(id: PluginID(rawValue: "two"), settingsOrder: 10))

        XCTAssertEqual(registry.settingsPages.map(\.order), [10, 20])
        XCTAssertThrowsError(try registry.register(TestPlugin(id: PluginID(rawValue: "one"), settingsOrder: 30)))
    }

    func testDuplicateActionIDRejected() {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try? registry.register(TestPlugin(id: PluginID(rawValue: "a"), actionID: PluginActionID(rawValue: "shared.action")))
        XCTAssertThrowsError(try registry.register(TestPlugin(id: PluginID(rawValue: "b"), actionID: PluginActionID(rawValue: "shared.action"))))
    }

    // MARK: - Lifecycle

    func testStartFailureIsolatedAndRecorded() async {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        let failing = TestPlugin(id: PluginID(rawValue: "bad"), settingsOrder: 30, startError: StubStartError())
        let healthy = TestPlugin(id: PluginID(rawValue: "good"), settingsOrder: 10)
        try? registry.register(failing)
        try? registry.register(healthy)

        await registry.startAll()

        XCTAssertEqual(failing.startCount, 1)
        XCTAssertEqual(healthy.startCount, 1)
        XCTAssertEqual(registry.state(of: PluginID(rawValue: "bad")), .failed)
        XCTAssertEqual(registry.state(of: PluginID(rawValue: "good")), .started)
        // 启动失败的插件贡献被隔离，健康插件贡献不受影响。
        XCTAssertEqual(registry.settingsPages.map(\.order), [10])
        XCTAssertTrue(registry.searchSources(of: PluginID(rawValue: "bad")).isEmpty)
        XCTAssertEqual(registry.searchSources(of: PluginID(rawValue: "good")).count, 1)
    }

    func testDisableStopsPluginAndHidesContributions() async {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        let plugin = TestPlugin(id: PluginID(rawValue: "one"), settingsOrder: 10)
        try? registry.register(plugin)

        await registry.startAll()
        XCTAssertEqual(registry.state(of: PluginID(rawValue: "one")), .started)

        await registry.setEnabled(false, for: PluginID(rawValue: "one"))
        XCTAssertEqual(plugin.stopCount, 1)
        XCTAssertEqual(registry.state(of: PluginID(rawValue: "one")), .stopped)
        XCTAssertTrue(registry.settingsPages.isEmpty)
        XCTAssertTrue(registry.searchSources.isEmpty)
        XCTAssertNil(registry.contributions(of: PluginID(rawValue: "one")))

        await registry.setEnabled(true, for: PluginID(rawValue: "one"))
        XCTAssertEqual(plugin.startCount, 2)
        XCTAssertEqual(registry.settingsPages.map(\.order), [10])
    }

    func testDefaultDisabledPluginNotStartedByStartAll() async {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        let plugin = TestPlugin(id: PluginID(rawValue: "opt"), defaultEnabled: false)
        try? registry.register(plugin)

        await registry.startAll()

        XCTAssertEqual(plugin.startCount, 0)
        XCTAssertTrue(registry.searchSources.isEmpty)

        await registry.setEnabled(true, for: PluginID(rawValue: "opt"))
        XCTAssertEqual(plugin.startCount, 1)
        XCTAssertEqual(registry.searchSources.count, 1)
    }

    // MARK: - Action routing

    func testActionExecutedOnlyByOwningPlugin() async throws {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        let pluginA = TestPlugin(id: PluginID(rawValue: "a"), actionID: PluginActionID(rawValue: "a.action"))
        let pluginB = TestPlugin(id: PluginID(rawValue: "b"), actionID: PluginActionID(rawValue: "b.action"))
        try registry.register(pluginA)
        try registry.register(pluginB)
        await registry.startAll()

        try await registry.execute(PluginActionID(rawValue: "a.action"))
        XCTAssertEqual(pluginA.actionRunCount, 1)
        XCTAssertEqual(pluginB.actionRunCount, 0)

        try await registry.execute(PluginActionID(rawValue: "b.action"))
        XCTAssertEqual(pluginA.actionRunCount, 1)
        XCTAssertEqual(pluginB.actionRunCount, 1)

        await expectActionUnavailable(PluginActionID(rawValue: "missing.action"), in: registry)
    }

    func testDisabledPluginActionUnavailable() async throws {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        let plugin = TestPlugin(id: PluginID(rawValue: "a"), actionID: PluginActionID(rawValue: "a.action"))
        try registry.register(plugin)
        await registry.startAll()

        await registry.setEnabled(false, for: PluginID(rawValue: "a"))
        await expectActionUnavailable(PluginActionID(rawValue: "a.action"), in: registry)
        XCTAssertEqual(plugin.actionRunCount, 0)
    }
}
