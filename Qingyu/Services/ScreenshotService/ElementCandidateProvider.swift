import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os.log

// MARK: - Element candidate provider (Task 012)

/// 控件级候选来源。返回指针下的**界面元素**在 AppKit 全局坐标中的矩形。
///
/// 与窗口级探测的分工（对应产品规则）：
/// - 窗口级用 `CGWindowListCopyWindowInfo`，**不需要辅助功能权限**；
/// - 控件级用辅助功能接口，需要授权；**未授权时必须静默降级为窗口级**，不弹窗、不阻断截图。
protocol ElementCandidateProviding: Sendable {
    /// 返回指针下控件矩形；不可用（未授权 / 被忽略 / 探测失败 / 命中应用自身）时返回 nil。
    func elementFrame(at point: CGPoint, on display: CaptureDisplay, options: ElementProbeOptions) -> CGRect?
}

/// 基于辅助功能接口的实现。
///
/// 命中判定与吸附计算不在本类型内（见 `CandidateHitTest`），这里只负责「把系统接口翻译成内部值类型」。
final class AXElementCandidateProvider: ElementCandidateProviding, @unchecked Sendable {
    private let logger = Logger.screenshot

    func elementFrame(
        at point: CGPoint,
        on display: CaptureDisplay,
        options: ElementProbeOptions
    ) -> CGRect? {
        guard options.isElementProbingEnabled else { return nil }
        // 未授权 → 静默降级，不提示、不请求。
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        // 超时上限由调用方给出：AX 的同步取值是跨进程 IPC，必须设上限避免拖住探测队列。
        AXUIElementSetMessagingTimeout(systemWide, Float(max(0.001, options.timeout)))

        // AX 的位置参数使用 Quartz 全局坐标（左上原点）。
        let mainDisplayHeight = NSScreen.screens.first?.frame.height ?? display.frame.height
        let quartzPoint = CGPoint(
            x: point.x,
            y: mainDisplayHeight - point.y
        )

        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(quartzPoint.x),
            Float(quartzPoint.y),
            &element
        )
        guard status == .success, let element else { return nil }

        // 命中清羽自身（叠层/悬浮层）时不作为候选。
        if let pid = Self.pid(of: element) {
            guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            if options.isIgnored(bundleID: Self.bundleID(forPID: pid)) { return nil }
        }

        guard let frame = Self.appKitFrame(of: element, mainDisplayHeight: mainDisplayHeight) else {
            return nil
        }
        guard frame.width > 0, frame.height > 0 else { return nil }
        // 元素必须落在指针所在显示器上，避免跨屏误高亮。
        guard display.frame.intersects(frame) else { return nil }
        return frame
    }

    // MARK: - Pure helpers (unit-testable without a live UI)

    /// AX 元素位置/尺寸是 Quartz 全局坐标（左上原点）；换算成 AppKit 全局坐标。
    static func appKitFrame(fromQuartz origin: CGPoint, size: CGSize, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: mainDisplayHeight - origin.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// 从 `AXValue` 读取 `CGPoint`；类型不符返回 nil。
    static func point(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// 从 `AXValue` 读取 `CGSize`；类型不符返回 nil。
    static func size(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    // MARK: - Private

    private static func appKitFrame(of element: AXUIElement, mainDisplayHeight: CGFloat) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionStatus = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        let sizeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )
        guard positionStatus == .success, sizeStatus == .success,
              let origin = point(from: positionValue),
              let size = size(from: sizeValue) else { return nil }
        return appKitFrame(fromQuartz: origin, size: size, mainDisplayHeight: mainDisplayHeight)
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private static func bundleID(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

/// 关闭态替身：不产生任何系统调用。
final class DisabledElementCandidateProvider: ElementCandidateProviding, @unchecked Sendable {
    func elementFrame(at point: CGPoint, on display: CaptureDisplay, options: ElementProbeOptions) -> CGRect? {
        nil
    }
}
