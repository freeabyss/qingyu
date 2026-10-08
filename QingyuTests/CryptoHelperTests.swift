import XCTest
@testable import Qingyu

final class CryptoHelperTests: XCTestCase {

    func testSHA256Consistency() {
        let input = "hello world"
        let hash1 = CryptoHelper.sha256(input)
        let hash2 = CryptoHelper.sha256(input)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64) // SHA-256 produces 64 hex chars
    }

    func testSHA256DifferentInputs() {
        let hash1 = CryptoHelper.sha256("foo")
        let hash2 = CryptoHelper.sha256("bar")
        XCTAssertNotEqual(hash1, hash2)
    }
}
