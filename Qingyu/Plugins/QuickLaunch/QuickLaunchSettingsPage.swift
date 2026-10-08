import KeyboardShortcuts
import SwiftUI

/// Settings page contributed by the Quick Launch plugin (Task 004).
///
/// Search shortcut, source switches, file search directories, and the
/// keyword-launch catalog (keywords are user-editable; custom entries can be added).
/// Bindings come from the shared `SettingsViewModel` injected by the settings
/// window's environment.
struct QuickLaunchPluginSettingsPage: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    private let fileSearchDirectories = ["~/Desktop", "~/Documents", "~/Downloads"]

    /// 未提交的关键词输入（回车或失焦才写回设置，避免每敲一个字都落库）。
    @State private var keywordDrafts: [String: String] = [:]
    @State private var keywordFilter = ""
    @State private var onlyEnabledKeywords = false
    @State private var showingAddEntryForm = false
    @State private var newKeyword = ""
    @State private var newSiteName = ""
    @State private var newURLTemplate = ""
    @State private var newCategory = KeywordLaunchCatalog.webSearchCategory
    @State private var newPrefillsURL = true

    var body: some View {
        SettingsScrollPage {
            SettingsHeader(
                titleKey: "settings.page.quickLaunch",
                subtitleKey: "management.searchSources.subtitle",
                iconName: "bolt.circle"
            )

            SettingsSection("management.settings.shortcuts") {
                shortcutRecorderRow(
                    label: L10n.localized("management.shortcuts.search"),
                    name: .togglePanel
                )
            }

            SettingsSection("management.settings.sources") {
                ForEach(Array($viewModel.sourceToggles.enumerated()), id: \.element.id) { index, $source in
                    if index > 0 { JadeSettingsDivider() }
                    JadeSwitchRow(icon: source.iconName,
                                  title: source.title,
                                  subtitle: source.subtitle,
                                  isOn: Binding(get: { source.isEnabled },
                                                set: { source.isEnabled = $0; Task { await viewModel.saveSettings() } }))
                }
                Text(L10n.localized("management.searchSources.hint"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }

            keywordSection

            SettingsSection("management.searchSources.fileDirectories") {
                ForEach(fileSearchDirectories, id: \.self) { dir in
                    Text(dir)
                        .font(JadeFont.callout)
                        .foregroundStyle(JadeColor.textSecondary)
                }
                .disabled(true)
                Text(L10n.localized("management.searchSources.fileDirectories.note"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.textTertiary)
            }
        }
    }

    // MARK: - 关键词表格

    /// 列宽固定：两张表与列头共用同一套 `HStack` 构造器，加上相同的卡片内边距，
    /// 列自然对齐；`Grid` 会让两张卡片各自算列宽，再和弹性的「显示文本」列打架。
    private enum KeywordColumn {
        static let glyph: CGFloat = 20
        static let keyword: CGFloat = 160
        /// 容得下「自定义」三个字，避免列头折行。
        static let custom: CGFloat = 44
        static let enabled: CGFloat = 48

        /// 表格分组。与 `QuickLaunchPlugin` 里两个搜索来源的分类切分保持一致。
        static let webCategories = [KeywordLaunchCatalog.webSearchCategory, KeywordLaunchCatalog.specialistCategory]
        static let aiCategories = [KeywordLaunchCatalog.aiSearchCategory, KeywordLaunchCatalog.aiChatCategory]
    }

    private var keywordSection: some View {
        Group {
            Text("输入「关键词 + 空格 + 文字」后回车，打开对应网页并把文字带过去。取消勾选「启用」即停用该条目，关键词会保留。")
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textTertiary)

            keywordTableControls

            keywordTable(titleKey: "settings.quickLaunch.keyword.webSearch",
                         categories: KeywordColumn.webCategories)
            keywordTable(titleKey: "settings.quickLaunch.keyword.aiSearch",
                         categories: KeywordColumn.aiCategories)

            addCustomEntryFooter

            if !conflictWarnings.isEmpty {
                Text(conflictWarnings.joined(separator: "\n"))
                    .font(JadeFont.caption)
                    .foregroundStyle(JadeColor.warning)
            }
        }
    }

    /// 过滤与「仅显示已启用」由两张表共用，因此放在表格之上而不是卡片内部。
    private var keywordTableControls: some View {
        HStack(spacing: JadeSpace.x3.value) {
            JadeTextField("搜索关键词或站点",
                          text: $keywordFilter,
                          icon: Image(systemName: "magnifyingglass"))
                .accessibilityIdentifier("settings.quickLaunch.keywordFilter")
            Toggle("仅显示已启用", isOn: $onlyEnabledKeywords)
                .toggleStyle(.checkbox)
                .font(JadeFont.caption)
                .foregroundStyle(JadeColor.textSecondary)
                .fixedSize()
        }
    }

    private func keywordTable(titleKey: String, categories: [String]) -> some View {
        let rows = tableEntries(categories: categories)
        return SettingsSection(titleKey) {
            tableHeaderRow
            JadeSettingsDivider()
            if rows.isEmpty {
                Text(keywordFilter.isEmpty && !onlyEnabledKeywords ? "该分组暂无条目" : "没有匹配的条目")
                    .font(JadeFont.callout)
                    .foregroundStyle(JadeColor.textTertiary)
                    .padding(.vertical, JadeSpace.x2.value)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { JadeSettingsDivider() }
                    keywordRow(entry)
                }
            }
        }
    }

    private var tableHeaderRow: some View {
        HStack(spacing: JadeSpace.x3.value) {
            Color.clear.frame(width: KeywordColumn.glyph)
            Text("关键词")
                .frame(width: KeywordColumn.keyword, alignment: .leading)
            Text("显示文本")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("自定义")
                .frame(width: KeywordColumn.custom, alignment: .center)
            Text("启用")
                .frame(width: KeywordColumn.enabled, alignment: .center)
        }
        .font(JadeFont.caption)
        .foregroundStyle(JadeColor.textTertiary)
        .lineLimit(1)
    }

    private func keywordRow(_ entry: KeywordLaunchPreset) -> some View {
        HStack(spacing: JadeSpace.x3.value) {
            Image(systemName: entry.iconSystemName)
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textSecondary)
                .frame(width: KeywordColumn.glyph)

            TextField("关键词", text: draftBinding(for: entry))
                .textFieldStyle(.roundedBorder)
                .font(JadeFont.callout)
                .frame(width: KeywordColumn.keyword)
                .onSubmit { commitKeywords(for: entry) }

            // 结果标题的真实格式是 `前缀「文字」`，这里用 `{query}` 占位展示。
            Text(entry.titlePrefix + "「{query}」")
                .font(JadeFont.callout)
                .foregroundStyle(JadeColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.urlTemplate)

            Group {
                if isCustomEntry(entry) {
                    Button {
                        removeCustomEntry(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(JadeColor.textSecondary)
                    .help("删除")
                }
            }
            .frame(width: KeywordColumn.custom)

            Toggle("", isOn: enabledBinding(for: entry))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: KeywordColumn.enabled)
                .help("停用后该关键词不再出现在命令栏，关键词文本会保留。")
        }
        .padding(.vertical, JadeSpace.x1.value)
    }

    // MARK: - 自定义条目

    @ViewBuilder
    private var addCustomEntryFooter: some View {
        HStack {
            Spacer()
            Button(showingAddEntryForm ? "收起" : "添加自定义搜索") {
                showingAddEntryForm.toggle()
            }
            .buttonStyle(.jadeSecondary)
        }

        if showingAddEntryForm {
            JadeSettingsCard {
                customEntryForm
            }
        }
    }

    private var customEntryForm: some View {
        HStack(spacing: JadeSpace.x2.value) {
            TextField("关键词", text: $newKeyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("名称", text: $newSiteName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("URL 模板（含 {query}）", text: $newURLTemplate)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $newCategory) {
                ForEach(KeywordLaunchCatalog.categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Toggle("支持 URL 预填", isOn: $newPrefillsURL)
                .toggleStyle(.checkbox)
                .font(JadeFont.caption)
            Button("添加") { addCustomEntry() }
                .buttonStyle(.jadeSecondary)
                .disabled(!canAddCustomEntry)
        }
    }

    // MARK: - 数据

    private var customization: KeywordLaunchCustomization {
        viewModel.keywordLaunchCustomization
    }

    /// 表格数据源。刻意不走 `KeywordLaunchCatalog.resolved` —— 这是编辑面板，
    /// 关键词被清空或被别的条目抢走的条目也必须继续显示，用户才有机会改回来。
    private func tableEntries(categories: [String]) -> [KeywordLaunchPreset] {
        (KeywordLaunchCatalog.builtIn + customization.customEntries)
            .filter { categories.contains($0.category) }
            .filter { !onlyEnabledKeywords || !isDisabled($0) }
            .filter { matchesFilter($0) }
    }

    private func matchesFilter(_ entry: KeywordLaunchPreset) -> Bool {
        let needle = keywordFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return entry.name.lowercased().contains(needle)
            || storedKeywords(entry).contains { $0.contains(needle) }
    }

    private func isCustomEntry(_ entry: KeywordLaunchPreset) -> Bool {
        customization.customEntries.contains { $0.id == entry.id }
    }

    private func isDisabled(_ entry: KeywordLaunchPreset) -> Bool {
        customization.disabledEntryIDs.contains(entry.id)
    }

    /// 复选框只反映显式停用开关；关键词是否为空由「关键词」列自己呈现。
    private func enabledBinding(for entry: KeywordLaunchPreset) -> Binding<Bool> {
        Binding(
            get: { !isDisabled(entry) },
            set: { enabled in
                // 用户可能刚改完关键词就点复选框，先把草稿写回去再改开关。
                commitKeywords(for: entry)
                var updated = customization
                if enabled {
                    updated.disabledEntryIDs.remove(entry.id)
                } else {
                    updated.disabledEntryIDs.insert(entry.id)
                }
                viewModel.saveKeywordLaunchCustomization(updated)
            }
        )
    }

    private func storedKeywords(_ entry: KeywordLaunchPreset) -> [String] {
        customization.keywordOverrides[entry.id] ?? entry.keywords
    }

    private func draftBinding(for entry: KeywordLaunchPreset) -> Binding<String> {
        Binding(
            get: { keywordDrafts[entry.id] ?? storedKeywords(entry).joined(separator: ", ") },
            set: { keywordDrafts[entry.id] = $0 }
        )
    }

    private func commitKeywords(for entry: KeywordLaunchPreset) {
        guard let raw = keywordDrafts[entry.id] else { return }
        var updated = customization
        updated.keywordOverrides[entry.id] = Self.splitKeywords(raw)
        viewModel.saveKeywordLaunchCustomization(updated)
        keywordDrafts[entry.id] = nil
    }

    /// 停用的条目不参与搜索，因此不该再报关键词冲突。
    private var conflictWarnings: [String] {
        KeywordLaunchCatalog.builtIn
            .filter { !isDisabled($0) }
            .compactMap { entry in
                let conflicts = KeywordLaunchCatalog.conflictingKeywords(
                    storedKeywords(entry),
                    forEntryID: entry.id,
                    customization: customization
                )
                guard !conflicts.isEmpty else { return nil }
                return "「\(entry.name)」的 \(conflicts.joined(separator: "、")) 已被更靠前的条目占用，实际不会生效。"
            }
    }

    private var canAddCustomEntry: Bool {
        !Self.splitKeywords(newKeyword).isEmpty
            && !newSiteName.trimmingCharacters(in: .whitespaces).isEmpty
            && newURLTemplate.contains("{query}")
    }

    private func addCustomEntry() {
        guard canAddCustomEntry else { return }
        let urlTemplate = newURLTemplate.trimmingCharacters(in: .whitespaces)
        let name = newSiteName.trimmingCharacters(in: .whitespaces)
        let isWeb = newCategory == KeywordLaunchCatalog.webSearchCategory
            || newCategory == KeywordLaunchCatalog.specialistCategory

        var updated = customization
        updated.customEntries.append(KeywordLaunchPreset(
            id: "custom-\(UUID().uuidString)",
            category: newCategory,
            keywords: Self.splitKeywords(newKeyword),
            name: name,
            site: URL(string: urlTemplate)?.host ?? name,
            titlePrefix: isWeb ? "用 \(name) 搜索" : "向 \(name) 提问",
            urlTemplate: urlTemplate,
            typeLabel: isWeb ? "Web Search" : "AI Chat",
            iconSystemName: isWeb ? "globe" : "bubble.left.and.text.bubble.right",
            prefill: newPrefillsURL ? .urlParam : .clipboardAndOpen
        ))
        viewModel.saveKeywordLaunchCustomization(updated)

        newKeyword = ""
        newSiteName = ""
        newURLTemplate = ""
        showingAddEntryForm = false
    }

    private func removeCustomEntry(_ entry: KeywordLaunchPreset) {
        var updated = customization
        updated.customEntries.removeAll { $0.id == entry.id }
        // 一并清掉该条目的关键词覆盖与停用标记，避免留孤儿字段。
        updated.keywordOverrides[entry.id] = nil
        updated.disabledEntryIDs.remove(entry.id)
        keywordDrafts[entry.id] = nil
        viewModel.saveKeywordLaunchCustomization(updated)
    }

    private static func splitKeywords(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func shortcutRecorderRow(label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
                .font(JadeFont.body)
                .foregroundStyle(JadeColor.textPrimary)
            Spacer()
            HotkeyRecorder(
                for: name,
                isConflicting: .constant(viewModel.isShortcutConflict(name)),
                conflictMessage: .constant(viewModel.conflictMessage(for: name))
            )
            .onChange(of: KeyboardShortcuts.getShortcut(for: name)) { _ in
                viewModel.refreshShortcutConflicts()
            }
        }
    }
}
