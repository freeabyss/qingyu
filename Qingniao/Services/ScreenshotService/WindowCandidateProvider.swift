import AppKit
import CoreGraphics
import Foundation

// MARK: - Window candidate provider (Task 006)

/// 按窗口命中规则返回指针下的可捕获窗口候选：z-order 从前到后取第一个
/// 「普通图层、非本进程、非透明、与指针相交」的屏幕窗口。
/// 青鸟自身截图叠层（本进程窗口）、菜单栏/状态项（layer 24/25）与桌面
/// （`.excludeDesktopElements`）都被排除。
protocol WindowCandidateProviding {
    func candidate(at point: CGPoint, on display: CaptureDisplay) -> CaptureWindowCandidate?
}

final class WindowCandidateProvider: WindowCandidateProviding {
    /// 解析后的窗口信息（保持 CGWindowList 的 z-order，前到后）。
    struct WindowInfo {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let layer: Int
        let alpha: CGFloat
        let cgBounds: CGRect
    }

    func candidate(at point: CGPoint, on display: CaptureDisplay) -> CaptureWindowCandidate? {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let infos = Self.parse(windowList: list)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return Self.firstCandidate(
            in: infos,
            at: point,
            on: display,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            primaryScreenHeight: primaryHeight
        )
    }

    // MARK: - Pure helpers (unit-testable)

    /// 解析 CGWindowListCopyWindowInfo 的原始字典；无效条目被跳过，顺序保留。
    static func parse(windowList: [[String: Any]]) -> [WindowInfo] {
        windowList.compactMap { entry in
            guard let windowNumber = entry[kCGWindowNumber as String] as? Int else { return nil }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let alpha = entry[kCGWindowAlpha as String] as? CGFloat ?? 1
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bounds = entry[kCGWindowBounds as String] as? CGRect ?? .zero
            return WindowInfo(
                windowID: CGWindowID(windowNumber),
                ownerPID: pid,
                layer: layer,
                alpha: alpha,
                cgBounds: bounds
            )
        }
    }

    /// CG 全局坐标（左上原点）→ AppKit 全局坐标（左下原点）。
    static func appKitFrame(cgBounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: cgBounds.minX,
            y: primaryScreenHeight - cgBounds.maxY,
            width: cgBounds.width,
            height: cgBounds.height
        )
    }

    /// 命中规则：普通窗口层（0）、非本进程、可见（alpha > 0）、在指定显示器上
    /// 且包含指针点。返回 z-order 第一个命中的候选。
    static func firstCandidate(
        in windows: [WindowInfo],
        at point: CGPoint,
        on display: CaptureDisplay,
        ownPID: pid_t,
        primaryScreenHeight: CGFloat
    ) -> CaptureWindowCandidate? {
        for info in windows {
            guard info.layer == 0 else { continue }
            guard info.ownerPID != ownPID else { continue }
            guard info.alpha > 0.01 else { continue }
            guard info.cgBounds.width > 0, info.cgBounds.height > 0 else { continue }

            let frame = appKitFrame(cgBounds: info.cgBounds, primaryScreenHeight: primaryScreenHeight)
            guard frame.contains(point) else { continue }
            guard display.frame.intersects(frame) else { continue }

            return CaptureWindowCandidate(
                windowID: info.windowID,
                frame: frame,
                displayID: display.id
            )
        }
        return nil
    }
}
