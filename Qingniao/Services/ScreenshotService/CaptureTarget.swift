import AppKit
import CoreGraphics
import Foundation

// MARK: - Capture target model (Task 005)

/// 一台显示器的捕获元数据。`frame` 为全局 AppKit 坐标（左下原点），
/// `pixelSize` 为该显示器的原生像素尺寸（Retina 下通常为 frame 的整数倍）。
/// 捕获前坐标保持 AppKit point，像素转换只在捕获后端内发生。
struct CaptureDisplay: Hashable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let pixelSize: CGSize
}

/// 一个可捕获的屏幕窗口候选。`frame` 为全局 AppKit 坐标。
struct CaptureWindowCandidate: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let displayID: CGDirectDisplayID
}

/// 统一捕获目标：窗口单击、区域拖拽或整屏选择。
enum CaptureTarget: Hashable {
    case window(CaptureWindowCandidate)
    case region(display: CaptureDisplay, globalRect: CGRect)
    case display(CaptureDisplay)
}

// MARK: - Live display lookup helpers

enum CaptureDisplayInfo {
    /// 指定显示器的原生像素尺寸；查询失败时返回 `.zero`（由调用方降级处理）。
    static func pixelSize(displayID: CGDirectDisplayID) -> CGSize {
        let mode = CGDisplayCopyDisplayMode(displayID)
        return CGSize(width: mode?.pixelWidth ?? 0, height: mode?.pixelHeight ?? 0)
    }

    /// AppKit 全局坐标系下包含给定矩形的显示器，找不到时回落到主显示器。
    static func displayID(containing appKitFrame: CGRect) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        if let match = screens.first(where: { screen in
            screen.frame.intersects(appKitFrame)
        }) {
            return displayID(of: match)
        }
        return displayID(of: NSScreen.main ?? screens.first)
    }

    private static func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
