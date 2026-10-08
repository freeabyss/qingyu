import Carbon
import XCTest

/// TC-UI-016~018、TC-UI-024：Command Bar 搜索基本交互 + 打开即聚焦回归
///
/// 依据：`docs/iterations/v1.2.1/test/cases.md` TC-UI-016~018；
/// TC-UI-024 为 v1.2.2 回归用例（⌥Space 打开命令栏后光标不在输入框、必须点击
/// 才能输入的缺陷），用例说明随本文件注释维护，不改已冻结的迭代文档。
/// 前置：`--uitest-mark-onboarding-completed` + `--uitest-trigger openSearch`（与 TC-UI-011 一致）
/// 硬依赖（cases.md §0.5）：`commandBar.searchField`、`commandBar.resultList`
/// 边界：不验证搜索结果正确性（那是 SearchServiceCoreTests / SearchTextMatcherTests 的事），
///   只验证 UI 行为链路（输入 -> 结果 -> 回车/ESC -> 关闭）。
///
/// 环境说明：命令栏是非激活浮动面板，中文输入法（WeType 等）的候选窗会在合成键入时
/// 抢走键盘焦点导致面板失焦自动关闭；输入型用例在 setUp 临时切到 ABC 键盘布局，
/// tearDown 还原原输入源（仅测试进程内调用 TIS API，不改产品代码）。
final class CommandBarUITests: XCTestCase {

    private var app: XCUIApplication!
    private var tmpDirURL: URL?
    private var originalInputSourceID: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        originalInputSourceID = UITestKeyboardLayout.selectABC()
    }

    override func tearDownWithError() throws {
        if let app = app, app.state != .notRunning {
            app.terminate()
        }
        if let url = tmpDirURL {
            try? FileManager.default.removeItem(at: url)
            tmpDirURL = nil
        }
        if let originalInputSourceID {
            UITestKeyboardLayout.restore(originalInputSourceID)
        }
    }

    // MARK: - Keyboard layout helper

    /// TIS 输入源治理：切换/还原系统键盘布局（会话级，随 tearDown 还原）。
    private enum UITestKeyboardLayout {
        private static let abcInputSourceID = "com.apple.keylayout.ABC"

        private static func inputSourceID(_ source: TISInputSource) -> String? {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }

        /// 切到 ABC 布局；返回原输入源 ID 供 `restore(_:)` 还原。
        static func selectABC() -> String? {
            let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let originalID = inputSourceID(original)
            let sourceList = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            for source in sourceList where inputSourceID(source) == abcInputSourceID {
                TISSelectInputSource(source)
                break
            }
            return originalID
        }

        /// 还原 setUp 时记录的输入源。
        static func restore(_ id: String) {
            let sourceList = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            for source in sourceList where inputSourceID(source) == id {
                TISSelectInputSource(source)
                break
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeTmpDir(for caseName: String) -> String {
        let path = NSTemporaryDirectory()
            + "QingyuUITest/CommandBarUITests/\(caseName)"
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
        // macOS 会按 app 记忆输入源：即使 setUp 已切到 ABC，新启动的 app 仍可能恢复
        // 其上次使用的中文输入法（候选栏劫持合成键入为标记文本，搜索不触发）。
        // 激活后（Qingyu 前台时）再切一次，确保当前应用上下文使用 ABC 布局。
        UITestKeyboardLayout.selectABC()
    }

    private var searchField: XCUIElement {
        app.textFields["commandBar.searchField"]
    }

    /// 结果列表在当前 macOS 运行时的 AX 类型是 Other（非 Group），
    /// 用任意类型 + identifier 匹配，避免对元素类型的硬依赖（同 PinWindowUITests）。
    private var resultList: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "commandBar.resultList").firstMatch
    }

    /// "未找到匹配项"文案（实际 L10n key `commandBar.noResults.title`，zh-Hans 值"未找到匹配项"）。
    /// AX StaticText 在当前运行时只带 value 不带 label，label/value 双匹配。
    private var noResultsText: XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "未找到", "未找到")
        ).firstMatch
    }

    /// 通过系统剪贴板把文本送入搜索框并确认生效（重试直至字段值一致）。
    ///
    /// 不用 `typeText`：macOS 会按 app 记忆输入源，中文输入法（WeType 等）会把合成键入
    /// 变成标记文本（候选栏劫持），SwiftUI 绑定收不到提交文本，搜索防抖不触发；
    /// 粘贴链路（Cmd+V）不经过输入法，字段值直接落地。
    private func inputSearchText(_ text: String) {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            searchField.click()
            searchField.typeKey("v", modifierFlags: .command)
            if (searchField.value as? String) == text { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
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
        // 粘贴输入（同 TC-UI-017/023）：元素级 typeText 会经过输入法，中文输入法
        // 候选栏劫持合成键入导致搜索防抖不触发（macOS 26 实测）。
        inputSearchText("设置")

        // 结果列表出现，或"未找到匹配项"staticText（全局 PRD §9.7）
        let resultExists = resultList.waitForExistence(timeout: 5)
        let noMatchExists = resultExists
            ? noResultsText.exists
            : noResultsText.waitForExistence(timeout: 3)

        XCTAssertTrue(
            resultExists || noMatchExists,
            "TC-UI-016: 输入后结果列表或未找到文案应出现"
        )

        // ESC 关闭（FR-SEARCH-7）。不用元素级 typeText("\u{1B}")：结果渲染重建 AX 层级后
        // 缓存元素快照易失效（Failed to get matching snapshot，macOS 26 实测）；
        // app 级按键仅需面板为 key window，对焦点/快照竞态稳健（同 ClipboardWindowUITests）。
        app.typeKey(.escape, modifierFlags: [])

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
        inputSearchText("设置")

        // 空查询时命令栏只有输入框，resultList 只在输入后才出现；仍以首条搜索结果行
        // （"设置" 的精确别名命中：通用设置）出现作为就绪信号，避免回车落在防抖空窗期
        // （visibleResults 为空时会被静默忽略，面板不关闭）。
        let firstResultRow = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "通用设置", "通用设置")
        ).firstMatch
        XCTAssertTrue(
            firstResultRow.waitForExistence(timeout: 20),
            "TC-UI-017: 搜索结果行应出现"
        )

        XCTAssertTrue(
            resultList.waitForExistence(timeout: 5),
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

    /// 覆盖：FR-SEARCH-14；US-003；全局 PRD §9.3 空态不展示内容区
    /// 备注：空查询时命令栏只有输入框（没有任何内容区），本用例只测"空输入时 panel 不消失"。
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
        inputSearchText("clipboard history")

        XCTAssertTrue(
            resultList.waitForExistence(timeout: 5),
            "TC-UI-023: 应显示剪贴板历史命令结果"
        )

        // 等命令结果行出现再回车（resultList 常驻渲染首页内容，不能作为搜索就绪信号）
        let commandRow = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "剪贴板历史", "剪贴板历史")
        ).firstMatch
        XCTAssertTrue(
            commandRow.waitForExistence(timeout: 20),
            "TC-UI-023: 剪贴板历史命令结果行应出现"
        )

        searchField.typeText("\r")

        let clipboardSearchField = app.textFields["clipboard.searchField"]
        XCTAssertTrue(
            clipboardSearchField.waitForExistence(timeout: 5),
            "TC-UI-023: 回车后应打开剪贴板历史窗口"
        )
        XCTAssertFalse(searchField.exists, "TC-UI-023: 打开历史窗口后 Command Bar 应关闭")
    }

    // MARK: - TC-UI-024　打开后立即获得键盘焦点（无需点击）

    /// 覆盖：FR-SEARCH-4；回归 v1.2.2「⌥Space 打开后必须点击才能输入」缺陷。
    /// 验证面板成为 key window 后搜索框已是 first responder：不点击搜索框，
    /// app 级 ⌘V 粘贴应直接落到输入框。粘贴不经过输入法（见 inputSearchText 注）；
    /// 若未自动聚焦，⌘V 无处落地、字段值保持为空，用例失败。
    /// 用 app 级按键而非元素级 typeText：与 TC-UI-016 的 ESC 同理，对焦点/快照
    /// 竞态稳健，且只依赖「字段是 first responder」这一被测行为本身。
    func testTCUI024ImmediateKeyboardFocusOnOpen() throws {
        launchWithCommandBar(for: "TC-UI-024")

        XCTAssertTrue(
            searchField.waitForExistence(timeout: 10),
            "TC-UI-024: Command Bar 搜索框应呈现"
        )

        // 关键差异：不调用 searchField.click()，依赖打开后自动聚焦。
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("设置", forType: .string)
        app.typeKey("v", modifierFlags: .command)

        // 粘贴落地是异步的，用 NSPredicate 轮询字段值（cases.md §0.6）。
        let pasted = expectation(
            for: NSPredicate(format: "value == %@", "设置"),
            evaluatedWith: searchField
        )
        wait(for: [pasted], timeout: 5)

        XCTAssertEqual(
            searchField.value as? String, "设置",
            "TC-UI-024: 打开后无需点击输入框即可接收键盘输入（自动聚焦）"
        )
    }

}
