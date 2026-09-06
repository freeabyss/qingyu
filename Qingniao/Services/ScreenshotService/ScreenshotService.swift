import Foundation
import ScreenCaptureKit
import CoreGraphics
import Cocoa
import os.log

// MARK: - Protocol

/// Protocol for screenshot operations.
protocol ScreenshotServiceProtocol {
    /// Capture a region selected by the user via an overlay.
    func captureRegion() async throws -> ScreenshotResult

    /// Capture the window under the mouse cursor.
    func captureWindow() async throws -> ScreenshotResult

    /// Capture the entire screen.
    func captureScreen() async throws -> ScreenshotResult

    /// Close the retained region selection overlay after its toolbar flow ends.
    /// The session guard prevents a delayed cleanup from closing a newer capture.
    @MainActor func finishRegionCapture(sessionID: UUID)
}

// MARK: - Types

/// Result of a screenshot capture.
struct ScreenshotResult {
    /// Task 005: stable per-capture id issued by the capture backend on success;
    /// Task 007 records navigate by this id.
    var id: UUID = UUID()
    let imageData: Data
    let width: Int
    let height: Int
    let captureDate: Date
    let sourceType: CaptureSource
    let regionSelection: RegionCaptureSelection?

    var selectionRect: NSRect? { regionSelection?.globalRect }

    /// Re-attaches the caller's region selection while keeping the
    /// backend-issued capture id.
    func overridingRegionSelection(_ selection: RegionCaptureSelection) -> ScreenshotResult {
        ScreenshotResult(
            id: id,
            imageData: imageData,
            width: width,
            height: height,
            captureDate: captureDate,
            sourceType: sourceType,
            regionSelection: selection
        )
    }
}

/// The source type of a screenshot capture.
enum CaptureSource: Equatable {
    case region
    case window
    case screen
}

/// Pure session matching used to keep delayed toolbar cleanup scoped to the
/// region capture that created it.
enum RegionCaptureSessionGuard {
    static func shouldFinish(activeSessionID: UUID?, requestedSessionID: UUID) -> Bool {
        activeSessionID == requestedSessionID
    }
}

// MARK: - CGImage Extension

extension CGImage {
    /// Convert CGImage to PNG data.
    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - ScreenshotService

/// Screenshot service for high-quality screen capture.
///
/// Uses ScreenCaptureKit (SCShareableContent) for window enumeration,
/// and CoreGraphics APIs for actual capture (compatible with macOS 13+).
///
/// Supports three capture modes:
/// - Region: User selects a rectangular area via a transparent overlay
/// - Window: Captures the window under the mouse cursor
/// - Screen: Captures the entire screen
/// ScreenshotService 的可变 overlay 状态仅在主队列访问（`DispatchQueue.main.async`
/// / `MainActor.run`），耗时捕获（CGDisplayCreateImage 等）在后台 Task 执行；
/// 因此以 `@unchecked Sendable` 显式声明这一既有的线程安全约定。
final class ScreenshotService: ScreenshotServiceProtocol, @unchecked Sendable {
    private let logger = Logger.screenshot
    /// Task 005: unified pixel-capture backend shared by all entry points.
    private let captureBackend: ScreenCaptureBackendProtocol
    private var activeRegionCaptureOverlay: ScreenshotOverlayController?
    private var activeRegionCaptureID: UUID?
    private var activeWindowCaptureOverlay: WindowCaptureOverlayController?

    init(captureBackend: ScreenCaptureBackendProtocol = ScreenCaptureBackend()) {
        self.captureBackend = captureBackend
    }

    /// Capture a region selected by the user.
    ///
    /// Shows a transparent overlay window covering the entire screen.
    /// The user drags to select a rectangle, then the selected region is captured.
    /// Pressing ESC cancels the capture.
    ///
    /// - Returns: The captured screenshot as PNG data
    /// - Throws: `SnapVaultError.screenshotFailed` if the user cancels or capture fails
    func captureRegion() async throws -> ScreenshotResult {
        logger.info("Starting region capture")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ScreenshotResult, Error>) in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SnapVaultError.screenshotFailed(reason: L10n.localized("error.serviceDeallocated")))
                    return
                }

                // A new region capture supersedes any unfinished selection session.
                self.activeRegionCaptureOverlay?.cancel()
                self.activeRegionCaptureOverlay = nil
                let captureID = UUID()
                self.activeRegionCaptureID = captureID

                let overlay = ScreenshotOverlayController(sessionID: captureID) { [weak self] selection in
                    guard let self else { return }

                    if let selection {
                        Task {
                            do {
                                let remainsActive = await MainActor.run {
                                    guard self.activeRegionCaptureID == captureID else { return false }
                                    self.activeRegionCaptureOverlay?.hideForCapture()
                                    return true
                                }
                                guard remainsActive else {
                                    throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
                                }
                                // Give WindowServer one tick to remove the overlay from the capture stack.
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                let activeAfterDelay = await MainActor.run {
                                    self.activeRegionCaptureID == captureID
                                }
                                guard activeAfterDelay else {
                                    throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
                                }
                                let result = try await self.captureRect(selection)
                                let shouldReturnResult = await MainActor.run {
                                    guard self.activeRegionCaptureID == captureID else { return false }
                                    self.activeRegionCaptureOverlay?.restoreAfterCapture()
                                    return true
                                }
                                guard shouldReturnResult else {
                                    throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
                                }
                                continuation.resume(returning: result)
                            } catch {
                                await MainActor.run {
                                    if self.activeRegionCaptureID == captureID {
                                        self.activeRegionCaptureOverlay?.finishCapture()
                                        self.activeRegionCaptureOverlay = nil
                                        self.activeRegionCaptureID = nil
                                    }
                                }
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        if self.activeRegionCaptureID == captureID {
                            self.activeRegionCaptureOverlay = nil
                            self.activeRegionCaptureID = nil
                        }
                        self.logger.info("Region capture cancelled by user")
                        continuation.resume(throwing: SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason))
                    }
                }

                self.activeRegionCaptureOverlay = overlay
                overlay.show()
                self.logger.debug("Screenshot overlay shown")
            }
        }
    }

    @MainActor
    func finishRegionCapture(sessionID: UUID) {
        guard RegionCaptureSessionGuard.shouldFinish(
            activeSessionID: activeRegionCaptureID,
            requestedSessionID: sessionID
        ) else { return }
        activeRegionCaptureOverlay?.finishCapture()
        activeRegionCaptureOverlay = nil
        activeRegionCaptureID = nil
    }

    /// Capture the window under the mouse cursor.
    ///
    /// Shows a confirmation overlay highlighting the target window.
    /// Click to confirm, press ESC to cancel.
    ///
    /// - Returns: The captured window screenshot as PNG data
    /// - Throws: `SnapVaultError.screenshotFailed` if no window is found, user cancels, or capture fails
    func captureWindow() async throws -> ScreenshotResult {
        logger.info("Starting window capture")

        let mouseLocation = NSEvent.mouseLocation
        logger.debug("Mouse location: \(mouseLocation.debugDescription)")

        // Get available content to enumerate on-screen windows
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard !content.windows.isEmpty else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.noWindows"))
        }

        // Find the window under the mouse cursor.
        guard let screen = NSScreen.main else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.noMainScreen"))
        }
        let screenHeight = screen.frame.height

        guard let targetWindow = content.windows.first(where: { window in
            let frame = window.frame
            let appKitFrame = CGRect(
                x: frame.origin.x,
                y: screenHeight - frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
            return appKitFrame.contains(mouseLocation)
        }) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.noWindowAtMouse"))
        }

        // Convert SCWindow frame to AppKit coordinates for the overlay
        let scFrame = targetWindow.frame
        let appKitFrame = CGRect(
            x: scFrame.origin.x,
            y: screenHeight - scFrame.origin.y - scFrame.height,
            width: scFrame.width,
            height: scFrame.height
        )

        let windowID = targetWindow.windowID
        logger.info("Found window: \(targetWindow.title ?? "untitled") (ID: \(windowID))")

        // Show confirmation overlay — user can click to confirm or ESC to cancel
        let confirmed = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                let overlay = WindowCaptureOverlayController(targetFrame: appKitFrame) { [weak self] confirmed in
                    self?.activeWindowCaptureOverlay = nil
                    continuation.resume(returning: confirmed)
                }
                self.activeWindowCaptureOverlay = overlay
                overlay.show()
                self.logger.debug("Window capture overlay shown")
            }
        }

        guard confirmed else {
            logger.info("Window capture cancelled by user")
            throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
        }

        // Task 005: pixel capture moved to the unified backend.
        let displayID = CaptureDisplayInfo.displayID(containing: appKitFrame) ?? CGMainDisplayID()
        let candidate = CaptureWindowCandidate(windowID: windowID, frame: appKitFrame, displayID: displayID)
        let result = try await captureBackend.capture(.window(candidate))

        logger.info("Window capture complete: \(result.width)x\(result.height)")
        return result
    }

    /// Capture the entire screen.
    ///
    /// - Returns: The captured full-screen screenshot as PNG data
    /// - Throws: `SnapVaultError.screenshotFailed` if capture fails
    func captureScreen() async throws -> ScreenshotResult {
        logger.info("Starting full screen capture")

        let mainDisplayID = CGMainDisplayID()
        let display = CaptureDisplay(
            id: mainDisplayID,
            frame: NSScreen.main?.frame ?? CGDisplayBounds(mainDisplayID),
            pixelSize: CaptureDisplayInfo.pixelSize(displayID: mainDisplayID)
        )
        return try await captureBackend.capture(.display(display))
    }

    // MARK: - Private

    /// Capture a specific rectangular region of the screen.
    ///
    /// Delegates to the unified backend: captures the display and crops to the
    /// region. The overlay's `RegionCaptureSelection` is re-attached so the
    /// delayed `finishRegionCapture(sessionID:)` guard keeps matching.
    ///
    /// - Parameter selection: The region to capture in AppKit coordinates (bottom-left origin)
    /// - Returns: The captured screenshot as PNG data
    private func captureRect(_ selection: RegionCaptureSelection) async throws -> ScreenshotResult {
        logger.info("Capturing rect: \(selection.globalRect.debugDescription) on display \(selection.displayID)")

        let display = CaptureDisplay(
            id: selection.displayID,
            frame: selection.screenFrame,
            pixelSize: CaptureDisplayInfo.pixelSize(displayID: selection.displayID)
        )
        let result = try await captureBackend.capture(.region(display: display, globalRect: selection.globalRect))
        return result.overridingRegionSelection(selection)
    }
}
