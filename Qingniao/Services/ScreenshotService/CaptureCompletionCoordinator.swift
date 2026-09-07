import Foundation
import AppKit

// MARK: - Capture completion model (Task 007)

/// 一次成功截图的终局类型。`pinned` 由 Task 008 的贴图转换签发记录 ID。
enum CaptureCompletion: Equatable {
    case copied
    case saved(URL)
    case quickSaved(URL)
    case pinned(UUID)
}

/// 用户可触发的终局动作；打印不进入历史记录。
enum CaptureCompletionAction {
    case copy
    case save
    case quickSave
    case pin
    case print
}

enum CaptureCompletionOutcome: Equatable {
    case completed(CaptureCompletion)
    case printed
}

/// 协调器可用的系统边界；单测注入替身，生产使用 `live`。
struct CaptureCompletionHandlers {
    /// 快捷保存目录（读取截图设置，默认 `~/Desktop`）。
    var quickSaveDirectory: () async -> URL
    /// 依据捕获结果生成建议文件名（不含扩展名）。
    var suggestedFilename: (ScreenshotResult) -> String
    /// 「另存为」面板；返回 nil 表示用户取消。
    var savePanel: (String) async -> URL?
    /// 贴图转换（Task 008 注入）；未注入时贴图不可用。
    var pin: ((ScreenshotResult) async throws -> UUID)?
    /// 打印（不写入历史）。
    var print: ((ScreenshotResult) -> Void)?

    static func live() -> CaptureCompletionHandlers {
        CaptureCompletionHandlers(
            quickSaveDirectory: {
                let service = SettingsService(persistence: .shared)
                return (try? await service.value(for: .screenshotQuickSaveDirectory, as: URL.self))
                    ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
            },
            suggestedFilename: { result in
                Self.defaultFilename(for: result.captureDate)
            },
            savePanel: { suggestedName in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = suggestedName
                panel.allowedContentTypes = [.png]
                return panel.runModal() == .OK ? panel.url : nil
            },
            pin: nil,
            print: { result in
                let imageView = NSImageView(frame: NSRect(
                    x: 0, y: 0,
                    width: min(792, CGFloat(result.width)),
                    height: min(612, CGFloat(result.height))
                ))
                imageView.image = NSImage(data: result.imageData)
                let operation = NSPrintOperation(view: imageView)
                operation.showsPrintPanel = true
                operation.run()
            }
        )
    }

    static func defaultFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }
}

enum CaptureCompletionError: LocalizedError, Equatable {
    case unsupportedAction(CaptureCompletionAction)
    case pasteboardWriteFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAction(let action):
            return "Action not available: \(action)"
        case .pasteboardWriteFailed:
            return "Failed to write capture to pasteboard"
        case .fileWriteFailed:
            return "Failed to write capture to disk"
        }
    }
}

// MARK: - CaptureCompletionCoordinator

/// 所有截图终局的唯一出口：复制、保存、快捷保存、贴图、打印。
/// 失败与用户取消向上抛错，由调用方保留会话且不写记录；
/// 只有 `.completed` 终局应写入 `CaptureHistory`。
@MainActor
final class CaptureCompletionCoordinator {
    private let handlers: CaptureCompletionHandlers
    /// 注入后：每个 `.completed` 终局自动写入一条运行期记录（单点保证不重不漏）。
    private let history: CaptureHistory?

    init(handlers: CaptureCompletionHandlers = .live(), history: CaptureHistory? = nil) {
        self.handlers = handlers
        self.history = history
    }

    func perform(_ action: CaptureCompletionAction, result: ScreenshotResult) async throws -> CaptureCompletionOutcome {
        let outcome = try await resolve(action, result: result)
        if case .completed(let completion) = outcome {
            history?.record(result, completion: completion)
        }
        return outcome
    }

    private func resolve(_ action: CaptureCompletionAction, result: ScreenshotResult) async throws -> CaptureCompletionOutcome {
        switch action {
        case .copy:
            try Self.copyToPasteboard(result)
            return .completed(.copied)

        case .save:
            guard let url = await handlers.savePanel(handlers.suggestedFilename(result)) else {
                throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
            }
            try Self.writePNG(result.imageData, to: url)
            return .completed(.saved(url))

        case .quickSave:
            let directory = await handlers.quickSaveDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory
                .appendingPathComponent(handlers.suggestedFilename(result))
                .appendingPathExtension("png")
            try Self.writePNG(result.imageData, to: url)
            return .completed(.quickSaved(url))

        case .pin:
            guard let pin = handlers.pin else {
                throw CaptureCompletionError.unsupportedAction(.pin)
            }
            let recordID = try await pin(result)
            return .completed(.pinned(recordID))

        case .print:
            guard let print = handlers.print else {
                throw CaptureCompletionError.unsupportedAction(.print)
            }
            print(result)
            return .printed
        }
    }

    // MARK: - Helpers

    static func copyToPasteboard(_ result: ScreenshotResult) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(result.imageData, forType: .png) else {
            throw CaptureCompletionError.pasteboardWriteFailed
        }
    }

    static func writePNG(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CaptureCompletionError.fileWriteFailed
        }
    }
}

// MARK: - CaptureHistory

/// 运行期截图记录：内存队列，默认 20 条、范围 `1…200`，超出丢弃最旧记录。
/// `,` 跳到上一条（更旧）、`.` 跳到下一条（更新），边界不循环。
/// 截图会话状态不写 Core Data。
@MainActor
final class CaptureHistory {
    struct Entry {
        let result: ScreenshotResult
        let completion: CaptureCompletion
    }

    static let defaultMaximumCount = 20
    static let minimumAllowedCount = 1
    static let maximumAllowedCount = 200

    private(set) var maximumCount: Int
    private var entries: [Entry] = []

    var count: Int { entries.count }

    init(maximumCount: Int = CaptureHistory.defaultMaximumCount) {
        self.maximumCount = min(max(maximumCount, Self.minimumAllowedCount), Self.maximumAllowedCount)
    }

    /// 只在成功终局时调用：每个终局恰好一条记录。
    func record(_ result: ScreenshotResult, completion: CaptureCompletion) {
        entries.append(Entry(result: result, completion: completion))
        if entries.count > maximumCount {
            entries.removeFirst(entries.count - maximumCount)
        }
    }

    /// `⌘,`：`from` 为 nil 时返回最新记录；已是最旧时返回 nil（不循环）。
    func previous(from id: UUID?) -> ScreenshotResult? {
        guard !entries.isEmpty else { return nil }
        guard let id,
              let index = entries.lastIndex(where: { $0.result.id == id }) else {
            return entries.last?.result
        }
        guard index > 0 else { return nil }
        return entries[index - 1].result
    }

    /// `⌘.`：跳到下一条（更新）；已是最新或 `from` 未知时返回 nil（不循环）。
    func next(from id: UUID?) -> ScreenshotResult? {
        guard let id,
              let index = entries.lastIndex(where: { $0.result.id == id }) else {
            return nil
        }
        guard index < entries.count - 1 else { return nil }
        return entries[index + 1].result
    }

    func contains(id: UUID) -> Bool {
        entries.contains { $0.result.id == id }
    }

    func clear() {
        entries.removeAll()
    }

    /// UI 层共享的运行期记录（会话状态不写 Core Data）。
    static let shared = CaptureHistory()
}
