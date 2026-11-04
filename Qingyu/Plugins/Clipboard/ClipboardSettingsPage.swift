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
        SettingsScrollPage {
            SettingsHeader(
                titleKey: "settings.page.clipboard",
                subtitleKey: "management.clipboard.subtitle",
                iconName: "doc.on.clipboard"
            )

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

                JadeSettingsDivider()

                // PRD §02-ui-spec 明确要求：「设置 → 剪贴板」必须提示
                // 会记录包括密码在内的敏感内容，且数据仅保存在本机。
                // 这是隐私告知，不能只写在文档里。
                HStack(alignment: .top, spacing: JadeSpace.x2.value) {
                    Image(systemName: "lock.shield")
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(L10n.localized("management.clipboard.sensitiveNote"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
