import XCTest
@testable import Qingyu

final class PinyinHelperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PinyinHelper.clearCache()
    }

    // MARK: - toPinyin

    func testToPinyinChinese() {
        XCTAssertEqual(PinyinHelper.toPinyin("采购合同"), "caigouhetong")
    }

    func testToPinyinSingleChar() {
        XCTAssertEqual(PinyinHelper.toPinyin("微"), "wei")
    }

    func testToPinyinMixedString() {
        // Mixed CJK + Latin: each segment converted, joined without spaces
        let result = PinyinHelper.toPinyin("微信App")
        XCTAssertTrue(result.contains("weixin"))
        XCTAssertTrue(result.contains("app"))
    }

    func testToPinyinASCIIFastPath() {
        XCTAssertEqual(PinyinHelper.toPinyin("Safari"), "safari")
        XCTAssertEqual(PinyinHelper.toPinyin("Hello World"), "hello world")
    }

    func testToPinyinEmpty() {
        XCTAssertEqual(PinyinHelper.toPinyin(""), "")
    }

    func testToPinyinLowercaseAndStripsTones() {
        // CFStringTransform yields lowercase output without tone marks
        let result = PinyinHelper.toPinyin("北京")
        XCTAssertEqual(result, "beijing")
        XCTAssertFalse(result.contains("ǎ"))
        XCTAssertFalse(result.contains("ī"))
    }

    // MARK: - toInitials

    func testToInitialsChinese() {
        XCTAssertEqual(PinyinHelper.toInitials("采购合同"), "cght")
    }

    func testToInitialsTwoChars() {
        XCTAssertEqual(PinyinHelper.toInitials("微信"), "wx")
    }

    func testToInitialsLatinSingleWord() {
        XCTAssertEqual(PinyinHelper.toInitials("Safari"), "s")
    }

    func testToInitialsLatinMultiWord() {
        XCTAssertEqual(PinyinHelper.toInitials("Sublime Text"), "st")
    }

    func testToInitialsCamelCase() {
        XCTAssertEqual(PinyinHelper.toInitials("VSCode"), "vsc")
    }

    func testToInitialsEmpty() {
        XCTAssertEqual(PinyinHelper.toInitials(""), "")
    }

    // MARK: - Cache

    func testCacheReturnsSameValue() {
        let a = PinyinHelper.toPinyin("采购合同")
        let b = PinyinHelper.toPinyin("采购合同")
        XCTAssertEqual(a, b)
    }
}
