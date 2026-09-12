import Foundation

// MARK: - Pin store (Task 008)

/// 运行期贴图状态：活跃贴图 + 关闭恢复队列（默认 1、钳制 `0…20`）。
/// 状态不持久化；退出应用调用 `destroyAll()`。
@MainActor
final class PinStore {
    static let defaultRestoreCapacity = 1
    static let minimumRestoreCapacity = 0
    static let maximumRestoreCapacity = 20

    private(set) var items: [PinItem] = []
    private var closedQueue: [PinItem] = []
    private(set) var restoreCapacity: Int

    /// 更新恢复队列容量（钳制 `0…20`；超出部分立即丢弃）。
    func setRestoreCapacity(_ capacity: Int) {
        restoreCapacity = min(max(capacity, Self.minimumRestoreCapacity), Self.maximumRestoreCapacity)
        if closedQueue.count > restoreCapacity {
            closedQueue.removeLast(closedQueue.count - restoreCapacity)
        }
    }

    init(restoreCapacity: Int = PinStore.defaultRestoreCapacity) {
        self.restoreCapacity = min(max(restoreCapacity, Self.minimumRestoreCapacity), Self.maximumRestoreCapacity)
    }

    var activeCount: Int { items.count }

    func item(id: UUID) -> PinItem? {
        items.first { $0.id == id }
    }

    /// 创建一张新贴图（默认变换、可见、可交互）。
    @discardableResult
    func add(payload: PinPayload) -> PinItem {
        let item = PinItem(payload: payload)
        items.append(item)
        return item
    }

    /// 关闭：移出活跃集合并进入恢复队列（新关闭的排最前，超出容量丢最旧）。
    func close(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        closedQueue.insert(item, at: 0)
        if closedQueue.count > restoreCapacity {
            closedQueue.removeLast(closedQueue.count - restoreCapacity)
        }
    }

    /// 恢复最近关闭的一张贴图；同一 id 复原（变换等状态保持关闭时快照）。
    @discardableResult
    func restoreLatestClosed() -> PinItem? {
        guard restoreCapacity > 0, !closedQueue.isEmpty else { return nil }
        var item = closedQueue.removeFirst()
        item.isHidden = false
        items.append(item)
        return item
    }

    /// 销毁：活跃与恢复队列中都移除，不可恢复。
    func destroy(_ id: UUID) {
        items.removeAll { $0.id == id }
        closedQueue.removeAll { $0.id == id }
    }

    /// 隐藏全部活跃贴图（不改变恢复队列）。
    func hideAll() {
        for index in items.indices {
            items[index].isHidden = true
        }
    }

    /// 显示全部活跃贴图。
    func showAll() {
        for index in items.indices {
            items[index].isHidden = false
        }
    }

    /// 退出应用：销毁全部运行期贴图（含恢复队列）。
    func destroyAll() {
        items.removeAll()
        closedQueue.removeAll()
    }

    /// 变换更新（窗口交互回写）。
    func updateTransform(_ transform: PinTransform, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].transform = transform
    }

    /// `⌘V` 替换载荷（保留 id 与变换）。
    func replacePayload(_ payload: PinPayload, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].payload = payload
    }

    /// 鼠标穿透开关。
    func setIgnoresMouseEvents(_ ignores: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].ignoresMouseEvents = ignores
    }

    var closedCount: Int { closedQueue.count }
}
