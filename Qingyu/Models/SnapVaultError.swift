import Foundation

/// Application-wide error type.
enum SnapVaultError: LocalizedError {
    static let userCancelledReason = "__USER_CANCELLED__"

    case databaseError(underlying: Error)
    case ocrFailed(reason: String)
    case clipboardAccessDenied
    case itemNotFound(id: Int64)
    case storageLimitExceeded
    case exportFailed(reason: String)
    case importFailed(reason: String)
    case screenshotFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .databaseError(let underlying):
            return L10n.localized("error.database", underlying.localizedDescription)
        case .ocrFailed(let reason):
            return L10n.localized("error.ocrFailed", reason)
        case .clipboardAccessDenied:
            return L10n.localized("error.clipboardDenied")
        case .itemNotFound(let id):
            return L10n.localized("error.itemNotFound", id)
        case .storageLimitExceeded:
            return L10n.localized("error.storageExceeded")
        case .exportFailed(let reason):
            return L10n.localized("error.exportFailed", reason)
        case .importFailed(let reason):
            return L10n.localized("error.importFailed", reason)
        case .screenshotFailed(let reason):
            if reason == Self.userCancelledReason {
                return L10n.localized("error.userCancelled")
            }
            return L10n.localized("error.screenshotFailed", reason)
        }
    }
}
