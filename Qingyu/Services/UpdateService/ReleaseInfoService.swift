import AppKit
import Foundation

struct AboutInfo: Hashable {
    let appName: String
    let version: String
    let buildNumber: String
    let homepageURL: URL
    let privacyPolicyURL: URL
    let releasesURL: URL
    let thirdPartyLicensesURL: URL
    let feedbackEmail: String
    let copyright: String
}

struct FeedbackContext: Hashable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let errorSummary: String?
    let userDescription: String
}

protocol AboutInfoProviderProtocol {
    var info: AboutInfo { get }
}

protocol FeedbackServiceProtocol {
    func makeFeedbackEmail(context: FeedbackContext) throws -> URL
}

protocol UpdateCheckServiceProtocol {
    func openDownloadPage()
}

protocol ReleaseURLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: ReleaseURLOpening {}

struct BundleAboutInfoProvider: AboutInfoProviderProtocol {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var info: AboutInfo {
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let year = Calendar.current.component(.year, from: Date())

        return AboutInfo(
            appName: displayName ?? bundleName ?? "Qingyu",
            version: version ?? "0.1.0",
            buildNumber: build ?? "1",
            homepageURL: ReleaseLinks.homepageURL,
            privacyPolicyURL: ReleaseLinks.privacyPolicyURL,
            releasesURL: ReleaseLinks.releasesURL,
            thirdPartyLicensesURL: ReleaseLinks.thirdPartyLicensesURL,
            feedbackEmail: ReleaseLinks.feedbackEmail,
            copyright: "© \(year) 清羽 Qingyu. All rights reserved."
        )
    }
}

enum ReleaseLinks {
    /// Safe URL construction: these literals are valid, but we avoid force-unwrap
    /// (`URL(string:)!`) to satisfy the v1.2 robustness pass. The `fileURLWithPath`
    /// fallback can never be reached for these constants and keeps the type non-optional.
    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    static let homepageURL = url("https://github.com/freeabyss/qingyu")
    static let privacyPolicyURL = url("https://github.com/freeabyss/qingyu/blob/main/docs/guides/privacy.md")
    static let releasesURL = url("https://github.com/freeabyss/qingyu/releases")
    static let thirdPartyLicensesURL = url("https://github.com/freeabyss/qingyu/blob/main/docs/guides/third-party-notices.md")
    static let feedbackEmail = "qingyu_freeabyss@163.com"
}

struct FeedbackEmailService: FeedbackServiceProtocol {
    private let recipient: String

    init(recipient: String = ReleaseLinks.feedbackEmail) {
        self.recipient = recipient
    }

    func makeFeedbackEmail(context: FeedbackContext) throws -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.localized("feedback.email.subject")),
            URLQueryItem(name: "body", value: emailBody(context: context))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func emailBody(context: FeedbackContext) -> String {
        let trimmedSummary = context.errorSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (trimmedSummary?.isEmpty == false ? trimmedSummary : nil)
            ?? L10n.localized("feedback.email.noSummary")
        let description = context.userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.localized("feedback.email.placeholder")
            : context.userDescription

        return """
        \(L10n.localized("feedback.email.intro"))
        \(description)

        \(L10n.localized("feedback.email.diagnostics"))
        \(L10n.localized("feedback.email.line.appVersion", "\(context.appVersion) (\(context.buildNumber))"))
        \(L10n.localized("feedback.email.line.macOSVersion", context.macOSVersion))
        \(L10n.localized("feedback.email.line.errorSummary", summary))

        \(L10n.localized("feedback.email.privacyNote"))
        """
    }
}

struct WebUpdateCheckService: UpdateCheckServiceProtocol {
    private let releasesURL: URL
    private let opener: ReleaseURLOpening

    init(releasesURL: URL = ReleaseLinks.releasesURL, opener: ReleaseURLOpening = NSWorkspace.shared) {
        self.releasesURL = releasesURL
        self.opener = opener
    }

    func openDownloadPage() {
        opener.open(releasesURL)
    }
}
