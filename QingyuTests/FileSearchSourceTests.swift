import XCTest
@testable import Qingyu

final class FileSearchSourceTests: XCTestCase {
    private var tempRoot: URL!
    private var desktop: URL!
    private var documents: URL!
    private var downloads: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fm = FileManager.default
        tempRoot = fm.temporaryDirectory
            .appendingPathComponent("FileSearchSourceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        desktop = tempRoot.appendingPathComponent("Desktop", isDirectory: true)
        documents = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        downloads = tempRoot.appendingPathComponent("Downloads", isDirectory: true)
        for dir in [desktop, documents, downloads] {
            try fm.createDirectory(at: dir!, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func write(_ name: String, in directory: URL, contents: String = "x") throws {
        let url = directory.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
    }

    private func makeSource() -> FileSearchSource {
        FileSearchSource(
            roots: [desktop, documents, downloads],
            homeDirectory: tempRoot,
            autoBuildIndex: false
        )
    }

    // MARK: - Indexing

    func testIndexesAllThreeDirectories() async throws {
        try write("desktop-report.pdf", in: desktop)
        try write("documents-notes.txt", in: documents)
        try write("downloads-installer.dmg", in: downloads)

        let source = makeSource()
        await source.rebuildIndex()

        let desktopHit = await source.search(query: "desktop-report")
        let documentsHit = await source.search(query: "documents-notes")
        let downloadsHit = await source.search(query: "downloads-installer")

        XCTAssertEqual(desktopHit.first?.title, "desktop-report.pdf")
        XCTAssertEqual(documentsHit.first?.title, "documents-notes.txt")
        XCTAssertEqual(downloadsHit.first?.title, "downloads-installer.dmg")
    }

    func testSearchReturnsCorrectResultAndActions() async throws {
        try write("quarterly-budget.xlsx", in: documents)
        let source = makeSource()
        await source.rebuildIndex()

        let results = await source.search(query: "budget")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.title, "quarterly-budget.xlsx")
        XCTAssertEqual(result.sourceID, .file)

        // 默认动作在 Finder 中打开文件所在目录并选中文件；直接打开与复制路径为次动作。
        // Compare by resolved path since the enumerator resolves the /var → /private/var symlink.
        guard case .revealInFinder(let revealURL) = result.primaryAction else {
            return XCTFail("primary action should be revealInFinder, got \(result.primaryAction)")
        }
        XCTAssertEqual(revealURL.lastPathComponent, "quarterly-budget.xlsx")

        let hasOpen = result.secondaryActions.contains {
            if case .openFile(let url) = $0 { return url.lastPathComponent == "quarterly-budget.xlsx" }
            return false
        }
        let hasCopyPath = result.secondaryActions.contains {
            if case .copyText(let path) = $0 { return path == revealURL.path }
            return false
        }
        XCTAssertTrue(hasOpen, "should offer direct open")
        XCTAssertTrue(hasCopyPath, "should offer copy-path")
    }

    // MARK: - Weight

    func testWeightIsSeventyFive() async throws {
        try write("weighted-file.txt", in: desktop)
        let source = makeSource()
        await source.rebuildIndex()

        let weighted = await source.search(query: "weighted")
        let result = try XCTUnwrap(weighted.first)
        XCTAssertEqual(result.baseScore, 75)
        XCTAssertEqual(result.baseScore, SourcePriority.file)
    }

    // MARK: - Minimum trigger length

    func testMinimumTwoCharactersToTrigger() async throws {
        try write("ab-file.txt", in: desktop)
        let source = makeSource()
        await source.rebuildIndex()

        XCTAssertFalse(source.canSearch(query: "a"))
        XCTAssertFalse(source.canSearch(query: " "))
        XCTAssertTrue(source.canSearch(query: "ab"))

        let tooShort = await source.search(query: "a")
        XCTAssertTrue(tooShort.isEmpty)

        let longEnough = await source.search(query: "ab")
        XCTAssertFalse(longEnough.isEmpty)
    }

    // MARK: - isEnabled toggle (via SettingsBackedSearchSource)

    func testIsEnabledToggleGatesResults() async throws {
        try write("toggle-target.txt", in: documents)
        let fileSource = makeSource()
        await fileSource.rebuildIndex()

        let settings = MockToggleSettingsService(enabled: true)
        let wrapped = SettingsBackedSearchSource(
            source: fileSource,
            settingsService: settings,
            settingKey: .fileSourceEnabled
        )

        let visible = await wrapped.search(query: "toggle-target")
        XCTAssertEqual(visible.first?.title, "toggle-target.txt")

        await settings.setEnabled(false)
        let hidden = await wrapped.search(query: "toggle-target")
        XCTAssertTrue(hidden.isEmpty)

        await settings.setEnabled(true)
        let restored = await wrapped.search(query: "toggle-target")
        XCTAssertEqual(restored.first?.title, "toggle-target.txt")
    }

    // MARK: - Matching semantics

    func testCaseAndDiacriticInsensitiveMatch() async throws {
        try write("Résumé-Final.PDF", in: documents)
        let source = makeSource()
        await source.rebuildIndex()

        let lower = await source.search(query: "resume")
        XCTAssertEqual(lower.first?.title, "Résumé-Final.PDF")

        let upper = await source.search(query: "FINAL")
        XCTAssertEqual(upper.first?.title, "Résumé-Final.PDF")
    }

    func testPrefixMatchRanksAboveContainsMatch() async throws {
        try write("report-yearly.txt", in: desktop)       // prefix match for "report"
        try write("annual-report.txt", in: desktop)        // contains match for "report"
        let source = makeSource()
        await source.rebuildIndex()

        let results = await source.search(query: "report")
        XCTAssertEqual(results.first?.title, "report-yearly.txt")
    }

    // MARK: - Exclusions

    func testSkipsHiddenFiles() async throws {
        try write(".hidden-secret.txt", in: desktop)
        try write("visible-secret.txt", in: desktop)
        let source = makeSource()
        await source.rebuildIndex()

        let results = await source.search(query: "secret")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "visible-secret.txt")
    }

    func testDoesNotIndexBundleContents() async throws {
        // Simulate a .app bundle: a package directory with inner content.
        let bundle = desktop.appendingPathComponent("MyApp.app", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try write("MyApp-binary", in: macOS)

        let source = makeSource()
        await source.rebuildIndex()

        // Inner bundle content must not be indexed.
        let innerHit = await source.search(query: "MyApp-binary")
        XCTAssertTrue(innerHit.isEmpty)
    }

    func testDefaultRootsAreDesktopDocumentsDownloads() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let roots = FileSearchSource.defaultRoots(home: home).map { $0.lastPathComponent }
        XCTAssertEqual(roots, ["Desktop", "Documents", "Downloads"])
    }
}

/// Minimal in-memory `SettingsServiceProtocol` used to exercise the file-source
/// enable toggle without spinning up a Core Data stack (which would contend with
/// other tests' in-memory stores under parallel execution).
private actor MockToggleSettingsService: SettingsServiceProtocol {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func setEnabled(_ value: Bool) {
        enabled = value
    }

    func value<T: Decodable & Sendable>(for key: SettingKey, as type: T.Type) async throws -> T {
        if type == Bool.self, let value = enabled as? T { return value }
        throw SettingsServiceError.missingDefault(key.rawValue)
    }

    func set<T: Encodable & Sendable>(_ value: T, for key: SettingKey) async throws {
        if let boolValue = value as? Bool { enabled = boolValue }
    }

    func reset(key: SettingKey) async throws {
        enabled = true
    }

    func stringValue(for key: SettingKey) async throws -> String {
        enabled ? "true" : "false"
    }
}
