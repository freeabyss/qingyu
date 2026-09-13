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
    private unowned let container: AppContainer

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
        logger.info("Screenshot capture triggered")
        guard ensureScreenRecordingPermission() else { return }

        #if DEBUG
        // TC-UI-013：跳过真实屏幕捕获（不弹全屏 overlay、不依赖屏幕录制权限），
        // 仅发通知标记"截图入口可达"，供 UI 测试断言。无 flag 时行为不变。
        if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.skipScreenshotCapture) {
            logger.info("UITest: skipping capture, posting notification")
            NotificationCenter.default.post(name: .uitestScreenshotTriggered, object: nil)
            return
        }
        #endif

        // Hide the command bar so it doesn't appear in the screenshot.
        let wasCommandBarVisible = container.commandBarController.isVisible
        if wasCommandBarVisible {
            container.commandBarController.hide()
        }

        let session = CaptureSessionController(
            displayProvider: NSScreenDisplayProvider(forcedDisplayCount: Self.forcedDisplayCountForUITest()),
            windowProvider: WindowCandidateProvider(),
            overlayFactory: ConcreteCaptureOverlayWindowFactory()
        )

        session.onLocked = { [weak self, weak session] target in
            guard let self, let session else { return }
            // Hide every overlay so it does not appear in the captured bitmap,
            // then give WindowServer one tick before reading pixels.
            session.hideForCapture()
            Task { @MainActor in
                do {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    let result = try await self.container.screenshotService.captureTarget(target)
                    self.showPreview(for: result)
                    session.finish()
                    self.logger.info("Capture completed, preview shown")
                } catch {
                    session.finish()
                    self.handleCaptureError(error, restoreCommandBar: wasCommandBarVisible)
                }
            }
        }

        session.onCancel = { [weak self] in
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

    private func ensureScreenRecordingPermission() -> Bool {
        let permissionService = container.permissionService
        guard permissionService.status(for: .screenRecording).isAuthorized else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.localized("screenshot.permission.title")
            alert.informativeText = L10n.localized("screenshot.permission.message")
            alert.addButton(withTitle: L10n.localized("screenshot.permission.openSettings"))
            alert.addButton(withTitle: L10n.localized("screenshot.permission.cancel"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                _ = permissionService.requestScreenRecordingPrompt()
                permissionService.openSystemSettings(for: .screenRecording)
            }
            return false
        }
        return true
    }
}
