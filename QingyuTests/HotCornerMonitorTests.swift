import AppKit
import XCTest
@testable import Qingyu

/// Task 014/07：屏幕四角热区（命中判定、停顿、去重）。
@MainActor
final class HotCornerMonitorTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func configuration(
        enabled: Bool = true,
        size: CGFloat = 10,
        dwell: TimeInterval = 0.4
    ) -> HotCornerConfiguration {
        HotCornerConfiguration(isEnabled: enabled, size: size, dwell: dwell)
    }

    // MARK: - 默认值

    func testDefaultConfigurationIsDisabled() {
        let config = HotCornerConfiguration.default

        XCTAssertFalse(config.isEnabled, "热区是最容易误触的交互，不能默认打开")
        XCTAssertTrue(config.isEffectivelyDisabled)
        XCTAssertEqual(config.size, HotCornerConfiguration.defaultSize)
        XCTAssertEqual(config.dwell, HotCornerConfiguration.defaultDwell)
        for corner in HotCorner.allCases {
            XCTAssertEqual(config.action(for: corner), .regionCapture, "默认动作为「开始截图」")
        }
    }

    func testSanitizedRejectsInvalidAndClampsUpperBounds() {
        let config = HotCornerConfiguration(isEnabled: true, size: -5, dwell: .nan).sanitized()

        XCTAssertEqual(config.size, HotCornerConfiguration.defaultSize, "非法尺寸回落默认值，而不是 0")
        XCTAssertEqual(config.dwell, HotCornerConfiguration.defaultDwell)

        let huge = HotCornerConfiguration(isEnabled: true, size: 999, dwell: 99).sanitized()
        XCTAssertEqual(huge.size, HotCornerConfiguration.maximumSize)
        XCTAssertEqual(huge.dwell, HotCornerConfiguration.maximumDwell)
    }

    func testEffectivelyDisabledWhenAllCornersIgnored() {
        var config = configuration()
        for corner in HotCorner.allCases {
            config.set(.ignore, for: corner)
        }

        XCTAssertTrue(config.isEnabled, "开关本身未变，只是没有角落会触发")
        XCTAssertTrue(config.isEffectivelyDisabled)
    }

    // MARK: - 命中判定（边界）

    func testCornerDetectionInsideEachCorner() {
        let size: CGFloat = 10

        XCTAssertEqual(
            HotCornerTracker.corner(for: CGPoint(x: 2, y: 895), screenFrame: screen, size: size),
            .topLeft
        )
        XCTAssertEqual(
            HotCornerTracker.corner(for: CGPoint(x: 1438, y: 895), screenFrame: screen, size: size),
            .topRight
        )
        XCTAssertEqual(
            HotCornerTracker.corner(for: CGPoint(x: 2, y: 3), screenFrame: screen, size: size),
            .bottomLeft
        )
        XCTAssertEqual(
            HotCornerTracker.corner(for: CGPoint(x: 1438, y: 3), screenFrame: screen, size: size),
            .bottomRight
        )
    }

    func testCornerDetectionBoundaries() {
        let size: CGFloat = 10

        // 恰好落在边界上算命中。
        XCTAssertEqual(
            HotCornerTracker.corner(for: CGPoint(x: 10, y: 890), screenFrame: screen, size: size),
            .topLeft
        )
        // 刚越过边界即不命中。
        XCTAssertNil(HotCornerTracker.corner(for: CGPoint(x: 10.5, y: 890), screenFrame: screen, size: size))
        XCTAssertNil(HotCornerTracker.corner(for: CGPoint(x: 10, y: 889.5), screenFrame: screen, size: size))
        // 屏幕中央不命中任何角。
        XCTAssertNil(HotCornerTracker.corner(for: CGPoint(x: 720, y: 450), screenFrame: screen, size: size))
        // 尺寸为 0 时永不命中。
        XCTAssertNil(HotCornerTracker.corner(for: CGPoint(x: 0, y: 900), screenFrame: screen, size: 0))
    }

    // MARK: - 停顿与去重

    func testDoesNotTriggerBeforeDwellElapsed() {
        var tracker = HotCornerTracker()
        let config = configuration(dwell: 0.4)
        let cornerPoint = CGPoint(x: 2, y: 895)

        XCTAssertNil(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 100))
        XCTAssertNil(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 100.3))
        XCTAssertEqual(
            tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 100.4),
            .topLeft
        )
    }

    func testDoesNotRepeatWhileStayingInCorner() {
        var tracker = HotCornerTracker()
        let config = configuration(dwell: 0.4)
        let cornerPoint = CGPoint(x: 2, y: 895)

        XCTAssertNil(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 0))
        XCTAssertEqual(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 1), .topLeft)
        for offset in stride(from: 1.1, through: 5.0, by: 0.1) {
            XCTAssertNil(
                tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: offset),
                "停留期间不得重复触发"
            )
        }
    }

    func testTriggersAgainAfterLeavingAndReturning() {
        var tracker = HotCornerTracker()
        let config = configuration(dwell: 0.4)
        let cornerPoint = CGPoint(x: 2, y: 895)
        let center = CGPoint(x: 720, y: 450)

        XCTAssertNil(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 0))
        XCTAssertEqual(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 0.5), .topLeft)

        // 离开角落 → 去重状态复位。
        XCTAssertNil(tracker.update(pointer: center, screenFrame: screen, configuration: config, now: 0.6))
        XCTAssertNil(tracker.activeCorner)
        XCTAssertNil(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 0.7))
        XCTAssertEqual(tracker.update(pointer: cornerPoint, screenFrame: screen, configuration: config, now: 1.2), .topLeft)
    }

    func testSwitchingCornerRestartsDwell() {
        var tracker = HotCornerTracker()
        let config = configuration(dwell: 0.4)

        XCTAssertNil(tracker.update(pointer: CGPoint(x: 2, y: 895), screenFrame: screen, configuration: config, now: 0))
        // 直接移到另一个角：需要重新计时。
        XCTAssertNil(tracker.update(pointer: CGPoint(x: 1438, y: 895), screenFrame: screen, configuration: config, now: 0.35))
        XCTAssertEqual(
            tracker.update(pointer: CGPoint(x: 1438, y: 895), screenFrame: screen, configuration: config, now: 0.75),
            .topRight
        )
    }

    func testDisabledConfigurationNeverTriggers() {
        var tracker = HotCornerTracker()
        let config = configuration(enabled: false)

        XCTAssertNil(tracker.update(pointer: CGPoint(x: 0, y: 900), screenFrame: screen, configuration: config, now: 0))
        XCTAssertNil(tracker.update(pointer: CGPoint(x: 0, y: 900), screenFrame: screen, configuration: config, now: 10))
    }

    func testIgnoredCornerNeverTriggers() {
        var tracker = HotCornerTracker()
        var config = configuration()
        config.set(.ignore, for: .topLeft)

        XCTAssertNil(tracker.update(pointer: CGPoint(x: 2, y: 895), screenFrame: screen, configuration: config, now: 0))
        XCTAssertNil(tracker.update(pointer: CGPoint(x: 2, y: 895), screenFrame: screen, configuration: config, now: 5))
        // 其它角照常工作。
        XCTAssertNil(tracker.update(pointer: CGPoint(x: 1438, y: 895), screenFrame: screen, configuration: config, now: 6))
        XCTAssertEqual(
            tracker.update(pointer: CGPoint(x: 1438, y: 895), screenFrame: screen, configuration: config, now: 6.5),
            .topRight
        )
    }

    func testMultiDisplayUsesTheScreenContainingThePointer() {
        // 次级屏在右侧：其左上角是 (1920, 1080) 附近。
        let secondary = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        var tracker = HotCornerTracker()
        let config = configuration(dwell: 0.2)

        XCTAssertNil(tracker.update(pointer: CGPoint(x: 1925, y: 1075), screenFrame: secondary, configuration: config, now: 0))
        XCTAssertEqual(
            tracker.update(pointer: CGPoint(x: 1925, y: 1075), screenFrame: secondary, configuration: config, now: 0.3),
            .topLeft
        )
    }

    // MARK: - 配置读写

    func testConfigurationCodableRoundTrip() throws {
        var config = HotCornerConfiguration(isEnabled: true, size: 12, dwell: 0.7)
        config.set(.ignore, for: .bottomRight)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HotCornerConfiguration.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testConfigurationMissingKeysFallBackToDefaults() throws {
        let json = Data(#"{"isEnabled":true}"#.utf8)
        let config = try JSONDecoder().decode(HotCornerConfiguration.self, from: json)

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.size, HotCornerConfiguration.defaultSize)
        XCTAssertEqual(config.dwell, HotCornerConfiguration.defaultDwell)
        XCTAssertEqual(config.action(for: .topLeft), .regionCapture)
    }

    // MARK: - 监听器（不启动真实定时器）

    func testMonitorTickDeliversTriggerOncePerDwell() {
        let monitor = HotCornerMonitor()
        monitor.configuration = configuration(dwell: 0.2)

        var now: TimeInterval = 0
        var pointer = CGPoint(x: 2, y: 895)
        monitor.pointerProvider = { (pointer, self.screen) }
        monitor.nowProvider = { now }

        var fired: [(HotCorner, HotCornerAction)] = []
        monitor.onTrigger = { fired.append(($0, $1)) }

        monitor.tick()
        now = 0.1
        monitor.tick()
        XCTAssertTrue(fired.isEmpty, "停留不足不触发")

        now = 0.25
        monitor.tick()
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.0, .topLeft)
        XCTAssertEqual(fired.first?.1, .regionCapture)

        now = 1.0
        monitor.tick()
        XCTAssertEqual(fired.count, 1, "停留期间不重复触发")

        // 移出再回来可再次触发。
        pointer = CGPoint(x: 720, y: 450)
        now = 1.1
        monitor.tick()
        pointer = CGPoint(x: 2, y: 895)
        now = 1.2
        monitor.tick()
        now = 1.5
        monitor.tick()
        XCTAssertEqual(fired.count, 2)
    }

    func testMonitorDoesNotRunTimerWhileDisabled() {
        let monitor = HotCornerMonitor()
        monitor.configuration = .default

        XCTAssertFalse(monitor.isRunning, "默认关闭时不得启动任何轮询")
    }

    func testEachHotCornerStringHasLocalization() {
        for corner in HotCorner.allCases {
            XCTAssertFalse(L10n.localized(corner.localizationKey).isEmpty)
        }
        for action in HotCornerAction.allCases {
            XCTAssertFalse(L10n.localized(action.localizationKey).isEmpty)
        }
    }
}
