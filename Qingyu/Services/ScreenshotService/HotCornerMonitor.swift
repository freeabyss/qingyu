import AppKit
import CoreGraphics
import Foundation

// MARK: - Hot corners (Task 014 / 07)

/// 屏幕四角。
enum HotCorner: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var localizationKey: String {
        switch self {
        case .topLeft: return "settings.hotCorner.topLeft"
        case .topRight: return "settings.hotCorner.topRight"
        case .bottomLeft: return "settings.hotCorner.bottomLeft"
        case .bottomRight: return "settings.hotCorner.bottomRight"
        }
    }
}

/// 推入热区后触发的动作。
enum HotCornerAction: String, CaseIterable, Codable {
    /// 区域截图（默认）。会话内仍可由用户改用窗口/整屏。
    case regionCapture
    /// 不响应。
    case ignore

    var localizationKey: String {
        switch self {
        case .regionCapture: return "settings.hotCorner.action.regionCapture"
        case .ignore: return "settings.hotCorner.action.ignore"
        }
    }
}

/// 四角热区配置。
struct HotCornerConfiguration: Equatable, Codable {
    /// 默认**关闭** —— 热区是最容易被误触的交互，不能默认打开。
    var isEnabled: Bool = false
    /// 热区边长（点，从屏幕角量起）。
    var size: CGFloat = HotCornerConfiguration.defaultSize
    /// 触发所需的停留时长（秒）。
    var dwell: TimeInterval = HotCornerConfiguration.defaultDwell

    static let defaultSize: CGFloat = 6
    static let defaultDwell: TimeInterval = 0.4
    static let maximumSize: CGFloat = 64
    static let maximumDwell: TimeInterval = 3

    private var actions: [String: String]

    static let `default` = HotCornerConfiguration(
        isEnabled: false,
        size: defaultSize,
        dwell: defaultDwell,
        actions: HotCornerConfiguration.defaultActions
    )

    private static var defaultActions: [String: String] {
        Dictionary(uniqueKeysWithValues: HotCorner.allCases.map {
            ($0.rawValue, HotCornerAction.regionCapture.rawValue)
        })
    }

    init(
        isEnabled: Bool = false,
        size: CGFloat = HotCornerConfiguration.defaultSize,
        dwell: TimeInterval = HotCornerConfiguration.defaultDwell,
        actions: [String: String] = HotCornerConfiguration.defaultActions
    ) {
        self.isEnabled = isEnabled
        self.size = size
        self.dwell = dwell
        var merged = Self.defaultActions
        for (key, value) in actions where merged[key] != nil {
            merged[key] = value
        }
        self.actions = merged
    }

    func action(for corner: HotCorner) -> HotCornerAction {
        guard let raw = actions[corner.rawValue],
              let action = HotCornerAction(rawValue: raw) else {
            return .ignore
        }
        return action
    }

    mutating func set(_ action: HotCornerAction, for corner: HotCorner) {
        actions[corner.rawValue] = action.rawValue
    }

    /// 收敛到合法范围；非法值（负值 / NaN）回落到默认值而不是 0，避免热区退化成「点不到」。
    func sanitized() -> HotCornerConfiguration {
        HotCornerConfiguration(
            isEnabled: isEnabled,
            size: Self.clamp(size, fallback: Self.defaultSize, upper: Self.maximumSize),
            dwell: Self.clamp(TimeInterval(dwell), fallback: Self.defaultDwell, upper: Self.maximumDwell),
            actions: actions
        )
    }

    /// 是否没有任何角落会触发。
    var isEffectivelyDisabled: Bool {
        !isEnabled || HotCorner.allCases.allSatisfy { action(for: $0) == .ignore }
    }

    private static func clamp(_ value: CGFloat, fallback: CGFloat, upper: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return min(value, upper)
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: (try? keyed.decode(Bool.self, forKey: .isEnabled)) ?? false,
            size: (try? keyed.decode(CGFloat.self, forKey: .size)) ?? Self.defaultSize,
            dwell: (try? keyed.decode(TimeInterval.self, forKey: .dwell)) ?? Self.defaultDwell,
            actions: (try? keyed.decode([String: String].self, forKey: .actions)) ?? Self.defaultActions
        )
    }

    func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: CodingKeys.self)
        try keyed.encode(isEnabled, forKey: .isEnabled)
        try keyed.encode(size, forKey: .size)
        try keyed.encode(dwell, forKey: .dwell)
        try keyed.encode(actions, forKey: .actions)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, size, dwell, actions
    }
}

// MARK: - Detection & dwell (pure)

/// 热区命中与停顿判定的纯状态机。
///
/// 两条防止误触的规则：
/// 1. **停顿**：指针必须在角内持续停留 `dwell` 秒才会触发；
/// 2. **去重**：触发后必须先把指针**移出**该角，才可能再次触发。
struct HotCornerTracker {
    private(set) var activeCorner: HotCorner?
    private var dwellStart: TimeInterval?
    private var hasFired = false

    /// 判定某个点落在哪个角内；不在任何角内返回 nil。
    ///
    /// AppKit 坐标原点在左下，因此「上」= `maxY`。热区从**屏幕整体 frame**
    /// 的角量起（不是可见区），否则菜单栏上的角永远推不进去。
    static func corner(for pointer: CGPoint, screenFrame: CGRect, size: CGFloat) -> HotCorner? {
        guard size > 0, !screenFrame.isEmpty else { return nil }
        let inLeft = pointer.x <= screenFrame.minX + size
        let inRight = pointer.x >= screenFrame.maxX - size
        let inBottom = pointer.y <= screenFrame.minY + size
        let inTop = pointer.y >= screenFrame.maxY - size

        switch (inLeft, inRight, inBottom, inTop) {
        case (true, false, true, false): return .bottomLeft
        case (true, false, false, true): return .topLeft
        case (false, true, true, false): return .bottomRight
        case (false, true, false, true): return .topRight
        default: return nil
        }
    }

    /// 喂入一次指针采样，返回本次应触发的角（nil = 不触发）。
    mutating func update(
        pointer: CGPoint,
        screenFrame: CGRect,
        configuration: HotCornerConfiguration,
        now: TimeInterval
    ) -> HotCorner? {
        guard !configuration.isEffectivelyDisabled else {
            reset()
            return nil
        }
        guard let corner = Self.corner(for: pointer, screenFrame: screenFrame, size: configuration.size) else {
            // 移出所有角：允许下次重新计时（去重规则的关键）。
            reset()
            return nil
        }
        guard configuration.action(for: corner) != .ignore else {
            reset()
            return nil
        }

        if activeCorner != corner {
            activeCorner = corner
            dwellStart = now
            hasFired = false
            return nil
        }
        guard !hasFired, let start = dwellStart else { return nil }
        guard now - start >= configuration.dwell else { return nil }

        hasFired = true
        return corner
    }

    mutating func reset() {
        activeCorner = nil
        dwellStart = nil
        hasFired = false
    }
}

// MARK: - Live monitor

/// 全局四角热区监听：定时采样指针位置，交给 `HotCornerTracker` 判定。
///
/// 用定时轮询而不是鼠标事件监听：热区必须在**任意应用前台**时都能工作，
/// 且轮询让停顿判定与去重完全由纯状态机承担，便于测试。
@MainActor
final class HotCornerMonitor {
    /// 采样间隔；0.1 秒足够跟上手速，也远低于可感知的 CPU 占用。
    static let samplingInterval: TimeInterval = 0.1

    var configuration = HotCornerConfiguration.default {
        didSet {
            configuration = configuration.sanitized()
            if configuration.isEffectivelyDisabled {
                stop()
            } else if !isRunning {
                start()
            }
        }
    }

    /// 触发回调；参数为命中的角与其动作。
    var onTrigger: ((HotCorner, HotCornerAction) -> Void)?

    private var timer: Timer?
    private var tracker = HotCornerTracker()

    var isRunning: Bool { timer != nil }

    /// 测试注入点：返回当前指针的 AppKit 全局坐标与所在屏 frame。
    var pointerProvider: () -> (pointer: CGPoint, screenFrame: CGRect)? = {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { return nil }
        return (pointer, screen.frame)
    }

    var nowProvider: () -> TimeInterval = { Date().timeIntervalSince1970 }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard !configuration.isEffectivelyDisabled, timer == nil else { return }
        let timer = Timer(timeInterval: Self.samplingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // `.common`：拖动/菜单弹出等事件跟踪模式下也要继续计时。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tracker.reset()
    }

    /// 单次判定；测试直接调用它，不依赖定时器。
    func tick() {
        guard let sample = pointerProvider() else {
            tracker.reset()
            return
        }
        guard let corner = tracker.update(
            pointer: sample.pointer,
            screenFrame: sample.screenFrame,
            configuration: configuration,
            now: nowProvider()
        ) else { return }
        onTrigger?(corner, configuration.action(for: corner))
    }
}
