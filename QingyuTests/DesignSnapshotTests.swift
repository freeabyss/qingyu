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
///
/// 已知局限：AppKit 支撑的控件（TextField / ProgressView 等）在 `ImageRenderer` 里
/// 会渲染成黄色「不支持」占位块。评审时把这类黄块当作「此处不可离屏验证」，
/// 不要误判成界面缺陷；它们需要真实窗口截图验证。
@MainActor
final class DesignSnapshotTests: XCTestCase {

    // MARK: - 被测界面

    /// 剪贴板历史主窗口：加载完成、没有任何记录。
    ///
    /// 注入 `SnapshotQueryService` 有两个作用：不让默认初始化里的后台索引重建任务干扰渲染，
    /// 以及让「空」是**确定的**空，而不是碰巧还没加载完。
    func testClipboardHistoryEmptySnapshot() async throws {
        let viewModel = ClipboardListViewModel(queryService: SnapshotQueryService(items: []))
        await viewModel.load()
        XCTAssertFalse(viewModel.isLoading, "加载结束后不应停留在加载态")
        XCTAssertTrue(viewModel.items.isEmpty, "空状态快照要求没有条目")

        try renderBothSchemes(
            ClipboardHistoryView(viewModel: viewModel, autoLoadsOnAppear: false),
            size: CGSize(width: 900, height: 560),
            name: "clipboard-history-empty"
        )
    }

    /// 剪贴板历史主窗口：首次读取中。
    ///
    /// 这是最容易做错的一个状态：`items` 为空 + `isLoading` 为 true 时，
    /// 早期实现会落进「列表 + 详情」分支，左栏整片空白，看起来像加载失败。
    func testClipboardHistoryLoadingSnapshot() async throws {
        let queryService = SnapshotQueryService(items: [Self.sampleIndexItem], blocksDetails: true)
        let viewModel = ClipboardListViewModel(queryService: queryService)

        let loading = Task { await viewModel.load() }
        // 必须等到 `loadDetails` 真正挂起（continuation 已安装）再渲染：
        // 只看 `isLoading` 会太早，那时 `release()` 还没人能接住，`loading.value` 就永远等不到。
        for _ in 0..<2000 where !queryService.isBlocked {
            await Task.yield()
        }
        XCTAssertTrue(queryService.isBlocked, "加载任务应停在 loadDetails 上")
        XCTAssertTrue(viewModel.isLoading, "快照要求渲染时确实处于加载态")

        try renderBothSchemes(
            ClipboardHistoryView(viewModel: viewModel),
            size: CGSize(width: 900, height: 560),
            name: "clipboard-history-loading"
        )

        queryService.release()
        await loading.value
    }

    // 命令栏（CommandBarView）没有快照：它的核心是 AppKit 支撑的 TextField，
    // ImageRenderer 无法离屏绘制，整屏会渲染成黄色「不支持」占位图——那样的图不是评审证据。
    // 命令栏的视觉评审只能在真实窗口里做。

    /// 列表行：评审信息密度与行内操作拥挤度的关键画面。
    ///
    /// 不能渲染整窗——窗口里的列表是 `LazyVStack`、详情是 `ScrollView`，
    /// `ImageRenderer` 离屏渲染这两类容器会得到**空白**（是渲染器局限，不是界面缺陷）。
    /// 所以这里直接渲染行本身，宽度取 900pt 窗口下左栏的实际宽度（900 − 360 详情 = 540）。
    func testClipboardRowListSnapshot() throws {
        try renderBothSchemes(
            Self.rowList(width: 540),
            size: CGSize(width: 540, height: 470),
            name: "clipboard-rows"
        )
    }

    /// 同一批行在窗口最小尺寸下的表现：860pt 窗口时左栏只有 500pt，
    /// 6 个操作图标 + 标题能不能同时读出来，只能看图判断。
    func testClipboardRowListMinWidthSnapshot() throws {
        try renderBothSchemes(
            Self.rowList(width: 500),
            size: CGSize(width: 500, height: 470),
            name: "clipboard-rows-min"
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

    private static let sampleIndexItem = SearchIndexItem(
        id: UUID(),
        sourceID: .clipboard,
        recordID: UUID(),
        title: "示例文本",
        plainText: "示例文本",
        summary: nil,
        contentType: .text,
        pinyin: nil,
        initials: nil,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: false,
        isFavorite: false,
        contentHash: nil,
        resourceReferences: [],
        usageCount: 0,
        lastUsedAt: nil
    )

    // MARK: - 快照数据

    /// 一批真实行：置顶、收藏、长链接、图片、文件（6 个操作图标）各一条。
    private static func rowList(width: CGFloat) -> some View {
        VStack(spacing: JadeSpace.x1.value) {
            ForEach(Array(populatedFixtures().snapshots.enumerated()), id: \.element.id) { index, item in
                JadeClipboardRow(
                    item: item,
                    selected: index == 0,
                    thumbnailProvider: { _ in nil },
                    onPin: {},
                    onFavorite: {},
                    onCopy: {},
                    onDelete: {},
                    onRevealInFinder: {},
                    onCopyPath: {}
                )
            }
        }
        .jadePadding(.x3)
        .frame(width: width, alignment: .leading)
        .background(JadeColor.surface1)
    }

    private struct Fixtures {
        let snapshots: [ClipboardRecordSnapshot]
        let indexItems: [SearchIndexItem]
        let snapshotsByID: [UUID: ClipboardRecordSnapshot]
    }

    /// 一份贴近真实使用的历史：置顶、收藏、长文本、链接、图片、文件各一条。
    private static func populatedFixtures() -> Fixtures {
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        func make(
            _ type: ClipboardContentType,
            summary: String,
            plainText: String?,
            minutesAgo: Int,
            pinned: Bool = false,
            favorite: Bool = false,
            source: (bundleID: String, name: String)? = nil,
            file: (path: String, bytes: Int64)? = nil
        ) -> ClipboardRecordSnapshot {
            let updated = now.addingTimeInterval(-Double(minutesAgo) * 60)
            let id = UUID()
            let resources: [ClipboardResourceSnapshot] = type == .image
                ? [ClipboardResourceSnapshot(
                    id: id,
                    type: .imageOriginal,
                    relativePath: "Clipboard/Images/\(id.uuidString).png",
                    mimeType: "image/png",
                    byteSize: 240_000,
                    width: 1440,
                    height: 900,
                    isMissing: false
                )]
                : []
            return ClipboardRecordSnapshot(
                id: id,
                contentType: type,
                plainText: plainText,
                summary: summary,
                contentHash: "hash-\(id.uuidString)",
                isPinned: pinned,
                isFavorite: favorite,
                createdAt: updated.addingTimeInterval(-120),
                updatedAt: updated,
                filePath: file.map { URL(fileURLWithPath: $0.path) },
                fileDisplayName: file.map { ($0.path as NSString).lastPathComponent },
                fileUTI: file == nil ? nil : "com.adobe.pdf",
                fileSize: file?.bytes,
                resources: resources,
                resourceStatus: .available,
                sourceAppBundleID: source?.bundleID,
                sourceAppName: source?.name
            )
        }

        let snapshots = [
            make(.text,
                 summary: "会议纪要 · Q4 路线图评审与优先级排序",
                 plainText: "会议纪要 · Q4 路线图评审与优先级排序",
                 minutesAgo: 3,
                 pinned: true,
                 source: (bundleID: "company.thebrowser.Browser", name: "Arc")),
            make(.richText,
                 summary: "设计规范 v2：排版层级与间距系统",
                 plainText: "设计规范 v2：排版层级与间距系统",
                 minutesAgo: 12,
                 favorite: true),
            make(.text,
                 summary: "https://developer.apple.com/design/human-interface-guidelines",
                 plainText: "https://developer.apple.com/design/human-interface-guidelines",
                 minutesAgo: 40,
                 source: (bundleID: "com.apple.Safari", name: "Safari")),
            make(.image,
                 summary: "Screenshot 2026-10-29 at 18.12.04.png",
                 plainText: nil,
                 minutesAgo: 90),
            make(.file,
                 summary: "Q4 路线图.pdf",
                 plainText: "Q4 路线图.pdf",
                 minutesAgo: 180,
                 file: (path: "/Users/abyss/Documents/Q4 路线图.pdf", bytes: 2_400_000)),
            make(.text,
                 summary: "git commit -m \"fix: 空状态缺少加载反馈\"",
                 plainText: "git commit -m \"fix: 空状态缺少加载反馈\"",
                 minutesAgo: 1_440,
                 source: (bundleID: "com.apple.Terminal", name: "Terminal"))
        ]

        return Fixtures(
            snapshots: snapshots,
            indexItems: snapshots.map(SearchIndexItem.init(clipboard:)),
            snapshotsByID: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
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
/// 快照专用查询服务：可注入条目，并可阻塞 `loadDetails` 把界面稳定停在加载态。
private final class SnapshotQueryService: ClipboardIndexQueryServiceProtocol, @unchecked Sendable {
    private let items: [SearchIndexItem]
    private let snapshots: [UUID: ClipboardRecordSnapshot]
    private let blocksDetails: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        items: [SearchIndexItem],
        snapshots: [UUID: ClipboardRecordSnapshot] = [:],
        blocksDetails: Bool = false
    ) {
        self.items = items
        self.snapshots = snapshots
        self.blocksDetails = blocksDetails
    }

    func searchIndex(query: String, filter: ClipboardContentType?, limit: Int?) -> [SearchIndexItem] {
        items
    }

    func historyIndex(filter: ClipboardContentType?, limit: Int?, offset: Int) -> [SearchIndexItem] {
        items
    }

    func loadDetails(for indexItem: SearchIndexItem) async throws -> ClipboardRecordSnapshot? {
        if blocksDetails {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return snapshots[indexItem.clipboardRecordID ?? indexItem.id]
    }

    /// `loadDetails` 是否已经挂起（continuation 已安装）。
    var isBlocked: Bool { continuation != nil }

    /// 放行被阻塞的 `loadDetails`，让加载任务正常收尾。
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
/// 快照专用资源仓库：让图片条目留在列表里。
///
/// 真实的 `FileResourceStore` 会去磁盘上找原图，快照数据里的相对路径当然不存在，
/// 于是图片行会被 `shouldShowInList` 过滤掉——而图片行恰恰是最需要看排版的一行。
private final class SnapshotResourceStore: FileResourceStoreProtocol, @unchecked Sendable {
    private struct Unused: Error {}

    func writeImageOriginal(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { throw Unused() }
    func writeThumbnail(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { throw Unused() }
    func writeRichTextRTF(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { throw Unused() }
    func writeRichTextHTML(_ data: Data, id: UUID) async throws -> FileResourceWriteResult { throw Unused() }
    func read(relativePath: String) async throws -> Data { throw Unused() }
    func delete(relativePath: String) async {}
    func exists(relativePath: String) -> Bool { true }
    func storageUsage() async throws -> Int64 { 0 }
}
