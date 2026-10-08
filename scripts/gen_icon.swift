#!/usr/bin/env swift

// gen_icon.swift — 清羽 Qingyu 占位图标生成脚本
//
// 用途：把 SF Symbol `feather`（羽毛）渲染成 jade 色，生成 AppIcon 全尺寸 PNG
// 以及菜单栏模板图标（MenuBarIcon）。
//
// 运行：
//   swift scripts/gen_icon.swift
//
// 依赖：macOS + AppKit（无需 SF Symbols.app / sfsymbols CLI）。
// 输出：
//   Qingyu/Resources/Assets.xcassets/AppIcon.appiconset/icon_<px>.png
//   Qingyu/Resources/Assets.xcassets/MenuBarIcon.imageset/menubar_<px>.png

import AppKit
import Foundation

// MARK: - Jade 品牌色（PRD §9.2.1 Light 基准值）

// Jade 500 主色 #0A9488 / Jade 600 深主色 #087A70，用于底色渐变。
let jade500 = NSColor(srgbRed: 0x0A / 255.0, green: 0x94 / 255.0, blue: 0x88 / 255.0, alpha: 1)
let jade600 = NSColor(srgbRed: 0x08 / 255.0, green: 0x7A / 255.0, blue: 0x70 / 255.0, alpha: 1)

// MARK: - 路径

let fm = FileManager.default
// 脚本位于 scripts/ 下，工程根为其上一级。
let scriptURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "scripts/gen_icon.swift")
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsRoot = repoRoot
    .appendingPathComponent("Qingyu/Resources/Assets.xcassets")
let appIconDir = assetsRoot.appendingPathComponent("AppIcon.appiconset")
let menuBarDir = assetsRoot.appendingPathComponent("MenuBarIcon.imageset")

// MARK: - 工具

/// 生成指定像素尺寸的位图上下文并把绘制结果写为 PNG。
func writePNG(size: Int, to url: URL, draw: (NSRect) -> Void) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("无法创建 \(size)px 位图")
    }
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    draw(rect)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败 \(size)px")
    }
    try! data.write(to: url)
    print("  wrote \(url.lastPathComponent) (\(size)px)")
}

/// 把 SF Symbol 渲染成指定 point size / 颜色的 NSImage。
func symbolImage(named name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "Qingyu")?
        .withSymbolConfiguration(config) else {
        return featherImage(size: NSSize(width: pointSize * 1.2, height: pointSize * 1.2), color: color)
    }
    // 以 tint 方式着色。
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    color.set()
    let r = NSRect(origin: .zero, size: base.size)
    base.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.isTemplate = false
    return tinted
}

/// Hand-drawn feather (system may lack SF Symbol `feather`).
func featherImage(size: NSSize, color: NSColor) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }
    color.set()

    let w = size.width
    let h = size.height
    // Quill shaft (slightly curved).
    let shaft = NSBezierPath()
    shaft.lineWidth = max(1, w * 0.045)
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: w * 0.22, y: h * 0.86))
    shaft.curve(
        to: NSPoint(x: w * 0.72, y: h * 0.22),
        controlPoint1: NSPoint(x: w * 0.42, y: h * 0.70),
        controlPoint2: NSPoint(x: w * 0.60, y: h * 0.42)
    )
    shaft.stroke()

    // Vane — elongated teardrop along the shaft.
    let vane = NSBezierPath()
    vane.move(to: NSPoint(x: w * 0.26, y: h * 0.88))
    vane.curve(
        to: NSPoint(x: w * 0.78, y: h * 0.18),
        controlPoint1: NSPoint(x: w * 0.78, y: h * 0.78),
        controlPoint2: NSPoint(x: w * 0.88, y: h * 0.48)
    )
    vane.curve(
        to: NSPoint(x: w * 0.26, y: h * 0.88),
        controlPoint1: NSPoint(x: w * 0.62, y: h * 0.28),
        controlPoint2: NSPoint(x: w * 0.42, y: h * 0.58)
    )
    vane.close()
    vane.fill()

    // Fine barbs — a few notches on the outer edge.
    let barbs = NSBezierPath()
    barbs.lineWidth = max(0.8, w * 0.018)
    barbs.lineCapStyle = .round
    let samples: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.42, 0.72, 0.58, 0.66),
        (0.50, 0.60, 0.68, 0.54),
        (0.58, 0.48, 0.74, 0.42),
        (0.64, 0.36, 0.76, 0.32)
    ]
    for s in samples {
        barbs.move(to: NSPoint(x: w * s.0, y: h * s.1))
        barbs.line(to: NSPoint(x: w * s.2, y: h * s.3))
    }
    barbs.stroke()

    return image
}

// MARK: - AppIcon 绘制

/// 绘制单个尺寸的 AppIcon：jade 渐变圆角底 + 白色羽毛。
func drawAppIcon(rect: NSRect) {
    let size = rect.width
    // macOS 图标留白：squircle 约占画布 ~82%，四周留边。
    let inset = size * 0.09
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    // 连续圆角半径 ≈ 边长 * 0.2237（macOS squircle 近似）。
    let radius = iconRect.width * 0.2237
    let path = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    // jade 垂直渐变底。
    let gradient = NSGradient(starting: jade500, ending: jade600)!
    path.addClip()
    gradient.draw(in: iconRect, angle: -90)

    // 重置裁剪后画白色羽毛，居中，占内框约 56%。
    NSGraphicsContext.current?.saveGraphicsState()
    let glyphSize = iconRect.width * 0.56
    let feather = symbolImage(named: "feather", pointSize: glyphSize, weight: .semibold, color: .white)
    let b = feather.size
    let origin = NSPoint(
        x: iconRect.midX - b.width / 2,
        y: iconRect.midY - b.height / 2
    )
    feather.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()
}

// MARK: - MenuBar 模板图标绘制

/// 绘制菜单栏模板图标：纯黑羽毛（isTemplate 由资源目录 template-rendering 控制）。
func drawMenuBar(rect: NSRect) {
    let glyphSize = rect.width * 0.86
    let feather = symbolImage(named: "feather", pointSize: glyphSize, weight: .regular, color: .black)
    let b = feather.size
    let origin = NSPoint(
        x: rect.midX - b.width / 2,
        y: rect.midY - b.height / 2
    )
    feather.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

// MARK: - 执行

try? fm.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try? fm.createDirectory(at: menuBarDir, withIntermediateDirectories: true)

print("AppIcon:")
// AppIcon required 像素尺寸（16/32/128/256/512 @1x/@2x）。
let appIconPx = [16, 32, 64, 128, 256, 512, 1024]
for px in appIconPx {
    writePNG(size: px, to: appIconDir.appendingPathComponent("icon_\(px).png"), draw: drawAppIcon)
}

print("MenuBarIcon:")
// 18pt @1x/@2x/@3x → 18/36/54px。
let menuPx = [18, 36, 54]
for px in menuPx {
    writePNG(size: px, to: menuBarDir.appendingPathComponent("menubar_\(px).png"), draw: drawMenuBar)
}

print("Done.")
