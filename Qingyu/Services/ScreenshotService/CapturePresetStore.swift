import Foundation

// MARK: - Capture preset persistence (Task 015)

/// 预设落盘边界；单测注入内存实现。
///
/// 沿用现有设置项机制（`SettingsService` 的键值存储 + JSON），**不新增数据库表**。
protocol CapturePresetPersisting {
    func load() async -> [CapturePreset]
    func save(_ presets: [CapturePreset]) async
}

/// 设置项实现：存于 `SettingKey.screenshotPresets`。
struct SettingsCapturePresetPersistence: CapturePresetPersisting {
    let settings: SettingsService

    init(settings: SettingsService = SettingsService(persistence: .shared)) {
        self.settings = settings
    }

    func load() async -> [CapturePreset] {
        let presets = (try? await settings.value(for: .screenshotPresets, as: [CapturePreset].self)) ?? []
        return presets
    }

    func save(_ presets: [CapturePreset]) async {
        try? await settings.set(presets, for: .screenshotPresets)
    }
}

/// 内存实现（单测与预览）。
final class InMemoryCapturePresetPersistence: CapturePresetPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var presets: [CapturePreset]

    init(presets: [CapturePreset] = []) {
        self.presets = presets
    }

    func load() async -> [CapturePreset] {
        lock.lock()
        defer { lock.unlock() }
        return presets
    }

    func save(_ presets: [CapturePreset]) async {
        lock.lock()
        defer { lock.unlock() }
        self.presets = presets
    }
}

// MARK: - Store

/// 预设仓库：内存目录 + 持久化，所有写操作立即落盘。
///
/// 会话期只读（`catalog`），因此截图过程中不会因为落盘抖动影响交互。
@MainActor
final class CapturePresetStore {
    private(set) var catalog: CapturePresetCatalog
    private let persistence: CapturePresetPersisting

    init(persistence: CapturePresetPersisting = SettingsCapturePresetPersistence()) {
        self.persistence = persistence
        self.catalog = CapturePresetCatalog()
    }

    /// 从持久化装载（应用启动与会话开始时调用）。
    func reload() async {
        catalog = CapturePresetCatalog(presets: await persistence.load())
    }

    /// 追加；满额返回 false。
    @discardableResult
    func add(_ preset: CapturePreset) async -> Bool {
        guard catalog.add(preset) else { return false }
        await persistence.save(catalog.ordered)
        return true
    }

    @discardableResult
    func update(_ preset: CapturePreset) async -> Bool {
        guard catalog.update(preset) else { return false }
        await persistence.save(catalog.ordered)
        return true
    }

    @discardableResult
    func remove(id: UUID) async -> Bool {
        guard catalog.remove(id: id) else { return false }
        await persistence.save(catalog.ordered)
        return true
    }

    @discardableResult
    func move(from: Int, to: Int) async -> Bool {
        guard catalog.move(from: from, to: to) else { return false }
        await persistence.save(catalog.ordered)
        return true
    }

    /// 自动命名：`前缀 + 序号`，避免与既有重名过多。
    func suggestedName(prefix: String) -> String {
        let existing = Set(catalog.presets.map(\.name))
        var index = catalog.count + 1
        while existing.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }
}
