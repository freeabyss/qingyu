import AppKit
import XCTest
@testable import Qingyu

@MainActor
final class PinPayloadFactoryTests: XCTestCase {

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinPayloadFactoryTests-\(UUID().uuidString)"))
        pasteboard.releaseGlobally()
        return pasteboard
    }

    private func makePNGData(size: NSSize = NSSize(width: 32, height: 24)) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    // MARK: - Resolution order

    func testImagePayloadDetectedFirst() throws {
        let pasteboard = makePasteboard()
        pasteboard.setData(makePNGData(), forType: .png)
        pasteboard.setString("#123456", forType: .string)

        let factory = PinPayloadFactory()
        XCTAssertEqual(try factory.makePayload(from: pasteboard).kind, .image)
    }

    func testHexColorPayload() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("#123456", forType: .string)

        let factory = PinPayloadFactory()
        let payload = try factory.makePayload(from: pasteboard)
        XCTAssertEqual(payload.kind, .color)
        XCTAssertEqual(payload, .color(red: 18, green: 52, blue: 86))
    }

    func testDecimalColorPayload() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("18, 52, 86", forType: .string)

        let factory = PinPayloadFactory()
        XCTAssertEqual(try factory.makePayload(from: pasteboard), .color(red: 18, green: 52, blue: 86))
    }

    func testPlainTextPayload() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("示例文本", forType: .string)

        let factory = PinPayloadFactory()
        XCTAssertEqual(try factory.makePayload(from: pasteboard), .text("示例文本"))
    }

    func testEmptyPasteboardThrows() {
        let pasteboard = makePasteboard()

        XCTAssertThrowsError(try PinPayloadFactory().makePayload(from: pasteboard)) { error in
            XCTAssertEqual(error as? PinPayloadFactoryError, .emptyPasteboard)
        }
    }

    func testInvalidImageDataThrowsInsteadOfCreatingEmptyPin() {
        let pasteboard = makePasteboard()
        pasteboard.setData(Data([0x00, 0x01, 0x02]), forType: .png)

        XCTAssertThrowsError(try PinPayloadFactory().makePayload(from: pasteboard)) { error in
            XCTAssertEqual(error as? PinPayloadFactoryError, .imageDecodeFailed)
        }
    }

    // MARK: - HTML

    func testHTMLBecomesLocalAttributedTextWithoutScriptOrRemoteResources() throws {
        let pasteboard = makePasteboard()
        let html = """
        <html><body>
        <script>alert('remote')</script>
        <b>Bold</b> and <img src="https://example.com/remote.png">
        </body></html>
        """
        pasteboard.setData(Data(html.utf8), forType: .html)

        let payload = try PinPayloadFactory().makePayload(from: pasteboard)
        XCTAssertEqual(payload.kind, .attributedText)
        guard case .attributedText(let attributed) = payload else {
            return XCTFail("Expected attributed text")
        }
        let plain = attributed.string
        XCTAssertTrue(plain.contains("Bold"), "本地富文本应保留文字")
        XCTAssertFalse(plain.contains("alert"), "脚本内容应被丢弃")
        XCTAssertNil(attributed.attribute(.attachment, at: 0, effectiveRange: nil) ?? attributed.attribute(.attachment, at: max(0, attributed.length - 1), effectiveRange: nil), "远程图片附件应被剥离")
        XCTAssertNil(attributed.attribute(.link, at: 0, effectiveRange: nil))
    }

    // MARK: - File path first→image, again→text

    func testFilePathFirstPinBecomesImageAndSecondBecomesText() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinPayloadFactoryTests-\(UUID().uuidString).png")
        try makePNGData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let factory = PinPayloadFactory(filePathToImage: true)

        let first = try factory.makePayload(from: makePathPasteboard(path: fileURL.path))
        XCTAssertEqual(first.kind, .image, "文件路径首贴应转图片")

        let second = try factory.makePayload(from: makePathPasteboard(path: fileURL.path))
        XCTAssertEqual(second.kind, .text, "同一路径再次贴图应按纯文本")
    }

    func testFilePathToImageDisabledYieldsText() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinPayloadFactoryTests-\(UUID().uuidString).png")
        try makePNGData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let factory = PinPayloadFactory(filePathToImage: false)
        let payload = try factory.makePayload(from: makePathPasteboard(path: fileURL.path))
        XCTAssertEqual(payload.kind, .text)
    }

    private func makePathPasteboard(path: String) -> NSPasteboard {
        let pasteboard = makePasteboard()
        pasteboard.setString(path, forType: .string)
        return pasteboard
    }

    // MARK: - Color parsing

    func testParseColorAcceptsHexCaseInsensitive() {
        let parsed = PinPayloadFactory.parseColor("#aBcDeF")
        XCTAssertEqual(parsed?.red, 0xAB)
        XCTAssertEqual(parsed?.green, 0xCD)
        XCTAssertEqual(parsed?.blue, 0xEF)
        XCTAssertNil(PinPayloadFactory.parseColor("#12345"))
        XCTAssertNil(PinPayloadFactory.parseColor("not a color"))
    }
}
