import XCTest
@testable import Qingniao

final class SystemCommandSourceTests: XCTestCase {
    func testAllFifteenMVPCommandsAreDefinedAndSearchable() async {
        let source = SystemCommandSource()
        let expectedIDs: [CommandID] = [
            .openSystemSettings,
            .openAppSettings,
            .openDownloads,
            .openApplications,
            .openDesktop,
            .captureRegion,
            .captureFullScreen,
            .captureWindow,
            .openClipboardHistory,
            .clearClipboardHistory,
            .toggleClipboardRecording,
            .checkPermissions,
            .restartFinder,
            .restartDock,
            .toggleAppearance
        ]

        XCTAssertEqual(source.commands.count, 15)
        XCTAssertEqual(Set(source.commands.map(\.id)), Set(expectedIDs))

        for command in source.commands {
            let results = await source.search(query: command.englishName)
            XCTAssertTrue(results.contains { $0.id == SearchResultID(rawValue: "command:\(command.id.rawValue)") }, "Expected \(command.id.rawValue) to be searchable by English name")
            XCTAssertEqual(results.first { $0.id == SearchResultID(rawValue: "command:\(command.id.rawValue)") }?.primaryAction, .runCommand(command.id))
        }
    }

    func testCommandsHaveChineseEnglishAliasesPinyinAndInitials() {
        let source = SystemCommandSource()

        for command in source.commands {
            XCTAssertFalse(command.chineseName.isEmpty)
            XCTAssertFalse(command.englishName.isEmpty)
            XCTAssertFalse(command.chineseAliases.isEmpty, "\(command.id.rawValue) should have Chinese aliases")
            XCTAssertFalse(command.englishAliases.isEmpty, "\(command.id.rawValue) should have English aliases")
            XCTAssertFalse(command.pinyin.isEmpty, "\(command.id.rawValue) should have pinyin")
            XCTAssertFalse(command.initials.isEmpty, "\(command.id.rawValue) should have initials")
        }
    }

    func testChineseEnglishPinyinAndInitialsMatching() async {
        let source = SystemCommandSource()

        let chinese = await source.search(query: "下载")
        let english = await source.search(query: "downloads")
        let pinyin = await source.search(query: "dakaixiazai")
        let initials = await source.search(query: "dkxz")

        XCTAssertTrue(chinese.containsCommand(.openDownloads))
        XCTAssertTrue(english.containsCommand(.openDownloads))
        XCTAssertTrue(pinyin.containsCommand(.openDownloads))
        XCTAssertTrue(initials.containsCommand(.openDownloads))
    }

    func testBilingualCommandSearchDoesNotDependOnInterfaceLanguage() async {
        let source = SystemCommandSource()
        let savedLanguages = UserDefaults.standard.array(forKey: "AppleLanguages")
        defer {
            if let savedLanguages {
                UserDefaults.standard.set(savedLanguages, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }

        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        let englishQueryInChineseUI = await source.search(query: "capture window")

        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        let chineseQueryInEnglishUI = await source.search(query: "窗口截图")

        XCTAssertTrue(englishQueryInChineseUI.containsCommand(.captureWindow))
        XCTAssertTrue(chineseQueryInEnglishUI.containsCommand(.captureWindow))
    }

    func testConfirmationFlagsMatchMVPRequirements() {
        let source = SystemCommandSource()
        let confirmationRequired = Set(source.commands.filter(\.requiresConfirmation).map(\.id))

        XCTAssertEqual(confirmationRequired, [.clearClipboardHistory, .restartFinder, .restartDock])
        XCTAssertFalse(source.commands.first { $0.id == .toggleAppearance }?.requiresConfirmation ?? true)
    }

    func testDangerousCommandsAndArbitraryShellAreNotSearchable() async {
        let source = SystemCommandSource()
        let dangerousQueries = [
            "shutdown",
            "关机",
            "reboot",
            "重启系统",
            "logout",
            "注销",
            "sudo rm -rf /",
            "rm -rf",
            "killall Finder",
            "kill process",
            "osascript -e",
            "任意 shell"
        ]

        for query in dangerousQueries {
            let results = await source.search(query: query)
            XCTAssertTrue(results.isEmpty, "Dangerous query should not return executable command: \(query)")
        }
    }

    func testSearchReturnsOnlyWhitelistCommands() async throws {
        let source = SystemCommandSource()
        let results = await source.search(query: "截图")

        XCTAssertFalse(results.isEmpty)
        for result in results {
            guard case .runCommand(let commandID) = result.primaryAction else {
                XCTFail("Command result should use runCommand action")
                continue
            }
            XCTAssertTrue(AssistantCommandCatalog.allowedIDs.contains(commandID))
            XCTAssertNotEqual(commandID.rawValue, "shutdown")
            XCTAssertNotEqual(commandID.rawValue, "restart")
        }
    }

    func testExecutorRequiresConfirmationBeforeMediumRiskCommands() async throws {
        let spy = SpyClipboardHistoryService()
        let executor = SystemCommandExecutor(clipboardHistoryService: spy)

        XCTAssertTrue(executor.requiresConfirmation(.clearClipboardHistory))
        XCTAssertTrue(executor.requiresConfirmation(.restartFinder))
        XCTAssertTrue(executor.requiresConfirmation(.restartDock))
        XCTAssertFalse(executor.requiresConfirmation(.toggleAppearance))

        do {
            try await executor.execute(.clearClipboardHistory, confirmed: false)
            XCTFail("Expected confirmationRequired error")
        } catch AssistantCommandExecutionError.confirmationRequired(let id) {
            XCTAssertEqual(id, .clearClipboardHistory)
        }
        XCTAssertFalse(spy.didClear)

        try await executor.execute(.clearClipboardHistory, confirmed: true)
        XCTAssertTrue(spy.didClear)
    }

    func testOpenClipboardHistoryPostsDedicatedNotification() async throws {
        let center = NotificationCenter()
        let executor = SystemCommandExecutor(notificationCenter: center)
        let expectation = expectation(
            forNotification: .commandOpenClipboardHistory,
            object: nil,
            notificationCenter: center
        ) { _ in
            XCTAssertTrue(Thread.isMainThread)
            return true
        }

        try await executor.execute(.openClipboardHistory)

        await fulfillment(of: [expectation], timeout: 0.1)
    }

    func testCommandSearchActionExecutorCancelsWhenConfirmationDenied() async throws {
        let commandExecutor = SpyCommandExecutor(requiresConfirmationIDs: [.restartDock])
        let confirmation = StubConfirmationProvider(result: false)
        let executor = CommandSearchActionExecutor(commandExecutor: commandExecutor, confirmationProvider: confirmation)

        try await executor.execute(.runCommand(.restartDock))

        XCTAssertTrue(confirmation.requestedCommands.map(\.id).contains(.restartDock))
        XCTAssertTrue(commandExecutor.executions.isEmpty)
    }

    func testCommandSearchActionExecutorRecordsConfirmedExecution() async throws {
        let commandExecutor = SpyCommandExecutor(requiresConfirmationIDs: [.restartDock])
        let confirmation = StubConfirmationProvider(result: true)
        let executor = CommandSearchActionExecutor(commandExecutor: commandExecutor, confirmationProvider: confirmation)

        try await executor.execute(.runCommand(.restartDock))

        XCTAssertEqual(commandExecutor.executions.count, 1)
        XCTAssertEqual(commandExecutor.executions.first?.0, .restartDock)
        XCTAssertEqual(commandExecutor.executions.first?.1, true)
    }

    func testSearchServiceUsageStatsBoostCommandsAfterSelection() async {
        let source = SystemCommandSource()
        let usage = InMemorySearchUsageStore(now: { Date(timeIntervalSince1970: 1_000) })
        let service = SearchService(sources: [source], usageStore: usage)

        let before = await service.search(query: "权限")
        guard let result = before.results.first(where: { $0.primaryAction == .runCommand(.checkPermissions) }) else {
            XCTFail("Expected check permissions command")
            return
        }

        await service.recordSelection(result)
        let after = await service.search(query: "权限")
        let boosted = after.results.first { $0.id == result.id }

        XCTAssertGreaterThan(boosted?.usageScore ?? 0, result.usageScore)
    }
}

private extension Array where Element == SearchResult {
    func containsCommand(_ id: CommandID) -> Bool {
        contains { $0.primaryAction == .runCommand(id) }
    }
}

private final class SpyClipboardHistoryService: ClipboardHistoryServiceProtocol {
    private(set) var didClear = false

    func clearAllConfirmation() -> ClipboardClearAllConfirmation {
        ClipboardClearAllConfirmation(
            title: "Clear",
            message: "Cannot undo",
            destructiveButtonTitle: "Clear",
            requiresExplicitConfirmation: true
        )
    }

    func clearAll(confirmed: Bool) async throws {
        guard confirmed else { throw AssistantClipboardRepositoryError.confirmationRequired }
        didClear = true
    }
}

private final class SpyCommandExecutor: CommandExecutorProtocol {
    let requiresConfirmationIDs: Set<CommandID>
    private(set) var executions: [(CommandID, Bool)] = []

    init(requiresConfirmationIDs: Set<CommandID>) {
        self.requiresConfirmationIDs = requiresConfirmationIDs
    }

    func execute(_ commandID: CommandID, confirmed: Bool) async throws {
        executions.append((commandID, confirmed))
    }

    func requiresConfirmation(_ commandID: CommandID) -> Bool {
        requiresConfirmationIDs.contains(commandID)
    }
}

private final class StubConfirmationProvider: CommandConfirmationProviding {
    let result: Bool
    private(set) var requestedCommands: [AssistantCommandDefinition] = []

    init(result: Bool) {
        self.result = result
    }

    func confirm(command: AssistantCommandDefinition) async -> Bool {
        requestedCommands.append(command)
        return result
    }
}
