import Foundation
import os.log

/// Service that periodically cleans up expired clipboard items.
///
/// - Runs on app launch and then every hour
/// - Executes on a background task to avoid blocking the UI
/// - Pinned items are never automatically deleted
/// - Backed by the Core Data clipboard repository (`ClipboardRepository`); the
///   retention window is read from the `clipboard.retention` setting inside the
///   repository. The legacy GRDB `ContentRepository` path was removed in v1.2
///   (T-005).
final class DataCleanupService {
    private let logger = Logger.database
    private let repository: ClipboardRepositoryProtocol

    /// Timer for periodic cleanup (every hour).
    private var timer: Timer?

    /// Whether a cleanup is currently in progress.
    private var isCleaning = false

    init(repository: ClipboardRepositoryProtocol = ClipboardRepository(persistence: .shared)) {
        self.repository = repository
    }

    // MARK: - Public API

    /// Start the periodic cleanup schedule.
    /// Also runs an immediate cleanup on the current call.
    func start() {
        logger.info("DataCleanupService starting")

        // Run immediate cleanup on launch
        Task { [weak self] in
            await self?.performCleanup()
        }

        // Schedule hourly cleanup
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performCleanup()
            }
        }
    }

    /// Stop the periodic cleanup timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        logger.info("DataCleanupService stopped")
    }

    // MARK: - Internal

    /// Perform a full cleanup cycle: run retention-based expiry.
    func performCleanup() async {
        guard !isCleaning else {
            logger.debug("Cleanup already in progress, skipping")
            return
        }

        isCleaning = true
        defer { isCleaning = false }

        do {
            let deleted = try await repository.cleanupExpired(now: Date())
            if deleted > 0 {
                logger.info("Cleanup complete: removed \(deleted) expired items")
            } else {
                logger.debug("Cleanup complete: no items to remove")
            }
        } catch {
            logger.error("Cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
