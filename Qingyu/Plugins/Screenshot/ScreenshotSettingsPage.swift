import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Settings page contributed by the Screenshot plugin (Task 004).
///
/// Hosts the merged screenshot settings per the page mapping: the single
/// screenshot shortcut recorder (PRD「截图与贴图」规则 1；Task 009：F1 开始截图),
/// save directory, format and after-capture behaviour. Bindings come from the
/// shared `SettingsViewModel` injected by the settings window's environment,
/// keeping the previous autosave/conflict-warning behaviour.
struct ScreenshotPluginSettingsPage: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    @AppStorage("screenshot.copyToClipboard") private var copyToClipboard = true
    @AppStorage("screenshot.playSound") private var playSound = true
    @AppStorage("screenshot.includeShadow") private var includeShadow = true

    @State private var pinFilePathToImage = true
    @State private var pinRestoreCapacity = PinStore.defaultRestoreCapacity
    @State private var saveDirectory: URL = URL(fileURLWithPath: ("~/Desktop" as NSString).expandingTildeInPath)
    @State private var showDirectoryImporter = false

    private struct RecorderRow: Identifiable {
        let id = UUID()
        let label: String
        let name: KeyboardShortcuts.Name
    }

    private var recorderRows: [RecorderRow] {
        [
            RecorderRow(label: L10n.localized("management.shortcuts.startScreenshot"), name: .startScreenshot)
        ]
    }

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(
                titleKey: "settings.page.screenshot",
                subtitleKey: "management.screenshot.subtitle",
                iconName: "camera.viewfinder"
            )

            SettingsSection("management.settings.shortcuts") {
                ForEach(Array(recorderRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { JadeSettingsDivider() }
                    recorderRow(row)
                }
            }

            SettingsSection("management.screenshot.saveDirectory") {
                HStack(spacing: JadeSpace.x2.value) {
                    Text(saveDirectory.path)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(JadeColor.surface1)
                        .jadeRadius(.md)
                        .jadeRadiusBorder(.md)
                    Button(L10n.localized("management.screenshot.choose")) {
                        showDirectoryImporter = true
                    }
                    .buttonStyle(.jadeSecondary)
                }
            }

            SettingsSection("management.screenshot.format") {
                Picker("", selection: .constant(0)) {
                    Text("PNG").tag(0)
                    Text("JPG").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(true)
                .help(L10n.localized("management.screenshot.format.jpgDisabled"))
                Text(L10n.localized("management.screenshot.format.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }

            SettingsSection("management.screenshot.afterCapture") {
                JadeSwitchRow(L10n.localized("management.screenshot.copyToClipboard"), isOn: $copyToClipboard)
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("management.screenshot.playSound"), isOn: $playSound)
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("management.screenshot.includeShadow"), isOn: $includeShadow)
            }

            SettingsSection("settings.pin.section") {
                JadeSwitchRow(
                    L10n.localized("settings.pin.filePathToImage"),
                    isOn: $pinFilePathToImage
                )
                .onChange(of: pinFilePathToImage) { newValue in
                    Task { try? await viewModel.set(newValue, for: .pinFilePathToImage) }
                }
                JadeSettingsDivider()
                VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                    Text(L10n.localized("settings.pin.restoreCapacity"))
                        .font(JadeFont.body)
                    Picker("", selection: $pinRestoreCapacity) {
                        ForEach(0...20, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: pinRestoreCapacity) { newValue in
                        Task { try? await viewModel.set(newValue, for: .pinRestoreCapacity) }
                    }
                }
                JadeSettingsDivider()
                HStack {
                    Text(L10n.localized("settings.pin.mouseEventsShortcut"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    Spacer()
                    HotkeyRecorder(
                        for: .pinToggleMouseEvents,
                        isConflicting: .constant(false),
                        conflictMessage: .constant(nil)
                    )
                }
            }
    }
    .fileImporter(isPresented: $showDirectoryImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
        if case .success(let urls) = result, let url = urls.first {
            saveDirectory = url
            Task { try? await viewModel.set(url, for: .screenshotSaveDirectory) }
        }
    }
    .task { await load() }
}

private func recorderRow(_ row: RecorderRow) -> some View {
    HStack {
        Text(row.label)
            .font(JadeFont.body)
            .foregroundStyle(JadeColor.textPrimary)
        Spacer()
        HotkeyRecorder(
            for: row.name,
            isConflicting: .constant(viewModel.isShortcutConflict(row.name)),
            conflictMessage: .constant(viewModel.conflictMessage(for: row.name))
        )
        .onChange(of: KeyboardShortcuts.getShortcut(for: row.name)) { _ in
            viewModel.refreshShortcutConflicts()
        }
        }
    }

    private func load() async {
        saveDirectory = (try? await viewModel.value(for: .screenshotSaveDirectory, as: URL.self))
            ?? URL(fileURLWithPath: ("~/Desktop" as NSString).expandingTildeInPath)
        pinFilePathToImage = (try? await viewModel.value(for: .pinFilePathToImage, as: Bool.self)) ?? true
        pinRestoreCapacity = (try? await viewModel.value(for: .pinRestoreCapacity, as: Int.self)) ?? PinStore.defaultRestoreCapacity
    }
}
