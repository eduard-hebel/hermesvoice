#!/usr/bin/env swift
// Rendert ein App-Icon mit Mic-Symbol auf Indigo→Sky-Gradient.
// Pure CoreGraphics, kein NSImage, kein NSApplication — läuft als Swift-Script.

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outputDir = "build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: outputDir)
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Squircle-Clip (macOS Big Sur+ canonical 0.2237 corner ratio)
    let cornerRadius = s * 0.2237
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect,
                       cornerWidth: cornerRadius,
                       cornerHeight: cornerRadius,
                       transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient Indigo → Sky (diagonal)
    let colors = [
        CGColor(red: 0.42, green: 0.27, blue: 0.96, alpha: 1),
        CGColor(red: 0.21, green: 0.55, blue: 0.98, alpha: 1),
    ]
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: colors as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])

    // Mic-Symbol weiß, zentriert
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    let cx = s * 0.5
    let stroke = s * 0.045

    // 1) Mic-Kapsel (Capsule), oben
    let capsuleW = s * 0.26
    let capsuleH = s * 0.42
    let capsuleY = s * 0.32   // bottom of capsule
    let capsuleRect = CGRect(
        x: cx - capsuleW / 2,
        y: capsuleY,
        width: capsuleW,
        height: capsuleH
    )
    let capsulePath = CGPath(roundedRect: capsuleRect,
                              cornerWidth: capsuleW / 2,
                              cornerHeight: capsuleW / 2,
                              transform: nil)
    ctx.addPath(capsulePath)
    ctx.fillPath()

    // 2) U-Bogen unter der Kapsel (Mic-Halter)
    let arcY = capsuleY + s * 0.04
    let arcRadius = capsuleW * 0.95
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: cx, y: arcY),
               radius: arcRadius,
               startAngle: .pi,
               endAngle: 0,
               clockwise: true)
    ctx.strokePath()

    // 3) Vertikale Linie vom Bogen nach unten zum Standfuß
    let baseY = arcY - arcRadius - s * 0.06
    ctx.setLineWidth(stroke)
    ctx.move(to: CGPoint(x: cx, y: arcY - arcRadius))
    ctx.addLine(to: CGPoint(x: cx, y: baseY))
    ctx.strokePath()

    // 4) Horizontale Basis
    let baseHalfWidth = s * 0.12
    ctx.move(to: CGPoint(x: cx - baseHalfWidth, y: baseY))
    ctx.addLine(to: CGPoint(x: cx + baseHalfWidth, y: baseY))
    ctx.strokePath()

    // PNG encoden
    let cgImage = ctx.makeImage()!
    let mutData = NSMutableData()
    let dest = CGImageDestinationCreateWithData(
        mutData as CFMutableData,
        UTType.png.identifier as CFString,
        1, nil
    )!
    CGImageDestinationAddImage(dest, cgImage, nil)
    CGImageDestinationFinalize(dest)
    return mutData as Data
}

let variants: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png",  1024),
]

for (filename, size) in variants {
    let png = renderIcon(size: size)
    let url = URL(fileURLWithPath: "\(outputDir)/\(filename)")
    try png.write(to: url)
    print("✓ \(filename) (\(size)px)")
}

print("Done → \(outputDir)")
