import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// P-03 Settings / Management Center.
///
/// A `NavigationSplitView` with a 200pt sectioned sidebar (Overview / 核心功能 /
/// 系统) and eleven detail pages. All surfaces, spacing, radius, and typography go
/// through Jade Design Tokens (T-004) and the shared Jade component library (T-007).
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var clipboardViewModel = ClipboardListViewModel()

    var body: some View {
        ManagementCenterView(viewModel: viewModel, clipboardViewModel: clipboardViewModel)
            .frame(minWidth: 920, minHeight: 640)
    }
}

// MARK: - Root split view

struct ManagementCenterView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var clipboardViewModel: ClipboardListViewModel

    @FocusState private var sidebarSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(JadeColor.surface1)
        }
        .tint(JadeColor.primary)
        .preferredColorScheme(viewModel.preferredColorScheme)
        .background(keyboardShortcuts)
        .task { await viewModel.load() }
        // 用户从“隐私与安全性”返回应用后，TCC 不会主动推送状态变化；
        // 重新激活时主动读取系统的实时授权状态，避免页面停留在授权前的旧值。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openManagementCenter)) { notification in
            if let route = notification.object as? SettingsRoute {
                viewModel.select(route: route)
            } else if let page = notification.object as? ManagementCenterPage {
                viewModel.select(page: page)
            } else {
                viewModel.select(page: .overview)
            }
        }
        .alert(L10n.localized("management.error.title"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(L10n.localized("settings.alert.ok")) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(L10n.localized("management.language.restart.title"), isPresented: $viewModel.showLanguageRestartAlert) {
            Button(L10n.localized("settings.alert.ok"), role: .cancel) {}
        } message: {
            Text(L10n.localized("management.language.restart.message"))
        }
        .alert(L10n.localized("management.data.restart.title"), isPresented: $viewModel.showResetAllDataRestartAlert) {
            Button(L10n.localized("management.data.restart.quit")) { NSApp.terminate(nil) }
        } message: {
            Text(L10n.localized("management.data.restart.message"))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: JadeSpace.x2.value) {
            JadeTextField(
                "management.sidebar.searchPlaceholder",
                text: $viewModel.sidebarFilter,
                icon: Image(systemName: "magnifyingglass")
            )
            .focused($sidebarSearchFocused)
            .padding(.horizontal, JadeSpace.x2.value)
            .padding(.top, JadeSpace.x2.value)

            List(selection: $viewModel.selectedPage) {
                if viewModel.sidebarFilter.isEmpty {
                    ForEach(ManagementSidebarSection.allCases) { section in
                        let pages = ManagementCenterPage.pages(in: section)
                        if let header = section.header {
                            Section(header) { rows(for: pages) }
                        } else {
                            Section { rows(for: pages) }
                        }
                    }
                } else {
                    Section { rows(for: filteredPages) }
                }
            }
            .listStyle(.sidebar)
        }
        .background(JadeColor.surface1)
        .onReceive(NotificationCenter.default.publisher(for: .focusSettingsSearch)) { _ in
            sidebarSearchFocused = true
        }
        .accessibilityIdentifier("settings.sidebar")
    }

    private var filteredPages: [ManagementCenterPage] {
        let needle = viewModel.sidebarFilter.lowercased()
        return ManagementCenterPage.allCases.filter { $0.title.lowercased().contains(needle) }
    }

    private func rows(for pages: [ManagementCenterPage]) -> some View {
        ForEach(pages) { page in
            Label(page.title, systemImage: page.iconName)
                .tag(page)
        }
    }

    // MARK: Detail router

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedPage {
        case .overview:
            OverviewPage(viewModel: viewModel)
        case .clipboard:
            ClipboardSettingsPage(viewModel: viewModel)
        case .shortcuts:
            ShortcutsPage(viewModel: viewModel)
        case .screenshot:
            ScreenshotPage(viewModel: viewModel)
        case .searchSources:
            SearchSourcesPage(viewModel: viewModel)
        case .appearance:
            AppearancePage(viewModel: viewModel)
        case .permissions:
            PermissionsPage(viewModel: viewModel)
        case .data:
            DataPage(viewModel: viewModel)
        case .updates:
            UpdatesPage(viewModel: viewModel)
        case .about:
            AboutPage()
        case .feedback:
            FeedbackPage()
        }
    }

    // ⌘W / ⎋ close, ⌘F focus search.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
            Button("") { NotificationCenter.default.post(name: .focusSettingsSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

extension Notification.Name {
    /// Posted by ⌘F to focus the settings sidebar search field.
    static let focusSettingsSearch = Notification.Name("com.assistant.focusSettingsSearch")
}

// MARK: - 1. Overview

private struct OverviewPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    private let about = BundleAboutInfoProvider().info

    var body: some View {
        SettingsScrollPage {
            VStack(spacing: JadeSpace.x6.value) {
                header
                statGrid
                commonSettings
            }
        }
    }

    private var header: some View {
        VStack(spacing: JadeSpace.x3.value) {
            AppIconView(size: 96, radius: .xl)
            VStack(spacing: JadeSpace.x1.value) {
                Text("青鸟 Qingniao")
                    .font(JadeFont.title1)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized("management.overview.versionLine", about.version, about.buildNumber))
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
                Text(about.copyright)
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: JadeSpace.x3.value),
                            GridItem(.flexible(), spacing: JadeSpace.x3.value)],
                  spacing: JadeSpace.x3.value) {
            StatCard(icon: Image(systemName: "calendar"),
                     title: "management.overview.stat.days",
                     value: "\(viewModel.usageDaysCount)")
            StatCard(icon: Image(systemName: "bolt"),
                     title: "management.overview.stat.dailyLaunches",
                     value: "\(viewModel.averageDailyLaunches)", tint: JadeColor.info)
            StatCard(icon: Image(systemName: "doc.on.clipboard"),
                     title: "management.overview.stat.clips",
                     value: "\(viewModel.clipboardItemCount)", tint: JadeColor.success)
            StatCard(icon: Image(systemName: "camera.viewfinder"),
                     title: "management.overview.stat.screenshots",
                     value: "\(viewModel.screenshotItemCount)", tint: JadeColor.orange)
        }
    }

    private var commonSettings: some View {
        SettingsSection("management.overview.common") {
            JadeSwitchRow(L10n.localized("settings.launchAtLogin"), isOn: launchBinding)
            Divider().overlay(JadeColor.border)
            VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                Text(L10n.localized("management.page.appearance"))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                Picker("", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(appearanceTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider().overlay(JadeColor.border)
            JadeSwitchRow(L10n.localized("management.overview.autoCheckUpdates"), isOn: $viewModel.autoCheckUpdates)
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.launchAtLoginEnabled = $0; Task { await viewModel.saveSettings() } })
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { viewModel.appearanceMode },
                set: { viewModel.updateAppearanceMode($0) })
    }

    private func appearanceTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return L10n.localized("management.appearance.system")
        case .light: return L10n.localized("management.appearance.light")
        case .dark: return L10n.localized("management.appearance.dark")
        }
    }
}

// MARK: - 2. Clipboard

private struct ClipboardSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .clipboard, subtitle: "management.clipboard.subtitle")

            SettingsSection("management.settings.clipboard") {
                JadeSwitchRow(L10n.localized("management.clipboard.enabled"), isOn: clipboardEnabledBinding)
                Divider().overlay(JadeColor.border)
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

            BlacklistManagementSection(viewModel: viewModel)
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

// MARK: - 3. Shortcuts

private struct ShortcutsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let name: KeyboardShortcuts.Name
    }

    private var rows: [Row] {
        [
            Row(label: L10n.localized("management.shortcuts.search"), name: .togglePanel),
            Row(label: L10n.localized("management.shortcuts.captureRegion"), name: .captureRegion),
            Row(label: L10n.localized("management.shortcuts.captureWindow"), name: .captureWindow),
            Row(label: L10n.localized("management.shortcuts.captureFullscreen"), name: .captureFullscreen),
            Row(label: L10n.localized("management.shortcuts.clipboardHistory"), name: .openClipboardHistory),
            Row(label: L10n.localized("management.shortcuts.openSettings"), name: .openSettings)
        ]
    }

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .shortcuts, subtitle: "management.shortcuts.subtitle")

            SettingsSection("management.settings.shortcuts") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(JadeColor.border) }
                    shortcutRow(row)
                }
            }

            HStack {
                Spacer()
                Button(L10n.localized("management.shortcuts.reset")) {
                    viewModel.resetAllShortcutsToDefaults()
                }
                .buttonStyle(.jadeGhost)
            }
        }
    }

    private func shortcutRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
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
    }
}

// MARK: - 4. Screenshot

private struct ScreenshotPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("screenshot.copyToClipboard") private var copyToClipboard = true
    @AppStorage("screenshot.playSound") private var playSound = true
    @AppStorage("screenshot.includeShadow") private var includeShadow = true

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .screenshot, subtitle: "management.screenshot.subtitle")

            SettingsSection("management.screenshot.saveDirectory") {
                HStack(spacing: JadeSpace.x2.value) {
                    Text(viewModel.screenshotSaveDirectory.path)
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
                        viewModel.showDirectoryImporter = true
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
                Divider().overlay(JadeColor.border)
                JadeSwitchRow(L10n.localized("management.screenshot.playSound"), isOn: $playSound)
                Divider().overlay(JadeColor.border)
                JadeSwitchRow(L10n.localized("management.screenshot.includeShadow"), isOn: $includeShadow)
            }
        }
        .fileImporter(isPresented: $viewModel.showDirectoryImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.updateScreenshotDirectory(url)
            }
        }
    }
}

// MARK: - 5. Search sources

private struct SearchSourcesPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    private let fileSearchDirectories = ["~/Desktop", "~/Documents", "~/Downloads"]

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .searchSources, subtitle: "management.searchSources.subtitle")

            SettingsSection("management.settings.sources") {
                ForEach(Array($viewModel.sourceToggles.enumerated()), id: \.element.id) { index, $source in
                    if index > 0 { Divider().overlay(JadeColor.border) }
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
        }
    }
}

// MARK: - 6. Appearance

private struct AppearancePage: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("accessibility.reduceMotion") private var reduceMotion = false

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .appearance, subtitle: "management.appearance.subtitle")

            SettingsSection("management.appearance.mode") {
                Picker("", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(title(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsSection("management.appearance.accent") {
                HStack(spacing: JadeSpace.x3.value) {
                    JadeRadius.md.shape
                        .fill(JadeColor.primary)
                        .frame(width: 40, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.localized("management.appearance.accent.jade"))
                            .font(JadeFont.body)
                            .foregroundStyle(JadeColor.textPrimary)
                        Text(L10n.localized("management.appearance.accent.note"))
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textTertiary)
                    }
                    Spacer()
                }
            }

            SettingsSection("management.appearance.motion") {
                JadeSwitchRow(L10n.localized("management.appearance.reduceMotion"), isOn: $reduceMotion)
                Text(L10n.localized("management.appearance.reduceMotion.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }
        }
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { viewModel.appearanceMode },
                set: { viewModel.updateAppearanceMode($0) })
    }

    private func title(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return L10n.localized("management.appearance.system")
        case .light: return L10n.localized("management.appearance.light")
        case .dark: return L10n.localized("management.appearance.dark")
        }
    }
}

// MARK: - 7. Permissions

private struct PermissionsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .permissions, subtitle: "management.permissions.subtitle")

            SettingsSection(nil) {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(JadeColor.border) }
                    permissionRow(kind)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await viewModel.refreshPermissions() }
                } label: {
                    Label(L10n.localized("management.permissions.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.jadeGhost)
            }
        }
    }

    private func permissionRow(_ kind: PermissionKind) -> some View {
        let status = viewModel.permissionStatuses[kind] ?? .unknown
        return HStack(alignment: .top, spacing: JadeSpace.x3.value) {
            Image(systemName: status.isAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(JadeFont.title3)
                .foregroundStyle(status.isAuthorized ? JadeColor.success : JadeColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(viewModel.permissionTitle(kind))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(viewModel.permissionDescription(kind))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            Spacer()
            if status.isAuthorized {
                Button(L10n.localized("management.permission.authorized")) {}
                    .buttonStyle(.jadeSecondary)
                    .disabled(true)
                    .accessibilityValue(Text(viewModel.statusTitle(status)))
            } else {
                Button(L10n.localized("onboarding.permission.openSettings")) {
                    viewModel.openSystemSettings(for: kind)
                }
                .buttonStyle(.jadeSecondary)
            }
        }
    }
}

// MARK: - 8. Data

private struct DataPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .data, subtitle: "management.data.subtitle")

            SettingsSection("management.data.storage") {
                HStack {
                    Text(L10n.localized("management.data.storageUsed"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    Spacer()
                    Text(viewModel.storageUsageText)
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                Divider().overlay(JadeColor.border)
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

            SettingsSection("management.data.actions") {
                HStack(spacing: JadeSpace.x3.value) {
                    Button(L10n.localized("management.data.openDirectory")) {
                        viewModel.openDataDirectory()
                    }
                    .buttonStyle(.jadeSecondary)

                    Button(L10n.localized("management.data.export")) {
                        viewModel.exportData()
                    }
                    .buttonStyle(.jadeSecondary)
                    .disabled(true)
                    .help(L10n.localized("management.data.export.disabled"))

                    Spacer()
                }
            }

            SettingsSection("management.data.dangerZone") {
                HStack {
                    VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                        Text(L10n.localized("management.data.resetAll"))
                            .font(JadeFont.body)
                            .foregroundStyle(JadeColor.textPrimary)
                        Text(L10n.localized("management.data.resetAll.note"))
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textTertiary)
                    }
                    Spacer()
                    Button(L10n.localized("management.data.resetAll.button")) {
                        viewModel.requestResetAllData()
                    }
                    .buttonStyle(.jadeDestructive)
                    .disabled(viewModel.isResettingAllData)
                }
            }
        }
        .jadeConfirmationDialog(
            "management.data.resetAll.confirm.title",
            isPresented: $viewModel.showResetAllDataConfirmation,
            confirmTitle: "management.data.resetAll.confirm.action",
            cancelTitle: "settings.alert.cancel",
            message: "management.data.resetAll.confirm.message"
        ) {
            Task { await viewModel.confirmResetAllData() }
        }
    }

    private var retentionBinding: Binding<ClipboardRetention> {
        Binding(get: { viewModel.clipboardRetention },
                set: { viewModel.clipboardRetention = $0; Task { await viewModel.saveSettings() } })
    }
}

// MARK: - 9. Updates

private struct UpdatesPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    private let about = BundleAboutInfoProvider().info
    private let updateService: UpdateCheckServiceProtocol = WebUpdateCheckService()

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .updates, subtitle: "management.updates.subtitle")

            SettingsSection("management.updates.current") {
                HStack {
                    Text(L10n.localized("about.version", about.version, about.buildNumber))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    Spacer()
                    Button(L10n.localized("about.checkUpdates")) {
                        updateService.openDownloadPage()
                    }
                    .buttonStyle(.jadePrimary)
                }
                Divider().overlay(JadeColor.border)
                JadeSwitchRow(L10n.localized("management.overview.autoCheckUpdates"), isOn: $viewModel.autoCheckUpdates)
            }

            SettingsSection(nil) {
                Text(L10n.localized("management.updates.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 10. About

private struct AboutPage: View {
    private let about = BundleAboutInfoProvider().info
    private let opener: ReleaseURLOpening = NSWorkspace.shared

    @State private var showingPrivacyPolicy = false

    var body: some View {
        SettingsScrollPage {
            VStack(spacing: JadeSpace.x3.value) {
                AppIconView(size: 64, radius: .lg)
                Text(about.appName)
                    .font(JadeFont.title2)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized("about.version", about.version, about.buildNumber))
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
                Text(about.copyright)
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }
            .frame(maxWidth: .infinity)

            SettingsSection("about.links.section") {
                HStack(spacing: JadeSpace.x3.value) {
                    Button(L10n.localized("about.homepage")) { opener.open(about.homepageURL) }
                        .buttonStyle(.jadeSecondary)
                    Button(L10n.localized("about.privacyPolicy")) { showingPrivacyPolicy = true }
                        .buttonStyle(.jadeSecondary)
                    Button(L10n.localized("about.thirdPartyLicenses")) { opener.open(about.thirdPartyLicensesURL) }
                        .buttonStyle(.jadeSecondary)
                    Spacer()
                }
            }

            SettingsSection("management.about.system") {
                aboutRow(L10n.localized("management.about.macos"), value: ProcessInfo.processInfo.operatingSystemVersionString)
                Divider().overlay(JadeColor.border)
                Text(L10n.localized("management.about.acknowledgements"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicySheet(info: about)
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer()
            Text(value)
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
        }
    }
}

// MARK: - 11. Feedback

private struct FeedbackPage: View {
    private let about = BundleAboutInfoProvider().info
    private let feedbackService: FeedbackServiceProtocol = FeedbackEmailService()
    private let opener: ReleaseURLOpening = NSWorkspace.shared

    @State private var email = ""
    @State private var category = FeedbackCategory.bug
    @State private var details = ""
    @State private var includeSystemInfo = true
    @State private var errorMessage: String?

    private enum FeedbackCategory: String, CaseIterable, Identifiable {
        case bug, suggestion, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bug: return L10n.localized("management.feedback.category.bug")
            case .suggestion: return L10n.localized("management.feedback.category.suggestion")
            case .other: return L10n.localized("management.feedback.category.other")
            }
        }
    }

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(page: .feedback, subtitle: "management.feedback.subtitle")

            SettingsSection(nil) {
                fieldLabel("management.feedback.email")
                JadeTextField("management.feedback.email.placeholder", text: $email)

                fieldLabel("management.feedback.category")
                Picker("", selection: $category) {
                    ForEach(FeedbackCategory.allCases) { c in Text(c.title).tag(c) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                fieldLabel("management.feedback.details")
                TextEditor(text: $details)
                    .font(JadeFont.body)
                    .frame(minHeight: 120)
                    .padding(JadeSpace.x1.value)
                    .background(JadeColor.surface1)
                    .jadeRadius(.md)
                    .jadeRadiusBorder(.md)

                JadeSwitchRow(L10n.localized("management.feedback.includeSystemInfo"), isOn: $includeSystemInfo)
            }

            HStack {
                Spacer()
                Button(L10n.localized("management.feedback.send")) { send() }
                    .buttonStyle(.jadePrimary)
            }
        }
        .alert(L10n.localized("about.feedback.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.localized("settings.alert.ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func fieldLabel(_ key: String) -> some View {
        Text(L10n.localized(key))
            .font(JadeFont.subhead)
            .foregroundStyle(JadeColor.textSecondary)
    }

    private func send() {
        do {
            let body: String
            if email.trimmingCharacters(in: .whitespaces).isEmpty {
                body = details
            } else {
                body = "\(L10n.localized("management.feedback.email")): \(email)\n\n\(details)"
            }
            let context = FeedbackContext(
                appVersion: about.version,
                buildNumber: about.buildNumber,
                macOSVersion: includeSystemInfo ? ProcessInfo.processInfo.operatingSystemVersionString : "(omitted)",
                errorSummary: category.title,
                userDescription: body
            )
            let url = try feedbackService.makeFeedbackEmail(context: context)
            opener.open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Blacklist management (preserved from prior SettingsView)

struct BlacklistManagementSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection("management.blacklist.title") {
            VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
                HStack {
                    Picker(L10n.localized("management.blacklist.source"), selection: $viewModel.newBlacklistSourceID) {
                        ForEach(SettingsViewModel.sourceOptions, id: \.id) { option in
                            Text(option.label).tag(option.id.rawValue)
                        }
                    }
                    TextField(L10n.localized("management.blacklist.resultID"), text: $viewModel.newBlacklistResultID)
                    TextField(L10n.localized("management.blacklist.titleField"), text: $viewModel.newBlacklistTitle)
                    TextField(L10n.localized("management.blacklist.type"), text: $viewModel.newBlacklistType)
                        .frame(width: 120)
                    Button(L10n.localized("management.blacklist.add")) {
                        Task { await viewModel.addBlacklistItem() }
                    }
                    .buttonStyle(.jadeSecondary)
                }

                if viewModel.blacklistItems.isEmpty {
                    Text(L10n.localized("management.blacklist.empty"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                } else {
                    ForEach(viewModel.blacklistItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(JadeFont.body)
                                Text("\(item.sourceID.rawValue) · \(item.resultID.rawValue) · \(item.resultType)")
                                    .font(JadeFont.caption)
                                    .foregroundStyle(JadeColor.textSecondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.removeBlacklistItem(item) }
                            } label: {
                                Label(L10n.localized("management.blacklist.remove"), systemImage: "trash")
                            }
                            .buttonStyle(.jadeGhost)
                        }
                        Divider().overlay(JadeColor.border)
                    }
                }
            }
        }
    }
}

// MARK: - Privacy policy sheet (preserved)

struct PrivacyPolicySheet: View {
    let info: AboutInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x4.value) {
            HStack {
                Text(L10n.localized("privacy.title"))
                    .font(JadeFont.title2)
                Spacer()
                Button(L10n.localized("settings.alert.ok")) { dismiss() }
                    .buttonStyle(.jadeSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
                    privacySection("privacy.local.title", bodyKey: "privacy.local.body")
                    privacySection("privacy.clipboard.title", bodyKey: "privacy.clipboard.body")
                    privacySection("privacy.screenshot.title", bodyKey: "privacy.screenshot.body")
                    privacySection("privacy.control.title", bodyKey: "privacy.control.body")
                    privacySection("privacy.feedback.title", bodyKey: "privacy.feedback.body")
                    Text(L10n.localized("privacy.contact", info.feedbackEmail))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(JadeSpace.x6.value)
        .frame(width: 640, height: 560)
        .background(JadeColor.surface1)
    }

    private func privacySection(_ titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
            Text(L10n.localized(titleKey))
                .font(JadeFont.title3)
            Text(L10n.localized(bodyKey))
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared layout primitives

/// Standard scrollable settings page container: 24pt padding, top-leading aligned.
private struct SettingsScrollPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JadeSpace.x6.value) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x6.value)
        }
    }
}

/// Page title header (icon chip + title + subtitle).
private struct SettingsHeader: View {
    let page: ManagementCenterPage
    let subtitle: String

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: page.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(JadeColor.primary)
                .frame(width: 44, height: 44)
                .background(JadeColor.primaryFill)
                .jadeRadius(.md)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(JadeFont.title2)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized(subtitle))
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            Spacer()
        }
    }
}

/// A titled card section: headline title + surface2 rounded card (radius-lg, padding 16).
struct SettingsSection<Content: View>: View {
    private let title: String?
    @ViewBuilder private let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
            if let title {
                Text(L10n.localized(title))
                    .font(JadeFont.title3)
                    .foregroundStyle(JadeColor.textPrimary)
            }
            VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JadeSpace.x4.value)
            .background(JadeColor.surface2)
            .jadeRadius(.lg)
        }
    }
}

/// A labeled switch row (Jade tinted toggle), optional icon + subtitle.
private struct JadeSwitchRow: View {
    private let icon: String?
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.icon = nil
        self.title = title
        self.subtitle = nil
        self._isOn = isOn
    }

    init(icon: String?, title: String, subtitle: String?, isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: JadeSpace.x2.value) {
                if let icon {
                    Image(systemName: icon)
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textSecondary)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textSecondary)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .tint(JadeColor.primary)
    }
}

/// App icon glyph: renders the bundle icon, falling back to a jade `bird` symbol.
private struct AppIconView: View {
    let size: CGFloat
    let radius: JadeRadius

    var body: some View {
        Group {
            if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "bird")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(JadeColor.primary)
                    .background(JadeColor.primaryFill)
            }
        }
        .frame(width: size, height: size)
        .jadeRadius(radius)
        .accessibilityHidden(true)
    }
}

#Preview {
    SettingsView()
}
