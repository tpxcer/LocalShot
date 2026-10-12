#!/usr/bin/env swift

import AppKit
import Foundation

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: #filePath)
private let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let fixturesURL = rootURL.appendingPathComponent("TestFixtures", isDirectory: true)
private let outputURL = fixturesURL.appendingPathComponent("LocalShot-UI-Acceptance.png")

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    text.draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

try fileManager.createDirectory(at: fixturesURL, withIntermediateDirectories: true)

let width = 1_200
let height = 800
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("无法创建测试图片")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(calibratedRed: 0.96, green: 0.98, blue: 1, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let headerRect = NSRect(x: 0, y: 650, width: width, height: 150)
NSColor(calibratedRed: 0.035, green: 0.12, blue: 0.28, alpha: 1).setFill()
headerRect.fill()
drawText(
    "LocalShot OCR · Translation · Annotation",
    in: NSRect(x: 64, y: 712, width: 1_070, height: 48),
    font: .systemFont(ofSize: 34, weight: .bold),
    color: .white
)
drawText(
    "纯本地界面验收图片  |  2026",
    in: NSRect(x: 66, y: 670, width: 1_000, height: 32),
    font: .systemFont(ofSize: 21, weight: .medium),
    color: NSColor(calibratedRed: 0.55, green: 0.9, blue: 0.96, alpha: 1)
)

let leftCard = NSBezierPath(roundedRect: NSRect(x: 56, y: 338, width: 660, height: 270), xRadius: 24, yRadius: 24)
NSColor.white.setFill()
leftCard.fill()
NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
leftCard.lineWidth = 2
leftCard.stroke()

drawText(
    "English",
    in: NSRect(x: 92, y: 548, width: 250, height: 34),
    font: .systemFont(ofSize: 24, weight: .semibold),
    color: NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.58, alpha: 1)
)
drawText(
    "Hello, world! This text should be recognized.\nCapture locally. Translate in place. Keep data private.",
    in: NSRect(x: 92, y: 452, width: 590, height: 90),
    font: .systemFont(ofSize: 24),
    color: NSColor(calibratedWhite: 0.12, alpha: 1)
)
drawText(
    "中文：截图、标注、识别文字、原位置翻译。\n日本語：こんにちは、世界。",
    in: NSRect(x: 92, y: 368, width: 590, height: 78),
    font: .systemFont(ofSize: 23),
    color: NSColor(calibratedWhite: 0.16, alpha: 1)
)

let rightCard = NSBezierPath(roundedRect: NSRect(x: 756, y: 338, width: 388, height: 270), xRadius: 24, yRadius: 24)
NSColor(calibratedRed: 0.04, green: 0.34, blue: 0.58, alpha: 1).setFill()
rightCard.fill()

let circleColors: [NSColor] = [
    NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.78, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.53, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.34, blue: 0.90, alpha: 1),
]
for index in 0..<3 {
    let y = 525 - CGFloat(index) * 72
    circleColors[index].setFill()
    NSBezierPath(ovalIn: NSRect(x: 792, y: y, width: 46, height: 46)).fill()
    drawText(
        "\(index + 1)",
        in: NSRect(x: 792, y: y + 8, width: 46, height: 30),
        font: .systemFont(ofSize: 21, weight: .bold),
        color: .white,
        alignment: .center
    )
    drawText(
        ["Capture", "Recognize", "Translate"][index],
        in: NSRect(x: 858, y: y + 7, width: 240, height: 32),
        font: .systemFont(ofSize: 23, weight: .semibold),
        color: .white
    )
}

let footerCard = NSBezierPath(roundedRect: NSRect(x: 56, y: 62, width: 1_088, height: 222), xRadius: 24, yRadius: 24)
NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
footerCard.fill()

drawText(
    "安全遮挡测试（以下内容为虚构）",
    in: NSRect(x: 92, y: 222, width: 480, height: 36),
    font: .systemFont(ofSize: 23, weight: .semibold),
    color: NSColor(calibratedRed: 0.70, green: 0.16, blue: 0.18, alpha: 1)
)
drawText(
    "订单号 LS-2026-0717    验证码 123456    邮箱 demo@example.invalid",
    in: NSRect(x: 92, y: 170, width: 950, height: 36),
    font: .monospacedSystemFont(ofSize: 22, weight: .regular),
    color: NSColor(calibratedWhite: 0.14, alpha: 1)
)

NSColor(calibratedRed: 0.04, green: 0.55, blue: 0.65, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 92, y: 104, width: 270, height: 42), xRadius: 12, yRadius: 12).fill()
drawText(
    "用于马赛克与遮挡",
    in: NSRect(x: 104, y: 113, width: 246, height: 28),
    font: .systemFont(ofSize: 20, weight: .semibold),
    color: .white,
    alignment: .center
)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码测试图片")
}
try data.write(to: outputURL, options: .atomic)
print(outputURL.path)
