import Foundation
import AppKit
import UniformTypeIdentifiers
import os

/// A single indexed file entry held in the in-memory cache.
///
/// The cache is intentionally lightweight: we keep the display name, absolute
/// path, pre-normalized name/path (for case- and diacritic-insensitive matching),
/// the UTI, size, and modification date. Icons are resolved lazily by the UI via
/// `SearchResultIcon.appIcon(url)` (`NSWorkspace.shared.icon(forFile:)`), so we do
/// not retain `NSImage` instances in the index.
struct FileIndexItem: Hashable {
    let name: String
    let path: URL
    /// Folded (case/diacritic/width-insensitive, lowercased) file name.
    let normalizedName: String
    /// Folded absolute path, used for path-substring matching.
    let normalizedPath: String
    let contentType: String
    let size: Int64
    let modifiedDate: Date
}

/// File search source contract (design §3.2 / api.md §5).
///
/// v1.2 indexes a fixed set of user directories (`~/Desktop`, `~/Documents`,
/// `~/Downloads`) once, in the background, into an in-memory cache. FS-watching /
/// incremental indexing is deferred to V1.x.
protocol FileSearchSourceProtocol: SearchSource {
    /// Default index roots: `~/Desktop`, `~/Documents`, `~/Downloads`.
    var indexedRoots: [URL] { get }

    /// Rebuild the in-memory file index from `indexedRoots`.
    func rebuildIndex() async
}

/// Search source for local files under the user's common directories.
///
/// - Scope: `~/Desktop`, `~/Documents`, `~/Downloads` (fixed in v1.2; the
///   `SettingKey.fileSearchPaths` extension point is reserved for V1.x).
/// - Indexing: a one-shot `FileManager.enumerator` walk on a background queue at
///   construction time, cached in memory. No FS monitoring in v1.2.
/// - Matching: case- and diacritic-insensitive substring match on the file name
///   or absolute path. No pinyin (FR-SEARCH-13), no content full-text search.
/// - Trigger: at least 2 characters (FR-SEARCH-FILE-7 / FR-SEARCH-17).
/// - Weight: `SourcePriority.file` = 75 (FR-SEARCH-11).
/// - Actions: ⏎ open with the default app, ⌘R reveal in Finder, ⌘C copy the path.
final class FileSearchSource: FileSearchSourceProtocol {
    let id: SearchSourceID = .file
    let displayName = "Files"
    let isEnabledInSearch = true
    let indexedRoots: [URL]

    private let logger = Logger.search
    private let fileManager: FileManager
    private let homeDirectory: URL

    /// Upper bound on cached files to keep memory and scan time bounded. A typical
    /// user's three folders stay well under this; the cap protects pathological
    /// cases (e.g. a huge Downloads tree).
    private let maxIndexedFiles: Int

    /// Maximum recursion depth relative to each root.
    private let maxDepth: Int

    /// Per-source result cap.
    private let resultLimit: Int

    private let lock = OSAllocatedUnfairLock()
    private var items: [FileIndexItem] = []
    private var isReady = false

    // MARK: - Init

    init(
        roots: [URL] = FileSearchSource.defaultRoots(),
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        maxIndexedFiles: Int = 100_000,
        maxDepth: Int = 8,
        resultLimit: Int = SearchService.defaultResultLimit,
        autoBuildIndex: Bool = true
    ) {
        self.indexedRoots = roots.map { $0.standardizedFileURL }
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.maxIndexedFiles = maxIndexedFiles
        self.maxDepth = maxDepth
        self.resultLimit = resultLimit

        if autoBuildIndex {
            Task.detached(priority: .utility) { [weak self] in
                await self?.rebuildIndex()
                NotificationCenter.default.post(name: .fileSearchIndexReady, object: nil)
            }
        }
    }

    /// Default index roots derived from the user's home directory.
    static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true)
        ]
    }

    // MARK: - SearchSource

    func canSearch(query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        // Warm up the index lazily on first query if the background build has not
        // finished. Other sources are unaffected because SearchService fans out
        // concurrently.
        if !readySnapshot() {
            await rebuildIndex()
        }

        let normalizedQuery = Self.normalize(trimmed)
        guard !normalizedQuery.isEmpty else { return [] }

        let snapshot = itemsSnapshot()

        var scored: [(item: FileIndexItem, match: Double)] = []
        scored.reserveCapacity(min(snapshot.count, resultLimit * 4))
        for item in snapshot {
            guard let match = matchScore(item: item, query: normalizedQuery) else { continue }
            scored.append((item, match))
        }

        // Rank by match quality (prefix > contains > path), then by recency.
        scored.sort { lhs, rhs in
            if lhs.match != rhs.match { return lhs.match > rhs.match }
            return lhs.item.modifiedDate > rhs.item.modifiedDate
        }

        let results = scored.prefix(resultLimit).map { makeResult(item: $0.item, matchScore: $0.match) }
        logger.info("FileSearchSource '\(trimmed, privacy: .public)': \(results.count) results (index=\(snapshot.count))")
        return results
    }

    // MARK: - Indexing

    func rebuildIndex() async {
        let start = CFAbsoluteTimeGetCurrent()
        var indexed: [FileIndexItem] = []
        var seen = Set<String>()

        for root in indexedRoots {
            if indexed.count >= maxIndexedFiles { break }
            scan(root: root, into: &indexed, seen: &seen)
        }

        let indexedSnapshot = indexed
        lock.withLock {
            items = indexedSnapshot
            isReady = true
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("FileSearchSource indexed \(indexed.count) files in \(String(format: "%.1f", elapsed))ms")
    }

    /// Enumerate a single root directory, appending regular files to `indexed`.
    ///
    /// Excludes hidden files/directories, package (bundle) contents, and the
    /// bundles themselves (e.g. `.app`, `.pkg`). Enforces `maxDepth` and the
    /// global `maxIndexedFiles` cap.
    private func scan(root: URL, into indexed: inout [FileIndexItem], seen: inout Set<String>) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentTypeKey,
            .nameKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        while let url = enumerator.nextObject() as? URL {
            if indexed.count >= maxIndexedFiles { break }

            // Depth guard relative to the root.
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))

            // Skip bundles/packages entirely (their contents are already skipped).
            if values?.isPackage == true { continue }

            // Only index regular files (directories are traversed but not indexed).
            guard values?.isRegularFile == true else { continue }

            let standardizedPath = url.standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted else { continue }

            let name = values?.name ?? url.lastPathComponent
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? Date.distantPast
            let uti = values?.contentType?.identifier ?? "public.data"

            indexed.append(FileIndexItem(
                name: name,
                path: url,
                normalizedName: Self.normalize(name),
                normalizedPath: Self.normalize(standardizedPath),
                contentType: uti,
                size: size,
                modifiedDate: modified
            ))
        }
    }

    // MARK: - Matching

    /// Returns a match score in the 0–30 band (aligned with the other sources'
    /// `matchScore`) or `nil` if the item does not match the query.
    ///
    /// Tiers (name matching wins over path matching):
    /// - exact name: 30
    /// - name prefix: 24
    /// - name contains: 18
    /// - path contains: 10
    /// A small recency bonus (0–4) breaks ties toward recently modified files.
    private func matchScore(item: FileIndexItem, query: String) -> Double? {
        let base: Double
        if item.normalizedName == query {
            base = 30
        } else if item.normalizedName.hasPrefix(query) {
            base = 24
        } else if item.normalizedName.contains(query) {
            base = 18
        } else if item.normalizedPath.contains(query) {
            base = 10
        } else {
            return nil
        }
        return base + recencyBonus(for: item.modifiedDate)
    }

    private func recencyBonus(for date: Date) -> Double {
        let days = Date().timeIntervalSince(date) / 86_400
        if days < 1 { return 4 }
        if days < 7 { return 3 }
        if days < 30 { return 1 }
        return 0
    }

    // MARK: - Result building

    private func makeResult(item: FileIndexItem, matchScore: Double) -> SearchResult {
        SearchResult(
            id: SearchResultID(rawValue: "file:\(item.path.path)"),
            sourceID: .file,
            title: item.name,
            subtitle: subtitle(for: item),
            icon: .appIcon(item.path),
            typeLabel: L10n.localized("searchPanel.type.file"),
            baseScore: SourcePriority.file,
            matchScore: matchScore,
            usageScore: 0,
            // 默认动作：在 Finder 中打开文件所在目录并选中该文件；直接打开为次动作。
            primaryAction: .revealInFinder(item.path),
            secondaryActions: [.openFile(item.path), .copyText(item.path.path)]
        )
    }

    /// Human-readable subtitle: the file's location relative to the home directory
    /// (e.g. `~/Downloads`), followed by size and relative modification time.
    private func subtitle(for item: FileIndexItem) -> String {
        var parts: [String] = [displayLocation(for: item.path)]

        if item.size > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            parts.append(formatter.string(fromByteCount: item.size))
        }

        return parts.joined(separator: " · ")
    }

    /// Location label for the parent directory, abbreviated with `~` when inside
    /// the home directory.
    private func displayLocation(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let parentPath = parent.path
        let homePath = homeDirectory.path
        if parentPath == homePath {
            return "~"
        }
        if parentPath.hasPrefix(homePath + "/") {
            return "~" + parentPath.dropFirst(homePath.count)
        }
        return parentPath
    }

    // MARK: - Snapshot helpers

    private func readySnapshot() -> Bool {
        lock.withLock { isReady }
    }

    private func itemsSnapshot() -> [FileIndexItem] {
        lock.withLock { items }
    }

    // MARK: - Normalization

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the file search index is first built.
    static let fileSearchIndexReady = Notification.Name("com.assistant.fileSearchIndexReady")
}
