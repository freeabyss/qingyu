import AppKit
import os.log

/// Thin wrapper around the screenshot capture + preview flow (design §2.5).
///
/// The single public entry `startCapture()` opens the unified multi-display
/// session (Task 006): one overlay window per screen, window highlight
/// following the pointer, click to capture the highlighted target (window or
/// current display), drag to select a region, `⌘A` full display, Esc cancels.
/// PRD「截图与贴图」规则 1：截图只提供一个入口和一个“截图”命令。
@MainActor
final class ScreenshotWindowController {
    private let logger = Logger.screenshot
    /// 截图提示音播放器（持有音效实例，避免播放中被释放）。
    private let soundPlayer = CaptureSoundPlayer()
    /// 防重入：会话进行中忽略重复触发（避免叠出两套全屏叠层）。
    private var isCapturing = false
    private unowned let container: AppContainer

    /// Task 011：放大镜配置。由 `AppContainer.syncRuntimeSettings()` 从设置同步；
    /// 默认值与 `MagnifierConfiguration.default` 一致，未改设置时行为不变。
    var magnifierConfiguration: MagnifierConfiguration = .default
    /// 截图后行为策略（保存后同时复制 / 截图完成播放提示音）。默认全关。
    var postCapturePolicy: ScreenshotPostCapturePolicy = .default {
        didSet { toolbar.postCapturePolicy = postCapturePolicy }
    }
    /// Task 014/04：取色输出格式（标注窗口内 `C` / `⇧C` 使用）。
    var colorValueOptions: ColorValueOptions = .default {
        didSet { toolbar.colorValueOptions = colorValueOptions }
    }
    /// Task 014/05：预览阶段可配置手势（Enter / 双击 / 中键 / 右键）。
    var gestureBindings: ScreenshotGestureBindings = .default {
        didSet { toolbar.gestureBindings = gestureBindings }
    }

    /// Task 012：控件级探测与选区吸附配置，同样由 `syncRuntimeSettings()` 同步。
    /// 默认关闭吸附（阈值 0）且控件探测需显式开启，避免改变既有手感。
    var elementDetectionOptions: ElementProbeOptions = ElementProbeOptions(
        isElementProbingEnabled: false,
        ignoredBundleIDs: [],
        timeout: ElementProbeOptions.default.timeout
    )
    var snapThreshold: CGFloat = 0

    /// Created lazily so the toolbar controller is only built on first capture.
    /// Task 008: the pin terminal action converts the capture into a pin window.
    private lazy var toolbar = ScreenshotToolbarController(pinHandler: { [weak self] result in
        guard let self else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.serviceDeallocated"))
        }
        let item = self.container.pinWindowController.present(result)
        // 终局由 CaptureCompletionCoordinator 统一处理：成功仅结束会话，不保留历史。
        return item.id
    })

    init(container: AppContainer) {
        self.container = container
    }

    /// 唯一公开入口：进入统一截图会话（模式由指针位置与鼠标操作自动判定）。
    ///
    /// 1.0.0 FeatureGate：截图入口整体隐藏，正常不应有调用方可达；
    /// 此守卫为防御性兜底（记录日志后直接返回）。
    func startCapture() {
        guard FeatureGate.screenshotEnabled else {
            logger.info("FeatureGate: screenshot disabled, startCapture ignored")
            return
        }
        // 防重入：会话进行中再次触发入口时忽略，避免叠出两套全屏叠层。
        guard !isCapturing else {
            logger.info("Screenshot ignored: a capture session is already active")
            return
        }
        isCapturing = true
        logger.info("Screenshot capture triggered")
        // 未授权：先走一次系统同意流程，拿到授权就继续本次截图，拿不到再展示引导 ——
        // 不直接放弃。macOS 15 起 `CGRequestScreenCaptureAccess()` 已不弹窗、也不把本 App
        // 写进 TCC 列表，必须**真的抓一次屏**才会弹同意窗，见 `ScreenRecordingConsentFlow`。
        guard container.permissionService.status(for: .screenRecording).isAuthorized else {
            Task { @MainActor in
                let granted = await container.permissionService.requestScreenRecordingAccess()
                isCapturing = false
                if granted {
                    logger.info("Screen recording granted during the consent flow; retrying capture")
                    startCapture()
                } else {
                    presentScreenRecordingGuidance()
                }
            }
            return
        }

        #if DEBUG
        // TC-UI-013：跳过真实屏幕捕获（不弹全屏 overlay、不依赖屏幕录制权限），
        // 仅发通知标记"截图入口可达"，供 UI 测试断言。无 flag 时行为不变。
        if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.skipScreenshotCapture) {
            logger.info("UITest: skipping capture, posting notification")
            NotificationCenter.default.post(name: .uitestScreenshotTriggered, object: nil)
            isCapturing = false
            return
        }
        #endif

        // Hide the command bar so it doesn't appear in the screenshot.
        let wasCommandBarVisible = container.commandBarController.isVisible
        if wasCommandBarVisible {
            container.commandBarController.hide()
        }

        #if DEBUG
        let forcedDisplayCount = Self.forcedDisplayCountForUITest()
        #else
        let forcedDisplayCount: Int? = nil
        #endif

        let session = CaptureSessionController(
            displayProvider: NSScreenDisplayProvider(forcedDisplayCount: forcedDisplayCount),
            windowProvider: WindowCandidateProvider(),
            overlayFactory: ConcreteCaptureOverlayWindowFactory(
                magnifierConfiguration: magnifierConfiguration
            ),
            // 控件级探测只在开启时构造真实实现；关闭时不触碰辅助功能接口。
            elementProvider: elementDetectionOptions.isElementProbingEnabled
                ? AXElementCandidateProvider()
                : DisabledElementCandidateProvider()
        )
        session.elementProbeOptions = elementDetectionOptions
        session.snapThreshold = snapThreshold
        // Task 015：会话期只读预设；保存走仓库（满额返回 false → 叠层给内联提示）。
        session.presets = container.capturePresetStore.catalog.ordered
        session.onSavePreset = { [weak container] preset in
            guard let container else { return false }
            return await container.capturePresetStore.add(preset)
        }
        // 设置页可能刚改过预设：会话开始时重新装载一次（同一持久化键，读写一致）。
        // 先放入缓存快照，异步装载完成后覆盖，保证清单始终有可用内容。
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            await self.container.capturePresetStore.reload()
            session.presets = self.container.capturePresetStore.catalog.ordered
        }

        session.onLocked = { [weak self, weak session] target in
            guard let self, let session else { return }
            Task { @MainActor in
                do {
                    let result = try await self.performCapture(
                        target,
                        session: session,
                        restoreCommandBar: wasCommandBarVisible
                    )
                    self.showPreview(for: result)
                    // 截图会话到「预览」即告结束（预览阶段不占用会话状态）。
                    self.logger.info("Capture completed, preview shown")
                } catch {
                    // 失败提示与命令条恢复已由 `performCapture` 统一处理。
                }
            }
        }

        // 区域选区落定（拖拽松开 / 方向键微调 / 套用预设）后**立即**展示工具条：
        // 此时尚未捕获，点动作或按 Enter 时才真正抓屏（懒捕获）。
        session.onRegionAdjustable = { [weak self, weak session] display, rect in
            guard let self, let session else { return }
            self.toolbar.showRegionDraft(
                globalRect: rect,
                screenFrame: display.frame,
                capture: { [weak self, weak session] in
                    guard let self, let session else {
                        throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.serviceDeallocated"))
                    }
                    return try await self.performCapture(
                        .region(display: display, globalRect: rect),
                        session: session,
                        restoreCommandBar: wasCommandBarVisible
                    )
                },
                onDismiss: { [weak session] in
                    // 用户放弃工具条（✕）：结束会话。会话若已因捕获结束，
                    // `cancel()` 自身会早退，不会重复广播取消。
                    session?.cancel()
                }
            )
        }
        session.onRegionAdjustableEnded = { [weak self] in
            self?.toolbar.dismissRegionDraft()
        }

        session.onCancel = { [weak self] in
            self?.isCapturing = false
            self?.logger.info("Capture cancelled")
            if wasCommandBarVisible {
                self?.container.commandBarController.show()
            }
            // 取消截图时同步关闭已打开的预览/工具条（复用旧取消广播语义）。
            NotificationCenter.default.post(name: .screenshotOverlayDidCancel, object: nil)
        }

        session.start()
        // 让叠层窗口立即成为活动 key 窗口：鼠标首击直接进入拖拽，Esc 立即可用。
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 执行一次捕获并收尾会话：隐藏叠层 → 让 WindowServer 走一帧 → 抓屏 → `finish()`。
    ///
    /// 窗口/整屏单击（`onLocked`）与区域懒捕获（工具条动作 / `Enter`）共用这一条路径，
    /// 保证「隐藏叠层再抓屏」「失败也要结束会话」这两条规则只有一处实现。
    private func performCapture(
        _ target: CaptureTarget,
        session: CaptureSessionController,
        restoreCommandBar: Bool
    ) async throws -> ScreenshotResult {
        // 叠层必须先隐藏，否则会出现在位图里；再给 WindowServer 一帧时间刷新。
        session.hideForCapture()
        do {
            try? await Task.sleep(nanoseconds: 80_000_000)
            let result = try await container.screenshotService.captureTarget(target)
            // 截图成功 → 可选提示音（默认关，与接通前行为一致）。
            soundPlayer.playIfNeeded(postCapturePolicy.playsSoundOnCapture)
            session.finish()
            isCapturing = false
            return result
        } catch {
            session.finish()
            isCapturing = false
            handleCaptureError(error, restoreCommandBar: restoreCommandBar)
            throw error
        }
    }

    private func showPreview(for result: ScreenshotResult) {
        if result.sourceType == .region, let selection = result.regionSelection {
            // 统一会话的叠层已随 session.finish() 关闭，无额外清理；
            // onDismiss 闭包保留以维持工具条的“来自区域截图”呈现语义。
            toolbar.showRegion(result: result, selection: selection) { }
        } else {
            toolbar.show(result: result)
        }
    }

    private func handleCaptureError(_ error: Error, restoreCommandBar: Bool) {
        if case SnapVaultError.screenshotFailed(let reason) = error, reason == SnapVaultError.userCancelledReason {
            logger.debug("Capture cancelled")
        } else {
            logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
        if restoreCommandBar {
            container.commandBarController.show()
        }
    }

    #if DEBUG
    /// `--uitest-screenshot-displays N`：UI 测试合成 N 个显示器拓扑。
    private static func forcedDisplayCountForUITest() -> Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: UITestLaunchArg.screenshotDisplays),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1]), count > 0 else {
            return nil
        }
        return count
    }
    #endif

    /// 屏幕录制授权未到位时的引导（系统同意流程已跑过，仍未拿到授权）。
    ///
    /// 文案必须点明「列表里可能还没有清羽，请用 + 手动添加」：macOS 15 起系统不再为屏幕
    /// 录制弹授权窗（见 `ScreenRecordingConsentFlow`），用户按老经验去列表里找是找不到的。
    private func presentScreenRecordingGuidance() {
        let permissionService = container.permissionService

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.localized("screenshot.permission.title")
        // ad-hoc 构建（本地编译的默认结果）下，TCC 按代码哈希记录授权：
        // 每次重新编译都会被当成另一个 App，旧授权立即失效，而系统设置里那条
        // 旧条目仍显示为已授权。必须把这一点讲清楚，否则用户只会反复授权却无效。
        var message = L10n.localized("screenshot.permission.message")
        if let noteKey = PermissionGuidance.developmentSignatureNoteKey(
            for: PermissionService.appSignatureStatus()
        ) {
            message += "\n\n" + L10n.localized(noteKey)
        }
        // 手动添加时要在文件选择器里定位到本 App，路径直接给出（不本地化）。
        message += "\n\n" + Bundle.main.bundleURL.path
        alert.informativeText = message
        for action in ScreenRecordingRecovery.actions {
            alert.addButton(withTitle: L10n.localized(action.localizationKey))
        }
        // 取消按钮响应 Esc。
        alert.buttons.last?.keyEquivalent = "\u{1B}"

        let response = alert.runModal()
        let index: Int
        switch response {
        case .alertFirstButtonReturn: index = 0
        case .alertSecondButtonReturn: index = 1
        default: index = ScreenRecordingRecovery.actions.count - 1
        }

        switch ScreenRecordingRecovery.actions[index] {
        case .openSystemSettings:
            permissionService.openSystemSettings(for: .screenRecording)
        case .relaunch:
            PermissionService.relaunch()
        case .cancel:
            break
        }
    }
}
