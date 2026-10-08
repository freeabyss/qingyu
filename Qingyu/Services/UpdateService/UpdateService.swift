import Foundation
import os.log

/// Protocol for update service operations.
protocol UpdateServiceProtocol {
    /// Check for updates and return update info if available.
    func checkForUpdates() async throws -> UpdateInfo?

    /// Trigger a user-facing MVP update check.
    func checkNow()
}

/// Describes an available update.
struct UpdateInfo {
    let version: String
    let releaseNotes: String
    let downloadURL: URL
    let isCritical: Bool
}

/// Update service for the MVP release flow.
///
/// Responsibilities:
/// - Exposes `checkNow()` for the MVP user-facing update action, which opens the
///   project's GitHub Releases page manually.
///
/// MVP update policy:
/// - User-facing update checks open the project download page / GitHub Releases.
/// - The MVP does not auto-download, auto-install, or restart to update.
/// - There is no embedded auto-update framework (removed in v1.2).
final class UpdateService: NSObject, UpdateServiceProtocol {
    private let logger = Logger.update
    private let updateCheckService: UpdateCheckServiceProtocol

    /// Retained for compatibility with existing tests/config: the app never starts
    /// a background auto-updater. Manual "check for updates" simply opens Releases.
    static let startsUpdaterAutomatically: Bool = false

    init(updateCheckService: UpdateCheckServiceProtocol = WebUpdateCheckService()) {
        self.updateCheckService = updateCheckService
        super.init()
    }

    /// Whether the user can initiate a manual check right now. Always available in
    /// the MVP because "check" is just a link-out to Releases.
    @objc dynamic var canCheckForUpdates: Bool = true

    // MARK: - Setup

    /// No-op retained so callers (AppDelegate) don't need to change. There is no
    /// background updater to initialize in the MVP.
    func setup() {
        logger.info("UpdateService ready (manual releases-page check; no auto-updater)")
    }

    // MARK: - UpdateServiceProtocol

    func checkForUpdates() async throws -> UpdateInfo? {
        // MVP has no in-app update feed; the user-facing action opens Releases.
        checkNow()
        return nil
    }

    func checkNow() {
        logger.info("Manual update check requested; opening releases page for MVP")
        updateCheckService.openDownloadPage()
    }
}
