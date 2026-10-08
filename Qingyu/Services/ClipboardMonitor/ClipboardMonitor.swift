import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

extension Notification.Name {
    static let clipboardItemSaved = Notification.Name("com.freeabyss.qingyu.clipboardItemSaved")
}

/// Legacy event shape kept for the historical GRDB/ContentStore code path.
/// Assistant MVP clipboard monitoring emits `AssistantClipboardEvent` instead.
struct ClipboardEvent {
    let contentType: ContentType
    let textContent: String?
    let imageData: Data?
    let fileURLs: [URL]?
    let contentHash: String
    let timestamp: Date
}

protocol ClipboardMonitorProtocol {
    var events: AsyncStream<AssistantClipboardEvent> { get }
    func start()
    func stop()
    func pollNow() async
}

/// Small pasteboard abstraction so tests do not depend on the user's real system clipboard.
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType] { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func fileURLs() -> [URL]
}

final class SystemPasteboardReader: PasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }
    var types: [NSPasteboard.PasteboardType] { pasteboard.types ?? [] }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        pasteboard.string(forType: type)
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        pasteboard.data(forType: type)
    }

    func fileURLs() -> [URL] {
        pasteboard.pasteboardItems?.compactMap { item in
            if let fileURLString = item.string(forType: .fileURL), let url = URL(string: fileURLString) {
                return url
            }
            if let urlString = item.string(forType: NSPasteboard.PasteboardType("public.file-url")), let url = URL(string: urlString) {
                return url
            }
            return nil
        } ?? []
    }
}

/// Monitors the system clipboard through `NSPasteboard.general.changeCount`.
///
/// Polling is adaptive and independent of app activation:
/// - 500ms while active/recently changed.
/// - 2s after a configurable period without changes.
/// - immediately restored to 500ms after any change.
final class ClipboardMonitor: ClipboardMonitorProtocol {
    private let logger = Logger.clipboard
    private let pasteboard: PasteboardReading
    private let activePollInterval: TimeInterval
    private let idlePollInterval: TimeInterval
    private let idleDowngradeAfter: TimeInterval
    private let now: () -> Date

    private var lastChangeCount: Int
    private var lastObservedChangeAt: Date
    private var timer: Timer?
    private var continuation: AsyncStream<AssistantClipboardEvent>.Continuation?
    private var recentHashes: [String] = []
    private var recentHashSet: Set<String> = []

    private(set) var currentPollInterval: TimeInterval

    init(
        pasteboard: PasteboardReading = SystemPasteboardReader(),
        activePollInterval: TimeInterval = 0.5,
        idlePollInterval: TimeInterval = 2.0,
        idleDowngradeAfter: TimeInterval = 10.0,
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.activePollInterval = activePollInterval
        self.idlePollInterval = idlePollInterval
        self.idleDowngradeAfter = idleDowngradeAfter
        self.now = now
        self.lastChangeCount = pasteboard.changeCount
        self.lastObservedChangeAt = now()
        self.currentPollInterval = activePollInterval
    }

    var events: AsyncStream<AssistantClipboardEvent> {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.logger.debug("Assistant clipboard event stream terminated")
            }
        }
    }

    func start() {
        guard timer == nil else {
            logger.warning("ClipboardMonitor already started")
            return
        }
        lastChangeCount = pasteboard.changeCount
        lastObservedChangeAt = now()
        startTimer(interval: activePollInterval)
        logger.info("Assistant ClipboardMonitor started with 500ms active polling")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        logger.info("Assistant ClipboardMonitor stopped")
    }

    func pollNow() async {
        await MainActor.run { checkForChanges() }
    }

    private func startTimer(interval: TimeInterval) {
        guard currentPollInterval != interval || timer == nil else { return }
        currentPollInterval = interval
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    @objc private func timerFired() {
        checkForChanges()
    }

    private func checkForChanges() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else {
            maybeDowngradePolling()
            return
        }

        lastChangeCount = count
        lastObservedChangeAt = now()
        startTimer(interval: activePollInterval)

        guard let event = readCurrentPayload().map({ payload in
            let source = frontmostSourceApp()
            return AssistantClipboardEvent(
                payload: payload,
                capturedAt: now(),
                sourceAppBundleID: source.bundleID,
                sourceAppName: source.name
            )
        }) else {
            logger.debug("Clipboard changed but no supported payload was found")
            return
        }

        guard rememberIfNew(hash: event.contentHash) else {
            logger.debug("Skipping duplicate clipboard payload seen recently")
            return
        }

        continuation?.yield(event)
        logger.info("Captured Assistant clipboard event hash=\(event.contentHash.prefix(12), privacy: .public)")
    }

    private func maybeDowngradePolling() {
        guard currentPollInterval == activePollInterval else { return }
        let idleFor = now().timeIntervalSince(lastObservedChangeAt)
        if idleFor >= idleDowngradeAfter {
            startTimer(interval: idlePollInterval)
            logger.debug("Clipboard idle for \(idleFor)s; downgraded polling to 2s")
        }
    }

    /// Frontmost app when the pasteboard change was observed (not Qingyu itself).
    private func frontmostSourceApp() -> (bundleID: String?, name: String?) {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return (front.bundleIdentifier, front.localizedName)
        }
        // Fall back to the first regular other app if frontmost is ourselves.
        if let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !$0.isTerminated
        }) {
            return (other.bundleIdentifier, other.localizedName)
        }
        return (nil, nil)
    }

    private func rememberIfNew(hash: String) -> Bool {
        guard !recentHashSet.contains(hash) else { return false }
        recentHashes.append(hash)
        recentHashSet.insert(hash)
        if recentHashes.count > 200 {
            let removed = Array(recentHashes.prefix(recentHashes.count - 100))
            recentHashes.removeFirst(recentHashes.count - 100)
            for hash in removed { recentHashSet.remove(hash) }
        }
        return true
    }

    private func readCurrentPayload() -> ClipboardPayload? {
        let types = Set(pasteboard.types)

        if types.contains(.rtf) || types.contains(.html) {
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html) ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.html"))
            let plainText = pasteboard.string(forType: .string)
                ?? rtfData.flatMap(Self.plainTextFromRTF(_:))
                ?? htmlData.flatMap(Self.plainTextFromHTML(_:))
                ?? ""
            if !plainText.isEmpty || rtfData != nil || htmlData != nil {
                return .richText(plainText: plainText, rtfData: rtfData, htmlData: htmlData)
            }
        }

        let fileURLs = pasteboard.fileURLs()
        if !fileURLs.isEmpty {
            let fileItems = fileURLs.map { url in
                FileClipboardItem(
                    path: url,
                    displayName: url.lastPathComponent,
                    uti: Self.typeIdentifier(for: url),
                    fileSize: Self.fileSize(for: url)
                )
            }
            return .files(fileItems)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .plainText(text)
        }

        if let imageData = readImageAsPNG(types: types) {
            return .image(data: imageData)
        }

        return nil
    }

    private func readImageAsPNG(types: Set<NSPasteboard.PasteboardType>) -> Data? {
        let pngType = NSPasteboard.PasteboardType("public.png")
        if types.contains(pngType), let data = pasteboard.data(forType: pngType), !data.isEmpty {
            return data
        }
        if types.contains(.png), let data = pasteboard.data(forType: .png), !data.isEmpty {
            return data
        }
        if types.contains(.tiff), let data = pasteboard.data(forType: .tiff), !data.isEmpty {
            return Self.pngData(fromImageData: data) ?? data
        }
        return nil
    }

    private static func plainTextFromRTF(_ data: Data) -> String? {
        (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))?.string
    }

    private static func plainTextFromHTML(_ data: Data) -> String? {
        (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil))?.string
    }

    static func pngData(fromImageData data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        return image.pngData()
    }

    private static func typeIdentifier(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier
    }

    private static func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }
}

protocol ClipboardServiceProtocol {
    var isRecordingEnabled: Bool { get }
    func handle(event: AssistantClipboardEvent) async throws -> ClipboardRecordSnapshot?
    func pauseRecording()
    func resumeRecording()
}

final class ClipboardService: ClipboardServiceProtocol {
    private let logger = Logger.clipboard
    private let repository: ClipboardRepositoryProtocol
    private let resourceStore: FileResourceStoreProtocol
    private let notificationCenter: NotificationCenter
    private var recordingEnabled: Bool

    init(
        repository: ClipboardRepositoryProtocol,
        resourceStore: FileResourceStoreProtocol,
        notificationCenter: NotificationCenter = .default,
        recordingEnabled: Bool = true
    ) {
        self.repository = repository
        self.resourceStore = resourceStore
        self.notificationCenter = notificationCenter
        self.recordingEnabled = recordingEnabled
    }

    var isRecordingEnabled: Bool { recordingEnabled }

    func pauseRecording() {
        recordingEnabled = false
    }

    func resumeRecording() {
        recordingEnabled = true
    }

    func handle(event: AssistantClipboardEvent) async throws -> ClipboardRecordSnapshot? {
        guard recordingEnabled else {
            logger.debug("Clipboard recording is paused; dropping event")
            return nil
        }

        let resources = try await makeResources(for: event.payload)
        let snapshot = try await repository.upsert(event: event, resources: resources)
        notificationCenter.post(name: .clipboardItemSaved, object: snapshot.id)
        logger.info("Assistant clipboard event persisted id=\(snapshot.id.uuidString, privacy: .public)")
        return snapshot
    }

    private func makeResources(for payload: ClipboardPayload) async throws -> [ClipboardResourceDraft] {
        switch payload {
        case .plainText, .files:
            return []
        case .richText(_, let rtfData, let htmlData):
            var drafts: [ClipboardResourceDraft] = []
            if let rtfData, !rtfData.isEmpty {
                let result = try await resourceStore.writeRichTextRTF(rtfData, id: UUID())
                drafts.append(ClipboardResourceDraft(result, type: .richTextRTF))
            }
            if let htmlData, !htmlData.isEmpty {
                let result = try await resourceStore.writeRichTextHTML(htmlData, id: UUID())
                drafts.append(ClipboardResourceDraft(result, type: .richTextHTML))
            }
            return drafts
        case .image(let data):
            let imageData = ClipboardMonitor.pngData(fromImageData: data) ?? data
            let imageSize = Self.imageSize(from: imageData)
            let original = try await resourceStore.writeImageOriginal(imageData, id: UUID())
            let thumbnailData = Self.thumbnailPNGData(from: imageData, maxPixelSize: 256) ?? imageData
            let thumbnailSize = Self.imageSize(from: thumbnailData)
            let thumbnail = try await resourceStore.writeThumbnail(thumbnailData, id: UUID())
            return [
                ClipboardResourceDraft(original, type: .imageOriginal, width: imageSize?.width, height: imageSize?.height),
                ClipboardResourceDraft(thumbnail, type: .imageThumbnail, width: thumbnailSize?.width, height: thumbnailSize?.height)
            ]
        }
    }

    private static func imageSize(from data: Data) -> (width: Int, height: Int)? {
        guard let image = NSImage(data: data) else { return nil }
        let representations = image.representations
        if let rep = representations.first {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width), Int(image.size.height))
    }

    static func thumbnailPNGData(from data: Data, maxPixelSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        let scale = min(maxPixelSize / originalSize.width, maxPixelSize / originalSize.height, 1.0)
        let targetSize = NSSize(width: max(1, originalSize.width * scale), height: max(1, originalSize.height * scale))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail.pngData()
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
