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
            appName: displayName ?? bundleName ?? "Qingniao",
            version: version ?? "0.1.0",
            buildNumber: build ?? "1",
            homepageURL: ReleaseLinks.homepageURL,
            privacyPolicyURL: ReleaseLinks.privacyPolicyURL,
            releasesURL: ReleaseLinks.releasesURL,
            thirdPartyLicensesURL: ReleaseLinks.thirdPartyLicensesURL,
            feedbackEmail: ReleaseLinks.feedbackEmail,
            copyright: "© \(year) 青鸟 Qingniao. All rights reserved."
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

    static let homepageURL = url("https://github.com/freeabyss/qingniao")
    static let privacyPolicyURL = url("https://github.com/freeabyss/qingniao/blob/main/PRIVACY.md")
    static let releasesURL = url("https://github.com/freeabyss/qingniao/releases")
    static let thirdPartyLicensesURL = url("https://github.com/freeabyss/qingniao/blob/main/THIRD_PARTY_NOTICES.md")
    static let feedbackEmail = "feedback@qingniao.app"
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
            URLQueryItem(name: "subject", value: "青鸟 Qingniao 反馈"),
            URLQueryItem(name: "body", value: emailBody(context: context))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func emailBody(context: FeedbackContext) -> String {
        let trimmedSummary = context.errorSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (trimmedSummary?.isEmpty == false ? trimmedSummary : nil) ?? "No error summary provided"
        let description = context.userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Please describe what happened here."
            : context.userDescription

        return """
        Please describe the issue or suggestion:
        \(description)

        Diagnostic information included by your action:
        - App version: \(context.appVersion) (\(context.buildNumber))
        - macOS version: \(context.macOSVersion)
        - Error summary: \(summary)

        Privacy note: this email is sent only after you confirm it in your mail app. 青鸟 Qingniao does not attach clipboard history, screenshots, files, or automatic crash logs.
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
