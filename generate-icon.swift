#!/usr/bin/env swift
// Generates AppIcon.iconset/ + AppIcon.icns for DynamicPomodoro.
// Run once from the project root: swift generate-icon.swift
// Requires: macOS 13+

import AppKit
import CoreGraphics

// MARK: - Palette

let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let bgDeep   = rgb(0.05, 0.03, 0.13)  // #0D0807  deep purple-black
let bgLight  = rgb(0.07, 0.10, 0.26)  // #121A42  dark navy
let hotPink  = rgb(1.00, 0.00, 0.43)  // #FF006E
let cyan     = rgb(0.00, 0.85, 1.00)  // #00D9FF
let gold     = rgb(1.00, 0.84, 0.04)  // #FFD60A
let coral    = rgb(1.00, 0.38, 0.52)  // #FF617A  lighter centre

// MARK: - Drawing

func drawIcon(ctx: CGContext, s: CGFloat) {
    let cx = s / 2, cy = s / 2

    // Rounded-rect clip — all drawing stays inside
    let corner = s * 0.225
    let bounds = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // 1 ── Background gradient (bottom-left dark → top-right navy)
    let bgColors = [bgDeep, bgLight] as CFArray
    let bgGrad = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad,
        start: .init(x: 0, y: 0), end: .init(x: s, y: s), options: [])

    // 2 ── Scattered background sparkles
    srand48(42)
    ctx.saveGState()
    for _ in 0..<28 {
        let x = CGFloat(drand48()) * s
        let y = CGFloat(drand48()) * s
        let r = CGFloat(drand48()) * s * 0.012 + s * 0.004
        let alpha = CGFloat(drand48()) * 0.45 + 0.1
        ctx.setFillColor(rgb(1, 1, 1, alpha))
        ctx.fillEllipse(in: .init(x: x - r, y: y - r, width: r*2, height: r*2))
    }
    ctx.restoreGState()

    let outerR = s * 0.388
    let trackW = s * 0.084

    // 3 ── Dim track ring
    ctx.saveGState()
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.setLineWidth(trackW)
    ctx.addEllipse(in: .init(x: cx-outerR, y: cy-outerR, width: outerR*2, height: outerR*2))
    ctx.strokePath()
    ctx.restoreGState()

    // 4 ── Colourful arc (≈80%, clockwise from 12 o'clock)
    //      Arc goes 12→3→6→9 and stops just before midnight.
    //      In standard CG coords (origin=bottom-left) 12 o'clock = π/2.
    ctx.saveGState()
    let arcPath = CGMutablePath()
    arcPath.addArc(
        center: .init(x: cx, y: cy), radius: outerR,
        startAngle:  .pi / 2,
        endAngle:    .pi / 2 - (2 * .pi * 0.80),  // clockwise
        clockwise: true
    )
    let filledArc = arcPath.copy(
        strokingWithWidth: trackW, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.addPath(filledArc)
    ctx.clip()
    // Gradient: pink (12 o'clock / top) → cyan (bottom-right) → gold (bottom-left)
    let arcColors = [hotPink, cyan, gold] as CFArray
    let arcGrad = CGGradient(colorsSpace: space, colors: arcColors, locations: [0, 0.52, 1])!
    ctx.drawLinearGradient(arcGrad,
        start: .init(x: cx, y: cy + outerR),  // top
        end:   .init(x: cx, y: cy - outerR),  // bottom
        options: [])
    ctx.restoreGState()

    // 5 ── Glow halo behind inner circle
    ctx.saveGState()
    let haloR = s * 0.30
    let haloColors = [rgb(1.0, 0.0, 0.43, 0.55), rgb(1.0, 0.0, 0.43, 0)] as CFArray
    let haloGrad = CGGradient(colorsSpace: space, colors: haloColors, locations: [0, 1])!
    ctx.drawRadialGradient(haloGrad,
        startCenter: .init(x: cx, y: cy), startRadius: 0,
        endCenter:   .init(x: cx, y: cy), endRadius: haloR,
        options: [])
    ctx.restoreGState()

    // 6 ── Inner filled circle (coral → hot-pink)
    let innerR = s * 0.235
    ctx.saveGState()
    ctx.addEllipse(in: .init(x: cx-innerR, y: cy-innerR, width: innerR*2, height: innerR*2))
    ctx.clip()
    let innerColors = [coral, hotPink] as CFArray
    let innerGrad = CGGradient(colorsSpace: space, colors: innerColors, locations: [0, 1])!
    ctx.drawRadialGradient(innerGrad,
        startCenter: .init(x: cx, y: cy + innerR * 0.25), startRadius: 0,
        endCenter:   .init(x: cx, y: cy),                 endRadius: innerR * 1.05,
        options: [])
    ctx.restoreGState()

    // 7 ── Specular highlight (small soft oval near top of inner circle)
    ctx.saveGState()
    let hlW = innerR * 0.72, hlH = innerR * 0.28
    let hlX = cx - hlW / 2, hlY = cy + innerR * 0.30
    let hlColors = [rgb(1,1,1,0.55), rgb(1,1,1,0)] as CFArray
    let hlGrad = CGGradient(colorsSpace: space, colors: hlColors, locations: [0, 1])!
    let hlPath = CGPath(ellipseIn: .init(x: hlX, y: hlY, width: hlW, height: hlH), transform: nil)
    ctx.addPath(hlPath)
    ctx.clip()
    ctx.drawRadialGradient(hlGrad,
        startCenter: .init(x: cx, y: hlY + hlH * 0.5), startRadius: 0,
        endCenter:   .init(x: cx, y: hlY),              endRadius: hlW * 0.6,
        options: [])
    ctx.restoreGState()

    // 8 ── Thin cyan ring around inner circle (neon edge)
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0, 0.85, 1.0, 0.70))
    ctx.setLineWidth(s * 0.012)
    ctx.addEllipse(in: .init(x: cx-innerR, y: cy-innerR, width: innerR*2, height: innerR*2))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Render to PNG

func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(ctx: ctx, s: s)
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Main

let fm = FileManager.default
let iconsetPath = "Sources/DynamicPomodoro/Resources/AppIcon.iconset"
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for (size, name) in sizes {
    let data = renderPNG(size: size)
    let path = "\(iconsetPath)/\(name).png"
    fm.createFile(atPath: path, contents: data)
    print("  \(name).png  (\(size)px)")
}
print("\nGenerating .icns …")
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns",
    "\(iconsetPath)",
    "-o", "Sources/DynamicPomodoro/Resources/AppIcon.icns"]
try result.run()
result.waitUntilExit()
if result.terminationStatus == 0 {
    print("AppIcon.icns created.")
} else {
    print("iconutil failed — iconset is still in \(iconsetPath)")
}
