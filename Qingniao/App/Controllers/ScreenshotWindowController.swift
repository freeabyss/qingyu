import AppKit
import os.log

/// Thin wrapper around the screenshot capture + preview flow (design §2.5).
///
/// Region and window captures enter the unified multi-display session
/// (Task 006): one overlay window per screen, window highlight following the
/// pointer, click to capture a window, drag to select a region, `⌘A` full
/// display, Esc cancels. Full-screen capture stays a direct backend call.
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

    func captureRegion() {
        startUnifiedCaptureSession(kind: "region")
    }

    func captureWindow() {
        startUnifiedCaptureSession(kind: "window")
    }

    func captureFullScreen() {
        performCapture(kind: "full screen") { try await self.container.screenshotService.captureScreen() }
    }

    // MARK: - Unified capture session (Task 006)

    private func startUnifiedCaptureSession(kind: String) {
        logger.info("\(kind, privacy: .public) capture triggered")
        guard ensureScreenRecordingPermission() else { return }

        #if DEBUG
        // TC-UI-013：跳过真实屏幕捕获（不弹全屏 overlay、不依赖屏幕录制权限），
        // 仅发通知标记"截图入口可达"，供 UI 测试断言。无 flag 时行为不变。
        if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.skipScreenshotCapture) {
            logger.info("UITest: skipping \(kind, privacy: .public) capture, posting notification")
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
                    self.logger.info("\(kind, privacy: .public) capture completed, preview shown")
                } catch {
                    session.finish()
                    self.handleCaptureError(error, kind: kind, restoreCommandBar: wasCommandBarVisible)
                }
            }
        }

        session.onCancel = { [weak self] in
            self?.logger.info("\(kind, privacy: .public) capture cancelled")
            if wasCommandBarVisible {
                self?.container.commandBarController.show()
            }
        }

        session.start()
    }

    private func showPreview(for result: ScreenshotResult) {
        if result.sourceType == .region, let selection = result.regionSelection {
            toolbar.showRegion(result: result, selection: selection) { [weak self] in
                self?.container.screenshotService.finishRegionCapture(sessionID: selection.sessionID)
            }
        } else {
            toolbar.show(result: result)
        }
    }

    private func handleCaptureError(_ error: Error, kind: String, restoreCommandBar: Bool) {
        if case SnapVaultError.screenshotFailed(let reason) = error, reason == SnapVaultError.userCancelledReason {
            logger.debug("\(kind, privacy: .public) capture cancelled")
        } else {
            logger.error("\(kind, privacy: .public) capture failed: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Legacy direct capture flow

    private func performCapture(kind: String, _ capture: @escaping () async throws -> ScreenshotResult) {
        logger.info("\(kind, privacy: .public) capture triggered")
        guard ensureScreenRecordingPermission() else { return }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.skipScreenshotCapture) {
            logger.info("UITest: skipping \(kind, privacy: .public) capture, posting notification")
            NotificationCenter.default.post(name: .uitestScreenshotTriggered, object: nil)
            return
        }
        #endif

        // Hide the command bar so it doesn't appear in the screenshot.
        let wasCommandBarVisible = container.commandBarController.isVisible
        if wasCommandBarVisible {
            container.commandBarController.hide()
        }

        Task {
            var shouldRestoreCommandBar = wasCommandBarVisible
            do {
                let result = try await capture()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if result.sourceType == .region, let selection = result.regionSelection {
                        self.toolbar.showRegion(result: result, selection: selection) { [weak self] in
                            self?.container.screenshotService.finishRegionCapture(sessionID: selection.sessionID)
                        }
                    } else {
                        self.toolbar.show(result: result)
                    }
                }
                // Keep the command bar hidden while the preview is active.
                shouldRestoreCommandBar = false
                logger.info("\(kind, privacy: .public) capture completed, preview shown")
            } catch {
                if case SnapVaultError.screenshotFailed(let reason) = error, reason == SnapVaultError.userCancelledReason {
                    logger.debug("\(kind, privacy: .public) capture cancelled")
                } else {
                    logger.error("\(kind, privacy: .public) capture failed: \(error.localizedDescription, privacy: .public)")
                    _ = await MainActor.run {
                        NSAlert(error: error).runModal()
                    }
                }
            }

            if shouldRestoreCommandBar {
                DispatchQueue.main.async { [weak self] in
                    self?.container.commandBarController.show()
                }
            }
        }
    }

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
