import AppKit
import CoreGraphics
import Foundation
import os.log

// MARK: - Screen capture backend (Task 005)

/// 统一像素捕获后端：把 `CaptureTarget` 变成一张 PNG。只负责像素捕获与裁剪，
/// 不管理 overlay / 窗口等 UI 生命周期。
protocol ScreenCaptureBackendProtocol: Sendable {
    func capture(_ target: CaptureTarget) async throws -> ScreenshotResult
}

final class ScreenCaptureBackend: ScreenCaptureBackendProtocol, @unchecked Sendable {
    private let logger = Logger.screenshot

    func capture(_ target: CaptureTarget) async throws -> ScreenshotResult {
        // Task 007: stable per-capture id issued together with the image.
        let id = UUID()
        switch target {
        case .window(let candidate):
            return try await captureWindow(candidate, id: id)
        case .region(let display, let globalRect):
            return try await captureRegion(display: display, globalRect: globalRect, id: id)
        case .display(let display):
            return try await captureDisplay(display, id: id)
        }
    }

    // MARK: - Pure coordinate conversion (unit-testable)

    /// 将全局 AppKit 选区换算为显示器像素裁剪框：裁剪到显示器范围内
    /// （负坐标多屏场景）、按 Retina 比例缩放、对齐整数像素。
    /// 实际转换复用 `ScreenshotGeometry.cropRect`。
    static func cropRect(for display: CaptureDisplay, globalRect: CGRect, imageSize: CGSize) -> CGRect? {
        ScreenshotGeometry.cropRect(
            globalSelection: globalRect,
            screenFrame: display.frame,
            imageSize: imageSize
        )
    }

    // MARK: - Targets

    private func captureWindow(_ candidate: CaptureWindowCandidate, id: UUID) async throws -> ScreenshotResult {
        logger.info("Capturing window \(candidate.windowID)")
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            candidate.windowID,
            .bestResolution
        ) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.captureWindowFailed"))
        }
        return try makeResult(
            id: id,
            image: cgImage,
            sourceType: .window,
            regionSelection: nil
        )
    }

    private func captureRegion(display: CaptureDisplay, globalRect: CGRect, id: UUID) async throws -> ScreenshotResult {
        logger.info("Capturing region \(globalRect.debugDescription) on display \(display.id)")
        guard let fullImage = CGDisplayCreateImage(display.id) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.captureScreenFailed"))
        }

        let imageSize = CGSize(width: fullImage.width, height: fullImage.height)
        guard let cgRect = Self.cropRect(for: display, globalRect: globalRect, imageSize: imageSize) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.cropFailed"))
        }
        logger.debug("CG rect for cropping: \(cgRect.debugDescription)")

        guard let croppedImage = fullImage.cropping(to: cgRect) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.cropFailed"))
        }

        let selection = RegionCaptureSelection(
            sessionID: id,
            displayID: display.id,
            screenFrame: display.frame,
            globalRect: globalRect
        )
        return try makeResult(
            id: id,
            image: croppedImage,
            sourceType: .region,
            regionSelection: selection
        )
    }

    private func captureDisplay(_ display: CaptureDisplay, id: UUID) async throws -> ScreenshotResult {
        logger.info("Capturing full display \(display.id)")
        guard let cgImage = CGDisplayCreateImage(display.id) else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.captureScreenFailed"))
        }
        return try makeResult(
            id: id,
            image: cgImage,
            sourceType: .screen,
            regionSelection: nil
        )
    }

    // MARK: - Helpers

    private func makeResult(
        id: UUID,
        image: CGImage,
        sourceType: CaptureSource,
        regionSelection: RegionCaptureSelection?
    ) throws -> ScreenshotResult {
        guard let data = image.pngData() else {
            throw SnapVaultError.screenshotFailed(reason: L10n.localized("error.pngConversionFailed"))
        }
        logger.info("Capture complete: \(image.width)x\(image.height), \(data.count) bytes")
        return ScreenshotResult(
            id: id,
            imageData: data,
            width: image.width,
            height: image.height,
            captureDate: Date(),
            sourceType: sourceType,
            regionSelection: regionSelection
        )
    }
}
