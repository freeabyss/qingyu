import Foundation

/// Assistant MVP clipboard SearchSource backed by the lightweight in-memory index.
///
/// This source intentionally returns no results for empty or 1-character queries;
/// SearchService also guards empty input globally, and the clipboard source starts
/// at 2 characters per PRD FR-SEARCH-17.
final class AssistantClipboardSource: SearchSource {
    let id: SearchSourceID = .clipboard
    let displayName = "Clipboard"
    let isEnabledInSearch = true

    private let queryService: ClipboardIndexQueryServiceProtocol
    private let settingsService: SettingsServiceProtocol?
    private let limit: Int

    init(
        queryService: ClipboardIndexQueryServiceProtocol,
        settingsService: SettingsServiceProtocol? = nil,
        limit: Int = SearchService.defaultResultLimit
    ) {
        self.queryService = queryService
        self.settingsService = settingsService
        self.limit = limit
    }

    func canSearch(query: String) -> Bool {
        SearchTriggerRules.standardMinimumLength(sourceID: .clipboard, query: query)
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch(query: trimmed) else { return [] }
        if let settingsService {
            let showInSearch = (try? await settingsService.value(for: .clipboardShowInSearch, as: Bool.self)) ?? false
            let clipboardEnabled = (try? await settingsService.value(for: .clipboardEnabled, as: Bool.self)) ?? true
            guard showInSearch && clipboardEnabled else { return [] }
        }

        return queryService.searchIndex(query: trimmed, filter: nil, limit: limit).map { item in
            SearchResult(
                id: SearchResultID(rawValue: "clipboard:\(item.clipboardRecordID?.uuidString ?? item.id.uuidString)"),
                sourceID: .clipboard,
                title: item.title,
                subtitle: subtitle(for: item),
                icon: icon(for: item.contentType),
                typeLabel: L10n.localized("searchPanel.type.clipboard"),
                baseScore: SourcePriority.clipboard,
                matchScore: item.isPinned ? 12 : 8,
                usageScore: 0,
                primaryAction: .copyClipboardRecord(item.clipboardRecordID ?? item.id),
                secondaryActions: []
            )
        }
    }

    private func subtitle(for item: SearchIndexItem) -> String? {
        let type = item.contentType.map(label(for:)) ?? L10n.localized("searchPanel.type.clipboard")
        return "\(type) · \(L10n.relativeTime(from: item.updatedAt))"
    }

    private func label(for type: ClipboardContentType) -> String {
        switch type {
        case .text:
            return L10n.localized("content.text")
        case .richText:
            return L10n.localized("content.rtf")
        case .image:
            return L10n.localized("content.image")
        case .file:
            return L10n.localized("content.file")
        }
    }

    private func icon(for type: ClipboardContentType?) -> SearchResultIcon {
        switch type {
        case .text:
            return .systemSymbol("doc.text")
        case .richText:
            return .systemSymbol("doc.richtext")
        case .image:
            return .systemSymbol("photo")
        case .file:
            return .systemSymbol("doc")
        case nil:
            return .systemSymbol("clipboard")
        }
    }
}
