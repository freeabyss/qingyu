import CoreGraphics
import XCTest
@testable import Qingyu

/// Task 014 / 06：拖拽选区时的长宽比锁定（纯函数契约）。
final class SelectionInteractionTests: XCTestCase {

    private let start = CGPoint(x: 100, y: 100)

    func testProjectLocksToOneToOneWhenDraggingDiagonally() {
        let projected = SelectionAspectLock.project(
            start: start,
            current: CGPoint(x: 160, y: 130),
            ratio: 1
        )
        XCTAssertEqual(abs(projected.x - start.x), abs(projected.y - start.y), accuracy: 0.001, "1:1 锁定后两轴位移相等")
        XCTAssertEqual(projected.x, 160, accuracy: 0.001, "取拖拽距离较大的一轴为基准")
    }

    func testProjectHonoursNonUnitRatio() {
        let projected = SelectionAspectLock.project(
            start: start,
            current: CGPoint(x: 300, y: 150),
            ratio: 2
        )
        let width = abs(projected.x - start.x)
        let height = abs(projected.y - start.y)
        XCTAssertEqual(width / height, 2, accuracy: 0.001)
    }

    /// 向左上拖拽时投影必须落在同一象限，否则选区会跳到对侧。
    func testProjectKeepsQuadrant() {
        let projected = SelectionAspectLock.project(
            start: start,
            current: CGPoint(x: 40, y: 70),
            ratio: 1
        )
        XCTAssertLessThan(projected.x, start.x)
        XCTAssertLessThan(projected.y, start.y)
    }

    func testProjectReturnsCurrentForInvalidRatioOrZeroDrag() {
        let current = CGPoint(x: 150, y: 120)
        XCTAssertEqual(SelectionAspectLock.project(start: start, current: current, ratio: 0), current)
        XCTAssertEqual(SelectionAspectLock.project(start: start, current: current, ratio: -1), current)
        XCTAssertEqual(SelectionAspectLock.project(start: start, current: current, ratio: .nan), current)
        XCTAssertEqual(SelectionAspectLock.project(start: start, current: start, ratio: 1), start, "零位移不投影")
    }

    func testRatioDerivationRejectsDegenerateRect() {
        XCTAssertEqual(SelectionAspectLock.ratio(of: CGRect(x: 0, y: 0, width: 100, height: 50)), 2)
        XCTAssertNil(SelectionAspectLock.ratio(of: CGRect(x: 0, y: 0, width: 100, height: 0)))
        XCTAssertNil(SelectionAspectLock.ratio(of: .zero))
    }
}

/// Task 014 / 02：标注笔宽步进的纯函数契约。
final class AnnotationLineWidthStepperTests: XCTestCase {

    func testStepWalksAdjacentWidths() {
        XCTAssertEqual(AnnotationLineWidthStepper.step(.thin, direction: 1), .medium)
        XCTAssertEqual(AnnotationLineWidthStepper.step(.medium, direction: 1), .thick)
        XCTAssertEqual(AnnotationLineWidthStepper.step(.thick, direction: -1), .medium)
        XCTAssertEqual(AnnotationLineWidthStepper.step(.medium, direction: -1), .thin)
    }

    /// 到边界后保持不动（不循环），避免滚轮一直滚就"跳回最细"。
    func testStepClampsAtBoundaries() {
        XCTAssertEqual(AnnotationLineWidthStepper.step(.thin, direction: -1), .thin)
        XCTAssertEqual(AnnotationLineWidthStepper.step(.thick, direction: 1), .thick)
    }

    func testStepWithZeroDirectionIsIdentity() {
        XCTAssertEqual(AnnotationLineWidthStepper.step(.medium, direction: 0), .thin, "0 视为变细一档")
    }
}

/// Task 014 / 04：取色文本格式化的纯函数契约。
final class ColorValueFormatterTests: XCTestCase {

    private let color = (red: UInt8(18), green: UInt8(52), blue: UInt8(86))

    /// 默认值必须与既有 UI 呈现一致（大写 `#RRGGBB`），否则接入即改变已有界面。
    func testDefaultMatchesExistingUppercaseHex() {
        XCTAssertEqual(
            ColorValueFormatter.string(red: color.red, green: color.green, blue: color.blue, options: .default),
            "#123456".uppercased()
        )
        XCTAssertEqual(
            ColorString.hex(red: color.red, green: color.green, blue: color.blue),
            ColorValueFormatter.hex(red: color.red, green: color.green, blue: color.blue, options: .default)
        )
    }

    func testLowercaseAndHashOptions() {
        var lowercase = ColorValueOptions.default
        lowercase.uppercaseHex = false
        XCTAssertEqual(
            ColorValueFormatter.string(red: color.red, green: color.green, blue: color.blue, options: lowercase),
            "#123456"
        )

        var noHash = ColorValueOptions.default
        noHash.omitHash = true
        XCTAssertEqual(
            ColorValueFormatter.string(red: color.red, green: color.green, blue: color.blue, options: noHash),
            "123456"
        )
    }

    /// 边界值：0 与 255 必须补零 / 满位，不能出现 `#0` 或 `#ff`。
    func testBoundaryValuesAreZeroPadded() {
        XCTAssertEqual(
            ColorValueFormatter.string(red: 0, green: 0, blue: 0, options: .default),
            "#000000".uppercased()
        )
        XCTAssertEqual(
            ColorValueFormatter.string(red: 255, green: 255, blue: 255, options: .default),
            "#FFFFFF"
        )
    }

    func testHSVAndHSLComponents() {
        var hsv = ColorValueOptions.default
        hsv.space = .hsv
        XCTAssertEqual(ColorValueFormatter.string(red: 255, green: 0, blue: 0, options: hsv), "0,100,100")
        XCTAssertEqual(ColorValueFormatter.string(red: 0, green: 0, blue: 0, options: hsv), "0,0,0")

        var hsl = ColorValueOptions.default
        hsl.space = .hsl
        XCTAssertEqual(ColorValueFormatter.string(red: 255, green: 0, blue: 0, options: hsl), "0,100,50")
        XCTAssertEqual(ColorValueFormatter.string(red: 128, green: 128, blue: 128, options: hsl), "0,0,50", "灰阶饱和度为 0")
    }

    func testSpacedComponentsSeparator() {
        var spaced = ColorValueOptions.default
        spaced.space = .hsv
        spaced.spacedComponents = true
        XCTAssertEqual(ColorValueFormatter.string(red: 0, green: 255, blue: 0, options: spaced), "120, 100, 100")
    }

    func testOptionsRoundTripThroughCodable() throws {
        var options = ColorValueOptions.default
        options.space = .hsl
        options.omitHash = true
        let data = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(ColorValueOptions.self, from: data), options)
    }
}
