import SwiftUI

/// Settings page contributed by the Clipboard plugin (Task 003).
///
/// The descriptor is exposed via `ClipboardPlugin.manifest.settingsPage`; the
/// settings sidebar consumes plugin pages starting in Task 004. Reuses the
/// existing `management.clipboard.*` localization keys and the persisted
/// `clipboard.enabled` setting the app core already honours via
/// `syncRuntimeSettings()`. Named `ClipboardPluginSettingsPage` to avoid the
/// pre-existing `ClipboardSettingsPage` section view in SettingsView.
struct ClipboardPluginSettingsPage: View {
    let settingsService: SettingsServiceProtocol

    @State private var recordingEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $recordingEnabled) {
                    Label {
                        Text(L10n.localized("management.clipboard.enabled"))
                        Text(L10n.localized("management.clipboard.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: recordingEnabled) { newValue in
                    Task { await persist(newValue) }
                }
            } header: {
                Text(L10n.localized("management.clipboard.retention"))
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    private func load() async {
        recordingEnabled = (try? await settingsService.value(for: .clipboardEnabled, as: Bool.self)) ?? true
    }

    private func persist(_ enabled: Bool) async {
        try? await settingsService.set(enabled, for: .clipboardEnabled)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}
