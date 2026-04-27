#!/usr/bin/env swift
// Generates the menu-bar template PNGs from tmp/dolphin.png.
// Run from the project root: swift generate-toolbar-icon.swift
// Requires: macOS 13+
//
// Pipeline:
//   1. Read tmp/dolphin.png (black silhouette on white background).
//   2. Invert colours and write tmp/dolphin-inverse.png.
//   3. Threshold the inverse so the white silhouette becomes opaque and the
//      black background becomes transparent (alpha = luma; RGB = luma keeps
//      the buffer premultiplied).
//   4. Crop to the bounding box of opaque pixels and rescale into menu-bar
//      template canvases (26×18 and 52×36) with transparent backgrounds.
//   5. Write Sources/DynamicPomodoro/Resources/DolphinTemplate{,@2x}.png.

import AppKit
import CoreImage

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL    = cwd.appendingPathComponent("tmp/dolphin.png")
let inverseURL   = cwd.appendingPathComponent("tmp/dolphin-inverse.png")
let resourcesDir = cwd.appendingPathComponent("Sources/DynamicPomodoro/Resources")
let template1xURL = resourcesDir.appendingPathComponent("DolphinTemplate.png")
let template2xURL = resourcesDir.appendingPathComponent("DolphinTemplate@2x.png")

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

func makeContext(width w: Int, height h: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: w, height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { die("could not create CGContext") }
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        die("PNG encode failed for \(url.lastPathComponent)")
    }
    do { try data.write(to: url) } catch { die("write failed: \(error)") }
    print("wrote \(url.path) (\(image.width)×\(image.height))")
}

// MARK: - 1 / Load source

guard let sourceNS = NSImage(contentsOf: sourceURL),
      let sourceCG = sourceNS.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { die("could not load \(sourceURL.path)") }

// MARK: - 2 / Invert colours (CIColorInvert)

let ciContext = CIContext(options: nil)
let ciSource  = CIImage(cgImage: sourceCG)
guard let invertFilter = CIFilter(name: "CIColorInvert") else { die("CIColorInvert unavailable") }
invertFilter.setValue(ciSource, forKey: kCIInputImageKey)
guard let ciInverted = invertFilter.outputImage,
      let invertedCG = ciContext.createCGImage(ciInverted, from: ciInverted.extent)
else { die("inversion failed") }

writePNG(invertedCG, to: inverseURL)

// MARK: - 3 / Threshold to alpha

let invW = invertedCG.width
let invH = invertedCG.height
let alphaCtx = makeContext(width: invW, height: invH)
alphaCtx.draw(invertedCG, in: CGRect(x: 0, y: 0, width: invW, height: invH))
guard let bufPtr = alphaCtx.data else { die("no pixel buffer") }
let pixels = bufPtr.bindMemory(to: UInt8.self, capacity: invW * invH * 4)
for i in 0..<(invW * invH) {
    let off = i * 4
    let r = Double(pixels[off])
    let g = Double(pixels[off + 1])
    let b = Double(pixels[off + 2])
    let luma = UInt8(min(255, max(0, (r * 0.299 + g * 0.587 + b * 0.114).rounded())))
    pixels[off]     = luma   // R (premultiplied: white * luma/255)
    pixels[off + 1] = luma   // G
    pixels[off + 2] = luma   // B
    pixels[off + 3] = luma   // A
}
guard let alphaCG = alphaCtx.makeImage() else { die("alpha makeImage failed") }

// MARK: - 4 / Crop to bounding box of opaque pixels

func boundingBox(of image: CGImage, alphaThreshold: UInt8 = 8) -> CGRect {
    let w = image.width, h = image.height
    let ctx = makeContext(width: w, height: h)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let p = ctx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4) else {
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            if p[(y * w + x) * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= 0 else { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bbox = boundingBox(of: alphaCG)
guard let croppedCG = alphaCG.cropping(to: bbox) else { die("crop failed") }
print("cropped to \(croppedCG.width)×\(croppedCG.height) (from \(invW)×\(invH))")

// MARK: - 5 / Render into template canvases

func render(_ source: CGImage, into canvas: CGSize) -> CGImage {
    let ctx = makeContext(width: Int(canvas.width), height: Int(canvas.height))
    ctx.interpolationQuality = .high
    let srcAspect = CGFloat(source.width) / CGFloat(source.height)
    let dstAspect = canvas.width / canvas.height
    let target: CGRect
    if srcAspect > dstAspect {
        let h = canvas.width / srcAspect
        target = CGRect(x: 0, y: (canvas.height - h) / 2, width: canvas.width, height: h)
    } else {
        let w = canvas.height * srcAspect
        target = CGRect(x: (canvas.width - w) / 2, y: 0, width: w, height: canvas.height)
    }
    ctx.draw(source, in: target)
    guard let img = ctx.makeImage() else { die("render failed") }
    return img
}

writePNG(render(croppedCG, into: CGSize(width: 26, height: 18)), to: template1xURL)
writePNG(render(croppedCG, into: CGSize(width: 52, height: 36)), to: template2xURL)

print("done.")
