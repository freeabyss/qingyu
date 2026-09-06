import XCTest

/// TC-UI-016~018：Command Bar 搜索基本交互
///
/// 依据：`docs/iterations/v1.2.1/test/cases.md` TC-UI-016~018
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSearch`（与 TC-UI-011 一致）
/// 硬依赖（cases.md §0.5）：`commandBar.searchField`、`commandBar.resultList`
/// 边界：不验证搜索结果正确性（那是 SearchServiceCoreTests / SearchTextMatcherTests 的事），
///   只验证 UI 行为链路（输入 -> 结果 -> 回车/ESC -> 关闭）。
final class CommandBarUITests: XCTestCase {

    private var app: XCUIApplication!
    private var tmpDirURL: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let app = app, app.state != .notRunning {
            app.terminate()
        }
        if let url = tmpDirURL {
            try? FileManager.default.removeItem(at: url)
            tmpDirURL = nil
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeTmpDir(for caseName: String) -> String {
        let path = NSTemporaryDirectory()
            + "QingniaoUITest/CommandBarUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    /// 启动并触发 Command Bar 呈现（mark-completed + trigger openSearch + 通用）。
    private func launchWithCommandBar(for caseName: String) {
        let tmpDir = makeTmpDir(for: caseName)
        app.launchArguments = ["--uitest-data-dir", tmpDir,
                               "--uitest-skip-shortcuts",
                               "--uitest-mark-onboarding-completed",
                               "--uitest-trigger", "openSearch"]
        app.launch()
        app.activate()
    }

    private var searchField: XCUIElement {
        app.textFields["commandBar.searchField"]
    }

    private var resultList: XCUIElement {
        app.groups["commandBar.resultList"]
    }

    /// "未找到匹配项"文案（实际 L10n key `commandBar.noResults.title`，zh-Hans 值"未找到匹配项"）。
    private var noResultsText: XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "未找到")
        ).firstMatch
    }

    /// 轮询 element 消失（cases.md §0.6：NSPredicate + expectation）。
    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval,
        message: String
    ) {
        let expectation = self.expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: element
        )
        wait(for: [expectation], timeout: timeout)
        XCTAssertFalse(element.exists, message)
    }

    // MARK: - TC-UI-016　输入 -> 结果 -> ESC 关闭

    /// 覆盖：FR-SEARCH-4/6/7；US-003；全局 PRD §9.4 P-01、§9.3
    /// 步骤：输入文本 -> 结果列表出现 -> ESC 关闭（FR-SEARCH-7）。
    func testTCUI016TypeResultAndEscape() throws {
        launchWithCommandBar(for: "TC-UI-016")

        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-016: Command Bar 搜索框应呈现"
        )
        searchField.click()
        searchField.typeText("设置")

        // 结果列表出现，或"未找到匹配项"staticText（全局 PRD §9.7）
        let resultExists = resultList.waitForExistence(timeout: 5)
        let noMatchExists = resultExists
            ? noResultsText.exists
            : noResultsText.waitForExistence(timeout: 3)

        XCTAssertTrue(
            resultExists || noMatchExists,
            "TC-UI-016: 输入后结果列表或未找到文案应出现"
        )

        // ESC 关闭（FR-SEARCH-7）。ESC = 0x1B
        searchField.typeText("\u{1B}")

        waitForDisappearance(
            searchField,
            timeout: 3,
            message: "TC-UI-016: ESC 后 Command Bar 应关闭（FR-SEARCH-7）"
        )
    }

    // MARK: - TC-UI-017　回车执行 + 自动关闭

    /// 覆盖：FR-SEARCH-27/29；US-003
    /// 验证 FR-SEARCH-29：执行主动作后搜索框自动关闭。
    /// 不验证主动作执行结果（如是否真打开设置窗口），只验证 panel 自动关闭行为。主动作正确性退回各 Provider 的 XCTest。
    func testTCUI017EnterExecutesAndCloses() throws {
        launchWithCommandBar(for: "TC-UI-017")

        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-017: Command Bar 搜索框应呈现"
        )
        searchField.click()
        searchField.typeText("设置")

        let resultExists = resultList.waitForExistence(timeout: 5)
        let noMatchExists = resultExists
            ? noResultsText.exists
            : noResultsText.waitForExistence(timeout: 3)

        XCTAssertTrue(
            resultExists || noMatchExists,
            "TC-UI-017: 输入后结果列表或未找到文案应出现"
        )

        // Enter 执行主动作（FR-SEARCH-27）
        searchField.typeText("\r")

        waitForDisappearance(
            searchField,
            timeout: 3,
            message: "TC-UI-017: 回车执行主动作后 Command Bar 应自动关闭（FR-SEARCH-29）"
        )
    }

    // MARK: - TC-UI-018　空输入不消失（空态）

    /// 覆盖：FR-SEARCH-14；US-003；全局 PRD §9.3 空态展示最近使用+收藏
    /// 备注：隔离数据目录下无使用记录，空态为初始占位。本用例只测"空输入时 panel 不消失"。
    ///       "最近使用+收藏"列表内容验证需 mock 使用记录（`--uitest-mock-usage-data`，后续迭代补）。
    ///       固定等待 2s 为 cases.md §TC-UI-018 明确要求（确保非瞬时关闭），属 §0.6 例外。
    func testTCUI018EmptyInputKeepsPanel() throws {
        launchWithCommandBar(for: "TC-UI-018")

        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-018: Command Bar 搜索框应呈现"
        )

        // 不输入任何文本，固定等待 2s 确保非瞬时关闭（cases.md §TC-UI-018 明确要求）
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(
            searchField.exists,
            "TC-UI-018: 空输入时 Command Bar panel 应保持可见（FR-SEARCH-14）"
        )
    }

    // MARK: - TC-UI-023　搜索栏打开剪贴板历史

    /// 覆盖 F01/F03：命令栏的“打开剪贴板历史”必须是独立主动作，不能退化为
    /// 单条剪贴板记录的复制动作。使用英文别名保证界面语言不影响测试。
    func testTCUI023SearchOpensClipboardHistory() throws {
        launchWithCommandBar(for: "TC-UI-023")

        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-023: Command Bar 搜索框应呈现"
        )
        searchField.click()
        searchField.typeText("clipboard history")

        XCTAssertTrue(
            resultList.waitForExistence(timeout: 5),
            "TC-UI-023: 应显示剪贴板历史命令结果"
        )

        searchField.typeText("\r")

        let clipboardSearchField = app.textFields["clipboard.searchField"]
        XCTAssertTrue(
            clipboardSearchField.waitForExistence(timeout: 5),
            "TC-UI-023: 回车后应打开剪贴板历史窗口"
        )
        XCTAssertFalse(searchField.exists, "TC-UI-023: 打开历史窗口后 Command Bar 应关闭")
    }

}
