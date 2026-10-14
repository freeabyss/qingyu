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

    // Task 014/03：导出结果图的外观。默认全 0 = 不装饰，导出内容与开启本能力前逐字节一致。
    @AppStorage(ScreenshotFrameStyle.DefaultsKey.cornerRadius) private var frameCornerRadius = 0.0
    @AppStorage(ScreenshotFrameStyle.DefaultsKey.borderWidth) private var frameBorderWidth = 0.0
    @AppStorage(ScreenshotFrameStyle.DefaultsKey.borderColor) private var frameBorderColor = "#000000"
    @AppStorage(ScreenshotFrameStyle.DefaultsKey.shadowWidth) private var frameShadowWidth = 0.0
    @AppStorage(ScreenshotFrameStyle.DefaultsKey.shadowColor) private var frameShadowColor = "#000000"

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
            }

            // Task 014/03：导出结果图的外观（圆角 / 边框 / 阴影）。
            // 只影响「复制 / 保存」，贴图与打印沿用原始像素。
            SettingsSection("management.screenshot.frame") {
                JadeSwitchRow(L10n.localized("management.screenshot.includeShadow"), isOn: $includeShadow)
                Text(L10n.localized("management.screenshot.frame.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
                JadeSettingsDivider()
                frameSlider(
                    titleKey: "management.screenshot.frame.cornerRadius",
                    value: $frameCornerRadius,
                    range: 0...60,
                    upperUnit: "pt"
                )
                JadeSettingsDivider()
                frameSlider(
                    titleKey: "management.screenshot.frame.shadowWidth",
                    value: $frameShadowWidth,
                    range: 0...60,
                    upperUnit: "pt"
                )
                .disabled(!includeShadow)
                JadeSettingsDivider()
                colorRow(
                    titleKey: "management.screenshot.frame.shadowColor",
                    hex: $frameShadowColor
                )
                .disabled(!includeShadow)
                JadeSettingsDivider()
                frameSlider(
                    titleKey: "management.screenshot.frame.borderWidth",
                    value: $frameBorderWidth,
                    range: 0...20,
                    upperUnit: "pt"
                )
                JadeSettingsDivider()
                colorRow(
                    titleKey: "management.screenshot.frame.borderColor",
                    hex: $frameBorderColor
                )
                .disabled(frameBorderWidth <= 0)
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

    // MARK: - Task 014/03 外观控件

    /// 带数值回显的滑杆行：0 明确显示「0 pt」，避免用户误以为开关失效。
    private func frameSlider(
        titleKey: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        upperUnit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            HStack {
                Text(L10n.localized(titleKey))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(upperUnit)")
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    /// 颜色行：以 `#RRGGBB` 存盘，直接复用 `ScreenshotFrameStyle` 的解析规则。
    private func colorRow(titleKey: String, hex: Binding<String>) -> some View {
        HStack {
            Text(L10n.localized(titleKey))
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer()
            ColorPicker("", selection: colorBinding(hex))
                .labelsHidden()
        }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hexString: hex.wrappedValue) ?? .black) },
            set: { newValue in
                guard let ns = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                hex.wrappedValue = String(
                    format: "#%02X%02X%02X",
                    Int((ns.redComponent * 255).rounded()),
                    Int((ns.greenComponent * 255).rounded()),
                    Int((ns.blueComponent * 255).rounded())
                )
            }
        )
    }
}
