import KeyboardShortcuts
import SwiftUI

/// Settings page contributed by the Quick Launch plugin (Task 004).
///
/// Merged content per the five-page mapping: search shortcut, search-source
/// switches, file search directories and the search blacklist / result
/// behaviour. Bindings come from the shared `SettingsViewModel` injected by
/// the settings window's environment (same bindings and autosave as before).
struct QuickLaunchPluginSettingsPage: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    private let fileSearchDirectories = ["~/Desktop", "~/Documents", "~/Downloads"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JadeSpace.x6.value) {
                SettingsSection("management.settings.shortcuts") {
                    shortcutRecorderRow(
                        label: L10n.localized("management.shortcuts.search"),
                        name: .togglePanel
                    )
                }

                SettingsSection("management.settings.sources") {
                    ForEach(Array($viewModel.sourceToggles.enumerated()), id: \.element.id) { index, $source in
                        if index > 0 { JadeSettingsDivider() }
                        JadeSwitchRow(icon: source.iconName,
                                      title: source.title,
                                      subtitle: source.subtitle,
                                      isOn: Binding(get: { source.isEnabled },
                                                    set: { source.isEnabled = $0; Task { await viewModel.saveSettings() } }))
                    }
                    Text(L10n.localized("management.searchSources.hint"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textTertiary)
                }

                SettingsSection("management.searchSources.fileDirectories") {
                    ForEach(fileSearchDirectories, id: \.self) { dir in
                        Text(dir)
                            .font(JadeFont.callout)
                            .foregroundStyle(JadeColor.textSecondary)
                    }
                    .disabled(true)
                    Text(L10n.localized("management.searchSources.fileDirectories.note"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textTertiary)
                }

                BlacklistManagementSection(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x6.value)
        }
    }

    private func shortcutRecorderRow(label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer()
            HotkeyRecorder(
                for: name,
                isConflicting: .constant(viewModel.isShortcutConflict(name)),
                conflictMessage: .constant(viewModel.conflictMessage(for: name))
            )
            .onChange(of: KeyboardShortcuts.getShortcut(for: name)) { _ in
                viewModel.refreshShortcutConflicts()
            }
        }
    }
}
