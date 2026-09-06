import SwiftUI

/// Settings page contributed by the Quick Launch plugin (Task 002).
///
/// The descriptor is exposed via `QuickLaunchPlugin.manifest.settingsPage`;
/// the settings sidebar consumes plugin pages starting in Task 004, so this
/// page is not yet wired into navigation. Toggles reuse the existing
/// `management.source.*` localization keys and the same `SettingKey` switches
/// the search panel has always honoured.
struct QuickLaunchSettingsPage: View {
    let settingsService: SettingsServiceProtocol

    @State private var appSourceEnabled = true
    @State private var commandSourceEnabled = true
    @State private var calculatorSourceEnabled = true
    @State private var fileSourceEnabled = true

    var body: some View {
        Form {
            Section {
                toggleRow(
                    titleKey: "management.source.app",
                    subtitleKey: "management.source.app.subtitle",
                    iconName: "app",
                    isOn: $appSourceEnabled,
                    settingKey: .appSourceEnabled
                )
                toggleRow(
                    titleKey: "management.source.command",
                    subtitleKey: "management.source.command.subtitle",
                    iconName: "terminal",
                    isOn: $commandSourceEnabled,
                    settingKey: .commandSourceEnabled
                )
                toggleRow(
                    titleKey: "management.source.calculator",
                    subtitleKey: "management.source.calculator.subtitle",
                    iconName: "function",
                    isOn: $calculatorSourceEnabled,
                    settingKey: .calculatorSourceEnabled
                )
                toggleRow(
                    titleKey: "management.source.file",
                    subtitleKey: "management.source.file.subtitle",
                    iconName: "folder",
                    isOn: $fileSourceEnabled,
                    settingKey: .fileSourceEnabled
                )
            } header: {
                Text(L10n.localized("management.settings.sources"))
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    private func toggleRow(
        titleKey: String,
        subtitleKey: String,
        iconName: String,
        isOn: Binding<Bool>,
        settingKey: SettingKey
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.localized(titleKey))
                    Text(L10n.localized(subtitleKey))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isOn.wrappedValue) { newValue in
            Task { await persist(newValue, for: settingKey) }
        }
    }

    private func load() async {
        appSourceEnabled = (try? await settingsService.value(for: .appSourceEnabled, as: Bool.self)) ?? true
        commandSourceEnabled = (try? await settingsService.value(for: .commandSourceEnabled, as: Bool.self)) ?? true
        calculatorSourceEnabled = (try? await settingsService.value(for: .calculatorSourceEnabled, as: Bool.self)) ?? true
        fileSourceEnabled = (try? await settingsService.value(for: .fileSourceEnabled, as: Bool.self)) ?? true
    }

    private func persist(_ enabled: Bool, for key: SettingKey) async {
        try? await settingsService.set(enabled, for: key)
    }
}
