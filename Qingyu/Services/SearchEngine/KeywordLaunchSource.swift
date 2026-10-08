import Foundation

/// 关键词触发的外部跳转：输入 `<关键词> <文字>` 后，打开对应网页并把文字带过去。
///
/// 目录是纯数据；用户可改写任一内置条目的关键词，或追加自定义条目（见
/// `KeywordLaunchCustomization`）。新增站点不需要改动解析、排序或执行链路。
enum KeywordLaunchPrefill: String, Codable, Hashable {
    /// 站点原生支持 URL 预填：打开即带文字（如 `chatgpt.com/?q=`）。
    case urlParam
    /// 站点不支持 URL 预填：打开站点并把文字放进剪贴板，提示用户粘贴。
    /// 依据：这些站点只有浏览器用户脚本代填（脚本从 URL 取参再写入输入框），
    /// 说明站点本身不读该参数。
    case clipboardAndOpen
}

struct KeywordLaunchPreset: Codable, Hashable {
    /// 稳定标识：内置条目用固定 slug，自定义条目由用户创建时生成。
    let id: String
    /// 设置页里的分组展示名。
    let category: String
    /// 触发关键词（比较前统一转小写，因此不要再写大小写变体）。
    let keywords: [String]
    /// 站点显示名（设置页与结果副标题）。
    let name: String
    /// 站点展示名（结果副标题）。
    let site: String
    /// 标题前缀，最终标题为 `前缀「文字」`。
    let titlePrefix: String
    /// 目标 URL，`{query}` 会替换为百分号编码后的文字。
    let urlTemplate: String
    let typeLabel: String
    let iconSystemName: String
    let prefill: KeywordLaunchPrefill

    /// 该关键词对应的目标 URL。
    func url(for text: String) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        return URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }
}

// MARK: - 用户定制

/// 用户对关键词跳转的定制：改写内置条目的关键词 + 追加自定义条目 + 停用条目。
struct KeywordLaunchCustomization: Codable, Hashable {
    /// 条目 id → 替换后的关键词；空数组表示该条目关键词被清空。
    var keywordOverrides: [String: [String]]
    var customEntries: [KeywordLaunchPreset]
    /// 被显式停用的条目 id。关键词原样保留，重新启用即恢复。
    var disabledEntryIDs: Set<String>

    init(keywordOverrides: [String: [String]] = [:],
         customEntries: [KeywordLaunchPreset] = [],
         disabledEntryIDs: Set<String> = []) {
        self.keywordOverrides = keywordOverrides
        self.customEntries = customEntries
        self.disabledEntryIDs = disabledEntryIDs
    }

    /// 显式声明：`init(from:)` 与 `encode(to:)` 都手写之后，编译器不再合成 `CodingKeys`。
    private enum CodingKeys: String, CodingKey {
        case keywordOverrides
        case customEntries
        case disabledEntryIDs
    }

    /// 容错解码：字段缺失或历史数据残缺时退回空定制，不阻塞搜索。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keywordOverrides = (try? container.decode([String: [String]].self, forKey: .keywordOverrides)) ?? [:]
        customEntries = (try? container.decode([KeywordLaunchPreset].self, forKey: .customEntries)) ?? []
        // 该字段是后加的：旧数据（含持久层的默认 JSON）没有它，走 `?? []`。
        disabledEntryIDs = Set((try? container.decode([String].self, forKey: .disabledEntryIDs)) ?? [])
    }

    /// 排序后写出：`Set` 遍历顺序不稳定，否则每次保存都会产生无意义的字节差异。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keywordOverrides, forKey: .keywordOverrides)
        try container.encode(customEntries, forKey: .customEntries)
        try container.encode(disabledEntryIDs.sorted(), forKey: .disabledEntryIDs)
    }

    static let empty = KeywordLaunchCustomization()
}

// MARK: - 目录与解析

enum KeywordLaunchCatalog {
    static let webSearchCategory = "Web Search"
    static let specialistCategory = "专业搜索"
    static let aiSearchCategory = "AI Search"
    static let aiChatCategory = "AI Chat"

    /// 设置页展示顺序。
    static let categories = [webSearchCategory, specialistCategory, aiSearchCategory, aiChatCategory]

    /// 合并内置目录与用户定制：
    /// 内置条目在前（顺序即优先级），自定义条目追加在后；
    /// 关键词按「先到先得」占用，冲突的后来者失去该关键词；
    /// 被停用、关键词被清空、或 URL 模板缺 `{query}` 的条目直接丢弃。
    static func resolved(customization: KeywordLaunchCustomization) -> [KeywordLaunchPreset] {
        var claimed = Set<String>()
        var result: [KeywordLaunchPreset] = []

        for preset in builtIn + customization.customEntries {
            // 停用的条目在占用关键词之前就退出，因此不再挡着后面想要同一关键词的条目。
            guard !customization.disabledEntryIDs.contains(preset.id) else { continue }
            guard preset.urlTemplate.contains("{query}") else { continue }
            let keywords = customization.keywordOverrides[preset.id] ?? preset.keywords
            let available = keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && claimed.insert($0).inserted }

            guard !available.isEmpty else { continue }
            result.append(KeywordLaunchPreset(
                id: preset.id,
                category: preset.category,
                keywords: available,
                name: preset.name,
                site: preset.site,
                titlePrefix: preset.titlePrefix,
                urlTemplate: preset.urlTemplate,
                typeLabel: preset.typeLabel,
                iconSystemName: preset.iconSystemName,
                prefill: preset.prefill
            ))
        }
        return result
    }

    /// 给定关键词是否已被**其它**条目占用（设置页用来阻止保存冲突输入）。
    static func conflictingKeywords(_ keywords: [String],
                                    forEntryID id: String,
                                    customization: KeywordLaunchCustomization) -> [String] {
        var taken = Set<String>()
        for preset in resolved(customization: customization) where preset.id != id {
            taken.formUnion(preset.keywords)
        }
        return keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && taken.contains($0) }
    }

    // MARK: 内置目录

    /// 站点与其预填形式。同一关键词只能指向一个网址，因此跨分类重复的站点
    /// （Brave Search / Kagi / ChatGPT / Gemini / Grok）只收录一次；
    /// 需要「同一站点、不同预填形式」的用户可用自定义条目再建一条。
    static let builtIn: [KeywordLaunchPreset] =
        webSearchEngines + specialistSearch + aiSearch + aiChat

    private static let webSearchEngines: [KeywordLaunchPreset] = [
        entry("google", webSearchCategory, "Google", ["google", "谷歌"], "https://www.google.com/search?q={query}"),
        entry("bing", webSearchCategory, "Bing", ["bing", "必应"], "https://www.bing.com/search?q={query}"),
        entry("brave", webSearchCategory, "Brave Search", ["brave"], "https://search.brave.com/search?q={query}"),
        entry("duckduckgo", webSearchCategory, "DuckDuckGo", ["duckduckgo", "ddg"], "https://duckduckgo.com/?q={query}"),
        entry("kagi", webSearchCategory, "Kagi", ["kagi"], "https://kagi.com/search?q={query}"),
        entry("baidu", webSearchCategory, "百度", ["baidu", "百度"], "https://www.baidu.com/s?wd={query}"),
        entry("sogou", webSearchCategory, "搜狗", ["sogou", "搜狗"], "https://www.sogou.com/web?query={query}"),
        entry("so360", webSearchCategory, "360 搜索", ["360"], "https://www.so.com/s?q={query}"),
        entry("yahoo", webSearchCategory, "Yahoo", ["yahoo"], "https://search.yahoo.com/search?p={query}"),
        entry("startpage", webSearchCategory, "Startpage", ["startpage"], "https://www.startpage.com/sp/search?query={query}"),
        entry("mojeek", webSearchCategory, "Mojeek", ["mojeek"], "https://www.mojeek.com/search?q={query}")
    ]

    private static let specialistSearch: [KeywordLaunchPreset] = [
        entry("github", specialistCategory, "GitHub", ["github", "gh"], "https://github.com/search?q={query}"),
        entry("stackoverflow", specialistCategory, "Stack Overflow", ["stackoverflow", "stack"], "https://stackoverflow.com/search?q={query}"),
        entry("reddit", specialistCategory, "Reddit", ["reddit"], "https://www.reddit.com/search/?q={query}"),
        entry("youtube", specialistCategory, "YouTube", ["youtube", "yt"], "https://www.youtube.com/results?search_query={query}"),
        entry("wikipedia", specialistCategory, "Wikipedia", ["wikipedia", "wiki", "维基"], "https://zh.wikipedia.org/w/index.php?search={query}"),
        entry("x", specialistCategory, "X", ["x", "twitter", "推特"], "https://x.com/search?q={query}"),
        entry("npm", specialistCategory, "npm", ["npm"], "https://www.npmjs.com/search?q={query}"),
        entry("pypi", specialistCategory, "PyPI", ["pypi"], "https://pypi.org/search/?q={query}"),
        entry("maven", specialistCategory, "Maven Central", ["maven"], "https://search.maven.org/search?q={query}"),
        entry("dockerhub", specialistCategory, "Docker Hub", ["docker"], "https://hub.docker.com/search?q={query}"),
        entry("arxiv", specialistCategory, "arXiv", ["arxiv"], "https://arxiv.org/search/?searchtype=all&query={query}"),
        entry("scholar", specialistCategory, "Google Scholar", ["scholar", "学术"], "https://scholar.google.com/scholar?q={query}"),
        entry("semanticscholar", specialistCategory, "Semantic Scholar", ["semanticscholar", "semantic"], "https://www.semanticscholar.org/search?q={query}")
    ]

    /// AI 搜索 / 对话。`prefill` 标注该站是否原生支持 URL 预填。
    private static let aiSearch: [KeywordLaunchPreset] = [
        ai("perplexity", aiSearchCategory, "Perplexity", ["perplexity"], "https://www.perplexity.ai/search?q={query}"),
        ai("chatgpt", aiSearchCategory, "ChatGPT", ["chatgpt", "gpt"], "https://chatgpt.com/?q={query}"),
        ai("gemini", aiSearchCategory, "Gemini", ["gemini"], "https://gemini.google.com/app?q={query}"),
        ai("copilot", aiSearchCategory, "Microsoft Copilot", ["copilot"], "https://copilot.microsoft.com/?q={query}"),
        ai("you", aiSearchCategory, "You.com", ["you"], "https://you.com/search?q={query}"),
        ai("phind", aiSearchCategory, "Phind", ["phind"], "https://www.phind.com/search?q={query}"),
        ai("grok", aiSearchCategory, "Grok", ["grok"], "https://grok.com/?q={query}")
    ]

    private static let aiChat: [KeywordLaunchPreset] = [
        ai("claude", aiChatCategory, "Claude", ["claude"], "https://claude.ai/new?q={query}"),
        ai("lechat", aiChatCategory, "Mistral Le Chat", ["lechat", "mistral"], "https://chat.mistral.ai/chat?q={query}"),
        ai("deepseek", aiChatCategory, "DeepSeek", ["deepseek"], "https://chat.deepseek.com/?q={query}", .clipboardAndOpen),
        ai("kimi", aiChatCategory, "Kimi", ["kimi"], "https://www.kimi.com/?q={query}", .clipboardAndOpen),
        ai("qwen", aiChatCategory, "Qwen", ["qwen"], "https://chat.qwen.ai/?q={query}", .clipboardAndOpen),
        ai("doubao", aiChatCategory, "豆包", ["doubao", "豆包"], "https://www.doubao.com/?q={query}", .clipboardAndOpen),
        ai("yuanbao", aiChatCategory, "腾讯元宝", ["yuanbao", "元宝"], "https://yuanbao.tencent.com/?q={query}", .clipboardAndOpen),
        ai("chatglm", aiChatCategory, "智谱清言", ["chatglm", "智谱", "glm"], "https://chatglm.cn/?q={query}", .clipboardAndOpen),
        ai("minimax", aiChatCategory, "MiniMax", ["minimax"], "https://agent.minimaxi.com/?q={query}", .clipboardAndOpen),
        ai("qianwen", aiChatCategory, "通义千问", ["qianwen", "通义"], "https://www.qianwen.com/?q={query}", .clipboardAndOpen),
        ai("poe", aiChatCategory, "Poe", ["poe"], "https://poe.com/?q={query}", .clipboardAndOpen),
        ai("character", aiChatCategory, "Character.AI", ["character"], "https://character.ai/?q={query}", .clipboardAndOpen),
        ai("metaai", aiChatCategory, "Meta AI", ["metaai", "meta"], "https://www.meta.ai/?q={query}", .clipboardAndOpen),
        ai("pi", aiChatCategory, "Pi", ["pi"], "https://pi.ai/?q={query}", .clipboardAndOpen)
    ]

    private static func entry(_ id: String,
                              _ category: String,
                              _ name: String,
                              _ keywords: [String],
                              _ urlTemplate: String) -> KeywordLaunchPreset {
        KeywordLaunchPreset(
            id: id,
            category: category,
            keywords: keywords,
            name: name,
            site: URL(string: urlTemplate)?.host ?? name,
            titlePrefix: "用 \(name) 搜索",
            urlTemplate: urlTemplate,
            typeLabel: "Web Search",
            iconSystemName: "globe",
            prefill: .urlParam
        )
    }

    private static func ai(_ id: String,
                           _ category: String,
                           _ name: String,
                           _ keywords: [String],
                           _ urlTemplate: String,
                           _ prefill: KeywordLaunchPrefill = .urlParam) -> KeywordLaunchPreset {
        KeywordLaunchPreset(
            id: id,
            category: category,
            keywords: keywords,
            name: name,
            site: URL(string: urlTemplate)?.host ?? name,
            titlePrefix: "向 \(name) 提问",
            urlTemplate: urlTemplate,
            typeLabel: "AI Chat",
            iconSystemName: "bubble.left.and.text.bubble.right",
            prefill: prefill
        )
    }
}

/// 关键词来源：命中目录条目后产出一条「打开网页」结果。
///
/// 每次搜索都按当前用户定制解析目录，因此设置页里改关键词会立刻生效。
final class KeywordLaunchSource: SearchSource {
    let id: SearchSourceID
    let displayName: String
    let isEnabledInSearch = true

    private let settingsService: SettingsServiceProtocol?
    /// 该来源负责的目录分类（网页搜索与 AI 各一个来源，避免同一结果出现两次）。
    private let categories: Set<String>

    init(id: SearchSourceID,
         displayName: String,
         settingsService: SettingsServiceProtocol? = nil,
         categories: Set<String> = Set(KeywordLaunchCatalog.categories)) {
        self.id = id
        self.displayName = displayName
        self.settingsService = settingsService
        self.categories = categories
    }

    /// 结构性预判：只有「关键词 + 空白 + 文字」才有可能命中；
    /// 是否真的命中由 `search` 按当前定制判断。
    func canSearch(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0.isWhitespace }) else { return false }
        let keyword = trimmed[trimmed.startIndex..<separator]
        let text = trimmed[trimmed.index(after: separator)...]
        return !keyword.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search(query: String) async -> [SearchResult] {
        guard let (preset, text) = parse(query, presets: await resolvedPresets()),
              let url = preset.url(for: text) else {
            return []
        }
        let action: SearchAction = preset.prefill == .urlParam
            ? .openURL(url)
            : .openURLWithClipboard(url: url, text: text)
        // 不支持预填的站点在结果行写明「会复制文字」，否则执行后面板立即关闭，
        // 用户无从知道需要粘贴。
        let subtitle = preset.prefill == .urlParam
            ? preset.site
            : "\(preset.site)（打开并复制文字，粘贴发送）"

        return [SearchResult(
            id: SearchResultID(rawValue: "\(id.rawValue):\(preset.id):\(text)"),
            sourceID: id,
            title: "\(preset.titlePrefix)「\(text)」",
            subtitle: subtitle,
            icon: .systemSymbol(preset.iconSystemName),
            typeLabel: preset.typeLabel,
            baseScore: SourcePriority.value(for: id),
            matchScore: 30,
            usageScore: 0,
            primaryAction: action,
            secondaryActions: []
        )]
    }

    /// 解析 `<关键词><空白><文字>`；关键词大小写不敏感，文字非空。
    func parse(_ query: String, presets: [KeywordLaunchPreset]) -> (preset: KeywordLaunchPreset, text: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }

        let keyword = trimmed[trimmed.startIndex..<separator].lowercased()
        let text = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !keyword.isEmpty, !text.isEmpty else { return nil }
        guard let preset = presets.first(where: { $0.keywords.contains(keyword) }) else { return nil }
        return (preset, text)
    }

    private func resolvedPresets() async -> [KeywordLaunchPreset] {
        let customization: KeywordLaunchCustomization
        if let settingsService {
            customization = (try? await settingsService.value(
                for: .keywordLaunchCustomization,
                as: KeywordLaunchCustomization.self
            )) ?? .empty
        } else {
            customization = .empty
        }
        return KeywordLaunchCatalog.resolved(customization: customization)
            .filter { categories.contains($0.category) }
    }
}
