import AppKit
import CoreGraphics
import Foundation

// MARK: - Whiteboard session (Task 016)

/// 白板底图种类。
enum WhiteboardBackgroundKind: String, CaseIterable, Codable {
    /// 纯色底图：**不读取屏幕内容，因此不要求屏幕录制权限**。
    case solid
    /// 冻结底图：以当前屏幕冻结画面为底。
    case frozen

    var localizationKey: String {
        switch self {
        case .solid: return "settings.whiteboard.background.solid"
        case .frozen: return "settings.whiteboard.background.frozen"
        }
    }
}

/// 白板开到哪些屏幕。
enum WhiteboardTarget: Equatable {
    /// 指针所在屏幕（默认）。
    case pointer
    /// 指定屏幕（稳定显示器标识）。
    case display(String)
    /// 所有屏幕各开一个白板。
    case allDisplays
}

/// 一次白板会话的可配置部分。
///
/// `shapes` 只在窗口控制器内维护，此处保留的是「是否有笔迹」这一判定所需的
/// 最小信息，便于纯函数测试空白退出规则。
struct WhiteboardSession: Equatable, Codable {
    var id: UUID
    var background: WhiteboardBackgroundKind
    /// 纯色底图颜色（`#RRGGBB`）；冻结底图模式下不生效。
    var solidColorHex: String
    /// 目标屏幕标识列表；空数组表示「所有屏幕」。
    var displayIDs: [String]

    static let defaultSolidColorHex = "#FFFFFF"
    static let maximumDisplayCount = 8

    init(
        id: UUID = UUID(),
        background: WhiteboardBackgroundKind = .solid,
        solidColorHex: String = WhiteboardSession.defaultSolidColorHex,
        displayIDs: [String] = []
    ) {
        self.id = id
        self.background = background
        self.solidColorHex = solidColorHex
        self.displayIDs = displayIDs
    }

    /// 非法颜色一律回落为白底，不抛错。
    var solidColor: NSColor {
        NSColor(hexString: solidColorHex) ?? NSColor(hexString: Self.defaultSolidColorHex)!
    }
}

/// 空白会话判定与退出规则（纯函数）。
enum WhiteboardExitRule {
    /// 空白白板退出：**不弹确认、不写文件、不写剪贴板**。
    static func requiresConfirmation(shapeCount: Int) -> Bool {
        shapeCount > 0
    }

    /// 空白会话退出时是否应产生产物。
    static func shouldProduceOutput(shapeCount: Int) -> Bool {
        shapeCount > 0
    }
}

// MARK: - Session exclusion

/// 会话种类（截图与白板互斥）。
enum ActiveSessionKind: Equatable {
    case screenshot
    case whiteboard
}

/// 会话互斥：白板进行中不允许启动截图，反之亦然。
struct SessionExclusion: Equatable {
    private(set) var active: ActiveSessionKind?

    init(active: ActiveSessionKind? = nil) {
        self.active = active
    }

    /// 尝试开始某类会话；已被另一类占用时返回 false（调用方据此拒绝并提示）。
    ///
    /// 同一类会话重复开始视为成功（幂等），避免重复触发入口时被自己挡住。
    mutating func begin(_ kind: ActiveSessionKind) -> Bool {
        guard let active else {
            self.active = kind
            return true
        }
        return active == kind
    }

    /// 结束某类会话；不是当前会话时忽略（避免错配的结束调用清掉别人的占用）。
    mutating func end(_ kind: ActiveSessionKind) {
        guard active == kind else { return }
        active = nil
    }

    var isIdle: Bool { active == nil }
}

/// 会话互斥的持有者。
///
/// `SessionExclusion` 是值类型（便于单测），但互斥状态需要被多个控制器共享，
/// 因此用引用类型包一层，避免各自持有一份副本导致互斥失效。
@MainActor
final class SessionCoordinator {
    private var exclusion = SessionExclusion()

    var active: ActiveSessionKind? { exclusion.active }
    var isIdle: Bool { exclusion.isIdle }

    @discardableResult
    func begin(_ kind: ActiveSessionKind) -> Bool {
        exclusion.begin(kind)
    }

    func end(_ kind: ActiveSessionKind) {
        exclusion.end(kind)
    }
}

// MARK: - Target resolution

/// 目标屏幕解析（纯函数）。
enum WhiteboardTargetResolver {
    /// 把目标解析成屏幕标识列表。
    ///
    /// - `pointerDisplayID`：指针所在屏；为 nil 时回退到列表首屏。
    /// - 指定的屏幕不存在时返回空数组 —— 由调用方提示，**不静默改用其它屏幕**。
    static func displayIDs(
        target: WhiteboardTarget,
        availableDisplayIDs: [String],
        pointerDisplayID: String?
    ) -> [String] {
        switch target {
        case .pointer:
            guard let pointerDisplayID, availableDisplayIDs.contains(pointerDisplayID) else {
                return availableDisplayIDs.first.map { [$0] } ?? []
            }
            return [pointerDisplayID]
        case .display(let id):
            return availableDisplayIDs.contains(id) ? [id] : []
        case .allDisplays:
            return Array(availableDisplayIDs.prefix(WhiteboardSession.maximumDisplayCount))
        }
    }
}
