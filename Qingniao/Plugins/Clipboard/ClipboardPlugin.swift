import Foundation
import os.log
import SwiftUI

// MARK: - Clipboard plugin identity (Task 003 / ADR-001)

extension PluginID {
    static let clipboard = PluginID(rawValue: "clipboard")
}

extension PluginActionID {
    static let openClipboardHistory = PluginActionID(rawValue: "clipboard.open-history")
    static let toggleClipboardRecording = PluginActionID(rawValue: "clipboard.toggle-recording")
    static let clearClipboardHistory = PluginActionID(rawValue: "clipboard.clear-history")
}

/// Task 003: owns the clipboard monitoring lifecycle, search contribution and
/// the history-window entry. The data stack (repository/index/store) is still
/// initialized by the app core and injected here; `start()`/`stop()` are
/// idempotent and the monitor task is held (and cancelled) by this plugin.
/// Disabling the plugin stops listening but keeps history and settings.
@MainActor
final class ClipboardPlugin: QingniaoPlugin {
    let manifest: PluginManifest

    /// Exposed so the app core can pause/resume recording when the persisted
    /// `clipboard.enabled` setting changes (single service instance ownership).
    let clipboardService: ClipboardServiceProtocol

    private let monitor: ClipboardMonitorProtocol
    private let settingsService: SettingsServiceProtocol
    private var monitorTask: Task<Void, Never>?
    private let logger = Logger.clipboard

    init(
        monitor: ClipboardMonitorProtocol,
        index: InMemorySearchIndex,
        repository: ClipboardRepositoryProtocol,
        resourceStore: FileResourceStoreProtocol,
        settingsService: SettingsServiceProtocol,
        openHistoryWindow: @escaping @MainActor () -> Void
    ) {
        self.monitor = monitor
        self.settingsService = settingsService
        self.clipboardService = ClipboardService(repository: repository, resourceStore: resourceStore)

        let searchSource = AssistantClipboardSource(
            queryService: ClipboardIndexQueryService(index: index, repository: repository),
            settingsService: settingsService
        )
        let historyService = ClipboardHistoryService(repository: repository)

        // Capture dependencies directly (not `self`) so the closures can be
        // built before `manifest` is initialized.
        let settings = settingsService
        let actions = [
            PluginAction(id: .openClipboardHistory) {
                openHistoryWindow()
            },
            PluginAction(id: .toggleClipboardRecording) {
                let current = (try? await settings.value(for: .clipboardEnabled, as: Bool.self)) ?? true
                try? await settings.set(!current, for: .clipboardEnabled)
                NotificationCenter.default.post(name: .settingsDidChange, object: nil)
            },
            PluginAction(id: .clearClipboardHistory) {
                try await historyService.clearAll(confirmed: true)
            }
        ]

        self.manifest = PluginManifest(
            descriptor: PluginDescriptor(
                id: .clipboard,
                displayNameKey: "plugin.clipboard.displayName",
                version: "1.0.0",
                defaultEnabled: true
            ),
            searchSources: [searchSource],
            actions: actions,
            settingsPage: PluginSettingsPageDescriptor(
                id: .clipboard,
                titleKey: "settings.page.clipboard",
                systemImageName: "doc.on.clipboard",
                order: 30,
                makeView: { AnyView(ClipboardPluginSettingsPage()) }
            ),
            menuItems: [],
            shortcuts: [],
            requiredPermissions: []
        )
    }

    // MARK: - Lifecycle

    /// Starts clipboard capture exactly once; repeated calls are no-ops.
    func start() async throws {
        guard monitorTask == nil else { return }
        monitor.start()

        let service = clipboardService
        let logger = self.logger
        let events = monitor.events
        monitorTask = Task { [weak self] in
            for await event in events {
                // A cancelled task may still observe buffered stream elements;
                // drop them so "stopped" deterministically means "no processing".
                guard self != nil, !Task.isCancelled else { break }
                do {
                    if let snapshot = try await service.handle(event: event) {
                        logger.debug("Processed clipboard event -> record id=\(snapshot.id.uuidString, privacy: .public)")
                    }
                } catch {
                    logger.error("Failed to process clipboard event: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        logger.info("Clipboard monitoring started (plugin)")
    }

    /// Stops capture and cancels the monitor task exactly once; history and
    /// settings are intentionally preserved.
    func stop() async {
        guard monitorTask != nil else { return }
        monitor.stop()
        monitorTask?.cancel()
        monitorTask = nil
        logger.info("Clipboard monitoring stopped (plugin)")
    }
}
