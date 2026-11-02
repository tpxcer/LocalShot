#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private struct IconVariant {
    let filename: String
    let pixels: Int
}

private let variants = [
    IconVariant(filename: "icon_16x16.png", pixels: 16),
    IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
    IconVariant(filename: "icon_32x32.png", pixels: 32),
    IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
    IconVariant(filename: "icon_128x128.png", pixels: 128),
    IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
    IconVariant(filename: "icon_256x256.png", pixels: 256),
    IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
    IconVariant(filename: "icon_512x512.png", pixels: 512),
    IconVariant(filename: "icon_512x512@2x.png", pixels: 1_024),
]

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: #filePath)
private let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let supportURL = rootURL.appendingPathComponent("Support", isDirectory: true)
private let iconsetURL = supportURL.appendingPathComponent("LocalShot.iconset", isDirectory: true)
private let icnsURL = supportURL.appendingPathComponent("LocalShot.icns")

private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func circlePath(center: CGPoint, radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ), transform: nil)
}

private func renderIcon(pixels: Int) throws -> Data {
    let scale = CGFloat(pixels) / 1_024
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "LocalShotIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建图标绘图上下文"])
    }

    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)

    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    }

    // 珍珠白底板，参考 ArcZip 的浅色立体风格
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRectPath(tileRect, radius: 186)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x2A2140, 0.24))
    context.addPath(tilePath)
    context.setFillColor(color(0xF6F3FB))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xFFFFFF), color(0xF3F0F9), color(0xE9E4F4)], [0, 0.55, 1]),
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
    context.drawRadialGradient(
        gradient([color(0xFBDDE3, 0.95), color(0xFBDDE3, 0)], [0, 1]),
        startCenter: CGPoint(x: 260, y: 780), startRadius: 0,
        endCenter: CGPoint(x: 260, y: 780), endRadius: 420,
        options: []
    )
    context.drawRadialGradient(
        gradient([color(0xDCD0FD, 0.95), color(0xDCD0FD, 0)], [0, 1]),
        startCenter: CGPoint(x: 790, y: 250), startRadius: 0,
        endCenter: CGPoint(x: 790, y: 250), endRadius: 440,
        options: []
    )
    context.restoreGState()

    context.addPath(roundedRectPath(tileRect.insetBy(dx: 3, dy: 3), radius: 183))
    context.setStrokeColor(color(0xFFFFFF, 0.9))
    context.setLineWidth(6)
    context.strokePath()
    context.addPath(tilePath)
    context.setStrokeColor(color(0x1B1530, 0.08))
    context.setLineWidth(2)
    context.strokePath()

    // 橙 → 粉 → 紫渐变取景框
    let frameMin: CGFloat = 282
    let frameMax: CGFloat = 742
    let bracketLength: CGFloat = 132
    let brackets = CGMutablePath()
    for (corner, horizontal, vertical) in [
        (CGPoint(x: frameMin, y: frameMax), CGFloat(1), CGFloat(-1)),
        (CGPoint(x: frameMax, y: frameMax), -1, -1),
        (CGPoint(x: frameMin, y: frameMin), 1, 1),
        (CGPoint(x: frameMax, y: frameMin), -1, 1),
    ] {
        brackets.move(to: CGPoint(x: corner.x + horizontal * bracketLength, y: corner.y))
        brackets.addLine(to: corner)
        brackets.addLine(to: CGPoint(x: corner.x, y: corner.y + vertical * bracketLength))
    }
    let strokedBrackets = brackets.copy(
        strokingWithWidth: 66,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 10
    )
    let accentGradient = gradient([color(0xFF9A5C), color(0xF2508E), color(0x8A5CF6)], [0, 0.48, 1])

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x8A5CF6, 0.32))
    context.addPath(strokedBrackets)
    context.setFillColor(color(0xF2508E))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(strokedBrackets)
    context.clip()
    context.drawLinearGradient(
        accentGradient,
        start: CGPoint(x: frameMin - 40, y: frameMax + 40),
        end: CGPoint(x: frameMax + 40, y: frameMin - 40),
        options: []
    )
    context.restoreGState()

    // 中心快门圆点
    let shutter = circlePath(center: CGPoint(x: 512, y: 512), radius: 78)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x8A5CF6, 0.36))
    context.addPath(shutter)
    context.setFillColor(color(0xB45CE0))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shutter)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xF2508E), color(0x8A5CF6)], [0, 1]),
        start: CGPoint(x: 450, y: 590),
        end: CGPoint(x: 580, y: 430),
        options: []
    )
    context.drawRadialGradient(
        gradient([color(0xFFFFFF, 0.75), color(0xFFFFFF, 0)], [0, 1]),
        startCenter: CGPoint(x: 482, y: 552), startRadius: 0,
        endCenter: CGPoint(x: 482, y: 552), endRadius: 56,
        options: []
    )
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw NSError(domain: "LocalShotIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法生成图标图像"])
    }

    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LocalShotIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法编码 PNG 图标"])
    }
    return data
}

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(variant.filename), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "LocalShotIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "iconutil 生成 .icns 失败"])
}

print(icnsURL.path)
