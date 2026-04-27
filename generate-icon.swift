#!/usr/bin/env swift
// Generates AppIcon.iconset/ + AppIcon.icns from tmp/dolphin_app_icon.png.
// Run from the project root: swift generate-icon.swift
// Requires: macOS 13+ and /usr/bin/iconutil.
//
// Pipeline:
//   1. Load the 768×768 source.
//   2. For each target size, draw the source into a square canvas clipped
//      to a continuous-curvature rounded square (CALayer.cornerCurve =
//      .continuous, the macOS Big Sur+ squircle), at the standard ~22.37%
//      corner-radius ratio.
//   3. Write the resulting PNGs into AppIcon.iconset/.
//   4. Hand the iconset to iconutil to produce AppIcon.icns.

import AppKit
import QuartzCore

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL  = cwd.appendingPathComponent("tmp/dolphin_app_icon.png")
let iconsetDir = cwd.appendingPathComponent("Sources/DynamicPomodoro/Resources/AppIcon.iconset")
let icnsURL    = cwd.appendingPathComponent("Sources/DynamicPomodoro/Resources/AppIcon.icns")

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

guard let sourceNS = NSImage(contentsOf: sourceURL),
      let sourceCG = sourceNS.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { die("could not load \(sourceURL.path)") }

// macOS Big Sur+ icon corner radius (≈ 22.37% of the side, rounded down a touch
// so the squircle hugs the canvas edge).
let cornerRadiusRatio: CGFloat = 0.2237

func makeContext(_ size: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { die("could not create CGContext at \(size)px") }
    return ctx
}

// Renders `sourceCG` into a `size × size` canvas, clipped by a continuous-corner
// squircle. Uses CALayer because Quartz has no built-in squircle path; the layer
// applies Apple's own continuous-curvature corner shape.
func renderIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let layer = CALayer()
    layer.frame = CGRect(x: 0, y: 0, width: s, height: s)
    layer.contentsGravity = .resize
    layer.contents = sourceCG
    layer.cornerRadius = s * cornerRadiusRatio
    layer.cornerCurve = .continuous
    layer.masksToBounds = true

    let ctx = makeContext(size)
    ctx.interpolationQuality = .high
    layer.render(in: ctx)
    guard let img = ctx.makeImage() else { die("makeImage at \(size)px") }
    return img
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        die("PNG encode failed for \(url.lastPathComponent)")
    }
    do { try data.write(to: url) } catch { die("write failed: \(error)") }
}

let fm = FileManager.default
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let cells: [(name: String, size: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for cell in cells {
    let img = renderIcon(size: cell.size)
    writePNG(img, to: iconsetDir.appendingPathComponent(cell.name))
    print("  \(cell.name) (\(cell.size)px)")
}

print("\nGenerating .icns …")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus == 0 {
    print("AppIcon.icns created at \(icnsURL.path)")
} else {
    die("iconutil failed (status \(proc.terminationStatus))")
}
