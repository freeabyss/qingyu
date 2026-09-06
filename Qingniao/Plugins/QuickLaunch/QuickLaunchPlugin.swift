import Foundation
import SwiftUI

// MARK: - Quick Launch plugin identity (Task 002 / ADR-001)

extension PluginID {
    static let quickLaunch = PluginID(rawValue: "quick-launch")
}

extension PluginActionID {
    /// One stable action ID per system command: `quick-launch.command.<commandID>`.
    static func quickLaunchCommand(_ commandID: CommandID) -> PluginActionID {
        PluginActionID(rawValue: "quick-launch.command.\(commandID.rawValue)")
    }

    /// Inverse mapping used by UI layers that need the underlying command
    /// (e.g. the danger-command confirmation flow).
    var quickLaunchCommandID: CommandID? {
        let prefix = "quick-launch.command."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return CommandID(rawValue: String(rawValue.dropFirst(prefix.count)))
    }
}

/// Task 002: first plugin on the Task 001 kernel. Owns the app, file,
/// calculator, system-command and settings search sources plus one
/// `PluginActionID`-routed action per whitelisted command. `AppContainer`
/// only injects dependencies; the plugin constructs its own contributions.
@MainActor
final class QuickLaunchPlugin: QingniaoPlugin {
    let manifest: PluginManifest

    init(
        appSource: AppSearchSource,
        fileSource: FileSearchSource,
        calculatorSource: CalculatorSource,
        commandSource: SystemCommandSource,
        settingsService: SettingsServiceProtocol,
        commandExecutor: CommandExecutorProtocol,
        confirmationProvider: CommandConfirmationProviding
    ) {
        // Same SettingsBackedSearchSource wrapping that used to live in
        // AppContainer.makeSearchPanelViewModel, preserving switch semantics.
        let searchSources: [any SearchSource] = [
            SettingsBackedSearchSource(source: appSource, settingsService: settingsService, settingKey: .appSourceEnabled),
            SettingsBackedSearchSource(source: commandSource, settingsService: settingsService, settingKey: .commandSourceEnabled),
            SettingsBackedSearchSource(source: calculatorSource, settingsService: settingsService, settingKey: .calculatorSourceEnabled),
            SettingsBackedSearchSource(source: fileSource, settingsService: settingsService, settingKey: .fileSourceEnabled),
            SettingsSource(settingsService: settingsService)
        ]

        // Capture the dependencies directly (not `self`) so the closures can be
        // built before `manifest` is initialized.
        let actions = AssistantCommandCatalog.commands.map { command -> PluginAction in
            PluginAction(id: .quickLaunchCommand(command.id)) {
                var confirmed = false
                if commandExecutor.requiresConfirmation(command.id) {
                    guard await confirmationProvider.confirm(command: command) else { return }
                    confirmed = true
                }
                try await commandExecutor.execute(command.id, confirmed: confirmed)
            }
        }

        self.manifest = PluginManifest(
            descriptor: PluginDescriptor(
                id: .quickLaunch,
                displayNameKey: "plugin.quickLaunch.displayName",
                version: "1.0.0",
                defaultEnabled: true
            ),
            searchSources: searchSources,
            actions: actions,
            settingsPage: PluginSettingsPageDescriptor(
                id: .quickLaunch,
                titleKey: "plugin.quickLaunch.settings.title",
                systemImageName: "bolt.circle",
                order: 20,
                makeView: { AnyView(QuickLaunchSettingsPage(settingsService: settingsService)) }
            ),
            menuItems: [],
            shortcuts: [],
            requiredPermissions: []
        )
    }

    func start() async throws {}
    func stop() async {}
}
