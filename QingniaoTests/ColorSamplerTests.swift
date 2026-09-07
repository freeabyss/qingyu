import AppKit
import CoreGraphics
import XCTest
@testable import Qingniao

final class ColorSamplerTests: XCTestCase {

    /// 直接以字节构造纯色 CGImage，避免 CGColor 填充的隐式颜色空间转换。
    private func makeSolidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            data[index * 4 + 0] = red
            data[index * 4 + 1] = green
            data[index * 4 + 2] = blue
            data[index * 4 + 3] = 255
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    func testHexFormatsTwoDigitUppercaseComponents() {
        XCTAssertEqual(ColorString.hex(red: 18, green: 52, blue: 86), "#123456")
        XCTAssertEqual(ColorString.hex(red: 0, green: 0, blue: 0), "#000000")
        XCTAssertEqual(ColorString.hex(red: 255, green: 255, blue: 255), "#FFFFFF")
    }

    func testRgbFormatsCommaSeparatedDecimalComponents() {
        XCTAssertEqual(ColorString.rgb(red: 18, green: 52, blue: 86), "18, 52, 86")
        XCTAssertEqual(ColorString.rgb(red: 255, green: 0, blue: 128), "255, 0, 128")
    }

    func testSamplesPixelFromCapturedImage() throws {
        let image = try XCTUnwrap(makeSolidImage(width: 4, height: 4, red: 255, green: 0, blue: 0))

        let sampled = try XCTUnwrap(ColorSampler.samplePixel(at: CGPoint(x: 2, y: 2), in: image))

        XCTAssertEqual(sampled.red, 255)
        XCTAssertEqual(sampled.green, 0)
        XCTAssertEqual(sampled.blue, 0)
    }

    func testSampleProducesBothFormats() throws {
        let image = try XCTUnwrap(makeSolidImage(width: 3, height: 3, red: 18, green: 52, blue: 86))

        let sample = try XCTUnwrap(ColorSampler.sample(at: CGPoint(x: 1, y: 1), in: image))

        XCTAssertEqual(sample.hex, "#123456")
        XCTAssertEqual(sample.rgb, "18, 52, 86")
    }

    func testOutOfRangePointReturnsNil() throws {
        let image = try XCTUnwrap(makeSolidImage(width: 2, height: 2, red: 0, green: 0, blue: 0))

        XCTAssertNil(ColorSampler.sample(at: CGPoint(x: -1, y: 0), in: image))
        XCTAssertNil(ColorSampler.sample(at: CGPoint(x: 2, y: 1), in: image))
        XCTAssertNil(ColorSampler.sample(at: CGPoint(x: 0, y: 2), in: image))
    }
}
