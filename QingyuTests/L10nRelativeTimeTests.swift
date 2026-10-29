import XCTest
@testable import Qingyu

/// `L10n.relativeTime` 的分档回归。
///
/// 这里锁死的是一个真实缺陷：旧实现用 `dateComponents([.day, .hour, .minute])` 的
/// `.minute` 判断「是否小于 60 分钟」，而那是区间拆开后的**余数**（恒为 0–59），
/// 于是小时 / 天 / 日期三个分支全是死代码——一周前的剪贴板记录会显示成
/// 「23m ago」这种假时间。由行级快照里的异常时间发现。
///
/// 断言一律与 `L10n.localized` 的同一份模板比对，不写死某一种语言的成品文案。
final class L10nRelativeTimeTests: XCTestCase {

    private func expected(_ key: String, _ value: Int) -> String {
        L10n.localized(key, value)
    }

    private func expectedDateShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = L10n.localized("time.dateShort")
        return fmt.string(from: date)
    }

    private func expectedDateWithYear(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = L10n.localized("time.dateWithYear")
        return fmt.string(from: date)
    }

    func testUnderOneMinuteIsJustNow() {
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-30)),
            L10n.localized("time.justNow")
        )
    }

    func testFutureDateIsJustNow() {
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(120)),
            L10n.localized("time.justNow"),
            "未来时间（时钟漂移）不应显示成负数分钟"
        )
    }

    func testMinutesBucket() {
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-5 * 60)),
            expected("time.minutesAgo", 5)
        )
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-59 * 60)),
            expected("time.minutesAgo", 59)
        )
    }

    func testHoursBucket() {
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-3 * 3_600)),
            expected("time.hoursAgo", 3)
        )
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-23 * 3_600)),
            expected("time.hoursAgo", 23)
        )
    }

    func testDaysBucket() {
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-2 * 86_400)),
            expected("time.daysAgo", 2)
        )
        XCTAssertEqual(
            L10n.relativeTime(from: Date().addingTimeInterval(-6 * 86_400)),
            expected("time.daysAgo", 6)
        )
    }

    /// 一周以上必须落到日期分支——这正是旧实现永远走不到的地方。
    func testOlderThanAWeekFallsBackToDate() {
        let date = Date().addingTimeInterval(-30 * 86_400)
        let rendered = L10n.relativeTime(from: date)
        XCTAssertEqual(rendered, expectedDateShort(date))
        XCTAssertFalse(rendered.contains("m ago"), "一周以上不应再显示分钟：\(rendered)")
    }

    /// 跨年旧记录：同样必须走日期分支，而不是被余数分钟骗过去。
    func testVeryOldDateDoesNotRenderAsMinutes() {
        let date = Date().addingTimeInterval(-400 * 86_400)
        let rendered = L10n.relativeTime(from: date)
        XCTAssertEqual(rendered, expectedDateWithYear(date))
    }

    /// 同年旧记录只显示月日；跨年必须带上年份，否则「去年 10/09」与「今年 10/09」无法区分。
    func testSameYearOmitsYearAndCrossYearIncludesIt() {
        let calendar = Calendar.current
        let now = Date()

        // 同年：取今年的 1 月 1 日（若今天就是 1 月初，则用今年 1 月 1 日仍成立）
        let sameYearDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1))!
        XCTAssertEqual(L10n.relativeTime(from: sameYearDate), expectedDateShort(sameYearDate))

        // 跨年：去年的同一天
        let crossYearDate = calendar.date(byAdding: .year, value: -1, to: sameYearDate)!
        XCTAssertEqual(L10n.relativeTime(from: crossYearDate), expectedDateWithYear(crossYearDate))
        XCTAssertNotEqual(
            L10n.relativeTime(from: crossYearDate),
            L10n.relativeTime(from: sameYearDate),
            "跨年记录不能与同年记录渲染成同一个串"
        )
    }
}
