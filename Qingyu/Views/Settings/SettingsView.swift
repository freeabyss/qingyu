import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// P-03 Settings / Management Center — five-page layout (Task 004).
///
/// Fixed two-column layout (not `NavigationSplitView`) so macOS never injects
/// a sidebar-toggle control into the title-bar / sidebar corner.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    /// 设置窗口最小宽度：920pt，仅用于设置窗口整体最小宽度；与隐私弹窗宽度 640pt 数值巧合但角色不同，不合并。
    private static let settingsWindowMinWidth: CGFloat = 920

    /// 设置窗口最小高度：640pt，仅用于设置窗口整体最小高度；与隐私弹窗高度 560pt 角色不同，不合并。
    private static let settingsWindowMinHeight: CGFloat = 640

    var body: some View {
        ManagementCenterView(viewModel: viewModel)
            .frame(minWidth: Self.settingsWindowMinWidth, minHeight: Self.settingsWindowMinHeight)
    }
}

// MARK: - Root split view

struct ManagementCenterView: View {

    /// 隐藏快捷键容器尺寸：0pt，仅用于承载 ⌘W / ⎋ 关闭快捷键的不可见容器宽高；不是布局尺寸，不与其它尺寸合并。
    private static let hiddenShortcutSize: CGFloat = 0

    @ObservedObject var viewModel: SettingsViewModel

    /// 管理中心侧栏列宽：200pt，仅用于管理中心左侧导航列宽度；与窗口宽度角色不同，不合并；不并入 JadeSpace，那是间距档位，不是列宽。
    private static let sidebarWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)

            // 侧栏与详情共处同一块玻璃，中间只有一条细线（系统设置同款语汇）。
            Rectangle()
                .fill(JadeGlass.separator)
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .jadePadding(.top, .x3)
        }
        .tint(JadeColor.primary)
        .preferredColorScheme(viewModel.preferredColorScheme)
        // 设置是长时阅读窗口：玻璃染色略深一档，桌面只透层次不干扰正文。
        .jadeGlassSurface(radius: .xxl, tint: .reading)
        .jadeGlassEdge(radius: .xxl)
        .jadeShadow(.xl, radius: .xxl)
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
        // 「清空所有数据」入口移除后，随之而来的重启提示也不再需要。
    }

    // MARK: Sidebar

    /// 侧栏导航行：玻璃语言里选中态是一枚 `controlActive` 胶囊，
    /// 而非系统 `List(.sidebar)` 自带的材质底（会在窗口玻璃上再叠一层材质）。
    private struct SettingsSidebarRow: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: JadeSpace.x2.value) {
                    SettingsSidebarIcon(systemImage: icon, isActive: isSelected)
                    Text(title)
                        .font(JadeFont.body)
                        .foregroundStyle(isSelected ? JadeColor.primary : JadeColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jadePadding(.horizontal, .x3)
                .jadePadding(.vertical, .x2)
                .background(
                    isSelected ? JadeGlass.controlActive : (isHovering ? JadeGlass.rowHover : Color.clear),
                    in: JadeRadius.md.shape
                )
                .contentShape(JadeRadius.md.shape)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .jadeAnimation(.easeInOut(duration: 0.12), value: isHovering)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 顶部留出红绿灯区：fullSizeContentView 下标题栏透明，内容直接顶到窗口边。
            SettingsBrandHeader()
                .jadePadding(.horizontal, .x4)
                .jadePadding(.top, .x6)
                .jadePadding(.bottom, .x3)
            Rectangle()
                .fill(JadeGlass.separator)
                .frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                    SettingsSidebarRow(
                        title: L10n.localized("settings.page.general"),
                        icon: "gearshape",
                        isSelected: viewModel.selectedPage == .general
                    ) {
                        viewModel.selectedPage = .general
                    }
                    .accessibilityIdentifier("settings.general")

                    if !pluginPageIDs.isEmpty {
                        Text(L10n.localized("settings.section.features"))
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textTertiary)
                            .jadePadding(.horizontal, .x3)
                            .jadePadding(.top, .x2)
                    }

                    ForEach(viewModel.visiblePageIDs, id: \.self) { pageID in
                        if case .plugin(let pluginID) = pageID,
                           let descriptor = viewModel.pluginSettingsPage(for: pluginID) {
                            SettingsSidebarRow(
                                title: L10n.localized(descriptor.titleKey),
                                icon: descriptor.systemImageName,
                                isSelected: viewModel.selectedPage == pageID
                            ) {
                                viewModel.selectedPage = pageID
                            }
                            .accessibilityIdentifier("settings.\(pluginID.rawValue)")
                        }
                    }

                    SettingsSidebarRow(
                        title: L10n.localized("settings.page.about"),
                        icon: "info.circle",
                        isSelected: viewModel.selectedPage == .about
                    ) {
                        viewModel.selectedPage = .about
                    }
                    .accessibilityIdentifier("settings.about")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jadePadding(.horizontal, .x2)
                .jadePadding(.vertical, .x2)
            }
        }
        .accessibilityIdentifier("settings.sidebar")
    }

    private var pluginPageIDs: [PluginID] {
        viewModel.visiblePageIDs.compactMap { pageID in
            if case .plugin(let pluginID) = pageID { return pluginID }
            return nil
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
        .jadeHiddenShortcut()
        .frame(width: Self.hiddenShortcutSize, height: Self.hiddenShortcutSize)
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
                JadeSettingsDivider()
                JadeSettingsRow(L10n.localized("settings.general.language")) {
                    Picker("", selection: languageBinding) {
                        ForEach(SettingsViewModel.languageOptions, id: \.self) { language in
                            Text(viewModel.languageTitle(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            // PRD §02-ui-spec：通用页包含「插件管理」——每一行显示名称、版本、
            // 状态和启用开关，失败时显示原因与重试操作。此前整块 UI 缺失，
            // 而注册表早就有 isEnabled / setEnabled / state / descriptor。
            if !viewModel.pluginRows.isEmpty {
                SettingsSection("settings.plugins.section") {
                    ForEach(Array(viewModel.pluginRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { JadeSettingsDivider() }
                        pluginRow(row)
                    }
                }
            }

            SettingsSection("management.page.appearance") {
                JadeSegmentedPicker(
                    options: AppearanceMode.allCases.map { ($0, appearanceTitle($0)) },
                    selection: appearanceBinding
                )

                JadeSettingsDivider()
                JadeSwitchRow(L10n.localized("management.appearance.reduceMotion"), isOn: $reduceMotion)
                Text(L10n.localized("management.appearance.reduceMotion.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }

            SettingsSection("management.page.permissions") {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { JadeSettingsDivider() }
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

            // 搜索黑名单（PRD FR-SEARCH-8i：只能通过设置页管理）。
            // 此前整个 section 在「合并为五页」重构中从页面里掉出，而结构体
            // 与后端一直保留——功能齐备但用户没有任何入口，属于入口丢失。
            BlacklistManagementSection(viewModel: viewModel)

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
                JadeSettingsDivider()
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
                // 禁用按钮的原因写在按钮旁边，而不是只藏在悬停提示里。
                // 按钮的灰态本身不解释任何东西，用户会以为是故障。
                Text(L10n.localized("management.data.export.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
                // PRD §02-ui-spec：「数据」区域只提供占用空间与打开数据目录等**非破坏性**操作，
                // 明确「不提供重置或清空全部数据」。此处原来的「清空所有数据…」违反该约束，
                // 且一键抹掉截图与设置的风险很高——已移除。
                // 剪贴板历史的清空在「设置 → 剪贴板」，是 PRD 规定的唯一入口。
            }
        }
    }

    /// 插件管理的一行：名称 + 版本 + 状态（+ 失败原因）+ 重试 + 启用开关。
    @ViewBuilder
    private func pluginRow(_ row: SettingsViewModel.PluginRowInfo) -> some View {
        HStack(alignment: .top, spacing: JadeSpace.x3.value) {
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                HStack(spacing: JadeSpace.x2.value) {
                    Text(L10n.localized(row.displayNameKey))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textPrimary)
                    Text(L10n.localized("settings.plugins.version", row.version))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textTertiary)
                }
                Text(pluginStateText(row))
                    .font(JadeFont.caption)
                    .foregroundStyle(pluginStateColor(row))
                // PRD：失败时显示原因与重试操作。
                if let reason = row.failureReason {
                    Text(reason)
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if row.state == .failed {
                Button(L10n.localized("settings.plugins.retry")) {
                    Task { await viewModel.retryPlugin(row.id) }
                }
                .buttonStyle(.jadeSecondary)
            }
            Toggle("", isOn: Binding(
                get: { row.isEnabled },
                set: { enabled in Task { await viewModel.setPluginEnabled(enabled, for: row.id) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(Text(L10n.localized(row.displayNameKey)))
        }
    }

    private func pluginStateText(_ row: SettingsViewModel.PluginRowInfo) -> String {
        switch row.state {
        case .started: return L10n.localized("settings.plugins.state.running")
        case .failed: return L10n.localized("settings.plugins.state.failed")
        case .stopped: return L10n.localized("settings.plugins.state.stopped")
        case .registered, .none: return L10n.localized("settings.plugins.state.registered")
        }
    }

    private func pluginStateColor(_ row: SettingsViewModel.PluginRowInfo) -> Color {
        switch row.state {
        case .failed: return JadeColor.dangerText
        case .started: return JadeColor.successText
        case .stopped, .registered, .none: return JadeColor.textTertiary
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
        // 顶部对齐：权限行常常有 3–5 行说明（含 ad-hoc 构建提示），
        // 垂直居中会让状态图标和「打开系统设置」按钮浮在长段文字的正中间，
        // 既不属于标题也不属于说明，按钮与它要处理的那一项脱节。
        return HStack(alignment: .top, spacing: JadeSpace.x3.value) {
            Image(systemName: status.isAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(JadeFont.body)
                .foregroundStyle(status.isAuthorized ? JadeColor.textSecondary : JadeColor.warningText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(viewModel.permissionTitle(kind))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(viewModel.permissionDescription(kind))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
                // 屏幕录制未授权：macOS 15 起系统不再自动把本 App 加入列表，
                // 不点明「+ 手动添加」用户会一直找不到清羽（见 `ScreenRecordingConsentFlow`）。
                // 长段落说明用常规文字色，警告语义交给左侧图标。
                // systemOrange 在浅色底上对比度约 2.2:1，远低于正文所需的 4.5:1——
                // 10pt 橙色正文读起来吃力，等于把「重要提示」写成了看不清的字。
                if !status.isAuthorized, kind == .screenRecording {
                    Text(L10n.localized("management.permission.screenRecording.manualAdd"))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 未授权 + ad-hoc 构建：直接说明「为什么授权了还是没授权」，
                // 避免用户反复授权却始终无效。
                if !status.isAuthorized,
                   let noteKey = PermissionGuidance.developmentSignatureNoteKey(for: viewModel.appSignatureStatus) {
                    Text(L10n.localized(noteKey))
                        .font(JadeFont.caption)
                        .foregroundStyle(JadeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            HStack(spacing: JadeSpace.x4.value) {
                AboutBrandHeader(about: about)
                Button(L10n.localized("about.checkUpdates")) {
                    updateService.openDownloadPage()
                }
                .buttonStyle(.jadeSecondary)
            }

            SettingsSection("about.feedback") {
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
                JadeSettingsDivider()
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

    /// 反馈详情输入框最小高度：90pt，仅用于反馈详情 TextEditor 最小高度；与其它高度角色不同，不合并。
    private static let feedbackDetailsMinHeight: CGFloat = 90

    private let about = BundleAboutInfoProvider().info
    private let feedbackService: FeedbackServiceProtocol = FeedbackEmailService()
    private let opener: ReleaseURLOpening = NSWorkspace.shared

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

            // 分段控件按内容宽度排布：撑满整行会让三个选项各占 1/3 行宽，
            // 看起来像一排被拉长的按钮，而不是「选一个」的控件。
            HStack {
                JadeSegmentedPicker(
                    options: FeedbackCategory.allCases.map { ($0, $0.title) },
                    selection: $category
                )
                .fixedSize()
                Spacer()
            }

            // 空输入框没有占位提示时，用户不知道这里该写什么。
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .font(JadeFont.body)
                    .frame(minHeight: Self.feedbackDetailsMinHeight)
                    .jadePadding(.x1)
                    // 输入井：半透明键帽底压在玻璃卡片上，形成「凹进去」的层次。
                    .background(JadeGlass.keycapFill)
                    .jadeRadius(.md)
                    .jadeRadiusBorder(.md)

                if details.isEmpty {
                    Text(L10n.localized("management.feedback.placeholder"))
                        .font(JadeFont.body)
                        .foregroundStyle(JadeColor.textTertiary)
                        .jadePadding(.x1)
                        .allowsHitTesting(false)
                }
            }

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
            let context = FeedbackContext(
                appVersion: about.version,
                buildNumber: about.buildNumber,
                macOSVersion: includeSystemInfo ? ProcessInfo.processInfo.operatingSystemVersionString : "(omitted)",
                errorSummary: category.title,
                userDescription: details
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

    /// 黑名单来源选择器最大宽度：180pt，仅用于黑名单来源 Picker 最大宽度；与类型输入框 220pt 角色不同，不合并。
    private static let blacklistSourceMaxWidth: CGFloat = 180

    /// 黑名单类型输入框最大宽度：220pt，仅用于黑名单类型 TextField 最大宽度；与来源选择器 180pt 角色不同，不合并。
    private static let blacklistTypeMaxWidth: CGFloat = 220

    @ObservedObject var viewModel: SettingsViewModel

    /// 带小标签的输入字段：标签在上（caption / 次要色），控件在下并撑满宽度。
    /// 让字段含义始终可见，不必依赖占位符猜测。
    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
            Text(label)
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        SettingsSection("management.blacklist.title") {
            VStack(alignment: .leading, spacing: JadeSpace.x3.value) {
                // 每个字段「小标签 + 输入框」竖排，三等分等宽：
                // 早先把三个输入框平铺在一行，Picker 固定 180pt、其余按剩余空间
                // 拉伸，出现「中间很宽、右边被压窄」的失衡；且只有 Picker 带可见标签，
                // 另两个靠占位符，填完后无法确认字段含义。
                HStack(alignment: .bottom, spacing: JadeSpace.x3.value) {
                    labeledField(L10n.localized("management.blacklist.source")) {
                        Picker("", selection: $viewModel.newBlacklistSourceID) {
                            ForEach(SettingsViewModel.sourceOptions, id: \.id) { option in
                                Text(option.label).tag(option.id.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    labeledField(L10n.localized("management.blacklist.resultID")) {
                        TextField("", text: $viewModel.newBlacklistResultID)
                    }
                    labeledField(L10n.localized("management.blacklist.titleField")) {
                        TextField("", text: $viewModel.newBlacklistTitle)
                    }
                }

                HStack(alignment: .bottom, spacing: JadeSpace.x3.value) {
                    labeledField(L10n.localized("management.blacklist.type")) {
                        TextField("", text: $viewModel.newBlacklistType)
                    }
                    .frame(maxWidth: Self.blacklistTypeMaxWidth)
                    Button(L10n.localized("management.blacklist.add")) {
                        Task { await viewModel.addBlacklistItem() }
                    }
                    .buttonStyle(.jadeSecondary)
                    Spacer()
                }

                // 高级功能说明：讲清「稳定 ID」是什么、这个功能怎么用。
                // 没有这段，普通用户面对「来源 / 稳定结果 ID / 类型」三个字段无从下手。
                Text(L10n.localized("management.blacklist.help"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
                        JadeSettingsDivider()
                    }
                }
            }
        }
    }
}

// MARK: - Privacy policy sheet (preserved)

struct PrivacyPolicySheet: View {
    let info: AboutInfo

    /// 隐私政策弹窗宽度：640pt，仅用于隐私政策弹窗整体宽度；与高度 560pt 角色不同，不合并。
    private static let privacySheetWidth: CGFloat = 640

    /// 隐私政策弹窗高度：560pt，仅用于隐私政策弹窗整体高度；与宽度 640pt 角色不同，不合并。
    private static let privacySheetHeight: CGFloat = 560
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
        .jadePadding(.x6)
        .frame(width: Self.privacySheetWidth, height: Self.privacySheetHeight)
        // macOS 12 没有 presentationBackground，sheet 自带不透明底；
        // 半透明 cardFill 叠在其上表达「玻璃语言的内容面」。
        .background(JadeGlass.cardFill)
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

/// 所有设置页共享的可滚动内容列；内容在宽窗口中保持易读行宽。
struct SettingsScrollPage<Content: View>: View {
    @ViewBuilder let content: Content

    /// 设置页可滚动内容列最大宽度：760pt，仅用于内容在宽窗口中保持易读行宽；与设置窗口最小宽度 920pt 角色不同，不合并；泛型类型不支持 static 存储属性，故用计算属性，值不变。
    private static var contentMaxWidth: CGFloat { 760 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JadeSpace.x6.value) {
                content
            }
            .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .jadePadding(.x6)
        }
    }
}

/// 设置页首以大标题和说明建立层级，图标只作单色辅助提示。
struct SettingsHeader: View {
    let titleKey: String
    let subtitleKey: String
    let iconName: String
    var body: some View {
        // 顶部对齐：28pt 图标与标题行（title1，行高约 31pt）光学居中对齐。
        // 用默认的垂直居中会把它对到「标题 + 说明」两行块的正中间——
        // 看起来既不属于标题、也不属于说明，像是浮在两者之间。
        HStack(alignment: .top, spacing: JadeSpace.x3.value) {
            SettingsHeaderIcon(systemImage: iconName)
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(L10n.localized(titleKey))
                    .font(JadeFont.title1)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized(subtitleKey))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            Spacer()
        }
    }
}

/// 扁平的标题与单层内容组，靠留白与细边界分隔，而非叠加背景。
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
                    .font(JadeFont.headline)
                    .foregroundStyle(JadeColor.textPrimary)
            }
            JadeSettingsCard {
                content
            }
        }
    }
}

/// A labeled switch row (Jade tinted toggle), optional icon + subtitle.
struct JadeSwitchRow: View {

    /// 开关行图标宽度：20pt，仅用于开关行左侧图标列宽；与其它列宽角色不同，不合并。
    private static let switchIconWidth: CGFloat = 20

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
                        .frame(width: Self.switchIconWidth)
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
            .jadePadding(.vertical, .x1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(JadeColor.actionFill)
    }
}

/// App icon glyph: renders the bundle icon, falling back to a jade `feather` symbol.
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
                Image(systemName: "leaf")
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

private struct SettingsBrandHeader: View {
    var body: some View {
        HStack(spacing: JadeSpace.x2.value) {
            AppIconView(size: 24, radius: .sm)
            // 品牌字样与菜单栏、首启引导保持一致（「清羽 Qingyu」）；
            // 直接用 CFBundleDisplayName 只会得到「Qingyu」，同一产品出现两种写法。
            Text(L10n.localized("about.brandName"))
                .font(JadeFont.headline)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

private struct AboutBrandHeader: View {
    let about: AboutInfo

    var body: some View {
        HStack(spacing: JadeSpace.x3.value) {
            AppIconView(size: 52, radius: .lg)
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(L10n.localized("about.brandName"))
                    .font(JadeFont.title1)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized("about.version", about.version, about.buildNumber))
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    SettingsView()
}
