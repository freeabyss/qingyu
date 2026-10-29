import Foundation

/// Localization helper providing a unified entry point for all user-facing strings.
///
/// Usage:
///   Text(L10n.localized("settings.general"))
///   Text(L10n.localized("settings.retention.format", viewModel.retentionDays))
///   Text(L10n.relativeTime(from: item.createdAt))
///
/// Keys are defined in `Resources/Localizable.xcstrings` (Xcode String Catalog format).
enum L10n {
    /// Retrieve a static localized string for the given key.
    static func localized(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, bundle: .main, comment: comment)
    }

    /// Retrieve a format string and interpolate the given arguments.
    static func localized(_ key: String, _ args: CVarArg..., comment: String = "") -> String {
        let format = NSLocalizedString(key, bundle: .main, comment: comment)
        return String(format: format, arguments: args)
    }

    /// Returns localized relative time string for the given date.
    /// Uses the current locale to choose the appropriate language.
    ///
    /// 用 `interval` 直接算总分钟 / 总小时 / 总天数，**不能**用
    /// `dateComponents([.day, .hour, .minute])` 的 `.minute`：那是把区间拆开后的
    /// 余数（恒为 0–59），于是 `minutes < 60` 永远成立，小时 / 天 / 日期三个分支
    /// 全成了死代码——一周前的记录会显示成「23m ago」这种假时间。
    static func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return L10n.localized("time.justNow")
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return L10n.localized("time.minutesAgo", minutes)
        }

        let hours = Int(interval / 3_600)
        if hours < 24 {
            return L10n.localized("time.hoursAgo", hours)
        }

        let days = Int(interval / 86_400)
        if days < 7 {
            return L10n.localized("time.daysAgo", days)
        }

        // 跨年记录只给「MM/dd」会分不清年份（去年 10/09 与今年 10/09 长得一样），
        // 因此按是否同年切换两种格式；两种格式各自按语言排列（en 月/日、zh/ja 年月日、fr 日/月）。
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let fmt = DateFormatter()
        fmt.dateFormat = L10n.localized(sameYear ? "time.dateShort" : "time.dateWithYear")
        return fmt.string(from: date)
    }
}
