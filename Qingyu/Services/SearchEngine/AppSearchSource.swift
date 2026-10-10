import AppKit
import CoreData
import Foundation
import os

// MARK: - App source domain models

/// Stable, lightweight app index item used by the Assistant MVP AppSource.
///
/// Icons are represented by the app bundle path in `SearchResultIcon.appIcon`
/// instead of being stored in the index, keeping the in-memory index cheap and
/// hashable while still allowing UI code to render the real app icon lazily.
struct ApplicationIndexItem: Identifiable, Hashable {
    let id: ApplicationID
    let bundleIdentifier: String?
    let displayName: String
    let localizedName: String?
    let path: URL
    let pinyin: String?
    let initials: String?
    let launchCount: Int
    let lastLaunchAt: Date?

    var targetID: String { id.rawValue }
}

protocol AppSourceProtocol: SearchSource {
    func rebuildIndex() async
    func refreshIndex() async
    func application(for id: ApplicationID) -> ApplicationIndexItem?
}

// MARK: - Usage stats

struct UsageStatSnapshot: Hashable {
    let targetID: String
    let targetType: String
    let useCount: Int
    let lastUsedAt: Date?
}

protocol UsageStatRepositoryProtocol: SearchUsageStoreProtocol {
    func usage(targetType: String, targetID: String) async -> UsageStatSnapshot?
    func recordUse(targetType: String, targetID: String) async throws -> UsageStatSnapshot
    /// Most-recently-used stats across all target types, newest first (T-011 command bar home).
    func recentlyUsed(limit: Int) async -> [UsageStatSnapshot]
}

/// Core Data backed UsageStat repository used by AppSource and later CommandSource.
final class UsageStatRepository: UsageStatRepositoryProtocol, @unchecked Sendable {
    static let applicationTargetType = "application"
    static let commandTargetType = "command"

    private let persistence: PersistenceController
    private let now: () -> Date

    init(persistence: PersistenceController = .shared, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
    }

    func usage(targetType: String, targetID: String) async -> UsageStatSnapshot? {
        let context = persistence.viewContext
        return await context.perform {
            do {
                guard let stat = try self.fetch(targetType: targetType, targetID: targetID, in: context) else {
                    return nil
                }
                return Self.snapshot(from: stat)
            } catch {
                return nil
            }
        }
    }

    func recentlyUsed(limit: Int) async -> [UsageStatSnapshot] {
        guard limit > 0 else { return [] }
        let context = persistence.viewContext
        return await context.perform {
            let request = CDUsageStat.fetchRequest()
            request.predicate = NSPredicate(format: "lastUsedAt != nil")
            request.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: false)]
            request.fetchLimit = limit
            let stats = (try? context.fetch(request)) ?? []
            return stats.map(Self.snapshot(from:))
        }
    }

    func recordUse(targetType: String, targetID: String) async throws -> UsageStatSnapshot {
        let context = persistence.viewContext
        return try await context.perform {
            let timestamp = self.now()
            let stat: CDUsageStat
            if let existing = try self.fetch(targetType: targetType, targetID: targetID, in: context) {
                stat = existing
                stat.useCount += 1
                stat.lastUsedAt = timestamp
                stat.updatedAt = timestamp
            } else {
                stat = CDUsageStat(context: context)
                stat.id = UUID()
                stat.targetType = targetType
                stat.targetID = targetID
                stat.useCount = 1
                stat.lastUsedAt = timestamp
                stat.createdAt = timestamp
                stat.updatedAt = timestamp
            }
            if context.hasChanges {
                try context.save()
            }
            return Self.snapshot(from: stat)
        }
    }

    func usageBoost(for resultID: SearchResultID, sourceID: SearchSourceID) async -> Double {
        guard sourceID == .app || sourceID == .command else { return 0 }
        let targetType = sourceID == .app ? Self.applicationTargetType : Self.commandTargetType
        let targetID = Self.targetID(from: resultID, sourceID: sourceID)
        guard let stat = await usage(targetType: targetType, targetID: targetID) else { return 0 }
        return Self.usageBoost(useCount: stat.useCount, lastUsedAt: stat.lastUsedAt, now: now())
    }

    func recordSelection(resultID: SearchResultID, sourceID: SearchSourceID) async {
        guard sourceID == .app || sourceID == .command else { return }
        let targetType = sourceID == .app ? Self.applicationTargetType : Self.commandTargetType
        let targetID = Self.targetID(from: resultID, sourceID: sourceID)
        _ = try? await recordUse(targetType: targetType, targetID: targetID)
    }

    static func usageBoost(useCount: Int, lastUsedAt: Date?, now: Date = Date()) -> Double {
        let frequencyBoost = min(12.0, log(Double(max(0, useCount)) + 1.0) / log(21.0) * 12.0)
        guard let lastUsedAt else { return frequencyBoost }

        let age = max(0, now.timeIntervalSince(lastUsedAt))
        let day: TimeInterval = 24 * 60 * 60
        let recencyBoost: Double
        if age <= day {
            recencyBoost = 8
        } else if age <= 7 * day {
            recencyBoost = 5
        } else if age <= 30 * day {
            recencyBoost = 2
        } else {
            recencyBoost = 0
        }
        return frequencyBoost + recencyBoost
    }

    private func fetch(targetType: String, targetID: String, in context: NSManagedObjectContext) throws -> CDUsageStat? {
        let request = CDUsageStat.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "targetType == %@ AND targetID == %@", targetType, targetID)
        return try context.fetch(request).first
    }

    private static func snapshot(from stat: CDUsageStat) -> UsageStatSnapshot {
        UsageStatSnapshot(
            targetID: stat.targetID,
            targetType: stat.targetType,
            useCount: Int(stat.useCount),
            lastUsedAt: stat.lastUsedAt
        )
    }

    private static func targetID(from resultID: SearchResultID, sourceID: SearchSourceID) -> String {
        let prefix = "\(sourceID.rawValue):"
        if resultID.rawValue.hasPrefix(prefix) {
            return String(resultID.rawValue.dropFirst(prefix.count))
        }
        return resultID.rawValue
    }
}

// MARK: - Application launching

protocol ApplicationLaunching {
    func launchApplication(at url: URL) async throws
}

/// Launches app bundles via NSWorkspace.
///
/// `_LSOpenURLsWithCompletionHandler` can fail with **-600 (`procNotFound`)**
/// even when the target app actually came up — common when a menu-bar
/// (`LSUIElement`) app opens a process that is already running, or when the
/// Launch Services PSN bookkeeping races. Strategy:
/// 1. Activate an already-running instance instead of re-opening.
/// 2. On error, treat a live running app as success.
/// 3. Fall back to the classic `NSWorkspace.open(_:)` path.
struct NSWorkspaceApplicationLauncher: ApplicationLaunching {
    private let logger = Logger.search

    func launchApplication(at url: URL) async throws {
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier

        if let bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            if running.activate(options: [.activateAllWindows]) {
                logger.info("Activated already-running app \(bundleIdentifier, privacy: .public)")
                return
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    let nsError = error as NSError
                    // -600 procNotFound: often a false negative when the app is live.
                    if let bundleIdentifier,
                       !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                        self.logger.info("openApplication error \(nsError.code) but \(bundleIdentifier, privacy: .public) is running; treating as success")
                        continuation.resume()
                        return
                    }
                    // Classic open path is more forgiving for some bundles.
                    if NSWorkspace.shared.open(url) {
                        self.logger.info("openApplication failed (\(nsError.code)); NSWorkspace.open succeeded for \(url.lastPathComponent, privacy: .public)")
                        continuation.resume()
                        return
                    }
                    self.logger.error("Failed to launch \(url.lastPathComponent, privacy: .public): \(nsError.localizedDescription, privacy: .public) code=\(nsError.code)")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Search action executor that launches indexed apps via NSWorkspace and records
/// successful launches in Core Data UsageStat.
final class AppSearchActionExecutor: SearchActionExecutorProtocol {
    private let appSource: AppSourceProtocol
    private let launcher: ApplicationLaunching

    init(appSource: AppSourceProtocol, launcher: ApplicationLaunching = NSWorkspaceApplicationLauncher()) {
        self.appSource = appSource
        self.launcher = launcher
    }

    func execute(_ action: SearchAction) async throws {
        guard case .openApplication(let applicationID) = action else { return }
        guard let app = appSource.application(for: applicationID) else {
            throw NSError(
                domain: "com.freeabyss.qingyusource",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Application not found: \(applicationID.rawValue)"]
            )
        }
        try await launcher.launchApplication(at: app.path)
        if let source = appSource as? AppSearchSource {
            await source.recordApplicationLaunch(applicationID)
        }
    }
}

// MARK: - AppSource

/// Assistant MVP AppSource.
///
/// Scans only `/Applications`, `~/Applications`, and `/System/Applications` by
/// default, indexes `.app` bundles in memory, supports exact/prefix/pinyin/
/// initials/contains/fuzzy matching, and returns stable `app:<id>` result IDs so
/// SearchService blacklist filtering can hide concrete app results.
final class AppSearchSource: AppSourceProtocol {
    let id: SearchSourceID = .app
    let displayName = "Applications"
    let isEnabledInSearch = true

    private let logger = Logger.search
    private let fileManager: FileManager
    private let usageRepository: UsageStatRepositoryProtocol
    private let allowedSearchDirectories: [URL]
    private let lock = UnfairLock()

    private var apps: [ApplicationIndexItem] = []
    private var isReady = false
    private var refreshTimer: Timer?

    init(
        searchDirectories: [URL] = AppSearchSource.defaultSearchDirectories(),
        fileManager: FileManager = .default,
        usageRepository: UsageStatRepositoryProtocol = UsageStatRepository(),
        autoBuildIndex: Bool = true,
        schedulesRefresh: Bool = true
    ) {
        self.fileManager = fileManager
        self.usageRepository = usageRepository
        self.allowedSearchDirectories = searchDirectories.map(Self.standardizedDirectory)

        if autoBuildIndex {
            Task.detached(priority: .utility) { [weak self] in
                await self?.rebuildIndex()
                NotificationCenter.default.post(name: .appSearchIndexReady, object: nil)
            }
        }

        if schedulesRefresh {
            schedulePeriodicRefresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    static func defaultSearchDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }

    func canSearch(query: String) -> Bool {
        SearchTriggerRules.standardMinimumLength(sourceID: .app, query: query)
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if !readySnapshot() {
            await rebuildIndex()
        }

        let snapshot = appSnapshot()
        let matches = rankMatches(query: trimmed, apps: snapshot)
        let results = await buildResults(from: matches)

        logger.info("AppSource search '\(trimmed, privacy: .public)': \(results.count) results")
        return results
    }

    func rebuildIndex() async {
        let start = CFAbsoluteTimeGetCurrent()
        let paths = scanApplicationPaths()
        var indexed: [ApplicationIndexItem] = []
        indexed.reserveCapacity(paths.count)
        for path in paths {
            if let item = await readApplicationIndexItem(from: path) {
                indexed.append(item)
            }
        }

        indexed.sort {
            SearchTextMatcher.normalize($0.displayName) < SearchTextMatcher.normalize($1.displayName)
        }

        let indexedSnapshot = indexed
        lock.withLock {
            apps = indexedSnapshot
            isReady = true
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("Indexed \(indexed.count) applications in \(String(format: "%.1f", elapsed))ms")
    }

    func refreshIndex() async {
        await rebuildIndex()
    }

    func application(for id: ApplicationID) -> ApplicationIndexItem? {
        lock.withLock { apps.first { $0.id == id } }
    }

    func recordApplicationLaunch(_ id: ApplicationID) async {
        guard let item = application(for: id) else { return }
        guard let stat = try? await usageRepository.recordUse(targetType: UsageStatRepository.applicationTargetType, targetID: item.targetID) else {
            return
        }
        updateUsageStats(for: id, stat: stat)
    }

    // MARK: - Scanning

    private func scanApplicationPaths() -> [URL] {
        var seen = Set<String>()
        var paths: [URL] = []

        for directory in allowedSearchDirectories {
            guard isAllowedSearchDirectory(directory) else { continue }
            for appURL in findAppBundles(in: directory) {
                let standardized = Self.standardizedDirectory(appURL)
                guard isAllowedApplicationURL(standardized) else { continue }
                let key = standardized.path
                if seen.insert(key).inserted {
                    paths.append(standardized)
                }
            }
        }
        return paths
    }

    private func findAppBundles(in directory: URL) -> [URL] {
        var result: [URL] = []
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return result
        }

        if directory.pathExtension.lowercased() == "app" {
            return [directory]
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return result
        }

        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension.lowercased() == "app" {
                result.append(url)
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private func readApplicationIndexItem(from appURL: URL) async -> ApplicationIndexItem? {
        guard appURL.pathExtension.lowercased() == "app", isAllowedApplicationURL(appURL) else { return nil }

        let bundle = Bundle(url: appURL)
        let info = bundle?.infoDictionary ?? readInfoPlist(at: appURL)
        let localizedInfo = bundle?.localizedInfoDictionary

        let displayName = firstNonEmptyString([
            info?["CFBundleDisplayName"],
            info?["CFBundleName"],
            appURL.deletingPathExtension().lastPathComponent
        ]) ?? appURL.deletingPathExtension().lastPathComponent

        let localizedName = firstNonEmptyString([
            localizedInfo?["CFBundleDisplayName"],
            localizedInfo?["CFBundleName"]
        ])

        let bundleIdentifier = firstNonEmptyString([info?["CFBundleIdentifier"]])
        let targetID = Self.makeApplicationTargetID(bundleIdentifier: bundleIdentifier, path: appURL)
        let stat = await usageRepository.usage(targetType: UsageStatRepository.applicationTargetType, targetID: targetID)
        let indexName = localizedName ?? displayName

        return ApplicationIndexItem(
            id: ApplicationID(rawValue: targetID),
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            localizedName: localizedName,
            path: appURL,
            pinyin: PinyinHelper.toPinyin(indexName),
            initials: PinyinHelper.toInitials(indexName),
            launchCount: stat?.useCount ?? 0,
            lastLaunchAt: stat?.lastUsedAt
        )
    }

    private func readInfoPlist(at appURL: URL) -> [String: Any]? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private func firstNonEmptyString(_ values: [Any?]) -> String? {
        for value in values {
            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        return nil
    }

    private static func makeApplicationTargetID(bundleIdentifier: String?, path: URL) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        return "path-\(abs(path.standardizedFileURL.path.hashValue))"
    }

    private static func standardizedDirectory(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isAllowedSearchDirectory(_ directory: URL) -> Bool {
        let path = Self.standardizedDirectory(directory).path
        return allowedSearchDirectories.contains { $0.path == path }
    }

    private func isAllowedApplicationURL(_ appURL: URL) -> Bool {
        let standardizedPath = Self.standardizedDirectory(appURL).path
        return allowedSearchDirectories.contains { root in
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            return standardizedPath.hasPrefix(rootPath) && standardizedPath.hasSuffix(".app")
        }
    }

    // MARK: - Matching

    private struct RankedAppMatch {
        let item: ApplicationIndexItem
        let kind: AppMatchKind
    }

    private enum AppMatchKind: Int, Comparable {
        case exact = 0
        case prefix = 1
        case suffix = 2
        case pinyinPrefix = 3
        case wordStart = 4
        case initials = 5
        case contains = 6
        case fuzzy = 7

        static func < (lhs: AppMatchKind, rhs: AppMatchKind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var score: Double {
            switch self {
            case .exact: return 30
            case .prefix: return 24
            case .suffix: return 20
            case .pinyinPrefix: return 17
            case .wordStart: return 16
            case .initials: return 15
            case .contains: return 12
            case .fuzzy: return 4
            }
        }
    }

    private func rankMatches(query: String, apps: [ApplicationIndexItem]) -> [RankedAppMatch] {
        let normalizedQuery = SearchTextMatcher.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var matches: [RankedAppMatch] = []
        for item in apps {
            if let kind = directMatchKind(query: normalizedQuery, item: item) {
                matches.append(RankedAppMatch(item: item, kind: kind))
            } else if isFuzzyMatch(query: normalizedQuery, item: item) {
                matches.append(RankedAppMatch(item: item, kind: .fuzzy))
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if lhs.item.launchCount != rhs.item.launchCount { return lhs.item.launchCount > rhs.item.launchCount }
            switch (lhs.item.lastLaunchAt, rhs.item.lastLaunchAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let left = lhs.item.localizedName ?? lhs.item.displayName
                let right = rhs.item.localizedName ?? rhs.item.displayName
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
        }
    }

    private func directMatchKind(query normalizedQuery: String, item: ApplicationIndexItem) -> AppMatchKind? {
        let title = item.localizedName ?? item.displayName
        // Bundle ids are reverse-DNS (`com.apple.iWork.Keynote`). Only the last
        // segment is a useful search token — earlier segments are noise that
        // caused false hits like `work` → Keynote via `iWork`.
        let aliases = [item.displayName, item.localizedName, item.bundleIdentifier.map(Self.lastBundleIdentifierComponent)]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != title }
        let candidate = SearchTextCandidate(
            text: title,
            aliases: aliases,
            pinyin: item.pinyin,
            initials: item.initials
        )
        guard let match = SearchTextMatcher.match(query: normalizedQuery, candidate: candidate) else { return nil }
        switch match {
        case .exact:
            return .exact
        case .prefix, .alias:
            return .prefix
        case .suffix:
            return .suffix
        case .pinyinPrefix:
            return .pinyinPrefix
        case .wordStart:
            return .wordStart
        case .initials:
            return .initials
        case .contains, .aliasContains, .pinyinContains:
            return .contains
        }
    }

    /// Last reverse-DNS segment of a bundle id (`com.apple.iWork.Keynote` → `Keynote`).
    static func lastBundleIdentifierComponent(_ bundleIdentifier: String) -> String {
        bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    }

    private func isFuzzyMatch(query: String, item: ApplicationIndexItem) -> Bool {
        guard query.count >= 3 else { return false }
        let title = SearchTextMatcher.normalize(item.localizedName ?? item.displayName)
        let maxDistance = min(2, max(1, query.count / 4))
        return levenshteinDistance(query, title) <= maxDistance
    }

    private func buildResults(from matches: [RankedAppMatch]) async -> [SearchResult] {
        var results: [SearchResult] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            let latestStat = await usageRepository.usage(targetType: UsageStatRepository.applicationTargetType, targetID: match.item.targetID)
            let usageScore = UsageStatRepository.usageBoost(
                useCount: latestStat?.useCount ?? match.item.launchCount,
                lastUsedAt: latestStat?.lastUsedAt ?? match.item.lastLaunchAt
            )
            let title = (match.item.localizedName ?? match.item.displayName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            results.append(SearchResult(
                id: SearchResultID(rawValue: "app:\(match.item.targetID)"),
                sourceID: .app,
                title: title,
                subtitle: match.item.path.path,
                icon: .appIcon(match.item.path),
                typeLabel: "Application",
                baseScore: SourcePriority.application,
                matchScore: match.kind.score,
                usageScore: usageScore,
                primaryAction: .openApplication(match.item.id),
                secondaryActions: []
            ))
        }
        return results
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    // MARK: - State helpers

    private func readySnapshot() -> Bool {
        lock.withLock { isReady }
    }

    private func appSnapshot() -> [ApplicationIndexItem] {
        lock.withLock { apps }
    }

    private func updateUsageStats(for id: ApplicationID, stat: UsageStatSnapshot) {
        lock.withLock {
            apps = apps.map { item in
                guard item.id == id else { return item }
                return ApplicationIndexItem(
                    id: item.id,
                    bundleIdentifier: item.bundleIdentifier,
                    displayName: item.displayName,
                    localizedName: item.localizedName,
                    path: item.path,
                    pinyin: item.pinyin,
                    initials: item.initials,
                    launchCount: stat.useCount,
                    lastLaunchAt: stat.lastUsedAt
                )
            }
        }
    }

    private func schedulePeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { [weak self] in
                await self?.refreshIndex()
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the application search index is first built.
    static let appSearchIndexReady = Notification.Name("com.freeabyss.qingyuSearchIndexReady")
}
