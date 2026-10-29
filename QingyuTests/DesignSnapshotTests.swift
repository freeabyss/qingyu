import AppKit
import SwiftUI
import XCTest
@testable import Qingyu

/// 设计快照：把**真实** SwiftUI 视图离屏渲染成 PNG，用于肉眼检查真实排版，
/// 而不是只读代码推断设计质量。
///
/// 每个快照断言三件事（都能抓住真实回归）：
/// 1. 渲染成功：视图布局不崩、`ImageRenderer` 返回非空位图；
/// 2. 像素尺寸与请求一致：布局没有被压成 0 或意外撑大；
/// 3. 画面不是单色：空渲染 / 全透明在视觉上就是白屏。
///
/// PNG 输出目录由环境变量 `QINGYU_SNAPSHOT_DIR` 指定，默认 `/tmp/qingyu-snapshots`。
/// 快照文件是评审证据，不进仓库。
@MainActor
final class DesignSnapshotTests: XCTestCase {

    // MARK: - 被测界面

    /// 剪贴板历史主窗口：空状态。
    func testClipboardHistorySnapshot() throws {
        try renderBothSchemes(
            ClipboardHistoryView(viewModel: ClipboardListViewModel()),
            size: CGSize(width: 900, height: 560),
            name: "clipboard-history-empty"
        )
    }

    /// 命令栏：空查询时面板就是输入框本身。
    func testCommandBarSnapshot() throws {
        try renderBothSchemes(
            CommandBarView(viewModel: SearchPanelViewModel(searchService: SearchService(sources: []))),
            size: CGSize(width: 760, height: 140),
            name: "command-bar-empty"
        )
    }

    /// 剪贴板详情面板：无选中项的空状态。
    func testClipboardDetailPaneSnapshot() throws {
        try renderBothSchemes(
            ClipboardDetailPane(
                item: nil,
                imageProvider: { _ in nil },
                richTextProvider: { _ in nil }
            ),
            size: CGSize(width: 360, height: 400),
            name: "clipboard-detail-empty"
        )
    }

    // MARK: - 渲染管线

    private func renderBothSchemes<V: View>(_ view: V, size: CGSize, name: String) throws {
        for scheme in [ColorScheme.light, .dark] {
            try render(view, size: size, scheme: scheme, name: name)
        }
    }

    private func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, name: String) throws {
        guard #available(macOS 13.0, *) else {
            throw XCTSkip("ImageRenderer 需要 macOS 13 及以上")
        }

        let appearanceName: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        XCTAssertNotNil(appearance, "\(appearanceName.rawValue) 外观不可用")

        let canvas = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))

        var rendered: CGImage?
        // JadeColor 用动态 NSColor 随 NSAppearance 解析：必须在目标外观下绘制，
        // 否则深色快照会渲染成浅色（评审证据失真）。
        appearance?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 2
            rendered = renderer.cgImage
        }

        guard let cgImage = rendered else {
            XCTFail("\(name) [\(scheme == .dark ? "dark" : "light")] 渲染失败：ImageRenderer 未产出位图")
            return
        }

        let expectedWidth = Int(size.width * 2)
        let expectedHeight = Int(size.height * 2)
        XCTAssertEqual(cgImage.width, expectedWidth, "\(name) 渲染宽度与请求不一致")
        XCTAssertEqual(cgImage.height, expectedHeight, "\(name) 渲染高度与请求不一致")
        XCTAssertGreaterThan(
            distinctColorCount(of: cgImage), 3,
            "\(name) [\(scheme == .dark ? "dark" : "light")] 画面接近单色，疑似空渲染"
        )

        try writePNG(cgImage, name: "\(name)-\(scheme == .dark ? "dark" : "light")")
    }

    // MARK: - 证据落盘

    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["QINGYU_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("qingyu-snapshots", isDirectory: true)
    }

    private func writePNG(_ image: CGImage, name: String) throws {
        let directory = Self.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("\(name) PNG 编码失败")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("[design-snapshot] \(url.path)")
    }

    // MARK: - 单色检测

    /// 在网格上采样像素，返回不同 RGB 组合的数量；用于识别空渲染。
    private func distinctColorCount(of image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) else { return 0 }
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return 0 }
        let bytesPerRow = image.bytesPerRow
        var seen = Set<UInt32>()
        let columns = 32
        let rows = 32
        for row in 0..<rows {
            let y = min(image.height - 1, row * max(1, image.height / rows))
            for column in 0..<columns {
                let x = min(image.width - 1, column * max(1, image.width / columns))
                let offset = y * bytesPerRow + x * bytesPerPixel
                let key = UInt32(pointer[offset]) << 16
                    | UInt32(pointer[offset + 1]) << 8
                    | UInt32(pointer[offset + 2])
                seen.insert(key)
            }
        }
        return seen.count
    }
}
