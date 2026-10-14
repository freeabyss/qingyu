import AppKit
import Foundation

// MARK: - Post-capture behaviour (Task 014 收尾：接通两个此前的哑开关)

/// 「截图后」行为策略。
///
/// 这两个开关（`screenshot.copyToClipboard` / `screenshot.playSound`）在设置页存在
/// 已久，但**全项目没有任何消费者**，属于「拨了没反应」的假设置。此处把它们接成
/// 显式、可测的策略：
///
/// - `copiesToClipboardAfterSave`：**保存成功后再写一份到剪贴板**（一次操作同时
///   落盘与粘贴，省掉「保存 + 复制」两步）。不影响 `Enter` 的复制终局动作。
/// - `playsSoundOnCapture`：**截图成功时播放一声系统提示音**（快门感）。
///
/// **默认全关**：这两个开关此前从未生效，因此「当前行为」等价于关闭；
/// 默认开会在用户没做任何配置的情况下凭空多出声音与剪贴板写入，属于可感知的行为
/// 倒退。默认关 + 用户显式打开，才符合「默认值下行为不倒退」的既有约束。
struct ScreenshotPostCapturePolicy: Equatable, Codable {
    var copiesToClipboardAfterSave: Bool = false
    var playsSoundOnCapture: Bool = false

    static let `default` = ScreenshotPostCapturePolicy()

    /// 设置页键（与既有 `@AppStorage` 保持一致）。
    enum DefaultsKey {
        static let copyToClipboard = "screenshot.copyToClipboard"
        static let playSound = "screenshot.playSound"
    }

    static func current(from defaults: UserDefaults = .standard) -> ScreenshotPostCapturePolicy {
        ScreenshotPostCapturePolicy(
            copiesToClipboardAfterSave: (defaults.object(forKey: DefaultsKey.copyToClipboard) as? NSNumber)?.boolValue ?? false,
            playsSoundOnCapture: (defaults.object(forKey: DefaultsKey.playSound) as? NSNumber)?.boolValue ?? false
        )
    }

    // MARK: - 音效

    /// 首选系统提示音；取不到时按顺序回退（`/System/Library/Sounds` 的成员）。
    static let soundNames = ["Tink", "Pop", "Glass"]

    /// 依次尝试可用音效；全部不可用返回 nil（调用方静默跳过，不报错）。
    static func resolveCaptureSound(
        loader: (String) -> NSSound? = { NSSound(named: NSSound.Name($0)) }
    ) -> NSSound? {
        for name in soundNames {
            if let sound = loader(name) { return sound }
        }
        return nil
    }
}

// MARK: - Player

/// 提示音播放器：持有当前正在播放的音效，避免被立即释放而截断。
@MainActor
final class CaptureSoundPlayer {
    private var sound: NSSound?

    func playIfNeeded(_ enabled: Bool) {
        guard enabled else { return }
        guard let resolved = ScreenshotPostCapturePolicy.resolveCaptureSound() else { return }
        sound = resolved
        resolved.play()
    }
}
