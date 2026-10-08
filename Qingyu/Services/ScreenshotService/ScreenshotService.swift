import Foundation
import CoreGraphics
import Cocoa
import os.log

// MARK: - Protocol

/// Protocol for screenshot operations.
protocol ScreenshotServiceProtocol {
    /// Unified entry (Task 005/006) — capture a `CaptureTarget` resolved by the
    /// capture session state machine through the shared pixel backend.
    /// PRD「截图与贴图」规则 1：区域、窗口和全屏不是三个独立入口。
    func captureTarget(_ target: CaptureTarget) async throws -> ScreenshotResult
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
}

/// The source type of a screenshot capture.
enum CaptureSource: Equatable {
    case region
    case window
    case screen
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
/// CoreGraphics APIs for actual capture (compatible with macOS 13+); window
/// enumeration lives in `WindowCandidateProvider`. All captures flow through
/// the unified `ScreenCaptureBackend`: the `CaptureSessionController` resolves
/// a `CaptureTarget` (window / region / display) and this service forwards it
/// for pixel capture.
final class ScreenshotService: ScreenshotServiceProtocol, @unchecked Sendable {
    private let logger = Logger.screenshot
    /// Task 005: unified pixel-capture backend shared by all entry points.
    private let captureBackend: ScreenCaptureBackendProtocol

    init(captureBackend: ScreenCaptureBackendProtocol = ScreenCaptureBackend()) {
        self.captureBackend = captureBackend
    }

    /// Task 005/006: unified capture entry used by the capture session.
    func captureTarget(_ target: CaptureTarget) async throws -> ScreenshotResult {
        try await captureBackend.capture(target)
    }
}
