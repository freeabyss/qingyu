import SwiftUI
import KeyboardShortcuts

/// 单屏 Onboarding（PRD §9.4 P-06）。
///
/// 整屏 720×520，`JadeRadius.xl` + `JadeShadow.xl`，padding 32。全部 token 化，
/// 不硬编码颜色/尺寸/字号。辅助功能不在此触发 TCC（按需申请）。
struct OnboardingView: View {
    @StateObject var viewModel: OnboardingViewModel
    @State private var showSkipConfirmation = false

    private let privacyURL = URL(string: "https://github.com/freeabyss/qingyu/blob/main/docs/guides/privacy.md")

    /// 卡片标签图标列宽：24pt，仅用于引导页卡片标签的图标列，让多行标题对齐；只定宽，高度随字号而定，不并入 JadeSpace，那是间距档位，不是图标列宽。
    private static let cardLabelIconWidth: CGFloat = 24

    /// 区块顶部分隔线高度：1pt，仅用于引导页区块顶部的细分隔线；不并入 JadeSpace，那是间距档位，不是线条厚度。
    private static let sectionDividerHeight: CGFloat = 1

    /// 引导页窗口宽度：720pt，仅用于引导页整屏的最小与理想宽度；不并入 JadeSpace，那是间距档位，不是窗口尺寸。
    private static let windowWidth: CGFloat = 720

    /// 引导页窗口最小高度：520pt，仅用于引导页整屏的最小高度；不并入 JadeSpace，那是间距档位，不是窗口尺寸。
    private static let windowMinHeight: CGFloat = 520

    /// 引导页窗口理想高度：620pt，仅用于引导页整屏的理想高度；不并入 JadeSpace，那是间距档位，不是窗口尺寸。
    private static let windowIdealHeight: CGFloat = 620

    init(viewModel: OnboardingViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        // 布局（v1.2.1 Bug 2 修复，PRD §4.2 方案① / AC-06/07/10）：
        // header 与 footer 固定吸顶/吸底，中部可变内容用 ScrollView 包裹，
        // 保证任意字号 / 明暗模式下 footer（开始使用 / 跳过设置）恒定可见可点，
        // 不再被固定高度裁剪；窗口最小为 720×520，用户可按需要放大。
        VStack(spacing: JadeSpace.x6.value) {
            header
            ScrollView {
                VStack(spacing: JadeSpace.x6.value) {
                    configCards
                    // 1.0.0 FeatureGate：截图整体隐藏，屏幕录制（必选）段不渲染；
                    // 「开始使用」不再被权限阻塞（见 OnboardingViewModel.canStart）。
                    if FeatureGate.screenshotEnabled {
                        screenRecordingSection
                    }
                    accessibilitySection
                }
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .jadePadding(.x8)
        .frame(minWidth: Self.windowWidth, idealWidth: Self.windowWidth, maxWidth: .infinity,
               minHeight: Self.windowMinHeight, idealHeight: Self.windowIdealHeight, maxHeight: .infinity)
        .background(JadeColor.surface1)
        .jadeRadius(.xl)
        .jadeShadow(.xl, radius: .xl)
        .onAppear { viewModel.onAppear() }
        // 授权通常在系统设置完成；回到应用后立即更新状态，而不是要求用户重启或再次点按钮。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshScreenRecordingStatus() }
        }
        .jadeConfirmationDialog(
            LocalizedStringKey("onboarding.skip.confirm.title"),
            isPresented: $showSkipConfirmation,
            confirmTitle: LocalizedStringKey("onboarding.skip.confirm.action"),
            cancelTitle: LocalizedStringKey("onboarding.skip.confirm.cancel"),
            message: LocalizedStringKey("onboarding.skip.confirm.message")
        ) {
            Task { await viewModel.skipOnboarding() }
        }
    }

    /// 欢迎页 Logo 磁贴边长：56pt 正方形，仅用于头部 leaf 图标磁贴；不并入 JadeSpace（那是间距档位，不是磁贴尺寸）。
    private static let logoTileSize: CGFloat = 56

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: JadeSpace.x4.value) {
            Image(systemName: "leaf")
                .font(JadeFont.onboardingLogoIcon)
                .foregroundStyle(JadeColor.textPrimary)
                .frame(width: Self.logoTileSize, height: Self.logoTileSize)
                .background(JadeColor.settingsCard, in: JadeRadius.xl.shape)
                .jadeRadiusBorder(.xl)
                .jadeShadow(.sm, radius: .xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
                Text(L10n.localized("onboarding.welcome.title"))
                    .font(JadeFont.title1)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(L10n.localized("onboarding.welcome.subtitle"))
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, JadeSpace.x2.value)
    }

    // MARK: - 三配置卡片

    private var configCards: some View {
        VStack(spacing: 0) {
            configCard {
                HStack {
                    cardLabel(
                        icon: "command",
                        title: L10n.localized("onboarding.hotkey.title"),
                        subtitle: L10n.localized("onboarding.hotkey.description")
                    )
                    Spacer()
                    HotkeyRecorder(
                        for: .togglePanel,
                        isConflicting: .constant(viewModel.hotkeyValidation == .conflict),
                        conflictMessage: .constant(viewModel.hotkeyValidation == .conflict
                            ? L10n.localized("onboarding.hotkey.conflict") : nil)
                    )
                    .onChange(of: KeyboardShortcuts.getShortcut(for: .togglePanel)) { _ in
                        viewModel.validateHotkey()
                    }
                    .accessibilityIdentifier("onboarding.hotkeyRecorder")
                }
            }

            Divider().padding(.leading, JadeSpace.x4.value)
            configCard {
                Toggle(isOn: $viewModel.clipboardEnabled) {
                    cardLabel(
                        icon: "doc.on.clipboard",
                        title: L10n.localized("onboarding.clipboard.toggle"),
                        subtitle: L10n.localized("onboarding.clipboard.toggle.subtitle")
                    )
                }
                .toggleStyle(.switch)
                .tint(JadeColor.primary)
                .accessibilityIdentifier("onboarding.clipboardToggle")
            }

            Divider().padding(.leading, JadeSpace.x4.value)
            configCard {
                Toggle(isOn: $viewModel.launchAtLoginEnabled) {
                    cardLabel(
                        icon: "power",
                        title: L10n.localized("onboarding.launchAtLogin.toggle"),
                        subtitle: L10n.localized("onboarding.launchAtLogin.toggle.subtitle")
                    )
                }
                .toggleStyle(.switch)
                .tint(JadeColor.primary)
                .accessibilityIdentifier("onboarding.launchAtLoginToggle")
            }
        }
        .background(JadeColor.settingsCard, in: JadeRadius.lg.shape)
        .jadeRadiusBorder(.lg)
    }

    // MARK: - 屏幕录制段（必选）

    private var screenRecordingSection: some View {
        onboardingSection {
            Text(L10n.localized("onboarding.screenRecording.title"))
                .font(JadeFont.headline)
                .foregroundStyle(JadeColor.textPrimary)
            Text(L10n.localized("onboarding.screenRecording.explain"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // 操作按钮与说明分开成两块：早先把 ad-hoc 说明放进按钮所在的 HStack，
            // 它被挤在按钮右侧的窄列里折成四行小字，左边却大片留白。
            // 说明属于整段权限的补充信息，应横跨整行、位于按钮下方。
            HStack(spacing: JadeSpace.x3.value) {
                if viewModel.screenRecordingAuthorized {
                    Label(L10n.localized("onboarding.screenRecording.granted"), systemImage: "checkmark.circle.fill")
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.success)
                } else {
                    Button(L10n.localized("onboarding.screenRecording.grant")) {
                        viewModel.requestScreenRecording()
                    }
                    .buttonStyle(.jadePrimary)
                    .accessibilityIdentifier("onboarding.screenRecording.grant")

                    Button(L10n.localized("onboarding.screenRecording.skip")) {
                        viewModel.skipScreenshot()
                    }
                    .buttonStyle(.jadeGhost)
                    .accessibilityIdentifier("onboarding.screenRecording.skip")

                    if viewModel.screenshotSkipped {
                        Text(L10n.localized("onboarding.screenRecording.skipped"))
                            .font(JadeFont.caption)
                            .foregroundStyle(JadeColor.textTertiary)
                    }
                }
            }

            // ad-hoc 构建（本地编译）下 TCC 按代码哈希记录授权：每次重编
            // 都会失效，而系统设置里的旧条目仍显示为已授权。
            if !viewModel.screenRecordingAuthorized,
               let noteKey = PermissionGuidance.developmentSignatureNoteKey(
                for: PermissionService.appSignatureStatus()
               ) {
                Text(L10n.localized(noteKey))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 辅助功能段（按需，不触发 TCC）

    private var accessibilitySection: some View {
        onboardingSection {
            Text(L10n.localized("onboarding.accessibility.title"))
                .font(JadeFont.headline)
                .foregroundStyle(JadeColor.textPrimary)
            Text(L10n.localized("onboarding.accessibility.explain"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.localized("onboarding.accessibility.later")) {
                viewModel.dismissAccessibility()
            }
            .buttonStyle(.jadeGhost)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: JadeSpace.x2.value) {
            if let message = viewModel.completionErrorMessage {
                Text(message)
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.dangerText)
                    .multilineTextAlignment(.center)
            } else if !viewModel.canStart {
                // 主按钮被禁用时必须说明原因。
                // 首启时「开始使用」默认是灰的（屏幕录制既未授权、也没点「暂不开启」），
                // 界面上却只有一句沉默的灰按钮——用户不知道差什么，也不知道旁边两个按钮哪个能解开。
                // 这是解释「开始使用为什么是灰的」的唯一线索，属于阻断性说明，
                // 不该用最弱的一档字号。用 callout 让它与正文同级可读。
                Text(L10n.localized("onboarding.start.blockedHint"))
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                Button(L10n.localized("onboarding.skip")) {
                    showSkipConfirmation = true
                }
                .buttonStyle(.jadeGhost)
                .accessibilityIdentifier("onboarding.skipButton")

                if let privacyURL {
                    Link(L10n.localized("about.privacyPolicy"), destination: privacyURL)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                Spacer()

                Button(L10n.localized("onboarding.start")) {
                    Task { await viewModel.start() }
                }
                .buttonStyle(.jadePrimary)
                .disabled(!viewModel.canStart)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.startButton")

            }
        }
    }

    // MARK: - Building blocks

    private func configCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .jadePadding(.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 权限说明、当前状态和下一步操作统一放在一个连续的可扫描区块中。
    private func onboardingSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            content()
        }
        .jadePadding(.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(JadeColor.border).frame(height: Self.sectionDividerHeight)
        }
    }

    private func cardLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: icon)
                .font(JadeFont.onboardingCardIcon)
                .foregroundStyle(JadeColor.textSecondary)
                .frame(width: Self.cardLabelIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JadeSpace.x1.value) {
                Text(title)
                    .font(JadeFont.body)
                    .foregroundStyle(JadeColor.textPrimary)
                Text(subtitle)
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Onboarding · Light") {
    OnboardingView(
        viewModel: OnboardingViewModel(
            permissionService: PermissionService(),
            hotkeyService: HotkeyValidationService(),
            settingsService: SettingsService(persistence: .shared)
        )
    )
    .tint(JadeColor.primary)
    .preferredColorScheme(.light)
}

#Preview("Onboarding · Dark") {
    OnboardingView(
        viewModel: OnboardingViewModel(
            permissionService: PermissionService(),
            hotkeyService: HotkeyValidationService(),
            settingsService: SettingsService(persistence: .shared)
        )
    )
    .tint(JadeColor.primary)
    .preferredColorScheme(.dark)
}
