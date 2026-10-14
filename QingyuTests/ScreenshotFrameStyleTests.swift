import AppKit
import XCTest
@testable import Qingyu

/// Task 014/03：导出结果图的圆角 / 边框 / 阴影。
///
/// 本能力的核心约束是**纯增量**：默认全关，导出结果与引入前逐字节一致。
/// 因此这里的用例分为三组：几何（纯函数）、绘制（像素级）、以及取值（UserDefaults 与协调器联动）。
final class ScreenshotFrameStyleTests: XCTestCase {

    // MARK: - Geometry

    func testDefaultStyleIsIdentity() {
        let style = ScreenshotFrameStyle.default

        XCTAssertTrue(style.isIdentity, "默认必须等于「不装饰」，否则会改变既有导出结果")
        XCTAssertEqual(style.effectiveShadowWidth, 0)
        XCTAssertEqual(
            style.canvasSize(forImagePixelSize: CGSize(width: 20, height: 10)),
            CGSize(width: 20, height: 10)
        )
    }

    func testCanvasGrowsByBorderAndShadowOnBothSides() {
        var style = ScreenshotFrameStyle()
        style.cornerRadius = 6
        style.borderWidth = 2
        style.shadowWidth = 4

        let size = CGSize(width: 20, height: 10)
        XCTAssertFalse(style.isIdentity)
        XCTAssertEqual(style.canvasSize(forImagePixelSize: size), CGSize(width: 32, height: 22))
        XCTAssertEqual(
            style.imageRect(forImagePixelSize: size),
            CGRect(x: 6, y: 6, width: 20, height: 10)
        )
    }

    func testShadowToggleRemovesShadowMarginOnly() {
        var style = ScreenshotFrameStyle()
        style.borderWidth = 2
        style.shadowWidth = 10
        style.showsShadow = false

        XCTAssertEqual(style.effectiveShadowWidth, 0)
        XCTAssertEqual(
            style.canvasSize(forImagePixelSize: CGSize(width: 20, height: 10)),
            CGSize(width: 24, height: 14),
            "阴影总开关关闭时只保留边框留白"
        )
    }

    func testScaleMultipliesFramingInPixels() {
        var style = ScreenshotFrameStyle()
        style.cornerRadius = 8
        style.borderWidth = 2
        style.shadowWidth = 0

        // 2 倍屏：8 点的圆角与 2 点的边框折算成 16 / 4 像素。
        XCTAssertEqual(
            style.canvasSize(forImagePixelSize: CGSize(width: 100, height: 50), scale: 2),
            CGSize(width: 108, height: 58)
        )
        XCTAssertEqual(
            style.imageRect(forImagePixelSize: CGSize(width: 100, height: 50), scale: 2),
            CGRect(x: 4, y: 4, width: 100, height: 50)
        )
    }

    func testSanitizedRejectsNegativeAndClampsHugeValues() {
        let style = ScreenshotFrameStyle(
            cornerRadius: -5,
            borderWidth: 10_000,
            borderColorHex: "#FF0000",
            shadowWidth: .nan,
            shadowColorHex: "#00FF00",
            showsShadow: true
        ).sanitized()

        XCTAssertEqual(style.cornerRadius, 0)
        XCTAssertEqual(style.borderWidth, 60, "超大值按上限截断，避免生成异常画布")
        XCTAssertEqual(style.shadowWidth, 0, "NaN 一律按 0")
    }

    func testDisplayScaleFallsBackToOne() {
        XCTAssertEqual(ScreenshotFrameStyle.displayScale(for: nil), 1)
    }

    // MARK: - Rendering

    func testIdentityStyleReturnsOriginalBytes() {
        let data = makePNG(width: 20, height: 10)
        let style = ScreenshotFrameStyle()

        XCTAssertEqual(style.applying(to: data), data, "全关时必须原样返回，保证逐字节一致")
    }

    func testUndecodableDataIsReturnedUntouched() {
        let garbage = Data([0x00, 0x01, 0x02])
        var style = ScreenshotFrameStyle()
        style.cornerRadius = 4

        XCTAssertEqual(style.applying(to: garbage), garbage)
    }

    func testRenderingProducesExpectedPixelSizeAndTransparentCorners() throws {
        let data = makePNG(width: 20, height: 10, color: .red)
        var style = ScreenshotFrameStyle()
        style.cornerRadius = 4
        style.borderWidth = 0
        style.shadowWidth = 0

        let output = style.applying(to: data)
        XCTAssertNotEqual(output, data)

        let rep = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(rep.pixelsWide, 20, "无边框无阴影时画布与源图等大")
        XCTAssertEqual(rep.pixelsHigh, 10)

        // 圆角落在四角：左上角必须被裁掉（alpha == 0）；中心保持源色。
        let corner = try XCTUnwrap(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01, "圆角处应透明")

        let center = try XCTUnwrap(rep.colorAt(x: 10, y: 5)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.8)
        XCTAssertLessThan(center.greenComponent, 0.2)
    }

    func testBorderColorPaintsInsideCanvasMargin() throws {
        let data = makePNG(width: 20, height: 10, color: .white)
        var style = ScreenshotFrameStyle()
        style.borderWidth = 4
        style.borderColorHex = "#0000FF"
        style.shadowWidth = 0

        let output = style.applying(to: data)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(rep.pixelsWide, 28, "左右各 4 像素边框")
        XCTAssertEqual(rep.pixelsHigh, 18)

        // 左边框中心（x = 2）应是蓝色而不是白色原图。
        let border = try XCTUnwrap(rep.colorAt(x: 2, y: 9)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(border.blueComponent, 0.8)
        XCTAssertLessThan(border.redComponent, 0.2)
    }

    func testShadowAddsTranslucentMargin() throws {
        let data = makePNG(width: 12, height: 12, color: .white)
        var style = ScreenshotFrameStyle()
        style.shadowWidth = 6
        style.shadowColorHex = "#000000"
        style.borderWidth = 0

        let output = style.applying(to: data)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(rep.pixelsWide, 24, "两侧各留 6 像素阴影空间")
        XCTAssertEqual(rep.pixelsHigh, 24)
        XCTAssertNotEqual(rep.colorAt(x: 0, y: 0)?.alphaComponent, 1, "最外侧不应是完全不透明的白")
    }

    // MARK: - Defaults & result plumbing

    func testCurrentReadsDefaultsAndDefaultsToNoDecoration() throws {
        let suiteName = "ScreenshotFrameStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(ScreenshotFrameStyle.current(from: defaults).isIdentity)
        XCTAssertTrue(
            ScreenshotFrameStyle.current(from: defaults).showsShadow,
            "阴影总开关未写入时默认开，与设置页初始值一致"
        )

        defaults.set(10.0, forKey: ScreenshotFrameStyle.DefaultsKey.cornerRadius)
        defaults.set(3.0, forKey: ScreenshotFrameStyle.DefaultsKey.borderWidth)
        defaults.set("#112233", forKey: ScreenshotFrameStyle.DefaultsKey.borderColor)
        defaults.set(8.0, forKey: ScreenshotFrameStyle.DefaultsKey.shadowWidth)
        defaults.set("#445566", forKey: ScreenshotFrameStyle.DefaultsKey.shadowColor)
        defaults.set(false, forKey: ScreenshotFrameStyle.DefaultsKey.includeShadow)

        let style = ScreenshotFrameStyle.current(from: defaults)
        XCTAssertEqual(style.cornerRadius, 10)
        XCTAssertEqual(style.borderWidth, 3)
        XCTAssertEqual(style.borderColorHex, "#112233")
        XCTAssertEqual(style.shadowWidth, 8)
        XCTAssertEqual(style.shadowColorHex, "#445566")
        XCTAssertFalse(style.showsShadow)
        XCTAssertEqual(style.effectiveShadowWidth, 0, "总开关关闭后阴影扩散不生效")
    }

    func testDecoratedKeepsIdentityAndUpdatesPixelSize() throws {
        let original = ScreenshotResult(
            imageData: makePNG(width: 20, height: 10),
            width: 20,
            height: 10,
            captureDate: Date(timeIntervalSince1970: 0),
            sourceType: .region,
            regionSelection: nil
        )

        let untouched = ScreenshotFrameStyle().decorated(original)
        XCTAssertEqual(untouched.imageData, original.imageData)
        XCTAssertEqual(untouched.id, original.id)

        var style = ScreenshotFrameStyle()
        style.borderWidth = 5
        let decorated = style.decorated(original)
        XCTAssertEqual(decorated.id, original.id, "装饰后不得换 id")
        XCTAssertEqual(decorated.width, 30)
        XCTAssertEqual(decorated.height, 20)
        XCTAssertEqual(decorated.sourceType, original.sourceType)
    }

    // MARK: - Helpers

    private func makePNG(width: Int, height: Int, color: NSColor = .red) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}


// MARK: - JPEG 导出格式

final class ScreenshotImageFormatTests: XCTestCase {

    private func makePNG(width: Int, height: Int, color: NSColor = .red) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// 带透明区域的 PNG：用于验证 JPEG 白底压平。
    private func makeTransparentPNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testDefaultFormatIsPNGSoBehaviorDoesNotRegress() throws {
        let suiteName = "ScreenshotImageFormatTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ScreenshotImageFormat.default, .png)
        XCTAssertEqual(ScreenshotImageFormat.current(from: defaults), .png)

        defaults.set("somethingElse", forKey: ScreenshotImageFormat.DefaultsKey.imageFormat)
        XCTAssertEqual(ScreenshotImageFormat.current(from: defaults), .png, "非法值回落 PNG")
    }

    func testCurrentReadsStoredFormat() throws {
        let suiteName = "ScreenshotImageFormatTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(ScreenshotImageFormat.jpeg.rawValue, forKey: ScreenshotImageFormat.DefaultsKey.imageFormat)
        XCTAssertEqual(ScreenshotImageFormat.current(from: defaults), .jpeg)
    }

    func testFileExtensions() {
        XCTAssertEqual(ScreenshotImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ScreenshotImageFormat.jpeg.fileExtension, "jpg")
    }

    func testPNGEncodingIsByteIdentical() {
        let png = makePNG(width: 8, height: 8)

        XCTAssertEqual(
            ScreenshotImageEncoder.encode(png, format: .png),
            png,
            "PNG 必须原样返回，保证导出逐字节不变"
        )
    }

    func testJPEGEncodingProducesJPEGData() throws {
        let png = makePNG(width: 16, height: 16)

        let jpeg = ScreenshotImageEncoder.encode(png, format: .jpeg)

        XCTAssertNotEqual(jpeg, png)
        // JPEG 以 SOI 标记 FF D8 开头、以 EOI 标记 FF D9 结尾。
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(Array(jpeg.suffix(2)), [0xFF, 0xD9])
    }

    func testJPEGKeepsPixelDimensions() throws {
        let png = makePNG(width: 20, height: 12)

        let jpeg = try XCTUnwrap(ScreenshotImageEncoder.encodeJPEG(png))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: jpeg))

        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 12, "JPEG 编码不得改变像素尺寸")
    }

    func testJPEGFlattensTransparencyToWhiteInsteadOfBlack() throws {
        let png = makeTransparentPNG(width: 20, height: 20)

        let jpeg = try XCTUnwrap(ScreenshotImageEncoder.encodeJPEG(png))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: jpeg))
        let right = try XCTUnwrap(rep.colorAt(x: 18, y: 10)?.usingColorSpace(.sRGB))

        // 透明区域应压平为白底：若被当作黑色，JPEG 上会出现明显黑边。
        XCTAssertGreaterThan(right.redComponent, 0.9)
        XCTAssertGreaterThan(right.greenComponent, 0.9)
        XCTAssertGreaterThan(right.blueComponent, 0.9)
    }

    func testJPEGEncodingReturnsNilForGarbage() {
        XCTAssertNil(ScreenshotImageEncoder.encodeJPEG(Data([0x00, 0x01])))
    }

    func testUndecodableDataFallsBackToOriginal() {
        let garbage = Data([0x00, 0x01, 0x02])

        XCTAssertEqual(
            ScreenshotImageEncoder.encode(garbage, format: .jpeg),
            garbage,
            "编码失败时回退原数据，绝不产出空文件"
        )
    }

    func testFormatLocalizationKeys() {
        for format in ScreenshotImageFormat.allCases {
            XCTAssertFalse(L10n.localized(format.localizationKey).isEmpty)
        }
    }
}
