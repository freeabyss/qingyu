import XCTest
@testable import Qingyu

final class DatabaseManagerTests: XCTestCase {

    func testDatabaseURL() {
        let url = DatabaseManager.databaseURL()
        XCTAssertTrue(url.path.hasSuffix("assistant.db"))
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertTrue(url.path.contains("Qingyu"))
    }

    func testMigratorRegistration() {
        let migrator = DatabaseManager.migrator()
        // Verify migrator is created without errors
        XCTAssertNotNil(migrator)
    }

    /// Verify ClipboardItem model exposes the isFavorite property (US-021).
    /// Default value is false and toggling works in-memory.
    func testClipboardItemIsFavoriteDefault() {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "hello",
            contentHash: "h1"
        )
        XCTAssertFalse(item.isFavorite, "isFavorite should default to false")
        XCTAssertFalse(item.isPinned, "isPinned should default to false")

        var mutable = item
        mutable.isFavorite = true
        XCTAssertTrue(mutable.isFavorite)
        XCTAssertFalse(mutable.isPinned, "Toggling favorite should not affect pin")
    }

    /// Verify pin and favorite are orthogonal flags.
    func testPinAndFavoriteAreIndependent() {
        var item = ClipboardItem(
            contentType: .text,
            textContent: "hi",
            contentHash: "h2",
            isPinned: true,
            isFavorite: true
        )
        XCTAssertTrue(item.isPinned)
        XCTAssertTrue(item.isFavorite)

        item.isPinned = false
        XCTAssertFalse(item.isPinned)
        XCTAssertTrue(item.isFavorite, "Unpinning should not affect favorite")

        item.isFavorite = false
        XCTAssertFalse(item.isFavorite)
        XCTAssertFalse(item.isPinned)
    }
}
