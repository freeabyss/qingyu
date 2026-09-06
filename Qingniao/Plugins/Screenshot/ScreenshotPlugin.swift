import Foundation
import SwiftUI

// MARK: - Screenshot plugin identity (Task 004 / ADR-001)

extension PluginID {
    static let screenshot = PluginID(rawValue: "screenshot")
}

/// Task 004: screenshot plugin shell. This task only registers the screenshot
/// settings page so the five-page sidebar can be driven by
/// `PluginRegistry.settingsPages`; capture actions, menu items and shortcut
/// contributions move onto this plugin in Task 009 (unified capture core).
@MainActor
final class ScreenshotPlugin: QingniaoPlugin {
    let manifest: PluginManifest

    init() {
        self.manifest = PluginManifest(
            descriptor: PluginDescriptor(
                id: .screenshot,
                displayNameKey: "settings.page.screenshot",
                version: "1.0.0",
                defaultEnabled: true
            ),
            searchSources: [],
            actions: [],
            settingsPage: PluginSettingsPageDescriptor(
                id: .screenshot,
                titleKey: "settings.page.screenshot",
                systemImageName: "camera.viewfinder",
                order: 40,
                makeView: { AnyView(ScreenshotPluginSettingsPage()) }
            ),
            menuItems: [],
            shortcuts: [],
            requiredPermissions: [.screenRecording]
        )
    }

    func start() async throws {}
    func stop() async {}
}
