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
    @State private var magnifierEnabled = MagnifierConfiguration.default.isEnabled
    @State private var magnifierZoom = MagnifierConfiguration.default.zoom
    @State private var magnifierOptions = MagnifierConfiguration.default.options
    @State private var elementDetectionEnabled = false
    @State private var snapThreshold: Double = 0
    @State private var ignoredAppsText = ""
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

            // Task 011：放大镜。关闭时整个分区置灰但保留当前取值，便于对照。
            SettingsSection("settings.magnifier.section") {
                JadeSwitchRow(
                    L10n.localized("settings.magnifier.enabled"),
                    isOn: $magnifierEnabled
                )
                .onChange(of: magnifierEnabled) { newValue in
                    Task { try? await viewModel.set(newValue, for: .magnifierShown) }
                }
                JadeSettingsDivider()
                VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                    Text(L10n.localized("settings.magnifier.zoom"))
                        .font(JadeFont.body)
                    Picker("", selection: $magnifierZoom) {
                        ForEach(MagnifierConfiguration.availableZooms, id: \.self) { zoom in
                            Text("\(zoom)×").tag(zoom)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: magnifierZoom) { newValue in
                        Task { try? await viewModel.set(newValue, for: .magnifierZoom) }
                    }
                }
                .disabled(!magnifierEnabled)
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("settings.magnifier.grid"), isOn: magnifierOptionBinding(.grid))
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("settings.magnifier.coordinate"), isOn: magnifierOptionBinding(.coordinate))
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("settings.magnifier.zoomLabel"), isOn: magnifierOptionBinding(.zoomLabel))
                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("settings.magnifier.mask"), isOn: magnifierOptionBinding(.mask))
            }
            .disabled(!magnifierEnabled)

            // Task 012：窗口与控件自动识别。
            SettingsSection("settings.elementDetection.section") {
                JadeSwitchRow(
                    L10n.localized("settings.elementDetection.enabled"),
                    isOn: $elementDetectionEnabled
                )
                .onChange(of: elementDetectionEnabled) { newValue in
                    Task { try? await viewModel.set(newValue, for: .elementDetection) }
                }
                Text(L10n.localized("settings.elementDetection.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
                JadeSettingsDivider()
                VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                    HStack {
                        Text(L10n.localized("settings.snapThreshold"))
                            .font(JadeFont.body)
                            .foregroundStyle(JadeColor.textPrimary)
                        Spacer()
                        Text(snapThreshold <= 0
                             ? L10n.localized("settings.snapThreshold.off")
                             : "\(Int(snapThreshold)) pt")
                            .font(JadeFont.callout)
                            .foregroundStyle(JadeColor.textSecondary)
                    }
                    Slider(value: $snapThreshold, in: 0...30, step: 1)
                        .onChange(of: snapThreshold) { newValue in
                            Task { try? await viewModel.set(newValue, for: .snapThreshold) }
                        }
                }
                JadeSettingsDivider()
                VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                    Text(L10n.localized("settings.elementIgnoredApps"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    TextEditor(text: $ignoredAppsText)
                        .font(JadeFont.caption)
                        .frame(height: 60)
                        .onChange(of: ignoredAppsText) { newValue in
                            let ids = newValue
                                .split(whereSeparator: \.isNewline)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            Task { try? await viewModel.set(ids, for: .elementIgnoredApps) }
                        }
                    Text(L10n.localized("settings.elementIgnoredApps.note"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textTertiary)
                }
                .disabled(!elementDetectionEnabled)
            }

            SettingsSection("settings.pin.section") {                JadeSwitchRow(
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

        let magnifierDefaults = MagnifierConfiguration.default
        magnifierEnabled = (try? await viewModel.value(for: .magnifierShown, as: Bool.self))
            ?? magnifierDefaults.isEnabled
        magnifierZoom = MagnifierConfiguration.clampZoom(
            (try? await viewModel.value(for: .magnifierZoom, as: Int.self)) ?? magnifierDefaults.zoom
        )
        let optionRaws = (try? await viewModel.value(for: .magnifierOptions, as: [String].self))
            ?? magnifierDefaults.options.map(\.rawValue).sorted()
        magnifierOptions = Set(optionRaws.compactMap(MagnifierDisplayOption.init(rawValue:)))

        elementDetectionEnabled = (try? await viewModel.value(for: .elementDetection, as: Bool.self)) ?? false
        snapThreshold = (try? await viewModel.value(for: .snapThreshold, as: Double.self)) ?? 0
        let ignoredApps = (try? await viewModel.value(for: .elementIgnoredApps, as: [String].self)) ?? []
        ignoredAppsText = ignoredApps.joined(separator: "\n")
    }

    /// 显示项开关：读写都走设置，避免「视图上有勾但重启后丢失」。
    private func magnifierOptionBinding(_ option: MagnifierDisplayOption) -> Binding<Bool> {
        Binding(
            get: { magnifierOptions.contains(option) },
            set: { isOn in
                if isOn {
                    magnifierOptions.insert(option)
                } else {
                    magnifierOptions.remove(option)
                }
                let raw = magnifierOptions.map(\.rawValue).sorted()
                Task { try? await viewModel.set(raw, for: .magnifierOptions) }
            }
        )
    }
}
