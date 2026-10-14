import CoreGraphics
import Foundation

// MARK: - Capture presets (Task 015)

/// 预设种类。**两类语义不同、不可混用**：
/// - `.region`：记录屏幕标识 + 屏幕内的逻辑矩形，套用时直接放到该位置；
/// - `.size`：只记录宽高，套用时以当前指针为中心生成并钳制到屏幕可见区。
enum CapturePresetKind: String, Codable, Equatable {
    case region
    case size
}

/// 一条用户预设。
///
/// `rect` 存的是**相对目标屏幕 `frame` 原点的偏移**，而不是全局绝对坐标：
/// 显示器重新排布后，绝对坐标会失效，相对偏移仍然正确。
struct CapturePreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var kind: CapturePresetKind
    /// `.region` 必填：稳定的显示器标识（`CGDirectDisplayID` 的字符串形式）。
    var displayID: String?
    /// `.region` 有效：相对该屏幕 `frame` 原点的矩形。
    var rect: CGRect?
    /// `.size` 有效：固定的宽高（逻辑点）。
    var size: CGSize?
    /// 用户可维护的排序权重；相同时按创建顺序。
    var order: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: CapturePresetKind,
        displayID: String? = nil,
        rect: CGRect? = nil,
        size: CGSize? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.displayID = displayID
        self.rect = rect
        self.size = size
        self.order = order
    }

    /// 该预设是否具备套用所需的最小数据。
    var isUsable: Bool {
        switch kind {
        case .region:
            guard let rect else { return false }
            return rect.width > 0 && rect.height > 0
        case .size:
            guard let size else { return false }
            return size.width > 0 && size.height > 0
        }
    }
}

// MARK: - Screens

/// 套用计算所需的屏幕描述（逻辑坐标）。
///
/// 单测直接构造，生产由 `NSScreen` 转换 —— 没有显示器也能完整测试。
struct ScreenDescriptor: Equatable {
    let displayID: String
    /// 屏幕整体范围（截图叠层覆盖的范围）。
    let frame: CGRect
    /// 可见范围（排除菜单栏 / Dock）；尺寸预设钳制到这里。
    let visibleFrame: CGRect

    init(displayID: String, frame: CGRect, visibleFrame: CGRect? = nil) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
    }
}

enum PresetApplyError: Error, Equatable {
    /// 目标屏幕已断开：**报错而不是静默改用其它屏幕**。
    case screenUnavailable(displayID: String)
    /// 预设在当前屏幕拓扑下已放不下。
    case outOfBounds
}

// MARK: - Resolver

/// 预设套用计算。全部为纯函数：入参含屏幕描述与指针位置，不读真实屏幕。
enum PresetResolver {
    /// 区域预设落位：屏幕存在且矩形仍放得下才返回。
    static func resolve(
        regionPreset: CapturePreset,
        availableScreens: [ScreenDescriptor]
    ) -> Result<CGRect, PresetApplyError> {
        guard let rect = regionPreset.rect, rect.width > 0, rect.height > 0 else {
            return .failure(.outOfBounds)
        }
        guard let displayID = regionPreset.displayID else {
            return .failure(.screenUnavailable(displayID: ""))
        }
        guard let screen = availableScreens.first(where: { $0.displayID == displayID }) else {
            return .failure(.screenUnavailable(displayID: displayID))
        }

        let resolved = CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        // 「直接放置在该位置」：不做位移补偿；但若已越出该屏范围，说明预设失效，报错而非悄悄改位置。
        guard screen.frame.contains(resolved) else {
            return .failure(.outOfBounds)
        }
        return .success(resolved)
    }

    /// 尺寸预设落位：以指针为中心，钳制到目标屏幕可见区内。
    ///
    /// 尺寸本身大于可见区时按可见区截断（返回屏幕可见区大小），不报错。
    static func resolve(
        sizePreset: CapturePreset,
        pointerLocation: CGPoint,
        screen: ScreenDescriptor
    ) -> CGRect {
        let requested = sizePreset.size ?? .zero
        let bounds = screen.visibleFrame
        let width = min(max(requested.width, 1), bounds.width)
        let height = min(max(requested.height, 1), bounds.height)

        let originX = clamp(
            pointerLocation.x - width / 2,
            lower: bounds.minX,
            upper: bounds.maxX - width
        )
        let originY = clamp(
            pointerLocation.y - height / 2,
            lower: bounds.minY,
            upper: bounds.maxY - height
        )
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}

// MARK: - Catalog

/// 预设集合：数量上限、排序与增删改。
///
/// 纯值类型，不涉及持久化；`CapturePresetStore` 负责落盘。
struct CapturePresetCatalog: Equatable {
    /// 数量上限（默认 20）。
    static let maximumCount = 20

    private(set) var presets: [CapturePreset]

    init(presets: [CapturePreset] = []) {
        self.presets = Self.normalized(presets)
    }

    /// 按 `order` 升序（相同则按数组位置）排列并重排 `order` 为连续序号。
    var ordered: [CapturePreset] {
        presets.sorted { lhs, rhs in
            lhs.order == rhs.order ? false : lhs.order < rhs.order
        }
    }

    var count: Int { presets.count }
    var isEmpty: Bool { presets.isEmpty }
    var isFull: Bool { presets.count >= Self.maximumCount }

    func preset(id: UUID) -> CapturePreset? {
        presets.first { $0.id == id }
    }

    /// 追加预设；已达上限返回 false（调用方据此提示，不静默丢弃）。
    @discardableResult
    mutating func add(_ preset: CapturePreset) -> Bool {
        guard !isFull else { return false }
        var appended = preset
        appended.order = presets.count
        presets.append(appended)
        return true
    }

    /// 按 id 覆盖（顺序不变）。
    @discardableResult
    mutating func update(_ preset: CapturePreset) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return false }
        presets[index] = preset
        return true
    }

    /// 删除；返回是否真的删掉了（供「删除后不可恢复」的二次确认流程使用）。
    @discardableResult
    mutating func remove(id: UUID) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return false }
        presets.remove(at: index)
        presets = Self.renumbered(presets)
        return true
    }

    /// 移动排序：把第 `from` 位移到第 `to` 位（越界按边界处理）。
    @discardableResult
    mutating func move(from: Int, to: Int) -> Bool {
        let list = presets
        guard list.indices.contains(from) else { return false }
        let target = min(max(to, 0), list.count - 1)
        guard target != from else { return false }
        var mutable = list
        let moved = mutable.remove(at: from)
        mutable.insert(moved, at: target)
        // 数组顺序即目标顺序，直接重编号（不能再排序：此时 order 已与目标顺序冲突）。
        presets = Self.renumbered(mutable)
        return true
    }

    /// 清单显示标签：允许重名，用「序号. 名称」区分。
    static func displayLabels(for presets: [CapturePreset]) -> [String] {
        presets.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
    }

    /// 排序 + 重编号。
    ///
    /// `order` 相同时用**原数组位置**做稳定兜底 —— Swift 的 `sorted` 不是稳定排序，
    /// 若依赖其巧合顺序，`move` 之后的结果会随机漂移。
    private static func normalized(_ presets: [CapturePreset]) -> [CapturePreset] {
        let sorted = presets.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.order != rhs.element.order {
                    return lhs.element.order < rhs.element.order
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return renumbered(sorted)
    }

    /// 只重编号，不改顺序（用于 `move` / `remove` 这类顺序已确定的场景）。
    private static func renumbered(_ presets: [CapturePreset]) -> [CapturePreset] {
        presets.enumerated().map { index, preset in
            var copy = preset
            copy.order = index
            return copy
        }
    }
}
