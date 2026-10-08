import XCTest
@testable import Qingyu

final class DataDirectoryMigratorTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("DataMigratorTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        root = nil
        try super.tearDownWithError()
    }

    private func makeMigrator() -> DataDirectoryMigrator {
        DataDirectoryMigrator(
            applicationSupportDirectory: root,
            legacySources: [
                .init(directoryName: "Qingniao", storeFileName: "Qingniao.sqlite"),
                .init(directoryName: "Assistant", storeFileName: "Assistant.sqlite"),
            ],
            newDirectoryName: "Qingyu",
            newStoreFileName: "Qingyu.sqlite",
            fileManager: fileManager
        )
    }

    func testFreshInstallWhenNoDirectories() {
        let outcome = makeMigrator().migrateIfNeeded()
        XCTAssertEqual(outcome, .freshInstall)
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("Qingyu").path))
    }

    func testAlreadyMigratedWhenNewDirectoryExists() throws {
        try fileManager.createDirectory(at: root.appendingPathComponent("Qingyu"), withIntermediateDirectories: true)
        let outcome = makeMigrator().migrateIfNeeded()
        XCTAssertEqual(outcome, .alreadyMigrated)
    }

    func testMovesQingniaoDirectoryAndRenamesStoreFiles() throws {
        let legacy = root.appendingPathComponent("Qingniao", isDirectory: true)
        try fileManager.createDirectory(at: legacy.appendingPathComponent("Clipboard/Images"), withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            try Data("db\(suffix)".utf8).write(to: legacy.appendingPathComponent("Qingniao.sqlite\(suffix)"))
        }
        try Data("thumb".utf8).write(to: legacy.appendingPathComponent("Clipboard/Images/a.png"))

        let outcome = makeMigrator().migrateIfNeeded()
        XCTAssertEqual(outcome, .migrated)

        let new = root.appendingPathComponent("Qingyu", isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: legacy.path))
        XCTAssertTrue(fileManager.fileExists(atPath: new.path))
        for suffix in ["", "-shm", "-wal"] {
            XCTAssertTrue(fileManager.fileExists(atPath: new.appendingPathComponent("Qingyu.sqlite\(suffix)").path))
            XCTAssertFalse(fileManager.fileExists(atPath: new.appendingPathComponent("Qingniao.sqlite\(suffix)").path))
        }
        // Non-store resources are preserved under the moved directory.
        XCTAssertTrue(fileManager.fileExists(atPath: new.appendingPathComponent("Clipboard/Images/a.png").path))
    }

    func testMovesAssistantDirectoryWhenQingniaoAbsent() throws {
        let legacy = root.appendingPathComponent("Assistant", isDirectory: true)
        try fileManager.createDirectory(at: legacy.appendingPathComponent("Clipboard/Images"), withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            try Data("db\(suffix)".utf8).write(to: legacy.appendingPathComponent("Assistant.sqlite\(suffix)"))
        }
        try Data("thumb".utf8).write(to: legacy.appendingPathComponent("Clipboard/Images/a.png"))

        let outcome = makeMigrator().migrateIfNeeded()
        XCTAssertEqual(outcome, .migrated)

        let new = root.appendingPathComponent("Qingyu", isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: legacy.path))
        XCTAssertTrue(fileManager.fileExists(atPath: new.path))
        for suffix in ["", "-shm", "-wal"] {
            XCTAssertTrue(fileManager.fileExists(atPath: new.appendingPathComponent("Qingyu.sqlite\(suffix)").path))
            XCTAssertFalse(fileManager.fileExists(atPath: new.appendingPathComponent("Assistant.sqlite\(suffix)").path))
        }
        XCTAssertTrue(fileManager.fileExists(atPath: new.appendingPathComponent("Clipboard/Images/a.png").path))
    }

    func testPrefersNewestLegacyWhenBothExist() throws {
        for name in ["Assistant", "Qingniao"] {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appendingPathComponent("\(name).sqlite"))
        }

        let outcome = makeMigrator().migrateIfNeeded()
        XCTAssertEqual(outcome, .migrated)

        let new = root.appendingPathComponent("Qingyu", isDirectory: true)
        XCTAssertTrue(fileManager.fileExists(atPath: new.appendingPathComponent("Qingyu.sqlite").path))
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("Qingyu.sqlite"), encoding: .utf8), "Qingniao")
        // Older unused legacy directory is left untouched.
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Assistant").path))
    }
}
