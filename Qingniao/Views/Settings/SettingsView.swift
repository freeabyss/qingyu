import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// P-03 Settings / Management Center — five-page layout (Task 004).
///
/// `NavigationSplitView` whose sidebar is 通用 + 功能列表下的插件页
/// (`pluginRegistry.settingsPages`：快速启动、剪贴板、截图) + 关于。All surfaces,
/// spacing, radius, and typography go through Jade Design Tokens (T-004) and the
/// shared Jade component library (T-007).
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        ManagementCenterView(viewModel: viewModel)
            .frame(minWidth: 920, minHeight: 640)
    }
}

// MARK: - Root split view

struct ManagementCenterView: View {
    @ObservedObject var viewModel: SettingsViewModel

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
        .environmentObject(viewModel)
        .task { await viewModel.load() }
        // 用户从“隐私与安全性”返回应用后，TCC 不会主动推送状态变化；
        // 重新激活时主动读取系统的实时授权状态，避免页面停留在授权前的旧值。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openManagementCenter)) { notification in
            if let route = notification.object as? SettingsRoute {
                viewModel.select(route: route)
            } else {
                viewModel.selectedPage = .general
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
        List(selection: $viewModel.selectedPage) {
            generalRow
            if !pluginPageIDs.isEmpty {
                Section(L10n.localized("settings.section.features")) {
                    pluginRows
                }
            }
            aboutRow
        }
        .listStyle(.sidebar)
        .background(JadeColor.surface1)
        .accessibilityIdentifier("settings.sidebar")
    }

    private var pluginPageIDs: [PluginID] {
        viewModel.visiblePageIDs.compactMap { pageID in
            if case .plugin(let pluginID) = pageID { return pluginID }
            return nil
        }
    }

    @ViewBuilder
    private var generalRow: some View {
        Label(L10n.localized("settings.page.general"), systemImage: "gearshape")
            .tag(SettingsPageID.general)
            .accessibilityIdentifier("settings.general")
    }

    @ViewBuilder
    private var aboutRow: some View {
        Label(L10n.localized("settings.page.about"), systemImage: "info.circle")
            .tag(SettingsPageID.about)
            .accessibilityIdentifier("settings.about")
    }

    @ViewBuilder
    private var pluginRows: some View {
        ForEach(viewModel.visiblePageIDs, id: \.self) { pageID in
            if case .plugin(let pluginID) = pageID, let descriptor = viewModel.pluginSettingsPage(for: pluginID) {
                Label(L10n.localized(descriptor.titleKey), systemImage: descriptor.systemImageName)
                    .tag(pageID)
                    .accessibilityIdentifier("settings.\(pluginID.rawValue)")
            }
        }
    }

    // MARK: Detail router

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedPage {
        case .general:
            GeneralPage(viewModel: viewModel)
        case .plugin(let pluginID):
            viewModel.makePluginPageView(id: pluginID)
        case .about:
            AboutPage()
        }
    }

    // ⌘W / ⎋ close.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - General page

/// 通用页（Task 004 映射表）：开机启动、语言、外观、权限、数据。
private struct GeneralPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("accessibility.reduceMotion") private var reduceMotion = false

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(titleKey: "settings.page.general",
                           subtitleKey: "settings.general.subtitle",
                           iconName: "gearshape")

            SettingsSection("settings.general.startup") {
                JadeSwitchRow(L10n.localized("settings.launchAtLogin"), isOn: launchBinding)
                Divider().overlay(JadeColor.border)
                VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                    Text(L10n.localized("settings.general.language"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    Picker("", selection: languageBinding) {
                        ForEach(SettingsViewModel.languageOptions, id: \.self) { language in
                            Text(viewModel.languageTitle(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            SettingsSection("management.page.appearance") {
                Picker("", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(appearanceTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

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

                JadeSwitchRow(L10n.localized("management.appearance.reduceMotion"), isOn: $reduceMotion)
                Text(L10n.localized("management.appearance.reduceMotion.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }

            SettingsSection("management.page.permissions") {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(JadeColor.border) }
                    permissionRow(kind)
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

            SettingsSection("management.page.data") {
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
                Divider().overlay(JadeColor.border)
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

    private var launchBinding: Binding<Bool> {
        Binding(get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.launchAtLoginEnabled = $0; Task { await viewModel.saveSettings() } })
    }

    private var languageBinding: Binding<LanguageMode> {
        Binding(get: { viewModel.languageMode },
                set: { viewModel.languageMode = $0; Task { await viewModel.saveSettings() } })
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

// MARK: - About page

/// 关于页（Task 004 映射表）：应用信息、链接与隐私、更新、反馈、系统信息。
private struct AboutPage: View {
    private let about = BundleAboutInfoProvider().info
    private let updateService: UpdateCheckServiceProtocol = WebUpdateCheckService()
    private let opener: ReleaseURLOpening = NSWorkspace.shared

    @State private var showingPrivacyPolicy = false

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(titleKey: "settings.page.about",
                           subtitleKey: "management.about.system",
                           iconName: "info.circle")

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
                FeedbackSection()
            }

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

// MARK: - Feedback section (merged into About, Task 004)

private struct FeedbackSection: View {
    private let about = BundleAboutInfoProvider().info
    private let feedbackService: FeedbackServiceProtocol = FeedbackEmailService()
    private let opener: ReleaseURLOpening = NSWorkspace.shared

    @State private var email = ""
    @State private var category: FeedbackCategory = .bug
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
        VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
            Text(L10n.localized("management.feedback.subtitle"))
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)

            JadeTextField("management.feedback.email.placeholder", text: $email)

            Picker("", selection: $category) {
                ForEach(FeedbackCategory.allCases) { c in Text(c.title).tag(c) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            TextEditor(text: $details)
                .font(JadeFont.body)
                .frame(minHeight: 90)
                .padding(JadeSpace.x1.value)
                .background(JadeColor.surface1)
                .jadeRadius(.md)
                .jadeRadiusBorder(.md)

            JadeSwitchRow(L10n.localized("management.feedback.includeSystemInfo"), isOn: $includeSystemInfo)

            HStack {
                Spacer()
                Button(L10n.localized("management.feedback.send")) { send() }
                    .buttonStyle(.jadeSecondary)
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
struct SettingsScrollPage<Content: View>: View {
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
struct SettingsHeader: View {
    let titleKey: String
    let subtitleKey: String
    let iconName: String

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(JadeColor.primary)
                .frame(width: 44, height: 44)
                .background(JadeColor.primaryFill)
                .jadeRadius(.md)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.localized(titleKey))
                    .font(JadeFont.title2)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized(subtitleKey))
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
struct JadeSwitchRow: View {
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
