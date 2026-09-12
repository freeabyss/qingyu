import Foundation

// MARK: - Pin model (Task 008)

/// 贴图载荷种类。
enum PinPayloadKind: Equatable {
    case image
    case color
    case attributedText
    case text
}

/// 贴图载荷：图像、颜色、富文本（本地渲染）或纯文本。
enum PinPayload: Equatable {
    case image(Data)
    case color(red: UInt8, green: UInt8, blue: UInt8)
    case attributedText(NSAttributedString)
    case text(String)

    var kind: PinPayloadKind {
        switch self {
        case .image: return .image
        case .color: return .color
        case .attributedText: return .attributedText
        case .text: return .text
        }
    }
}

/// 贴图变换：缩放、不透明度、旋转与翻转；构造时自动钳制到合法范围。
struct PinTransform: Equatable {
    static let minimumScale: CGFloat = 0.1
    static let maximumScale: CGFloat = 8.0
    static let minimumOpacity: CGFloat = 0.1
    static let maximumOpacity: CGFloat = 1.0

    var scale: CGFloat
    var opacity: CGFloat
    /// 顺时针四分之一圈数，存储时归一化到 `0...3`。
    var quarterTurns: Int
    var flippedHorizontally: Bool
    var flippedVertically: Bool

    init(
        scale: CGFloat = 1,
        opacity: CGFloat = 1,
        quarterTurns: Int = 0,
        flippedHorizontally: Bool = false,
        flippedVertically: Bool = false
    ) {
        self.scale = Self.clampScale(scale)
        self.opacity = Self.clampOpacity(opacity)
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.flippedHorizontally = flippedHorizontally
        self.flippedVertically = flippedVertically
    }

    /// 滚轮 / `+/-` 缩放：钳制 `10%…800%`。
    static func clampScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    /// 不透明度钳制 `10%…100%`。
    static func clampOpacity(_ opacity: CGFloat) -> CGFloat {
        min(max(opacity, minimumOpacity), maximumOpacity)
    }

    /// 中键复位：仅恢复 100% 缩放与 100% 不透明度，保留旋转/翻转（UI 规范「贴图」键位表）。
    mutating func resetScaleAndOpacity() {
        scale = 1
        opacity = 1
    }

    mutating func scale(by multiplier: CGFloat) {
        scale = Self.clampScale(scale * multiplier)
    }

    /// `⌘`+滚轮 / `⌘+/-`：按步进调整不透明度，钳制 `10%…100%`。
    mutating func adjustOpacity(by delta: CGFloat) {
        opacity = Self.clampOpacity(opacity + delta)
    }

    mutating func rotate(byQuarterTurns turns: Int) {
        quarterTurns = (((quarterTurns + turns) % 4) + 4) % 4
    }

    mutating func toggleHorizontalFlip() {
        flippedHorizontally.toggle()
    }

    mutating func toggleVerticalFlip() {
        flippedVertically.toggle()
    }
}

/// 运行期贴图条目：状态不持久化，退出应用即销毁。
struct PinItem: Identifiable, Equatable {
    let id: UUID
    var payload: PinPayload
    var transform: PinTransform
    var isHidden: Bool
    var ignoresMouseEvents: Bool

    init(
        id: UUID = UUID(),
        payload: PinPayload,
        transform: PinTransform = PinTransform(),
        isHidden: Bool = false,
        ignoresMouseEvents: Bool = false
    ) {
        self.id = id
        self.payload = payload
        self.transform = transform
        self.isHidden = isHidden
        self.ignoresMouseEvents = ignoresMouseEvents
    }
}
