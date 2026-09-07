import CoreGraphics
import XCTest
@testable import Qingniao

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

    // MARK: - CaptureHistory basics

    func testPreviousNavigatesNewestToOldest() {
        let history = CaptureHistory()
        let a = makeResult(), b = makeResult(), c = makeResult()
        history.record(a, completion: .copied)
        history.record(b, completion: .saved(URL(fileURLWithPath: "/tmp/b.png")))
        history.record(c, completion: .quickSaved(URL(fileURLWithPath: "/tmp/c.png")))

        XCTAssertEqual(history.previous(from: c.id)?.id, b.id)
        XCTAssertEqual(history.previous(from: b.id)?.id, a.id)
        XCTAssertNil(history.previous(from: a.id), "已是最旧，边界不循环")
    }

    func testPreviousFromNilReturnsNewest() {
        let history = CaptureHistory()
        let a = makeResult(), b = makeResult()
        history.record(a, completion: .copied)
        history.record(b, completion: .copied)

        XCTAssertEqual(history.previous(from: nil)?.id, b.id)
    }

    func testNextNavigatesWithoutWrapping() {
        let history = CaptureHistory()
        let a = makeResult(), b = makeResult(), c = makeResult()
        history.record(a, completion: .copied)
        history.record(b, completion: .copied)
        history.record(c, completion: .copied)

        XCTAssertEqual(history.next(from: a.id)?.id, b.id)
        XCTAssertEqual(history.next(from: b.id)?.id, c.id)
        XCTAssertNil(history.next(from: c.id), "已是最新，边界不循环")
        XCTAssertNil(history.next(from: nil), "未知当前位置时 next 不可用")
    }

    func testHistoryClampsMaximumCountToOneThroughTwoHundred() {
        XCTAssertEqual(CaptureHistory(maximumCount: 0).maximumCount, 1)
        XCTAssertEqual(CaptureHistory(maximumCount: -5).maximumCount, 1)
        XCTAssertEqual(CaptureHistory(maximumCount: 500).maximumCount, 200)
        XCTAssertEqual(CaptureHistory(maximumCount: 42).maximumCount, 42)
    }

    func testHistoryDropsOldestEntriesBeyondCapacity() {
        let history = CaptureHistory(maximumCount: 2)
        let a = makeResult(), b = makeResult(), c = makeResult()
        history.record(a, completion: .copied)
        history.record(b, completion: .copied)
        history.record(c, completion: .copied)

        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history.contains(id: a.id), "超出容量应丢弃最旧记录")
        XCTAssertEqual(history.previous(from: nil)?.id, c.id)
    }

    // MARK: - Coordinator outcomes

    func testCopyCompletionWritesPasteboardOnceAndRecords() async throws {
        let history = CaptureHistory()
        let coordinator = CaptureCompletionCoordinator(handlers: .testHandlers(), history: history)
        let result = makeResult()

        let outcome = try await coordinator.perform(.copy, result: result)

        XCTAssertEqual(outcome, .completed(.copied))
        XCTAssertEqual(history.count, 1, "每个成功终局只写一条记录")
        XCTAssertTrue(history.contains(id: result.id))
    }

    func testQuickSaveWritesFileAndRecordsOnce() async throws {
        let history = CaptureHistory()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCompletionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.quickSaveDirectory = { directory }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers, history: history)
        let result = makeResult()

        let outcome = try await coordinator.perform(.quickSave, result: result)

        guard case .completed(.quickSaved(let url)) = outcome else {
            return XCTFail("Expected quickSaved outcome")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.previous(from: nil)?.id, result.id)
    }

    func testSaveThroughInjectedPanelRecordsOnce() async throws {
        let history = CaptureHistory()
        var handlers = CaptureCompletionHandlers.testHandlers()
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCompletionTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: targetURL) }
        handlers.savePanel = { _ in targetURL }

        let coordinator = CaptureCompletionCoordinator(handlers: handlers, history: history)
        let result = makeResult()

        let outcome = try await coordinator.perform(.save, result: result)

        XCTAssertEqual(outcome, .completed(.saved(targetURL)))
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testCancelledSavePanelThrowsAndDoesNotRecord() async {
        let history = CaptureHistory()
        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.savePanel = { _ in nil }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers, history: history)

        do {
            _ = try await coordinator.perform(.save, result: makeResult())
            XCTFail("Expected cancellation error")
        } catch {
            XCTAssertEqual(history.count, 0, "取消不写记录")
        }
    }

    func testPrintReturnsPrintedAndNeverRecords() async throws {
        let history = CaptureHistory()
        var printed = false
        var handlers = CaptureCompletionHandlers.testHandlers()
        handlers.print = { _ in printed = true }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers, history: history)

        let outcome = try await coordinator.perform(.print, result: makeResult())

        XCTAssertEqual(outcome, .printed)
        XCTAssertTrue(printed)
        XCTAssertEqual(history.count, 0, "打印不进入记录")
    }

    func testPinRequiresHandler() async {
        let history = CaptureHistory()
        let coordinator = CaptureCompletionCoordinator(handlers: .testHandlers(), history: history)

        do {
            _ = try await coordinator.perform(.pin, result: makeResult())
            XCTFail("Expected unsupported pin error")
        } catch let error as CaptureCompletionError {
            XCTAssertEqual(error, .unsupportedAction(.pin))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(history.count, 0)
    }

    func testPinHandlerProducesPinnedCompletion() async throws {
        let history = CaptureHistory()
        var handlers = CaptureCompletionHandlers.testHandlers()
        let recordID = UUID()
        handlers.pin = { _ in recordID }
        let coordinator = CaptureCompletionCoordinator(handlers: handlers, history: history)

        let outcome = try await coordinator.perform(.pin, result: makeResult())

        XCTAssertEqual(outcome, .completed(.pinned(recordID)))
        XCTAssertEqual(history.count, 1)
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
