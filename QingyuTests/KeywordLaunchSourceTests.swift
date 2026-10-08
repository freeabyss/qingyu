import Foundation
import XCTest
@testable import Qingyu

/// 关键词触发的外部跳转：`<关键词> <文字>` → 打开对应网页。
final class KeywordLaunchSourceTests: XCTestCase {

    private func webSource() -> KeywordLaunchSource {
        KeywordLaunchSource(
            id: .webSearch,
            displayName: "Web Search",
            categories: [KeywordLaunchCatalog.webSearchCategory, KeywordLaunchCatalog.specialistCategory]
        )
    }

    private func aiSource() -> KeywordLaunchSource {
        KeywordLaunchSource(
            id: .aiChat,
            displayName: "AI Chat",
            categories: [KeywordLaunchCatalog.aiSearchCategory, KeywordLaunchCatalog.aiChatCategory]
        )
    }

    private func presets() -> [KeywordLaunchPreset] {
        KeywordLaunchCatalog.resolved(customization: .empty)
    }

    private func targetURL(_ results: [SearchResult], file: StaticString = #filePath, line: UInt = #line) -> URL? {
        guard results.count == 1 else {
            XCTFail("应产生一条结果，实际 \(results.count) 条", file: file, line: line)
            return nil
        }
        switch results[0].primaryAction {
        case .openURL(let url), .openURLWithClipboard(let url, _):
            return url
        default:
            XCTFail("应产生打开网页动作", file: file, line: line)
            return nil
        }
    }

    private func queryValue(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
    }

    // MARK: - 内置目录完整性

    func testBuiltInCatalogIsWellFormed() {
        let all = KeywordLaunchCatalog.builtIn

        XCTAssertGreaterThanOrEqual(all.count, 40, "内置目录应覆盖用户提供的站点清单")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "条目 id 必须唯一")
        for preset in all {
            XCTAssertFalse(preset.keywords.isEmpty, "\(preset.id) 缺少关键词")
            XCTAssertTrue(preset.urlTemplate.contains("{query}"), "\(preset.id) 的模板缺少 {query}")
            XCTAssertTrue(preset.urlTemplate.hasPrefix("https://"), "\(preset.id) 应使用 https")
            for keyword in preset.keywords {
                XCTAssertEqual(keyword, keyword.lowercased(), "\(preset.id) 的关键词必须小写")
            }
        }

        // 关键词全局唯一，且四个分组都有条目。
        let resolved = presets()
        let keywords = resolved.flatMap(\.keywords)
        XCTAssertEqual(Set(keywords).count, keywords.count, "解析后关键词不得重复")
        XCTAssertEqual(Set(resolved.map(\.category)), Set(KeywordLaunchCatalog.categories), "四个分组都应存在")
    }

    func testListedSitesAreCovered() {
        let ids = Set(KeywordLaunchCatalog.builtIn.map(\.id))
        for expected in [
            "google", "bing", "brave", "duckduckgo", "kagi", "baidu", "sogou", "so360", "yahoo", "startpage", "mojeek",
            "github", "stackoverflow", "reddit", "youtube", "wikipedia", "x", "npm", "pypi", "maven", "dockerhub",
            "arxiv", "scholar", "semanticscholar",
            "perplexity", "chatgpt", "gemini", "copilot", "you", "phind", "grok",
            "claude", "lechat", "deepseek", "kimi", "qwen", "doubao", "yuanbao", "chatglm", "minimax", "qianwen",
            "poe", "character", "metaai", "pi",
        ] {
            XCTAssertTrue(ids.contains(expected), "目录缺少 \(expected)")
        }
    }

    // MARK: - 触发与 URL

    func testGoogleSearchBuildsSearchURL() async {
        let results = await webSource().search(query: "google 天气")

        guard let url = targetURL(results) else { return }
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(url.path, "/search")
        XCTAssertEqual(queryValue(url), "天气")
        XCTAssertEqual(results[0].title, "用 Google 搜索「天气」")
        XCTAssertEqual(results[0].typeLabel, "Web Search")
    }

    func testKeywordIsCaseInsensitiveAndAcceptsChineseAlias() async {
        let source = webSource()

        for query in ["Google 天气", "GOOGLE 天气", "谷歌 天气"] {
            let results = await source.search(query: query)
            XCTAssertEqual(queryValue(targetURL(results) ?? URL(fileURLWithPath: "/")), "天气", "\(query) 应命中 Google")
        }
    }

    func testSpecialistSearchIsCovered() async {
        let results = await webSource().search(query: "github swift concurrency")

        guard let url = targetURL(results) else { return }
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(queryValue(url), "swift concurrency")
    }

    func testKeywordWithoutTextDoesNotTrigger() async {
        let source = webSource()

        for query in ["google", "google ", "  google  ", "谷歌"] {
            XCTAssertFalse(source.canSearch(query: query), "\(query) 不应触发")
            let results = await source.search(query: query)
            XCTAssertTrue(results.isEmpty)
        }
    }

    func testUnregisteredKeywordDoesNotTrigger() async {
        let source = webSource()

        let unknown = await source.search(query: "nope 天气")
        XCTAssertTrue(unknown.isEmpty, "未登记的关键词不触发")
        let noText = await source.search(query: "nope")
        XCTAssertTrue(noText.isEmpty)
    }

    func testChatGPTSearchBuildsPromptURL() async {
        let results = await aiSource().search(query: "chatgpt 说明一下量子纠缠")

        guard let url = targetURL(results) else { return }
        XCTAssertEqual(url.host, "chatgpt.com")
        XCTAssertEqual(queryValue(url), "说明一下量子纠缠")
        XCTAssertEqual(results[0].title, "向 ChatGPT 提问「说明一下量子纠缠」")
    }

    func testTextIsPercentEncoded() async {
        let text = "a&b=c?d#e f/g"
        let results = await webSource().search(query: "google \(text)")

        guard let url = targetURL(results) else { return }
        XCTAssertEqual(queryValue(url), text, "编码后应能原样解回")
        XCTAssertFalse(url.absoluteString.contains("&b"), "裸 & 会截断查询")
        XCTAssertFalse(url.absoluteString.contains("#"), "裸 # 会变成 fragment")
    }

    /// 不支持 URL 预填的站点：打开网页的同时把文字放进剪贴板。
    func testNonPrefillSiteUsesClipboardFallback() async {
        let results = await aiSource().search(query: "doubao 你是谁")

        XCTAssertEqual(results.count, 1)
        guard case .openURLWithClipboard(let url, let text)? = results.first?.primaryAction else {
            return XCTFail("豆包应使用「打开 + 复制」模式")
        }
        XCTAssertEqual(text, "你是谁")
        XCTAssertEqual(url.host, "www.doubao.com")
    }

    // MARK: - 用户定制

    func testKeywordOverrideReplacesBuiltInKeywords() {
        let customization = KeywordLaunchCustomization(keywordOverrides: ["google": ["g"]])
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        let google = resolved.first { $0.id == "google" }
        XCTAssertEqual(google?.keywords, ["g"])
        XCTAssertFalse(resolved.contains { $0.keywords.contains("google") }, "原关键词应被替换掉")
    }

    func testEmptyOverrideDisablesEntry() {
        let customization = KeywordLaunchCustomization(keywordOverrides: ["github": []])
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        XCTAssertFalse(resolved.contains { $0.id == "github" }, "关键词清空即停用该条目")
    }

    func testCustomEntryIsAppendedAndSearchable() async {
        let custom = KeywordLaunchPreset(
            id: "custom-1",
            category: KeywordLaunchCatalog.webSearchCategory,
            keywords: ["我站"],
            name: "我站",
            site: "example.com",
            titlePrefix: "在 我站 搜索",
            urlTemplate: "https://example.com/s?q={query}",
            typeLabel: "Web Search",
            iconSystemName: "globe",
            prefill: .urlParam
        )
        let customization = KeywordLaunchCustomization(customEntries: [custom])
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        XCTAssertEqual(resolved.last?.id, "custom-1", "自定义条目应追加在末尾")
        let source = webSource()
        let parsed = source.parse("我站 你好", presets: resolved)
        XCTAssertEqual(parsed?.preset.id, "custom-1")
        XCTAssertEqual(parsed?.text, "你好")
    }

    /// 设置里改关键词后，来源应在下一次搜索立刻生效。
    func testSourceAppliesStoredCustomizationImmediately() async {
        let customization = KeywordLaunchCustomization(keywordOverrides: ["google": ["g"]])
        let source = KeywordLaunchSource(
            id: .webSearch,
            displayName: "Web Search",
            settingsService: CustomizationSettingsStub(customization),
            categories: [KeywordLaunchCatalog.webSearchCategory]
        )

        let renamed = await source.search(query: "g 天气")
        XCTAssertEqual(queryValue(targetURL(renamed) ?? URL(fileURLWithPath: "/")), "天气")

        let removed = await source.search(query: "google 天气")
        XCTAssertTrue(removed.isEmpty, "被改写掉的原关键词不应再命中")
    }

    func testCustomEntryWithoutPlaceholderIsDropped() {
        let broken = KeywordLaunchPreset(
            id: "custom-broken",
            category: KeywordLaunchCatalog.webSearchCategory,
            keywords: ["坏"],
            name: "坏",
            site: "example.com",
            titlePrefix: "坏",
            urlTemplate: "https://example.com/s",
            typeLabel: "Web Search",
            iconSystemName: "globe",
            prefill: .urlParam
        )
        let resolved = KeywordLaunchCatalog.resolved(
            customization: KeywordLaunchCustomization(customEntries: [broken])
        )

        XCTAssertFalse(resolved.contains { $0.id == "custom-broken" }, "缺 {query} 的条目应被丢弃")
    }

    func testKeywordCollisionKeepsFirstClaimantAndReportsConflict() {
        let duplicate = KeywordLaunchPreset(
            id: "custom-dup",
            category: KeywordLaunchCatalog.webSearchCategory,
            keywords: ["google", "dup"],
            name: "重复",
            site: "example.com",
            titlePrefix: "重复",
            urlTemplate: "https://example.com/s?q={query}",
            typeLabel: "Web Search",
            iconSystemName: "globe",
            prefill: .urlParam
        )
        let customization = KeywordLaunchCustomization(customEntries: [duplicate])
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        XCTAssertEqual(resolved.first { $0.id == "google" }?.keywords, ["google", "谷歌"], "内置条目先占用关键词")
        XCTAssertEqual(resolved.first { $0.id == "custom-dup" }?.keywords, ["dup"], "冲突关键词被让出，其余保留")

        let conflicts = KeywordLaunchCatalog.conflictingKeywords(
            ["google", "dup"],
            forEntryID: "custom-dup",
            customization: customization
        )
        XCTAssertEqual(conflicts, ["google"], "应报告被占用的关键词")
    }

    // MARK: - 停用条目

    func testDisabledEntryIsExcludedFromResolved() {
        let customization = KeywordLaunchCustomization(disabledEntryIDs: ["github"])
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        XCTAssertFalse(resolved.contains { $0.id == "github" }, "停用的条目不应进入解析结果")
        XCTAssertTrue(resolved.contains { $0.id == "google" }, "其余条目不受影响")
    }

    /// 停用必须发生在占用关键词之前，否则被停用的条目会一直挡着后面想要同一关键词的条目。
    func testDisablingEntryReleasesItsKeyword() {
        let taker = customPreset(id: "custom-taker", keywords: ["google"])
        let customization = KeywordLaunchCustomization(
            customEntries: [taker],
            disabledEntryIDs: ["google"]
        )
        let resolved = KeywordLaunchCatalog.resolved(customization: customization)

        XCTAssertFalse(resolved.contains { $0.id == "google" })
        XCTAssertEqual(resolved.first { $0.id == "custom-taker" }?.keywords, ["google"],
                       "内置条目停用后应让出关键词")
    }

    func testDisablingEntryPreservesStoredKeywords() {
        let customization = KeywordLaunchCustomization(
            keywordOverrides: ["google": ["g"]],
            disabledEntryIDs: ["google"]
        )
        XCTAssertFalse(KeywordLaunchCatalog.resolved(customization: customization).contains { $0.id == "google" })

        // 重新启用（同一个关键词覆盖，去掉停用标记）后，用户改过的关键词仍在。
        let reenabled = KeywordLaunchCustomization(keywordOverrides: ["google": ["g"]])
        XCTAssertEqual(KeywordLaunchCatalog.resolved(customization: reenabled).first { $0.id == "google" }?.keywords,
                       ["g"])
    }

    func testDisabledCustomEntryIsExcluded() {
        let custom = customPreset(id: "custom-1", keywords: ["我站"])
        let customization = KeywordLaunchCustomization(
            customEntries: [custom],
            disabledEntryIDs: ["custom-1"]
        )

        XCTAssertFalse(KeywordLaunchCatalog.resolved(customization: customization).contains { $0.id == "custom-1" })
    }

    func testDisabledEntryIsNotAConflictClaimant() {
        let customization = KeywordLaunchCustomization(disabledEntryIDs: ["google"])

        XCTAssertTrue(
            KeywordLaunchCatalog.conflictingKeywords(["google"], forEntryID: "custom-dup", customization: customization).isEmpty,
            "停用的条目不该再占用关键词"
        )
    }

    /// 走完整搜索链路：设置里停用后，来源立刻不再命中。
    func testDisabledEntryIsNotSearchableFromSource() async {
        let source = KeywordLaunchSource(
            id: .webSearch,
            displayName: "Web Search",
            settingsService: CustomizationSettingsStub(KeywordLaunchCustomization(disabledEntryIDs: ["google"])),
            categories: [KeywordLaunchCatalog.webSearchCategory]
        )

        let disabled = await source.search(query: "google 天气")
        XCTAssertTrue(disabled.isEmpty, "停用的条目不应再产生结果")

        let stillEnabled = await source.search(query: "bing 天气")
        XCTAssertEqual(stillEnabled.count, 1, "同来源的其它条目不受影响")
    }

    // MARK: - 定制的编解码

    /// `disabledEntryIDs` 是后加字段，历史数据里没有它，解码必须退回空集合。
    func testDecodingLegacyCustomizationWithoutDisabledField() throws {
        let decoder = JSONDecoder()

        let legacy = try decoder.decode(
            KeywordLaunchCustomization.self,
            from: Data(#"{"keywordOverrides":{},"customEntries":[]}"#.utf8)
        )
        XCTAssertTrue(legacy.disabledEntryIDs.isEmpty)

        let empty = try decoder.decode(KeywordLaunchCustomization.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.disabledEntryIDs.isEmpty)
        XCTAssertTrue(empty.keywordOverrides.isEmpty)
    }

    func testCustomizationRoundTripsDisabledEntryIDs() throws {
        let original = KeywordLaunchCustomization(disabledEntryIDs: ["b", "a"])

        let data = try JSONEncoder().encode(original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#"["a","b"]"#),
                      "应写成排序后的数组，避免每次保存产生无意义的字节差异")

        let decoded = try JSONDecoder().decode(KeywordLaunchCustomization.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    private func customPreset(id: String, keywords: [String]) -> KeywordLaunchPreset {
        KeywordLaunchPreset(
            id: id,
            category: KeywordLaunchCatalog.webSearchCategory,
            keywords: keywords,
            name: "我站",
            site: "example.com",
            titlePrefix: "用 我站 搜索",
            urlTemplate: "https://example.com/s?q={query}",
            typeLabel: "Web Search",
            iconSystemName: "globe",
            prefill: .urlParam
        )
    }

    /// `google <文字>` 必须排在任何应用名命中之前，
    /// 否则回车会变成启动 Google Chrome 而不是搜索。
    func testKeywordLaunchOutranksApplicationMatch() async {
        let service = SearchService(sources: [
            NameMatchingAppSourceStub(),
            webSource(),
        ])

        let response = await service.search(query: "google 天气")

        XCTAssertEqual(response.results.first?.sourceID, .webSearch, "关键词触发结果必须排第一")
    }
}

/// 只提供一份定制值的设置服务替身。
private final class CustomizationSettingsStub: SettingsServiceProtocol {
    private let customization: KeywordLaunchCustomization

    init(_ customization: KeywordLaunchCustomization) {
        self.customization = customization
    }

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        guard let value = customization as? T else { throw SettingsServiceError.encodingFailed }
        return value
    }

    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {}
    func reset(key: SettingKey) async throws {}
    func stringValue(for key: SettingKey) async throws -> String { "" }
}

/// 名称命中查询的应用来源（模拟 "Google Chrome" 命中 "google 天气"）。
private final class NameMatchingAppSourceStub: SearchSource {
    let id: SearchSourceID = .app
    let displayName = "Applications"
    let isEnabledInSearch = true

    func canSearch(query: String) -> Bool { true }

    func search(query: String) async -> [SearchResult] {
        [SearchResult(
            id: SearchResultID(rawValue: "app:com.google.Chrome"),
            sourceID: .app,
            title: "Google Chrome",
            subtitle: "/Applications/Google Chrome.app",
            icon: .none,
            typeLabel: "Application",
            baseScore: SourcePriority.application,
            matchScore: 0,
            usageScore: 0,
            primaryAction: .openApplication(ApplicationID(rawValue: "com.google.Chrome")),
            secondaryActions: []
        )]
    }
}
