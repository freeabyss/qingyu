import XCTest
@testable import Qingyu

final class SearchTextMatcherTests: XCTestCase {
    func testPinyinPrefixMatchesChineseCandidate() {
        let candidate = SearchTextCandidate(text: "微信", aliases: [])

        XCTAssertEqual(SearchTextMatcher.match(query: "weix", candidate: candidate), .pinyinPrefix)
    }

    func testInitialsMatchChineseCandidate() {
        let candidate = SearchTextCandidate(text: "快捷键设置", aliases: [])

        XCTAssertEqual(SearchTextMatcher.match(query: "kjj", candidate: candidate), .initials)
    }

    func testEnglishAliasMatchesChineseCandidate() {
        let candidate = SearchTextCandidate(text: "权限", aliases: ["Permissions", "privacy"])

        XCTAssertEqual(SearchTextMatcher.match(query: "privacy", candidate: candidate), .alias)
    }

    func testChineseAliasPinyinMatches() {
        let candidate = SearchTextCandidate(text: "Settings", aliases: ["剪贴板历史"])

        XCTAssertEqual(SearchTextMatcher.match(query: "jtb", candidate: candidate), .initials)
    }

    // MARK: - Position ranking (left > right > middle)

    func testLeftMatchBeatsRightMatchBeatsMiddleMatch() {
        let left = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "Workbench")
        )
        let right = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "homework")
        )
        let middle = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "mysqlworkbench")
        )

        XCTAssertEqual(left, .prefix)
        XCTAssertEqual(right, .suffix)
        XCTAssertEqual(middle, .contains)
        XCTAssertGreaterThan(left!.score, right!.score)
        XCTAssertGreaterThan(right!.score, middle!.score)
    }

    func testWordStartMatchRanksBetweenSuffixAndMiddle() {
        let wordStart = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "mysql workbench")
        )
        XCTAssertEqual(wordStart, .wordStart)
        let suffixScore = SearchTextMatcher.MatchKind.suffix.score
        let middleScore = SearchTextMatcher.MatchKind.contains.score
        XCTAssertLessThan(wordStart!.score, suffixScore)
        XCTAssertGreaterThan(wordStart!.score, middleScore)
    }

    /// Regression: `work` used to match Keynote via bundle id
    /// `com.apple.iWork.Keynote`. Bundle ids are indexed by their **last
    /// segment only**, so `work` must not hit Keynote at all through the id.
    func testBundleIdentifierMatchesOnlyLastComponent() {
        XCTAssertEqual(AppSearchSource.lastBundleIdentifierComponent("com.apple.iWork.Keynote"), "Keynote")
        XCTAssertEqual(AppSearchSource.lastBundleIdentifierComponent("com.mysql.workbench"), "workbench")
        XCTAssertEqual(AppSearchSource.lastBundleIdentifierComponent("single"), "single")

        // Last-segment alias matching still works (e.g. "keynote" finds Keynote).
        let byLastSegment = SearchTextMatcher.match(
            query: "keynote",
            candidate: SearchTextCandidate(
                text: "Keynote",
                aliases: [AppSearchSource.lastBundleIdentifierComponent("com.apple.iWork.Keynote")]
            )
        )
        XCTAssertEqual(byLastSegment, .exact)

        // `work` must not match Keynote via its bundle id.
        let workViaBundleID = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(
                text: "Keynote",
                aliases: [AppSearchSource.lastBundleIdentifierComponent("com.apple.iWork.Keynote")]
            )
        )
        XCTAssertNil(workViaBundleID)

        let workbench = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "MySQLWorkbench")
        )
        XCTAssertEqual(workbench, .contains)
    }

    /// Full reverse-DNS as an alias is still weakly searchable, but must not
    /// outrank a name contains match (kept for matcher-level safety).
    func testAliasContainsDoesNotOutrankNameContains() {
        let keynote = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(
                text: "Keynote",
                aliases: ["com.apple.iWork.Keynote"]
            )
        )
        let workbench = SearchTextMatcher.match(
            query: "work",
            candidate: SearchTextCandidate(text: "MySQLWorkbench")
        )

        XCTAssertEqual(keynote, .aliasContains)
        XCTAssertEqual(workbench, .contains)
        XCTAssertGreaterThan(workbench!.score, keynote!.score)
    }
}
