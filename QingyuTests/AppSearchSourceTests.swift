import XCTest
@testable import Qingyu

final class AppSearchSourceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var persistence: PersistenceController!
    private var usageRepository: UsageStatRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSearchSourceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let fileSystem = AssistantFileSystem(rootDirectory: temporaryRoot.appendingPathComponent("Support", isDirectory: true))
        persistence = PersistenceController(storeConfiguration: .temporary, fileSystem: fileSystem)
        try persistence.load()
        usageRepository = UsageStatRepository(persistence: persistence, now: { Date(timeIntervalSince1970: 1_000) })
    }

    override func tearDownWithError() throws {
        persistence = nil
        usageRepository = nil
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testDefaultSearchDirectoriesAreStrictMVPDirectories() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = AppSearchSource.defaultSearchDirectories(homeDirectory: home).map(\.path)

        XCTAssertEqual(paths, [
            "/Applications",
            "/Users/tester/Applications",
            "/System/Applications"
        ])
    }

    func testRebuildIndexScansOnlyConfiguredApplicationDirectoriesAndBuildsApplicationIndexItems() async throws {
        let localApplications = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
        let userApplications = temporaryRoot.appendingPathComponent("Users/me/Applications", isDirectory: true)
        let systemApplications = temporaryRoot.appendingPathComponent("System/Applications", isDirectory: true)
        let outside = temporaryRoot.appendingPathComponent("Downloads", isDirectory: true)
        try [localApplications, userApplications, systemApplications, outside].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        try makeApp(named: "Calendar", bundleID: "com.example.calendar", in: localApplications)
        try makeApp(named: "Notes", bundleID: "com.example.notes", in: userApplications)
        try makeApp(named: "System Settings", bundleID: "com.example.settings", in: systemApplications)
        try makeApp(named: "Outside", bundleID: "com.example.outside", in: outside)

        let source = makeSource(searchDirectories: [localApplications, userApplications, systemApplications])
        await source.rebuildIndex()

        let results = await source.search(query: "e")
        let titles = Set(results.map(\.title))

        XCTAssertTrue(titles.contains("Calendar"))
        XCTAssertTrue(titles.contains("Notes"))
        XCTAssertTrue(titles.contains("System Settings"))
        XCTAssertFalse(titles.contains("Outside"))
        XCTAssertEqual(source.application(for: ApplicationID(rawValue: "com.example.notes"))?.bundleIdentifier, "com.example.notes")
        XCTAssertEqual(source.application(for: ApplicationID(rawValue: "com.example.notes"))?.pinyin, "notes")
        XCTAssertEqual(source.application(for: ApplicationID(rawValue: "com.example.notes"))?.initials, "n")
    }

    func testSearchSupportsExactPrefixPinyinInitialsContainsAndFuzzyMatches() async throws {
        let apps = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try makeApp(named: "Safari", bundleID: "com.example.safari", in: apps)
        try makeApp(named: "Notes", bundleID: "com.example.notes", in: apps)
        try makeApp(named: "My Player", bundleID: "com.example.player", in: apps)
        try makeApp(named: "微信", bundleID: "com.example.wechat", in: apps)

        let source = makeSource(searchDirectories: [apps])
        await source.rebuildIndex()

        let exact = await source.search(query: "Safari")
        let prefix = await source.search(query: "Saf")
        let pinyin = await source.search(query: "weix")
        let initials = await source.search(query: "wx")
        let contains = await source.search(query: "Player")
        let fuzzy = await source.search(query: "Safri")

        XCTAssertEqual(exact.first?.title, "Safari")
        XCTAssertEqual(prefix.first?.title, "Safari")
        XCTAssertEqual(pinyin.first?.title, "微信")
        XCTAssertEqual(initials.first?.title, "微信")
        XCTAssertTrue(contains.contains { $0.title == "My Player" })
        XCTAssertTrue(fuzzy.contains { $0.title == "Safari" })
    }

    func testSearchServiceBlacklistHidesConcreteAppResultAndRemovalRestoresIt() async throws {
        let apps = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try makeApp(named: "Notes", bundleID: "com.example.notes", in: apps)

        let source = makeSource(searchDirectories: [apps])
        await source.rebuildIndex()
        let blacklist = SearchBlacklistRepository(persistence: persistence)
        let service = SearchService(sources: [source], blacklistChecker: blacklist)

        let before = await service.search(query: "Notes")
        let notes = try XCTUnwrap(before.results.first)
        XCTAssertEqual(notes.id.rawValue, "app:com.example.notes")

        _ = try await blacklist.add(result: notes)
        let hidden = await service.search(query: "Notes")
        XCTAssertFalse(hidden.results.contains { $0.id == notes.id })

        try await blacklist.remove(sourceID: .app, resultID: notes.id)
        let restored = await service.search(query: "Notes")
        XCTAssertTrue(restored.results.contains { $0.id == notes.id })
    }

    func testRecordApplicationLaunchPersistsUsageStatAndAffectsOrdering() async throws {
        let apps = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try makeApp(named: "Alpha Notes", bundleID: "com.example.alpha", in: apps)
        try makeApp(named: "Beta Notes", bundleID: "com.example.beta", in: apps)

        let source = makeSource(searchDirectories: [apps])
        await source.rebuildIndex()

        await source.recordApplicationLaunch(ApplicationID(rawValue: "com.example.beta"))
        await source.recordApplicationLaunch(ApplicationID(rawValue: "com.example.beta"))

        let stat = await usageRepository.usage(targetType: UsageStatRepository.applicationTargetType, targetID: "com.example.beta")
        XCTAssertEqual(stat?.useCount, 2)
        XCTAssertEqual(stat?.lastUsedAt, Date(timeIntervalSince1970: 1_000))

        let results = await source.search(query: "Notes")
        XCTAssertEqual(results.first?.title, "Beta Notes")
        XCTAssertGreaterThan(results.first?.usageScore ?? 0, 0)
    }

    func testAppSearchActionExecutorLaunchesViaMacOSAPIAndRecordsUsage() async throws {
        let apps = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let appURL = try makeApp(named: "Notes", bundleID: "com.example.notes", in: apps)

        let source = makeSource(searchDirectories: [apps])
        await source.rebuildIndex()
        let launcher = RecordingLauncher()
        let executor = AppSearchActionExecutor(appSource: source, launcher: launcher)

        try await executor.execute(.openApplication(ApplicationID(rawValue: "com.example.notes")))

        let launchedURLs = await launcher.launchedURLsSnapshot()
        XCTAssertEqual(launchedURLs, [appURL.standardizedFileURL.resolvingSymlinksInPath()])
        let stat = await usageRepository.usage(targetType: UsageStatRepository.applicationTargetType, targetID: "com.example.notes")
        XCTAssertEqual(stat?.useCount, 1)
    }

    private func makeSource(searchDirectories: [URL]) -> AppSearchSource {
        AppSearchSource(
            searchDirectories: searchDirectories,
            usageRepository: usageRepository,
            autoBuildIndex: false,
            schedulesRefresh: false
        )
    }

    @discardableResult
    private func makeApp(named name: String, bundleID: String, in directory: URL) throws -> URL {
        let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleName": name,
            "CFBundleIdentifier": bundleID,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private actor RecordingLauncher: ApplicationLaunching {
    private var launchedURLs: [URL] = []

    func launchApplication(at url: URL) async throws {
        launchedURLs.append(url.standardizedFileURL.resolvingSymlinksInPath())
    }

    func launchedURLsSnapshot() -> [URL] {
        launchedURLs
    }
}
