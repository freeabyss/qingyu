import AppKit
import XCTest
@testable import Qingyu

/// 区域「草稿」工具条的窗口契约（产品决策 2026-10-17：框选松开即出工具条）。
///
/// 这些断言都落在**真实窗口**上，因为出问题的地方正是窗口层面：
/// - 松开后工具条必须立刻可见（用户报告过「框选成功后没有工具栏」）；
/// - 草稿态**不得夺 key**——截图会话仍在进行，活动叠层必须继续持有键盘，
///   否则方向键微调、`Tab` 辅助线、`Enter` 确认、`P`/`⌘S` 预设全部失效；
/// - 方向键微调只更新位置、不重建窗口（重建会闪一下）；
/// - 真正抓屏推迟到用户点动作时（懒捕获），微调后画面不会过期。
@MainActor
final class RegionDraftToolbarTests: XCTestCase {

    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// 记录调用的捕获替身：草稿态下不应被调用；点动作时才被调用一次。
    private final class CaptureSpy {
        private(set) var calls = 0
        var result: ScreenshotResult?

        func capture() async throws -> ScreenshotResult {
            calls += 1
            guard let result else {
                throw SnapVaultError.screenshotFailed(reason: "draft capture is not expected here")
            }
            return result
        }
    }

    /// 期望位置用**工具条自己的尺寸**计算：尺寸由内容（17 个紧凑按钮）决定。
    private func expectedFrame(for selection: CGRect, controller: ScreenshotToolbarController) -> NSRect {
        ScreenshotGeometry.toolbarFrame(
            selection: selection,
            toolbarSize: controller.regionToolbarSize,
            screenFrame: screenFrame
        )
    }

    /// 窗口宽度必须容纳全部动作按钮：写死宽度会把复制/保存/贴图/关闭挤到窗口外。
    func testToolbarIsWideEnoughForItsContent() throws {
        let controller = ScreenshotToolbarController()
        controller.showRegionDraft(
            globalRect: CGRect(x: 200, y: 300, width: 600, height: 400),
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: {}
        )
        let window = try XCTUnwrap(controller.window)
        // 17 个 30pt 紧凑按钮 + 16 个 4pt 间距 + 两侧 4pt 内边距 = 582。
        XCTAssertGreaterThanOrEqual(window.frame.width, 580, "宽度必须容纳全部动作按钮")
        XCTAssertLessThanOrEqual(window.frame.width, screenFrame.width, "不得宽于屏幕")
    }

    /// 松开选区后立刻展示工具条，且**不**预捕获。
    func testDraftToolbarIsVisibleAtSelectionWithoutCapturing() throws {
        let controller = ScreenshotToolbarController()
        let spy = CaptureSpy()
        let selection = CGRect(x: 200, y: 300, width: 600, height: 400)

        controller.showRegionDraft(
            globalRect: selection,
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            onDismiss: {}
        )

        let window = try XCTUnwrap(controller.window, "松开选区后必须立刻建出工具条窗口")
        XCTAssertTrue(controller.isShowingRegionDraft)
        XCTAssertTrue(window.isVisible, "工具条必须可见，而不是只建了窗口")
        XCTAssertEqual(window.frame, expectedFrame(for: selection, controller: controller), "工具条应贴在选区下方居中")
        XCTAssertEqual(spy.calls, 0, "草稿态不得预捕获：抓屏推迟到用户点动作")
    }

    /// 草稿工具条禁止成为 key 窗口：会话期间键盘必须留在叠层上。
    func testDraftToolbarNeverStealsKey() throws {
        let controller = ScreenshotToolbarController()

        controller.showRegionDraft(
            globalRect: CGRect(x: 200, y: 300, width: 600, height: 400),
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: {}
        )

        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(
            window.becomesKeyOnlyIfNeeded,
            "草稿态工具条不得夺 key：一旦夺走，方向键微调 / Enter 确认就全部失效"
        )
        // 已捕获态（会话已结束）则可以正常拿 key，保证 Esc 与手势可用。
        // `showRegion` 内部会先把草稿工具条收掉，无需单独调用。
        controller.showRegion(
            result: try makeResult(),
            selection: RegionCaptureSelection(
                sessionID: UUID(),
                displayID: 1,
                screenFrame: screenFrame,
                globalRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            onDismiss: {}
        )
        XCTAssertFalse(try XCTUnwrap(controller.window).becomesKeyOnlyIfNeeded)
    }

    /// 方向键微调：只挪位置，窗口实例不变（否则每按一次键都闪一下）。
    func testDraftToolbarFollowsSelectionWithoutRecreatingWindow() throws {
        let controller = ScreenshotToolbarController()
        let first = CGRect(x: 200, y: 300, width: 600, height: 400)
        let moved = first.offsetBy(dx: -20, dy: 0)

        controller.showRegionDraft(
            globalRect: first,
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: {}
        )
        let window = try XCTUnwrap(controller.window)

        controller.showRegionDraft(
            globalRect: moved,
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: {}
        )

        XCTAssertTrue(controller.window === window, "微调只更新位置，不重建窗口")
        XCTAssertEqual(window.frame, expectedFrame(for: moved, controller: controller), "工具条应跟随选区左移")
    }

    /// 选区作废（例如显示器拓扑变化后重建叠层）：收起工具条，但**不**结束会话。
    func testDismissRegionDraftHidesToolbarWithoutEndingSession() throws {
        let controller = ScreenshotToolbarController()
        var dismissCallbacks = 0

        controller.showRegionDraft(
            globalRect: CGRect(x: 200, y: 300, width: 600, height: 400),
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: { dismissCallbacks += 1 }
        )
        let window = try XCTUnwrap(controller.window)

        controller.dismissRegionDraft()

        XCTAssertFalse(window.isVisible, "工具条必须收起")
        XCTAssertFalse(controller.isShowingRegionDraft)
        XCTAssertEqual(dismissCallbacks, 0, "作废不是用户放弃，不该结束会话")

        // 再次进入可微调态时应重新建出工具条。
        controller.showRegionDraft(
            globalRect: CGRect(x: 10, y: 10, width: 200, height: 200),
            screenFrame: screenFrame,
            capture: { throw SnapVaultError.screenshotFailed(reason: "unused") },
            onDismiss: {}
        )
        XCTAssertTrue(try XCTUnwrap(controller.window).isVisible)
        XCTAssertTrue(controller.isShowingRegionDraft)
    }

    /// 草稿态动作链路：点动作 → **此刻才抓屏** → 走既有动作路径（复制）→ 收掉工具条。
    ///
    /// 按钮本身的点击由窗口层保证（草稿工具条不夺 key、点击直接落到按钮上，
    /// 见 `testDraftToolbarNeverStealsKey`）；这里驱动按钮回调之后的链路。
    func testDraftActionCapturesLazilyThenPerformsAction() async throws {
        let controller = ScreenshotToolbarController()
        let spy = CaptureSpy()
        spy.result = try makeResult(withRealImage: true)

        controller.showRegionDraft(
            globalRect: CGRect(x: 200, y: 300, width: 600, height: 400),
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            onDismiss: {}
        )
        XCTAssertEqual(spy.calls, 0, "草稿态不得预捕获")

        try await withPreservedPasteboard {
            await controller.performDraftAction(.copy)

            XCTAssertEqual(spy.calls, 1, "点动作时才抓屏，且只抓一次")
            XCTAssertFalse(controller.isShowingRegionDraft)
            XCTAssertNil(controller.window, "动作完成后工具条应收起")
            XCTAssertNotNil(
                NSPasteboard.general.data(forType: .png),
                "「复制」应把捕获结果写进剪贴板"
            )
        }
    }

    /// 捕获失败：收掉工具条，不把用户留在「点了没反应」的状态。
    func testDraftActionDismissesToolbarWhenCaptureFails() async {
        let controller = ScreenshotToolbarController()
        let spy = CaptureSpy()   // result 为 nil → 捕获抛错

        controller.showRegionDraft(
            globalRect: CGRect(x: 200, y: 300, width: 600, height: 400),
            screenFrame: screenFrame,
            capture: { try await spy.capture() },
            onDismiss: {}
        )

        await controller.performDraftAction(.copy)

        XCTAssertEqual(spy.calls, 1)
        XCTAssertFalse(controller.isShowingRegionDraft)
        XCTAssertNil(controller.window)
    }

    /// 保存并还原系统剪贴板：复制动作会写它，测试不该留下痕迹。
    private func withPreservedPasteboard(_ body: () async throws -> Void) async rethrows {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
        defer {
            if let saved, !saved.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(saved)
            }
        }
        try await body()
    }

    private func makeResult(withRealImage: Bool = false) throws -> ScreenshotResult {
        let data: Data
        if withRealImage {
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 4,
                pixelsHigh: 4,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ))
            data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        } else {
            data = Data([0x89, 0x50, 0x4E, 0x47])
        }
        return ScreenshotResult(
            id: UUID(),
            imageData: data,
            width: 4,
            height: 4,
            captureDate: Date(),
            sourceType: .region,
            regionSelection: RegionCaptureSelection(
                sessionID: UUID(),
                displayID: 1,
                screenFrame: screenFrame,
                globalRect: CGRect(x: 200, y: 300, width: 600, height: 400)
            )
        )
    }
}
