import SwiftUI
import os.log

@main
struct AssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings are managed by SettingsWindowController (design §16), not the
        // SwiftUI Settings scene. This empty scene only satisfies the `App`
        // requirement for an LSUIElement menu-bar app whose UI is driven by
        // AppDelegate / AppContainer.
        Settings {
            EmptyView()
        }
    }
}
