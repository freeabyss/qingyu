import Foundation
import AppKit

// MARK: - Capture completion model (Task 007)

/// 一次成功截图的终局类型。`pinned` 由 Task 008 的贴图转换签发贴图条目 ID。
enum CaptureCompletion: Equatable {
    case copied
    case saved(URL)
    case quickSaved(URL)
    case pinned(UUID)
}

/// 用户可触发的终局动作；成功终局仅结束当前截图会话，不保留历史记录。
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
    /// 「另存为」面板；返回 nil 表示用户取消。NSSavePanel 链路为 MainActor 隔离。
    var savePanel: @MainActor (String) async -> URL?
    /// 贴图转换（Task 008 注入）；未注入时贴图不可用。
    var pin: ((ScreenshotResult) async throws -> UUID)?
    /// 导出**落盘**格式（PNG / JPEG）；默认 PNG，与引入前行为一致。
    /// 剪贴板路径不使用它（始终 PNG，见 `ScreenshotImageFormat` 的说明）。
    var imageFormat: () -> ScreenshotImageFormat = { .png }
    /// Task 014/03：导出前的圆角 / 边框 / 阴影装饰。`nil` 或全关时原样导出。
    ///
    /// 只作用于「复制 / 保存 / 快捷保存」；贴图与打印沿用原始像素
    /// （贴图窗口自带阴影、且需对齐屏幕上原选区位置）。
    var decorate: ((ScreenshotResult) async -> ScreenshotResult)? = nil
    /// 打印（仅结束会话，不产生记录）。NSImageView/NSPrintOperation 为 MainActor 隔离。
    var print: (@MainActor (ScreenshotResult) -> Void)?

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
            imageFormat: { ScreenshotImageFormat.current() },
            decorate: { result in
                let style = ScreenshotFrameStyle.current()
                return style.decorated(result, scale: ScreenshotFrameStyle.displayScale())
            },
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
/// 失败与用户取消向上抛错，由调用方保留会话；
/// 成功终局仅结束当前会话，不保留任何历史记录。
@MainActor
final class CaptureCompletionCoordinator {
    private let handlers: CaptureCompletionHandlers

    init(handlers: CaptureCompletionHandlers = .live()) {
        self.handlers = handlers
    }

    func perform(_ action: CaptureCompletionAction, result: ScreenshotResult) async throws -> CaptureCompletionOutcome {
        try await resolve(action, result: result)
    }

    private func resolve(_ action: CaptureCompletionAction, result: ScreenshotResult) async throws -> CaptureCompletionOutcome {
        switch action {
        case .copy:
            try Self.copyToPasteboard(await decorated(result))
            return .completed(.copied)

        case .save:
            guard let url = await handlers.savePanel(handlers.suggestedFilename(result)) else {
                throw SnapVaultError.screenshotFailed(reason: SnapVaultError.userCancelledReason)
            }
            try Self.writeImage((await decorated(result)).imageData, to: url, format: handlers.imageFormat())
            return .completed(.saved(url))

        case .quickSave:
            let directory = await handlers.quickSaveDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let format = handlers.imageFormat()
            let url = directory
                .appendingPathComponent(handlers.suggestedFilename(result))
                .appendingPathExtension(format.fileExtension)
            try Self.writeImage((await decorated(result)).imageData, to: url, format: format)
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

    /// Task 014/03：按当前圆角 / 边框 / 阴影设置装饰结果图；未注入或全关时原样返回。
    private func decorated(_ result: ScreenshotResult) async -> ScreenshotResult {
        guard let decorate = handlers.decorate else { return result }
        return await decorate(result)
    }

    static func copyToPasteboard(_ result: ScreenshotResult) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(result.imageData, forType: .png) else {
            throw CaptureCompletionError.pasteboardWriteFailed
        }
    }

    static func writePNG(_ data: Data, to url: URL) throws {
        try writeImage(data, to: url, format: .png)
    }

    /// 按格式编码后写盘。PNG 原样、JPEG 白底压平后重编码。
    static func writeImage(_ data: Data, to url: URL, format: ScreenshotImageFormat) throws {
        do {
            try ScreenshotImageEncoder.encode(data, format: format).write(to: url, options: .atomic)
        } catch {
            throw CaptureCompletionError.fileWriteFailed
        }
    }
}
