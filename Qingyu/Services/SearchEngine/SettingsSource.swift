import Foundation

struct SettingsSearchRoute: Identifiable, Hashable {
    let id: SettingsRoute
    let title: String
    let aliases: [String]
    let pinyin: String
    let initials: String
    let subtitle: String
    let iconSystemName: String
}

final class SettingsSource: SearchSource {
    let id = SearchSourceID.settings
    let displayName = "Settings"

    private let staticIsEnabledInSearch: Bool
    private let settingsService: SettingsServiceProtocol?

    var isEnabledInSearch: Bool {
        staticIsEnabledInSearch
    }

    let routes: [SettingsSearchRoute]

    init(
        isEnabledInSearch: Bool = true,
        settingsService: SettingsServiceProtocol? = nil,
        routes: [SettingsSearchRoute] = SettingsSource.defaultRoutes
    ) {
        self.staticIsEnabledInSearch = isEnabledInSearch
        self.settingsService = settingsService
        self.routes = routes
    }

    func canSearch(query: String) -> Bool {
        SearchTriggerRules.standardMinimumLength(sourceID: id, query: query)
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard await resolvedIsEnabledInSearch() else { return [] }

        return routes.compactMap { route -> (SettingsSearchRoute, SearchTextMatcher.MatchKind)? in
            let candidate = SearchTextCandidate(
                text: route.title,
                aliases: route.aliases,
                pinyin: route.pinyin,
                initials: route.initials
            )
            guard let kind = SearchTextMatcher.match(query: trimmed, candidate: candidate) else { return nil }
            return (route, kind)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        .map { route, matchKind in
            SearchResult(
                id: SearchResultID(rawValue: "setting:\(route.id.rawValue)"),
                sourceID: id,
                title: route.title,
                subtitle: route.subtitle,
                icon: .systemSymbol(route.iconSystemName),
                typeLabel: "Settings",
                baseScore: SourcePriority.settings,
                matchScore: matchKind.score,
                usageScore: 0,
                primaryAction: .openSettings(route.id),
                secondaryActions: []
            )
        }
    }

    private func resolvedIsEnabledInSearch() async -> Bool {
        guard let settingsService else { return staticIsEnabledInSearch }
        return (try? await settingsService.value(for: .settingsSourceEnabled, as: Bool.self)) ?? true
    }

    static let defaultRoutes: [SettingsSearchRoute] = [
        .make(.general, title: "通用设置", english: "General Settings", aliases: ["设置", "偏好设置", "preferences", "prefs", "配置", "configuration", "权限", "隐私", "privacy", "开机启动", "外观", "数据", "language", "appearance", "permissions"], icon: "gearshape"),
        .make(.quickLaunch, title: "快速启动设置", english: "Quick Launch Settings", aliases: ["搜索源", "搜索来源", "搜索源开关", "快捷键", "provider", "providers", "sources", "shortcut", "shortcuts", "hotkey"], icon: "bolt.circle"),
        .make(.clipboard, title: "剪贴板设置", english: "Clipboard Settings", aliases: ["剪贴板", "剪贴板历史", "clipboard", "clipboard history", "保留时间", "retention"], icon: "doc.on.clipboard"),
        .make(.screenshot, title: "截图设置", english: "Screenshot Settings", aliases: ["截图", "screen capture", "capture", "保存目录", "save directory", "贴图", "screenshots"], icon: "camera.viewfinder"),
        .make(.about, title: "关于", english: "About", aliases: ["版本", "隐私政策", "about", "privacy", "license", "许可证", "反馈", "feedback", "更新", "updates"], icon: "info.circle")
    ]
}

private extension SettingsSearchRoute {
    static func make(_ route: SettingsRoute, title: String, english: String, aliases: [String], icon: String) -> SettingsSearchRoute {
        let allAliases = [english] + aliases
        return SettingsSearchRoute(
            id: route,
            title: title,
            aliases: allAliases,
            pinyin: PinyinHelper.toPinyin(title),
            initials: PinyinHelper.toInitials(title),
            subtitle: english,
            iconSystemName: icon
        )
    }
}
