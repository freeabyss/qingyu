import SwiftUI
import KeyboardShortcuts

/// 单屏 Onboarding（PRD §9.4 P-06）。
///
/// 整屏 720×520，`JadeRadius.xl` + `JadeShadow.xl`，padding 32。全部 token 化，
/// 不硬编码颜色/尺寸/字号。辅助功能不在此触发 TCC（按需申请）。
struct OnboardingView: View {
    @StateObject var viewModel: OnboardingViewModel
    @State private var showSkipConfirmation = false

    private let privacyURL = URL(string: "https://github.com/freeabyss/assistant/blob/main/PRIVACY.md")

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
        .frame(minWidth: 720, idealWidth: 720, maxWidth: .infinity,
               minHeight: 520, idealHeight: 620, maxHeight: .infinity)
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: JadeSpace.x2.value) {
            Image(systemName: "bird")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(JadeColor.primary)
                .accessibilityHidden(true)
            Text(L10n.localized("onboarding.welcome.title"))
                .font(JadeFont.display)
                .foregroundStyle(JadeColor.textPrimary)
            Text(L10n.localized("onboarding.welcome.subtitle"))
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 三配置卡片

    private var configCards: some View {
        VStack(spacing: JadeSpace.x3.value) {
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
    }

    // MARK: - 屏幕录制段（必选）

    private var screenRecordingSection: some View {
        onboardingSection {
            Text(L10n.localized("onboarding.screenRecording.title"))
                .font(JadeFont.title3)
                .foregroundStyle(JadeColor.textPrimary)
            Text(L10n.localized("onboarding.screenRecording.explain"))
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    // MARK: - 辅助功能段（按需，不触发 TCC）

    private var accessibilitySection: some View {
        onboardingSection {
            Text(L10n.localized("onboarding.accessibility.title"))
                .font(JadeFont.title3)
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
                    .foregroundStyle(JadeColor.danger)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button(L10n.localized("onboarding.skip")) {
                    showSkipConfirmation = true
                }
                .buttonStyle(.jadeGhost)
                .accessibilityIdentifier("onboarding.skipButton")

                Spacer()

                Button(L10n.localized("onboarding.start")) {
                    Task { await viewModel.start() }
                }
                .buttonStyle(.jadePrimary)
                .disabled(!viewModel.canStart)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.startButton")

                Spacer()

                if let privacyURL {
                    Link(L10n.localized("about.privacyPolicy"), destination: privacyURL)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.primary)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func configCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .jadePadding(.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JadeColor.surface2)
            .jadeRadius(.md)
            .jadeRadiusBorder(.md)
    }

    /// 权限说明、当前状态和下一步操作统一放在一个连续的可扫描区块中。
    private func onboardingSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JadeSpace.x2.value) {
            content()
        }
        .jadePadding(.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JadeColor.surface2)
        .jadeRadius(.lg)
        .jadeRadiusBorder(.lg)
    }

    private func cardLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(JadeColor.primary)
                .frame(width: 24)
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
