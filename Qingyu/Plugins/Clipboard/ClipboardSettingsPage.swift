import KeyboardShortcuts
import SwiftUI

/// Settings page contributed by the Clipboard plugin (Task 004).
///
/// Merged content per the five-page mapping: clipboard shortcut, recording
/// switch and retention period. Bindings come from the shared
/// `SettingsViewModel` injected by the settings window's environment.
struct ClipboardPluginSettingsPage: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    /// 「清空全部记录」的确认弹窗与就地结果反馈。
    @State private var showClearAllConfirmation = false
    @State private var clearAllStatus: String?

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
                    JadeSegmentedPicker(
                        options: SettingsViewModel.retentionOptions.map { ($0, viewModel.retentionTitle($0)) },
                        selection: retentionBinding
                    )
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

            // PRD §02-ui-spec：清空全部记录**只在「设置 → 剪贴板」提供**。
            // 此前这一页没有入口，操作却藏在历史窗口的右键菜单里——
            // 想彻底清空数据的用户在这个页面找不到东西可点。
            SettingsSection("clipboard.settings.clearAll") {
                HStack(alignment: .top, spacing: JadeSpace.x3.value) {
                    VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                        Text(L10n.localized("clipboard.settings.clearAll.note"))
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let clearAllStatus {
                            Text(clearAllStatus)
                                .font(JadeFont.caption)
                                .foregroundStyle(JadeColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(L10n.localized("clipboard.clearAll.action")) {
                        showClearAllConfirmation = true
                    }
                    .buttonStyle(.jadeDestructive)
                    .accessibilityIdentifier("clipboard.settings.clearAll")
                }
            }
        }
        // 破坏性确认：标题/说明/按钮全部复用剪贴板窗口已在用的三条键，
        // 同一件事只有一套措辞。
        .jadeConfirmationDialog(
            "clipboard.clearAll.title",
            isPresented: $showClearAllConfirmation,
            confirmTitle: "clipboard.clearAll.action",
            message: "clipboard.clearAll.message"
        ) {
            Task { await clearAllHistory() }
        }
    }

    /// 清空全部剪贴板历史与本地资源；结果就地反馈，不弹额外窗口。
    private func clearAllHistory() async {
        let repository = ClipboardRepository(
            persistence: .shared,
            resourceStore: FileResourceStore(fileSystem: PersistenceController.shared.fileSystem)
        )
        let service = ClipboardHistoryService(repository: repository)
        do {
            try await service.clearAll(confirmed: true)
            clearAllStatus = L10n.localized("clipboard.clearAll.success")
        } catch {
            clearAllStatus = error.localizedDescription
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
