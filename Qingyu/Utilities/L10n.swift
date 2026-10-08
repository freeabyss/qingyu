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
    static func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)

        if interval < 60 {
            return L10n.localized("time.justNow")
        } else if let minutes = components.minute, minutes < 60 {
            return L10n.localized("time.minutesAgo", minutes)
        } else if let hours = components.hour, hours < 24 {
            return L10n.localized("time.hoursAgo", hours)
        } else if let days = components.day, days < 7 {
            return L10n.localized("time.daysAgo", days)
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = L10n.localized("time.dateShort")
            return fmt.string(from: date)
        }
    }
}
