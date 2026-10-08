import Foundation
import GRDB
import os.log

/// Manages the GRDB database connection and schema migrations.
final class DatabaseManager {
    static let shared = DatabaseManager()

    private let logger = Logger.database

    /// The shared GRDB database queue. All database access goes through this.
    private(set) var dbQueue: DatabaseQueue?

    /// Whether the database has been successfully set up.
    private(set) var isReady = false

    private init() {}

    // MARK: - Setup

    /// Initialize the database: create the file, register migrations, and run them.
    func setup() throws {
        let dbURL = Self.databaseURL()
        logger.info("Database path: \(dbURL.path, privacy: .public)")

        // Ensure parent directory exists
        let parentDir = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Open or create the database
        let queue = try DatabaseQueue(path: dbURL.path)
        self.dbQueue = queue

        // Register and run migrations
        let migrator = Self.migrator()
        try migrator.migrate(queue)

        isReady = true
        logger.info("Database setup complete")
    }

    // MARK: - Database Location

    /// Returns the URL for the SQLite database file.
    /// Location: ~/Library/Application Support/Qingyu/assistant.db
    ///
    /// Legacy GRDB stack (v1.2 technical debt, see docs/architecture/db.md §14).
    /// The directory moved from `Assistant/` to `Qingyu/` in v1.2 alongside the
    /// Core Data store; the db file name stays `assistant.db` (no rename needed —
    /// GRDB is read-compatible legacy and not renamed).
    static func databaseURL() -> URL {
        #if DEBUG
        if let override = _debugDatabaseURL {
            return override
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(AssistantFileSystem.directoryName).appendingPathComponent("assistant.db")
    }

    #if DEBUG
    /// DEBUG-only override for UITest data isolation (`--uitest-data-dir`).
    /// Must be set before `setup()` is called.
    private static var _debugDatabaseURL: URL?

    /// Redirect the GRDB database to a custom path for `--uitest-data-dir` (DEBUG only).
    static func setDebugDatabaseURL(_ url: URL) {
        _debugDatabaseURL = url
    }
    #endif

    // MARK: - Migrations

    /// Registers all database migrations.
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // clipboard_items core table
            try db.create(table: "clipboard_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content_type", .text).notNull().indexed()
                t.column("text_content", .text)
                t.column("rtf_content", .text)
                t.column("image_data", .blob)
                t.column("file_path", .text)
                t.column("ocr_text", .text)
                t.column("content_hash", .text).notNull().indexed()
                t.column("is_pinned", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Indexes for clipboard_items
            try db.create(index: "idx_clipboard_content_hash", on: "clipboard_items", columns: ["content_hash"])
            try db.create(index: "idx_clipboard_created_at", on: "clipboard_items", columns: ["created_at"])
            try db.create(index: "idx_clipboard_content_type", on: "clipboard_items", columns: ["content_type"])
            try db.create(index: "idx_clipboard_is_pinned", on: "clipboard_items", columns: ["is_pinned"])

            // FTS5 virtual table for full-text search
            try db.create(virtualTable: "clipboard_items_fts", using: FTS5()) { t in
                t.column("text_content")
                t.column("ocr_text")
                t.content = "clipboard_items"
                t.contentRowID = "id"
                t.tokenizer = .unicode61()
            }

            // Sync triggers for FTS5
            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_ai AFTER INSERT ON clipboard_items BEGIN
                    INSERT INTO clipboard_items_fts(rowid, text_content, ocr_text)
                    VALUES (new.id, new.text_content, new.ocr_text);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN
                    INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, text_content, ocr_text)
                    VALUES ('delete', old.id, old.text_content, old.ocr_text);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_au AFTER UPDATE ON clipboard_items BEGIN
                    INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, text_content, ocr_text)
                    VALUES ('delete', old.id, old.text_content, old.ocr_text);
                    INSERT INTO clipboard_items_fts(rowid, text_content, ocr_text)
                    VALUES (new.id, new.text_content, new.ocr_text);
                END;
            """)

            // tags table
            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("created_at", .datetime).notNull()
            }

            // item_tags junction table (many-to-many)
            try db.create(table: "item_tags") { t in
                t.column("item_id", .integer).notNull()
                    .references("clipboard_items", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["item_id", "tag_id"])
            }

            // app_settings key-value table
            try db.create(table: "app_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            // Insert default settings
            let defaultSettings: [(String, String)] = [
                ("retention_days", "30"),
                ("max_storage_mb", "500"),
                ("ocr_enabled", "1"),
                ("poll_interval_ms", "500"),
                ("search_provider", "fts"),
                ("launch_at_login_enabled", "1")
            ]
            for (key, value) in defaultSettings {
                try db.execute(
                    sql: "INSERT INTO app_settings (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            }
        }

        // v2: Favorites (US-021)
        // Adds an `is_favorite` column independent of `is_pinned`.
        // Pin and favorite are two orthogonal flags: pin affects list order (top of list),
        // favorite is a user-curated bookmark. Both protect items from cleanup.
        migrator.registerMigration("v2_favorites") { db in
            try db.alter(table: "clipboard_items") { t in
                t.add(column: "is_favorite", .integer).notNull().defaults(to: 0)
            }
            try db.create(
                index: "idx_clipboard_items_is_favorite",
                on: "clipboard_items",
                columns: ["is_favorite"]
            )
        }

        // v3: Assistant app shell defaults (US-001)
        // Keep launch-at-login enabled by default for existing databases while
        // preserving later user changes through SettingsView.
        migrator.registerMigration("v3_assistant_app_shell_settings") { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO app_settings (key, value) VALUES (?, ?)",
                arguments: ["launch_at_login_enabled", "1"]
            )
        }

        return migrator
    }
}
