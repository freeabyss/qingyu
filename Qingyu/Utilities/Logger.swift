import Foundation
import os.log

/// Centralized logging infrastructure using Apple's unified logging system (OSLog).
///
/// Usage:
///   let logger = Logger.database
///   logger.info("Database ready")
///
/// View logs in Console.app by filtering on subsystem "com.freeabyss.qingyu".
extension Logger {
    /// The subsystem identifier shared by all Assistant loggers.
    private static let subsystem = "com.freeabyss.qingyu"

    // MARK: - Categories

    /// Database operations (GRDB queries, migrations, cleanup).
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Clipboard monitoring (polling, content detection, dedup).
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")

    /// OCR processing (Vision framework text recognition).
    static let ocr = Logger(subsystem: subsystem, category: "ocr")

    /// Search engine (FTS5 queries, Spotlight integration).
    static let search = Logger(subsystem: subsystem, category: "search")

    /// UI events (window management, user interactions).
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Update checks (opens Releases page; no embedded auto-updater).
    static let update = Logger(subsystem: subsystem, category: "update")

    /// App lifecycle (startup, shutdown, general app events).
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Screenshot operations (ScreenCaptureKit, overlay, capture).
    static let screenshot = Logger(subsystem: subsystem, category: "screenshot")
}
