import KeyboardShortcuts
import SwiftUI

/// Settings page contributed by the Clipboard plugin (Task 004).
///
/// Merged content per the five-page mapping: clipboard shortcut, recording
/// switch and retention period. Bindings come from the shared
/// `SettingsViewModel` injected by the settings window's environment.
struct ClipboardPluginSettingsPage: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JadeSpace.x6.value) {
                SettingsSection("management.settings.shortcuts") {
                    HStack {
                        Text(L10n.localized("management.shortcuts.clipboardHistory"))
                            .font(JadeFont.body)
                            .foregroundStyle(JadeColor.textPrimary)
                        Spacer()
                        HotkeyRecorder(
                            for: .openClipboardHistory,
                            isConflicting: .constant(viewModel.isShortcutConflict(.openClipboardHistory)),
                            conflictMessage: .constant(viewModel.conflictMessage(for: .openClipboardHistory))
                        )
                        .onChange(of: KeyboardShortcuts.getShortcut(for: .openClipboardHistory)) { _ in
                            viewModel.refreshShortcutConflicts()
                        }
                    }
                }

                SettingsSection("management.settings.clipboard") {
                    JadeSwitchRow(L10n.localized("management.clipboard.enabled"), isOn: clipboardEnabledBinding)
                    JadeSettingsDivider()
                    VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                        Text(L10n.localized("management.clipboard.retention"))
                            .font(JadeFont.body)
                        Picker("", selection: retentionBinding) {
                            ForEach(SettingsViewModel.retentionOptions, id: \.self) { retention in
                                Text(viewModel.retentionTitle(retention)).tag(retention)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x6.value)
        }
    }

    private var clipboardEnabledBinding: Binding<Bool> {
        Binding(get: { viewModel.clipboardEnabled },
                set: { viewModel.clipboardEnabled = $0; Task { await viewModel.saveSettings() } })
    }

    private var retentionBinding: Binding<ClipboardRetention> {
        Binding(get: { viewModel.clipboardRetention },
                set: { viewModel.clipboardRetention = $0; Task { await viewModel.saveSettings() } })
    }
}
