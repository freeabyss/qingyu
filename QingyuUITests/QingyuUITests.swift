import XCTest

/// 占位 UI 测试，用于验证 QingyuUITests target 可编译、可运行。
/// 实际用例将在 T-UI-004 起实现。
final class QingyuUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    /// 验证 UITest bundle 能被加载、test runner 能执行用例。
    func testPlaceholder() throws {
        // 仅验证 target 可编译可运行，不启动被测 app。
        XCTAssertTrue(true, "QingyuUITests target is wired up and runnable.")
    }
}
