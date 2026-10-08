import XCTest
import SwiftUI
@testable import Qingyu

@MainActor
final class SettingsNavigationTests: XCTestCase {

    // MARK: - Test doubles

    private final class InMemoryEnablementStore: PluginEnablementStore {
        var overrides: [PluginID: Bool] = [:]

        func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool {
            overrides[id] ?? defaultValue
        }

        func setEnabled(_ enabled: Bool, for id: PluginID) {
            overrides[id] = enabled
        }
    }

    private final class StubPlugin: QingyuPlugin {
        let manifest: PluginManifest

        init(id: PluginID, settingsOrder: Int) {
            self.manifest = PluginManifest(
                descriptor: PluginDescriptor(
                    id: id,
                    displayNameKey: "settings.page.\(id.rawValue)",
                    version: "1.0.0",
                    defaultEnabled: true
                ),
                searchSources: [],
                actions: [],
                settingsPage: PluginSettingsPageDescriptor(
                    id: id,
                    titleKey: "settings.page.\(id.rawValue)",
                    systemImageName: "gearshape",
                    order: settingsOrder,
                    makeView: { AnyView(EmptyView()) }
                ),
                menuItems: [],
                shortcuts: [],
                requiredPermissions: []
            )
        }

        func start() async throws {}
        func stop() async {}
    }

    // MARK: - Sidebar composition

    func testVisiblePageIDsBracketPluginPages() throws {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(StubPlugin(id: .screenshot, settingsOrder: 40))
        try registry.register(StubPlugin(id: .quickLaunch, settingsOrder: 20))
        try registry.register(StubPlugin(id: .clipboard, settingsOrder: 30))
        let viewModel = SettingsViewModel(pluginRegistry: registry)

        XCTAssertEqual(viewModel.visiblePageIDs, [
            .general, .plugin(.quickLaunch), .plugin(.clipboard), .about
        ])
    }

    func testVisiblePageIDsWithoutRegistryShowsFixedPagesOnly() {
        let viewModel = SettingsViewModel()

        XCTAssertEqual(viewModel.visiblePageIDs, [.general, .about])
    }

    func testDisabledPluginPageHiddenFromSidebar() async throws {
        let registry = PluginRegistry(enablementStore: InMemoryEnablementStore())
        try registry.register(StubPlugin(id: .clipboard, settingsOrder: 30))
        try registry.register(StubPlugin(id: .screenshot, settingsOrder: 40))
        await registry.startAll()

        await registry.setEnabled(false, for: .clipboard)
        let viewModel = SettingsViewModel(pluginRegistry: registry)

        XCTAssertEqual(viewModel.visiblePageIDs, [.general, .about])
    }

    // MARK: - Route mapping

    func testNewRoutesMapToPages() {
        let viewModel = SettingsViewModel()

        viewModel.select(route: .general)
        XCTAssertEqual(viewModel.selectedPage, .general)
        viewModel.select(route: .quickLaunch)
        XCTAssertEqual(viewModel.selectedPage, .plugin(.quickLaunch))
        viewModel.select(route: .clipboard)
        XCTAssertEqual(viewModel.selectedPage, .plugin(.clipboard))
        viewModel.select(route: .screenshot)
        XCTAssertEqual(viewModel.selectedPage, .plugin(.clipboard), "隐藏功能路由不得改变当前设置页")
        viewModel.select(route: .about)
        XCTAssertEqual(viewModel.selectedPage, .about)
    }

    // MARK: - About keeps reading the Bundle

    func testAboutInfoReadsVersionAndBuildNumberFromBundle() {
        let about = BundleAboutInfoProvider().info

        XCTAssertFalse(about.version.isEmpty, "关于页版本号必须从 Bundle 读取")
        XCTAssertFalse(about.buildNumber.isEmpty, "关于页构建号必须从 Bundle 读取")
    }

    func testInfoPlistVersionFieldsStayInSync() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
        let marketing = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(plist["CFBundleVersion"] as? String)

        XCTAssertEqual(marketing, aboutVersionFromPlistFile(), "MARKETING_VERSION 必须与 CFBundleShortVersionString 一致")
        XCTAssertEqual(build, buildNumberFromPlistFile())
    }

    private func aboutVersionFromPlistFile() -> String {
        readPlistValue("CFBundleShortVersionString")
    }

    private func buildNumberFromPlistFile() -> String {
        readPlistValue("CFBundleVersion")
    }

    private func readPlistValue(_ key: String) -> String {
        guard
            let data = FileManager.default.contents(atPath: Bundle.main.bundlePath + "/Contents/Info.plist"),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let value = plist[key] as? String
        else {
            return ""
        }
        return value
    }
}
