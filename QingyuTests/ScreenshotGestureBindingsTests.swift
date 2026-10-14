import AppKit
import XCTest
@testable import Qingyu

/// Task 014/05：预览阶段可配置手势（Enter / 双击 / 中键 / 右键）。
final class ScreenshotGestureBindingsTests: XCTestCase {

    // MARK: - 默认值 = 当前行为

    func testDefaultsMatchCurrentBehavior() {
        let bindings = ScreenshotGestureBindings.default

        XCTAssertEqual(
            bindings.action(for: .enter),
            .copyAndEnd,
            "Enter 的既有提示是「Enter 复制」，默认必须与之一致"
        )
        // 另外三种此前完全没有行为：默认开启等于凭空多出会误触的交互。
        XCTAssertEqual(bindings.action(for: .doubleClick), .ignore)
        XCTAssertEqual(bindings.action(for: .middleClick), .ignore)
        XCTAssertEqual(bindings.action(for: .rightClick), .ignore)
        XCTAssertFalse(bindings.isAllIgnoring, "Enter 默认有动作，不算「全部不响应」")
    }

    func testAllIgnoringDetection() {
        var bindings = ScreenshotGestureBindings.default
        for gesture in ScreenshotGesture.allCases {
            bindings.set(.ignore, for: gesture)
        }

        XCTAssertTrue(bindings.isAllIgnoring)
    }

    // MARK: - 取值与容错

    func testSetAndReadBack() {
        var bindings = ScreenshotGestureBindings.default
        bindings.set(.pin, for: .middleClick)
        bindings.set(.save, for: .rightClick)
        bindings.set(.ignore, for: .enter)

        XCTAssertEqual(bindings.action(for: .middleClick), .pin)
        XCTAssertEqual(bindings.action(for: .rightClick), .save)
        XCTAssertEqual(bindings.action(for: .enter), .ignore)
    }

    func testUnknownStoredValuesFallBackToIgnore() {
        let bindings = ScreenshotGestureBindings(actions: [
            ScreenshotGesture.doubleClick.rawValue: "somethingElse",
            "notAGesture": "copyAndEnd"
        ])

        XCTAssertEqual(bindings.action(for: .doubleClick), .ignore, "非法值回退为不响应，不抛错")
        XCTAssertEqual(
            bindings.action(for: .enter),
            .copyAndEnd,
            "只覆盖能识别的键；其余保持默认"
        )
    }

    func testPartialArchiveIsFilledWithDefaults() throws {
        // 模拟旧存档：只存了一个键。
        let json = Data(#"{"doubleClick":"pin"}"#.utf8)
        let bindings = try JSONDecoder().decode(ScreenshotGestureBindings.self, from: json)

        XCTAssertEqual(bindings.action(for: .doubleClick), .pin)
        XCTAssertEqual(bindings.action(for: .enter), .copyAndEnd, "缺失的键回落到默认值")
        XCTAssertEqual(bindings.action(for: .middleClick), .ignore)
    }

    func testCodableRoundTrip() throws {
        var bindings = ScreenshotGestureBindings.default
        bindings.set(.save, for: .doubleClick)
        bindings.set(.pin, for: .rightClick)

        let data = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode(ScreenshotGestureBindings.self, from: data)

        XCTAssertEqual(decoded, bindings)
    }

    // MARK: - 派发矩阵

    func testDispatcherCoversEveryGestureBinding() {
        var bindings = ScreenshotGestureBindings.default
        let matrix: [ScreenshotGesture: ScreenshotGestureAction] = [
            .enter: .pin,
            .doubleClick: .save,
            .middleClick: .copyAndEnd,
            .rightClick: .ignore
        ]
        for (gesture, action) in matrix {
            bindings.set(action, for: gesture)
        }

        for (gesture, action) in matrix {
            XCTAssertEqual(
                ScreenshotGestureDispatcher.action(for: gesture, bindings: bindings),
                action,
                "\(gesture.rawValue) 应分发到 \(action.rawValue)"
            )
        }
    }

    // MARK: - 事件分类

    func testLeftDoubleClickOutsidePanelIsRecognized() {
        XCTAssertEqual(
            ScreenshotGestureDispatcher.gesture(
                eventType: .leftMouseUp, buttonNumber: 0, clickCount: 2, isOutsidePanel: true
            ),
            .doubleClick
        )
    }

    func testSingleLeftClickIsNotAGesture() {
        XCTAssertNil(ScreenshotGestureDispatcher.gesture(
            eventType: .leftMouseUp, buttonNumber: 0, clickCount: 1, isOutsidePanel: true
        ))
    }

    func testMiddleAndRightClickAreRecognizedOnlyOutsidePanel() {
        XCTAssertEqual(
            ScreenshotGestureDispatcher.gesture(
                eventType: .otherMouseUp, buttonNumber: 2, clickCount: 1, isOutsidePanel: true
            ),
            .middleClick
        )
        XCTAssertEqual(
            ScreenshotGestureDispatcher.gesture(
                eventType: .rightMouseUp, buttonNumber: 1, clickCount: 1, isOutsidePanel: true
            ),
            .rightClick
        )
        // 点在工具条上：一律不识别，避免与按钮抢事件。
        XCTAssertNil(ScreenshotGestureDispatcher.gesture(
            eventType: .otherMouseUp, buttonNumber: 2, clickCount: 1, isOutsidePanel: false
        ))
        XCTAssertNil(ScreenshotGestureDispatcher.gesture(
            eventType: .rightMouseUp, buttonNumber: 1, clickCount: 1, isOutsidePanel: false
        ))
        XCTAssertNil(ScreenshotGestureDispatcher.gesture(
            eventType: .leftMouseUp, buttonNumber: 0, clickCount: 2, isOutsidePanel: false
        ))
    }

    func testNonMouseButtonIsIgnored() {
        // buttonNumber 3+（侧键）不属于四种手势。
        XCTAssertNil(ScreenshotGestureDispatcher.gesture(
            eventType: .otherMouseUp, buttonNumber: 3, clickCount: 1, isOutsidePanel: true
        ))
    }

    func testEachGestureAndActionHasLocalizationKey() {
        for gesture in ScreenshotGesture.allCases {
            XCTAssertFalse(L10n.localized(gesture.localizationKey).isEmpty)
        }
        for action in ScreenshotGestureAction.allCases {
            XCTAssertFalse(L10n.localized(action.localizationKey).isEmpty)
        }
    }
}
