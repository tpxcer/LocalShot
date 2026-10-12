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

private func drawBracket(
    in context: CGContext,
    corner: CGPoint,
    horizontalDirection: CGFloat,
    verticalDirection: CGFloat,
    length: CGFloat
) {
    context.beginPath()
    context.move(to: CGPoint(x: corner.x + horizontalDirection * length, y: corner.y))
    context.addLine(to: corner)
    context.addLine(to: CGPoint(x: corner.x, y: corner.y + verticalDirection * length))
    context.strokePath()
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

    let tileRect = CGRect(x: 88, y: 88, width: 848, height: 848)
    let tilePath = roundedRectPath(tileRect, radius: 190)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -28),
        blur: 44,
        color: NSColor(calibratedWhite: 0.02, alpha: 0.45).cgColor
    )
    context.addPath(tilePath)
    context.setFillColor(NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.18, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.20, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.02, green: 0.28, blue: 0.54, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.04, green: 0.77, blue: 0.77, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 0.56, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 180, y: 870),
        end: CGPoint(x: 850, y: 145),
        options: []
    )

    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 0.26, green: 0.96, blue: 0.95, alpha: 0.35).cgColor,
            NSColor(calibratedRed: 0.26, green: 0.96, blue: 0.95, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: 735, y: 720),
        startRadius: 10,
        endCenter: CGPoint(x: 735, y: 720),
        endRadius: 410,
        options: []
    )

    context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.075).cgColor)
    context.move(to: CGPoint(x: 88, y: 720))
    context.addCurve(
        to: CGPoint(x: 936, y: 505),
        control1: CGPoint(x: 315, y: 845),
        control2: CGPoint(x: 700, y: 735)
    )
    context.addLine(to: CGPoint(x: 936, y: 936))
    context.addLine(to: CGPoint(x: 88, y: 936))
    context.closePath()
    context.fillPath()
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.22).cgColor)
    context.setLineWidth(max(12, 1.2 / scale))
    context.strokePath()

    let frameMin: CGFloat = 264
    let frameMax: CGFloat = 760
    let bracketLength: CGFloat = 122
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(max(48, 1.8 / scale))
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.97).cgColor)
    drawBracket(in: context, corner: CGPoint(x: frameMin, y: frameMax), horizontalDirection: 1, verticalDirection: -1, length: bracketLength)
    drawBracket(in: context, corner: CGPoint(x: frameMax, y: frameMax), horizontalDirection: -1, verticalDirection: -1, length: bracketLength)
    drawBracket(in: context, corner: CGPoint(x: frameMin, y: frameMin), horizontalDirection: 1, verticalDirection: 1, length: bracketLength)
    drawBracket(in: context, corner: CGPoint(x: frameMax, y: frameMin), horizontalDirection: -1, verticalDirection: 1, length: bracketLength)

    let handleTop = circlePath(center: CGPoint(x: 392, y: 614), radius: 67)
    let handleBottom = circlePath(center: CGPoint(x: 392, y: 410), radius: 67)
    let blades = CGMutablePath()
    blades.move(to: CGPoint(x: 438, y: 565))
    blades.addCurve(
        to: CGPoint(x: 512, y: 512),
        control1: CGPoint(x: 468, y: 550),
        control2: CGPoint(x: 492, y: 528)
    )
    blades.addLine(to: CGPoint(x: 694, y: 354))
    blades.move(to: CGPoint(x: 438, y: 459))
    blades.addCurve(
        to: CGPoint(x: 512, y: 512),
        control1: CGPoint(x: 468, y: 474),
        control2: CGPoint(x: 492, y: 496)
    )
    blades.addLine(to: CGPoint(x: 694, y: 670))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -16),
        blur: 30,
        color: NSColor(calibratedWhite: 0, alpha: 0.34).cgColor
    )
    context.setFillColor(NSColor(calibratedRed: 0.01, green: 0.08, blue: 0.20, alpha: 0.82).cgColor)
    context.addPath(handleTop)
    context.addPath(handleBottom)
    context.fillPath()
    context.setStrokeColor(NSColor(calibratedRed: 0.01, green: 0.08, blue: 0.20, alpha: 0.72).cgColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(max(62, 2.8 / scale))
    context.addPath(blades)
    context.strokePath()
    context.restoreGState()

    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.96).cgColor)
    context.setLineWidth(max(32, 1.6 / scale))
    context.addPath(handleTop)
    context.addPath(handleBottom)
    context.strokePath()

    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
    context.setLineWidth(max(38, 1.8 / scale))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(blades)
    context.strokePath()

    let pivotOuter = circlePath(center: CGPoint(x: 512, y: 512), radius: 34)
    context.addPath(pivotOuter)
    context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
    context.fillPath()
    let pivotInner = circlePath(center: CGPoint(x: 512, y: 512), radius: 20)
    context.addPath(pivotInner)
    context.setFillColor(NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.86, alpha: 1).cgColor)
    context.fillPath()

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
