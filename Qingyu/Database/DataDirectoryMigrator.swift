import Foundation
import os.log

/// Migrates the Application Support data directory from a historical brand name
/// (`Qingniao/` or `Assistant/`) to the current brand name (`Qingyu/`).
///
/// Strategy (see docs/architecture/db.md §8.4):
/// - If the new `Qingyu/` directory already exists → no-op (already migrated or
///   fresh install).
/// - Else try each legacy source (newest first). On the first hit, `moveItem`
///   (rename, not copy) the whole directory to `Qingyu/`, then rename the Core
///   Data store files from that source's store name to `Qingyu.sqlite(-shm/-wal)`.
/// - If the move fails (permissions / disk) → fallback: `copyItem` the legacy
///   directory to a timestamped `Qingyu-migration-backup-<ISO8601>/` sibling
///   and create a fresh empty `Qingyu/`, so the app can still launch. The
///   failure is surfaced so the caller can alert the user.
///
/// The Core Data lightweight migration (removing `ocrText`) is handled separately
/// by `PersistenceController` via `NSMigratePersistentStoresAutomaticallyOption` +
/// `NSInferMappingModelAutomaticallyOption`.
struct DataDirectoryMigrator {
    /// Outcome of a migration attempt, for logging / user-facing alerts.
    enum Outcome: Equatable {
        /// New directory already present; nothing to do.
        case alreadyMigrated
        /// No legacy directory found; fresh install.
        case freshInstall
        /// Legacy directory successfully moved/renamed to the new location.
        case migrated
        /// Move failed; legacy data was copied to `backupURL` and a fresh empty
        /// directory was created. The user should be informed.
        case fallbackBackup(backupURL: URL, underlying: String)
    }

    let applicationSupportDirectory: URL
    let legacySources: [AssistantFileSystem.LegacySource]
    let newDirectoryName: String
    let newStoreFileName: String
    private let fileManager: FileManager
    private let logger = Logger.database
    private let now: () -> Date

    init(
        applicationSupportDirectory: URL = AssistantFileSystem.applicationSupportDirectory,
        legacySources: [AssistantFileSystem.LegacySource] = AssistantFileSystem.legacySources,
        newDirectoryName: String = AssistantFileSystem.directoryName,
        newStoreFileName: String = AssistantFileSystem.storeFileName,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.legacySources = legacySources
        self.newDirectoryName = newDirectoryName
        self.newStoreFileName = newStoreFileName
        self.fileManager = fileManager
        self.now = now
    }

    private var newURL: URL {
        applicationSupportDirectory.appendingPathComponent(newDirectoryName, isDirectory: true)
    }

    private func legacyURL(for source: AssistantFileSystem.LegacySource) -> URL {
        applicationSupportDirectory.appendingPathComponent(source.directoryName, isDirectory: true)
    }

    /// Runs the migration if needed. Never throws: on any move failure it falls
    /// back to a copy-based backup + fresh empty directory so the app still boots.
    @discardableResult
    func migrateIfNeeded() -> Outcome {
        // New directory already exists → already migrated or fresh install path
        // that created it. Treat as done.
        if fileManager.fileExists(atPath: newURL.path) {
            logger.debug("Data directory migration: new directory already present, skipping")
            return .alreadyMigrated
        }

        // Prefer the most recent legacy brand directory that is still on disk.
        guard let source = legacySources.first(where: { fileManager.fileExists(atPath: legacyURL(for: $0).path) }) else {
            logger.info("Data directory migration: no legacy directory, fresh install")
            return .freshInstall
        }

        let sourceURL = legacyURL(for: source)

        // Attempt an atomic move (rename) of the whole directory.
        do {
            try fileManager.moveItem(at: sourceURL, to: newURL)
            renameStoreFiles(in: newURL, from: source.storeFileName)
            logger.info("Data directory migrated: \(source.directoryName, privacy: .public) -> \(newDirectoryName, privacy: .public)")
            return .migrated
        } catch {
            logger.error("Data directory move failed: \(error.localizedDescription, privacy: .public); falling back to backup + fresh directory")
            return fallback(from: sourceURL, after: error)
        }
    }

    /// Renames the Core Data store files inside `directory` from the legacy name
    /// to the new name (including -shm / -wal sidecars).
    private func renameStoreFiles(in directory: URL, from legacyStoreFileName: String) {
        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            let source = directory.appendingPathComponent(legacyStoreFileName + suffix, isDirectory: false)
            let destination = directory.appendingPathComponent(newStoreFileName + suffix, isDirectory: false)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: source, to: destination)
                logger.debug("Renamed store file \(source.lastPathComponent, privacy: .public) -> \(destination.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("Failed to rename store file \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Fallback when the move fails: copy the legacy directory to a timestamped
    /// backup and create a fresh empty new directory so the app can still launch.
    private func fallback(from sourceURL: URL, after moveError: Error) -> Outcome {
        let timestamp = ISO8601DateFormatter.filenameSafe.string(from: now())
        let backupURL = applicationSupportDirectory
            .appendingPathComponent("\(newDirectoryName)-migration-backup-\(timestamp)", isDirectory: true)

        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
            logger.info("Legacy data copied to backup: \(backupURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to back up legacy data during fallback: \(error.localizedDescription, privacy: .public)")
        }

        // Ensure a fresh empty new directory exists so Core Data can create a store.
        do {
            try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create fresh data directory during fallback: \(error.localizedDescription, privacy: .public)")
        }

        return .fallbackBackup(backupURL: backupURL, underlying: moveError.localizedDescription)
    }
}

private extension ISO8601DateFormatter {
    /// ISO8601 formatter producing a filename-safe timestamp (no colons).
    static let filenameSafe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        // `.withTime` without `.withColonSeparatorInTime` yields HHmmss (no colons),
        // safe for use in a directory name.
        return formatter
    }()
}
