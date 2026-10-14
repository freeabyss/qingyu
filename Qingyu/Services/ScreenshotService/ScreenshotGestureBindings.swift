import AppKit
import Foundation

// MARK: - Configurable mouse/keyboard gestures (Task 014 / 05)

/// 截图完成后可配置的四种手势。
///
/// 作用于**截图预览阶段**（捕获已结束、工具条已出现）。手势落在工具条之外
/// ——也就是被截取的那块画面上——才生效，避免与工具条按钮抢事件。
enum ScreenshotGesture: String, CaseIterable, Codable {
    case enter
    case doubleClick
    case middleClick
    case rightClick

    /// 设置页顺序与本地化键。
    var localizationKey: String {
        switch self {
        case .enter: return "settings.gesture.enter"
        case .doubleClick: return "settings.gesture.doubleClick"
        case .middleClick: return "settings.gesture.middleClick"
        case .rightClick: return "settings.gesture.rightClick"
        }
    }
}

/// 手势可触发的动作。
enum ScreenshotGestureAction: String, CaseIterable, Codable {
    case copyAndEnd
    case save
    case pin
    /// 不响应（默认）。
    case ignore

    var localizationKey: String {
        switch self {
        case .copyAndEnd: return "settings.gesture.action.copyAndEnd"
        case .save: return "settings.gesture.action.save"
        case .pin: return "settings.gesture.action.pin"
        case .ignore: return "settings.gesture.action.ignore"
        }
    }
}

/// 四种手势的绑定表。
///
/// 默认值 = 当前行为：`Enter` 复制并结束（与既有快捷键提示
/// `screenshot.hint.enterCopy` 一致），其余三种默认「不响应」——它们此前
/// 完全没有行为，默认开启等于凭空多出会误触的交互。
struct ScreenshotGestureBindings: Equatable, Codable {
    private var actions: [String: String]

    static let `default` = ScreenshotGestureBindings(actions: [
        ScreenshotGesture.enter.rawValue: ScreenshotGestureAction.copyAndEnd.rawValue,
        ScreenshotGesture.doubleClick.rawValue: ScreenshotGestureAction.ignore.rawValue,
        ScreenshotGesture.middleClick.rawValue: ScreenshotGestureAction.ignore.rawValue,
        ScreenshotGesture.rightClick.rawValue: ScreenshotGestureAction.ignore.rawValue
    ])

    init(actions: [String: String] = [:]) {
        // 以默认值为底，用传入值覆盖：旧版本存档缺少新键时自动补齐，不会读出空表。
        var merged = Self.defaultActions
        for (key, value) in actions where merged[key] != nil {
            merged[key] = value
        }
        self.actions = merged
    }

    private static var defaultActions: [String: String] {
        [
            ScreenshotGesture.enter.rawValue: ScreenshotGestureAction.copyAndEnd.rawValue,
            ScreenshotGesture.doubleClick.rawValue: ScreenshotGestureAction.ignore.rawValue,
            ScreenshotGesture.middleClick.rawValue: ScreenshotGestureAction.ignore.rawValue,
            ScreenshotGesture.rightClick.rawValue: ScreenshotGestureAction.ignore.rawValue
        ]
    }

    /// 取值；无法识别的存档值一律回退到 `.ignore`，不抛错。
    func action(for gesture: ScreenshotGesture) -> ScreenshotGestureAction {
        guard let raw = actions[gesture.rawValue],
              let action = ScreenshotGestureAction(rawValue: raw) else {
            return .ignore
        }
        return action
    }

    /// 是否全部为「不响应」，便于设置页显示「当前不响应任何手势」。
    var isAllIgnoring: Bool {
        ScreenshotGesture.allCases.allSatisfy { action(for: $0) == .ignore }
    }

    mutating func set(_ action: ScreenshotGestureAction, for gesture: ScreenshotGesture) {
        actions[gesture.rawValue] = action.rawValue
    }

    /// 未知键与非法值在解码时被剔除，保证解码结果与 `default` 同构。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode([String: String].self)) ?? [:]
        self.init(actions: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(actions)
    }
}

/// 手势 → 动作的派发（纯函数）。
enum ScreenshotGestureDispatcher {
    /// 返回应执行的动作；`.ignore` 表示不响应（调用方应放行原始事件）。
    static func action(for gesture: ScreenshotGesture, bindings: ScreenshotGestureBindings) -> ScreenshotGestureAction {
        bindings.action(for: gesture)
    }

    /// 事件分类：把 AppKit 事件类型 + 按键信息映射成手势。
    ///
    /// `isOutsidePanel` 为 false（点在工具条上）时一律不识别，避免与按钮抢事件。
    /// 其余判定完全基于入参，便于单测覆盖矩阵。
    static func gesture(
        eventType: NSEvent.EventType,
        buttonNumber: Int,
        clickCount: Int,
        isOutsidePanel: Bool
    ) -> ScreenshotGesture? {
        switch eventType {
        case .leftMouseUp:
            guard clickCount == 2, isOutsidePanel else { return nil }
            return .doubleClick
        case .otherMouseUp:
            guard buttonNumber == 2, isOutsidePanel else { return nil }
            return .middleClick
        case .rightMouseUp:
            guard isOutsidePanel else { return nil }
            return .rightClick
        default:
            return nil
        }
    }
}
