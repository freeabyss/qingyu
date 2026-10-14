import CoreGraphics
import XCTest
@testable import Qingyu

@MainActor
final class CaptureCompletionTests: XCTestCase {

    private func makeResult(date: Date = Date()) -> ScreenshotResult {
        ScreenshotResult(
            imageData: Data([0x89, 0x50]),
            width: 100,
            height: 80,
            captureDate: date,
            sourceType: .region,
            regionSelection: nil
        )
    }

    // MARK: - Coordinator outcomes

    func testCopyCompletionWritesPasteboard() async throws {
        let coordinator = CaptureCompletionCoordinator(handlers: .testHandlers())
        let result = makeResult()

        let outcome = try await coordinator.perform(.copy, result: result)

        XCTAssertEqual(outcome, .completed(.copied))
    }

    func testQuickSaveWritesFileToInjectedDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCompletionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.quickSaveDirectory = { directory }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)
        let result = makeResult()

        let outcome = try await coordinator.perform(.quickSave, result: result)

        guard case .completed(.quickSaved(let url)) = outcome else {
            return XCTFail("Expected quickSaved outcome")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSaveThroughInjectedPanelWritesFile() async throws {
        var handlers = CaptureCompletionHandlers.testHandlers()
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCompletionTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: targetURL) }
        handlers.savePanel = { _ in targetURL }

        let coordinator = CaptureCompletionCoordinator(handlers: handlers)
        let result = makeResult()

        let outcome = try await coordinator.perform(.save, result: result)

        XCTAssertEqual(outcome, .completed(.saved(targetURL)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testCancelledSavePanelThrowsCancellationError() async {
        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.savePanel = { _ in nil }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)

        do {
            _ = try await coordinator.perform(.save, result: makeResult())
            XCTFail("Expected cancellation error")
        } catch {
            // 取消向上抛错：调用方据此保留会话；终局不产生任何历史记录。
            guard case SnapVaultError.screenshotFailed(let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reason, SnapVaultError.userCancelledReason)
        }
    }

    func testPrintReturnsPrintedOutcome() async throws {
        var printed = false
        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.print = { _ in printed = true }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)

        let outcome = try await coordinator.perform(.print, result: makeResult())

        XCTAssertEqual(outcome, .printed)
        XCTAssertTrue(printed)
    }

    func testPinRequiresHandler() async {
        let coordinator = CaptureCompletionCoordinator(handlers: .testHandlers())

        do {
            _ = try await coordinator.perform(.pin, result: makeResult())
            XCTFail("Expected unsupported pin error")
        } catch let error as CaptureCompletionError {
            XCTAssertEqual(error, .unsupportedAction(.pin))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPinHandlerProducesPinnedCompletion() async throws {
        var handlers = CaptureCompletionHandlers.testHandlers()
        let pinItemID = UUID()
        handlers.pin = { _ in pinItemID }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)

        let outcome = try await coordinator.perform(.pin, result: makeResult())

        XCTAssertEqual(outcome, .completed(.pinned(pinItemID)))
    }
}

extension CaptureCompletionHandlers {
    /// 单测替身：可注入目录/面板/贴图/打印；默认全部走内存或临时路径。
    static func testHandlers() -> CaptureCompletionHandlers {
        CaptureCompletionHandlers(
            quickSaveDirectory: { FileManager.default.temporaryDirectory },
            suggestedFilename: { result in CaptureCompletionHandlers.defaultFilename(for: result.captureDate) },
            savePanel: { _ in nil },
            pin: nil,
            print: { _ in }
        )
    }
}

// MARK: - Task 014/03：导出装饰挂载点

extension CaptureCompletionTests {
    /// 用固定字节替换图像，便于在终局产物上断言装饰是否生效。
    private func decorateHandlers(
        marker: Data,
        into handlers: inout CaptureCompletionHandlers
    ) {
        handlers.decorate = { result in
            ScreenshotResult(
                id: result.id,
                imageData: marker,
                width: 12,
                height: 8,
                captureDate: result.captureDate,
                sourceType: result.sourceType,
                regionSelection: result.regionSelection
            )
        }
    }

    func testCopyExportsDecoratedPixels() async throws {
        let marker = Data("decorated-png".utf8)
        var handlers = CaptureCompletionHandlers.testHandlers()
        decorateHandlers(marker: marker, into: &handlers)
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)

        _ = try await coordinator.perform(.copy, result: makeResult())

        XCTAssertEqual(NSPasteboard.general.data(forType: .png), marker)
    }

    func testSaveWritesDecoratedPixels() async throws {
        let marker = Data("decorated-png".utf8)
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCompletionDecorated-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: targetURL) }

        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.savePanel = { _ in targetURL }
        decorateHandlers(marker: marker, into: &handlers)
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)

        _ = try await coordinator.perform(.save, result: makeResult())

        XCTAssertEqual(try Data(contentsOf: targetURL), marker)
    }

    /// 贴图与打印必须拿到原始像素：贴图窗口自带阴影，且要沿用在屏幕上的选区位置。
    func testPinAndPrintKeepOriginalPixels() async throws {
        var decoratedCalls = 0
        var pinnedImageData: Data?
        var printedImageData: Data?

        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.decorate = { result in
            decoratedCalls += 1
            return result
        }
        handlers.pin = { result in
            pinnedImageData = result.imageData
            return UUID()
        }
        handlers.print = { result in
            printedImageData = result.imageData
        }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers)
        let original = makeResult()

        _ = try await coordinator.perform(.pin, result: original)
        _ = try await coordinator.perform(.print, result: original)

        XCTAssertEqual(decoratedCalls, 0, "贴图与打印不应经过导出装饰")
        XCTAssertEqual(pinnedImageData, original.imageData)
        XCTAssertEqual(printedImageData, original.imageData)
    }
}
