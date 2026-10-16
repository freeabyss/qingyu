import Foundation

struct SettingsSearchRoute: Identifiable, Hashable {
    let id: SettingsRoute
    /// 显示名本地化 key。结果行显示它，随界面语言变化。
    let titleKey: String
    /// 匹配文本：固定中文名。搜索行为因此**与界面语言无关**——中文界面下用
    /// 拼音/首字母、英文界面下用 `settings` 之类的别名都能命中同一条路由。
    let title: String
    let aliases: [String]
    let pinyin: String
    let initials: String
    let subtitle: String
    let iconSystemName: String

    /// 结果行标题，语言跟随界面。
    var localizedTitle: String { L10n.localized(titleKey) }

    /// 副标题用英文名做对照；界面语言是英文时标题已等于英文名，不再重复一行。
    var localizedSubtitle: String? { localizedTitle == subtitle ? nil : subtitle }

    func candidate() -> SearchTextCandidate {
        SearchTextCandidate(text: title, aliases: aliases, pinyin: pinyin, initials: initials)
    }
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
            guard let kind = SearchTextMatcher.match(query: trimmed, candidate: route.candidate()) else { return nil }
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
                title: route.localizedTitle,
                subtitle: route.localizedSubtitle,
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
        .make(.general, titleKey: "settings.page.general", title: "通用设置", english: "General Settings", aliases: ["设置", "偏好设置", "preferences", "prefs", "配置", "configuration", "权限", "隐私", "privacy", "开机启动", "外观", "数据", "language", "appearance", "permissions"], icon: "gearshape"),
        .make(.quickLaunch, titleKey: "settings.page.quickLaunch", title: "快速启动设置", english: "Quick Launch Settings", aliases: ["搜索源", "搜索来源", "搜索源开关", "快捷键", "provider", "providers", "sources", "shortcut", "shortcuts", "hotkey"], icon: "bolt.circle"),
        .make(.clipboard, titleKey: "settings.page.clipboard", title: "剪贴板设置", english: "Clipboard Settings", aliases: ["剪贴板", "剪贴板历史", "clipboard", "clipboard history", "保留时间", "retention"], icon: "doc.on.clipboard"),
        .make(.screenshot, titleKey: "settings.page.screenshot", title: "截图设置", english: "Screenshot Settings", aliases: ["截图", "screen capture", "capture", "保存目录", "save directory", "贴图", "screenshots"], icon: "camera.viewfinder"),
        .make(.about, titleKey: "settings.page.about", title: "关于", english: "About", aliases: ["版本", "隐私政策", "about", "privacy", "license", "许可证", "反馈", "feedback", "更新", "updates"], icon: "info.circle")
    ]
}

private extension SettingsSearchRoute {
    static func make(_ route: SettingsRoute, titleKey: String, title: String, english: String, aliases: [String], icon: String) -> SettingsSearchRoute {
        let allAliases = [english] + aliases
        return SettingsSearchRoute(
            id: route,
            titleKey: titleKey,
            title: title,
            aliases: allAliases,
            pinyin: PinyinHelper.toPinyin(title),
            initials: PinyinHelper.toInitials(title),
            subtitle: english,
            iconSystemName: icon
        )
    }
}
