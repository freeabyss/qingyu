import XCTest

/// TC-UI-021~022：剪贴板窗口导航
///
/// 依据：`docs/iterations/v1.2.1/test/cases.md` TC-UI-021~022
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openClipboard`
/// 硬依赖（cases.md §0.5）：`clipboard.searchField`、`clipboard.filterMenu`
/// 边界：首期无 mock 剪贴板数据（`--uitest-mock-clipboard-data` 后续迭代补），
///   验证空态与搜索框基本可用性。
///
/// 文案偏差说明：cases.md §TC-UI-021 引用空态文案"剪贴板历史为空"，实际 L10n key
/// `clipboard.empty.title` 的 zh-Hans 值为"暂无剪贴板记录"。本用例用实际 L10n 文案。
/// 筛选项收拢在与命令栏一致的搜索栏筛选菜单中，避免剪贴板窗口维护独立侧栏导航。
final class ClipboardWindowUITests: XCTestCase {

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
            + "QingniaoUITest/ClipboardWindowUITests/\(caseName)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirURL = url
        return url.path
    }

    private func baseArgs(tmpDir: String) -> [String] {
        ["--uitest-data-dir", tmpDir, "--uitest-skip-shortcuts"]
    }

    private func launchWithClipboard(for caseName: String) {
        let tmpDir = makeTmpDir(for: caseName)
        app.launchArguments = baseArgs(tmpDir: tmpDir)
            + ["--uitest-mark-onboarding-completed", "--uitest-trigger", "openClipboard"]
        app.launch()
        app.activate()
    }

    // MARK: - TC-UI-021　空态 + 筛选菜单 + 搜索框可见可聚焦

    /// 覆盖：FR-CLIP-18/19；US-008；全局 PRD §9.4 P-02、§9.7
    /// 验证：空态文案、筛选菜单、搜索框可见可聚焦。
    func testTCUI021EmptyStateTypeFiltersAndSearchField() throws {
        launchWithClipboard(for: "TC-UI-021")

        let searchField = app.textFields["clipboard.searchField"]
        let fieldExists = searchField.waitForExistence(timeout: 10)

        // 隔离数据目录下剪贴板为空，应走空态。实际 L10n: "暂无剪贴板记录"（clipboard.empty.title）。
        let emptyState = app.staticTexts["暂无剪贴板记录"]
        let emptyExists = fieldExists
            ? emptyState.waitForExistence(timeout: 5)
            : emptyState.waitForExistence(timeout: 10)

        XCTAssertTrue(
            fieldExists || emptyExists,
            "TC-UI-021: 剪贴板窗口应呈现（搜索框或空态文案可见）"
        )

        // 空态文案（cases.md §TC-UI-021：隔离数据目录下为空）
        if !emptyState.exists {
            XCTAssertTrue(
                emptyState.waitForExistence(timeout: 5),
                "TC-UI-021: 隔离数据目录下应显示空态文案\"暂无剪贴板记录\""
            )
        }

        // 类型筛选：收拢在命令栏样式的筛选菜单；展开后应可选择文本类型。
        let filterMenu = app.buttons["clipboard.filterMenu"]
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 5), "TC-UI-021: 搜索栏应包含筛选菜单")
        XCTAssertTrue(filterMenu.isHittable, "TC-UI-021: 筛选菜单应可点击")
        filterMenu.click()
        XCTAssertTrue(app.menuItems["文本"].waitForExistence(timeout: 3),
                      "TC-UI-021: 筛选菜单应包含\"文本\"")
        app.typeKey(.escape, modifierFlags: [])

        // 搜索框可见可聚焦（硬依赖 §0.5：clipboard.searchField）
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "TC-UI-021: 搜索框应可见")
        XCTAssertTrue(searchField.isHittable,
                      "TC-UI-021: 搜索框应可点击聚焦")
        searchField.click()
        // 验证可输入：typeText 不抛错即视为可输入（cases.md §TC-UI-021：通过键盘输入验证可输入）
        searchField.typeText("a")
        XCTAssertTrue(searchField.exists,
                      "TC-UI-021: 输入后搜索框应仍存在")
    }

    // MARK: - TC-UI-022　搜索框输入（空数据过滤）

    /// 覆盖：FR-CLIP-19b；US-008
    /// 验证：空数据下搜索框输入不崩溃，列表过滤无异常。
    /// 备注：真实过滤行为需 mock 剪贴板数据（`--uitest-mock-clipboard-data`，后续迭代补）。
    ///       首期无 mock 数据时只测"搜索框输入不报错、空数据过滤无异常"（设计文档 §6.1）。
    ///       固定等待 1s 为 cases.md §TC-UI-022 明确要求（FR-CLIP-19d debounce），属 §0.6 例外。
    func testTCUI022SearchFieldInputWithEmptyData() throws {
        launchWithClipboard(for: "TC-UI-022")

        let searchField = app.textFields["clipboard.searchField"]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-022: 剪贴板搜索框应呈现"
        )

        searchField.click()
        searchField.typeText("test")

        // FR-CLIP-19d debounce：固定等待 1s（cases.md §TC-UI-022 明确要求）
        Thread.sleep(forTimeInterval: 1)

        // 不崩溃：XCUIApplication.State 无 .running case，用 "!= .notRunning" 判定进程仍在
        XCTAssertNotEqual(
            app.state,
            .notRunning,
            "TC-UI-022: 搜索框输入后 app 应保持运行（不崩溃）"
        )
        // 搜索框仍可用
        XCTAssertTrue(searchField.exists,
                      "TC-UI-022: 输入后搜索框应仍存在")
        // 空数据下列表过滤无异常：空态文案保持或变为"没有匹配的剪贴板项目"
        // （实际 L10n: clipboard.empty.title="暂无剪贴板记录", clipboard.empty.search.title="没有匹配的剪贴板项目"）
        let emptyState = app.staticTexts["暂无剪贴板记录"]
        let searchEmptyState = app.staticTexts["没有匹配的剪贴板项目"]
        XCTAssertTrue(
            emptyState.exists || searchEmptyState.exists,
            "TC-UI-022: 空数据下过滤后应显示空态或搜索空态文案（无异常）"
        )
    }
}
