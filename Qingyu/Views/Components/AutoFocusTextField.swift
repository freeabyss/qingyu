import SwiftUI
import AppKit

/// Notifications used by the floating search panel.
///
/// Relocated from the removed MenuBarView.swift (T-005). focusSearchField
/// requests the search text field to become first responder; checkForUpdates
/// triggers a manual update check.
///
/// Note: the AutoFocusTextField wrapper that used to live here was removed:
/// it had no production call sites (T-011 CommandBarView uses a native SwiftUI
/// TextField with FocusState instead) and carried a hard-coded 16pt font
/// outside JadeFont. This file is retained only for the notification names
/// above, still posted and observed by the command bar, clipboard history
/// window, and update flow.
extension Notification.Name {
    static let focusSearchField = Notification.Name("Assistant.focusSearchField")
    /// Clipboard history window: put the caret in its search field on open.
    static let focusClipboardSearchField = Notification.Name("com.freeabyss.qingyu.focusClipboardSearchField")
    static let checkForUpdates = Notification.Name("Assistant.checkForUpdates")
}
