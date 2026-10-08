import AppKit
import CoreData
import Foundation
import os.log

/// Error surfaced by data-management operations (T-003).
///
/// db.md §11.5 specifies "清空所有数据" failure should throw a `dataResetFailed`
/// case. A dedicated `QingyuError` umbrella type does not exist yet (the
/// `SnapVaultError` -> `QingyuError` rename is tracked by T-005/T-006), so this
/// task introduces a focused error type here.
enum DataManagementError: LocalizedError {
    case dataResetFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .dataResetFailed(let reason):
            return L10n.localized("data.reset.failed", reason)
        }
    }
}

extension Notification.Name {
    /// Posted after "清空所有数据" (reset all data) completes successfully, so the
    /// UI can prompt the user to restart the app (db.md §11.5).
    static let dataDidReset = Notification.Name("com.freeabyss.qingyu.dataDidReset")
}

/// Service backing the settings "Data" page (T-013 UI binds to this).
///
/// Provides three capabilities (docs/architecture/db.md §11.5, design §3.6):
/// - `resetAllData()`: fully wipes the Core Data store, file resource
///   directories, and the app's `UserDefaults` domain, then posts `.dataDidReset`.
/// - `openDataDirectory()`: reveals `~/Library/Application Support/Qingyu/` in
///   Finder (does not delete anything).
/// - `exportData()`: v1.3 placeholder — the UI keeps its button disabled and this
///   method is not expected to be called in v1.2.
final class DataManagementService {
    private let fileSystem: AssistantFileSystem
    private let persistence: PersistenceController
    private let userDefaults: UserDefaults
    private let bundleIdentifier: String
    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let logger = Logger.database

    init(
        persistence: PersistenceController = .shared,
        fileSystem: AssistantFileSystem? = nil,
        // Uses the app-specific UserDefaults suite (Bundle.main.bundleIdentifier ==
        // com.freeabyss.qingyu) rather than `.standard`, so a reset never clears
        // preferences belonging to other apps.
        userDefaults: UserDefaults? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.freeabyss.qingyu",
        notificationCenter: NotificationCenter = .default,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.persistence = persistence
        self.fileSystem = fileSystem ?? persistence.fileSystem
        self.bundleIdentifier = bundleIdentifier
        self.userDefaults = userDefaults ?? UserDefaults(suiteName: bundleIdentifier) ?? .standard
        self.notificationCenter = notificationCenter
        self.workspace = workspace
        self.fileManager = fileManager
    }

    // MARK: - Reset all data (db.md §11.5)

    /// Fully resets the app to a first-run state:
    /// - deletes the Core Data SQLite store (`Qingyu.sqlite` + `-shm`/`-wal`),
    /// - deletes the clipboard file resource directories (Images/Thumbnails/RichText),
    /// - removes the app's UserDefaults domain,
    /// then posts `.dataDidReset` so the UI can ask the user to restart.
    ///
    /// Throws `DataManagementError.dataResetFailed` if any critical step fails.
    func resetAllData() async throws {
        logger.info("resetAllData starting")
        do {
            try tearDownPersistentStores()
            try removeStoreFiles()
            try removeResourceDirectories()
            removeUserDefaultsDomain()
        } catch {
            logger.error("resetAllData failed: \(error.localizedDescription, privacy: .public)")
            throw DataManagementError.dataResetFailed(reason: error.localizedDescription)
        }

        logger.info("resetAllData completed; posting dataDidReset")
        notificationCenter.post(name: .dataDidReset, object: nil)
    }

    /// Removes the loaded Core Data persistent stores so the underlying files can
    /// be deleted without SQLite file-lock contention.
    private func tearDownPersistentStores() throws {
        let coordinator = persistence.container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            guard let storeURL = store.url, storeURL.isFileURL else { continue }
            try coordinator.remove(store)
        }
    }

    /// Deletes the Core Data SQLite store and its `-shm` / `-wal` sidecar files.
    private func removeStoreFiles() throws {
        let storeURL = fileSystem.storeURL
        for suffix in ["", "-shm", "-wal"] {
            let url = storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + suffix, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    /// Deletes the clipboard large-object directories (Images/Thumbnails/RichText).
    private func removeResourceDirectories() throws {
        for directory in [fileSystem.imagesDirectory, fileSystem.thumbnailsDirectory, fileSystem.richTextDirectory] {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    /// Clears the app-specific UserDefaults domain (never `.standard` globally).
    private func removeUserDefaultsDomain() {
        userDefaults.removePersistentDomain(forName: bundleIdentifier)
        userDefaults.synchronize()
    }

    // MARK: - Open data directory (db.md §11.5)

    /// Reveals `~/Library/Application Support/Qingyu/` in Finder. Ensures the
    /// directory exists first so Finder always has something to select.
    @discardableResult
    func openDataDirectory() -> Bool {
        let root = fileSystem.rootDirectory
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        logger.info("Opening data directory: \(root.path, privacy: .public)")
        return workspace.open(root)
    }

    // MARK: - Export (v1.3 placeholder)

    /// v1.3 feature (FR-DATA-EXPORT-BACKUP). Not implemented in v1.2 — the UI keeps
    /// the export button disabled with a "v1.3" tooltip and must not call this.
    func exportData() throws {
        assertionFailure("Data export is a v1.3 feature and is not implemented in v1.2")
        logger.error("exportData invoked but is not implemented (v1.3 placeholder)")
        print("DataManagementService.exportData is a v1.3 placeholder and is not implemented.")
    }
}
