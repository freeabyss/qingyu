import Foundation
import Combine

/// Global application state shared across views.
@MainActor
final class AppState: ObservableObject {
    /// Whether the main panel is currently visible.
    @Published var isPanelVisible = false

    /// Current search text entered by the user.
    @Published var searchText = ""

    /// Currently selected content type filter.
    @Published var selectedContentType: ContentType?

    /// Whether the database has been successfully initialized.
    @Published var isDatabaseReady = false

    init() {
        // Check database readiness
        isDatabaseReady = DatabaseManager.shared.isReady
    }
}
