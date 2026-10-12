import CoreGraphics
import Foundation
import ImageIO
import LocalShotEditing
import UniformTypeIdentifiers

enum EditingCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

private struct LegacyAnnotationProject: Codable {
    let id: UUID
    let imageFilename: String
    let canvasWidth: Int
    let canvasHeight: Int
    let cropRect: AnnotationRect?
    let annotations: [AnnotationItem]
    let createdAt: Date
    let updatedAt: Date
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw EditingCheckError.failed(message)
    }
}

func writeBaseImage(to url: URL, width: Int, height: Int) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw EditingCheckError.failed("无法创建基础图片")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 20, y: 20, width: 80, height: 50))

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw EditingCheckError.failed("无法创建基础图片文件")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw EditingCheckError.failed("无法写入基础图片")
    }
}

func writeEffectBaseImage(to url: URL, width: Int, height: Int) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw EditingCheckError.failed("无法创建效果测试图片")
    }
    for y in stride(from: 0, to: height, by: 4) {
        for x in stride(from: 0, to: width, by: 4) {
            let isEven = ((x / 4) + (y / 4)).isMultiple(of: 2)
            context.setFillColor(isEven
                ? CGColor(red: 0.95, green: 0.12, blue: 0.18, alpha: 1)
                : CGColor(red: 0.08, green: 0.72, blue: 0.96, alpha: 1))
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw EditingCheckError.failed("无法创建效果测试文件")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw EditingCheckError.failed("无法写入效果测试文件")
    }
}

func meanPixelDifference(_ first: CGImage, _ second: CGImage, rect: CGRect) throws -> Double {
    guard first.width == second.width, first.height == second.height else {
        throw EditingCheckError.failed("效果测试图片尺寸不一致")
    }
    let width = first.width
    let height = first.height
    let bytesPerRow = width * 4
    func pixels(for image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let created = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else {
            throw EditingCheckError.failed("无法读取效果测试像素")
        }
        return bytes
    }
    let firstPixels = try pixels(for: first)
    let secondPixels = try pixels(for: second)
    let sampleRect = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    var total = 0
    var count = 0
    for y in Int(sampleRect.minY)..<Int(sampleRect.maxY) {
        for x in Int(sampleRect.minX)..<Int(sampleRect.maxX) {
            let offset = y * bytesPerRow + x * 4
            for channel in 0..<3 {
                total += abs(Int(firstPixels[offset + channel]) - Int(secondPixels[offset + channel]))
                count += 1
            }
        }
    }
    return count > 0 ? Double(total) / Double(count) : 0
}

func samplePixel(
    _ image: CGImage,
    x: Int,
    y: Int
) throws -> (red: Double, green: Double, blue: Double) {
    var bytes = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
        data: &bytes,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw EditingCheckError.failed("无法读取渲染像素")
    }
    context.interpolationQuality = .none
    context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (
        Double(bytes[0]) / 255,
        Double(bytes[1]) / 255,
        Double(bytes[2]) / 255
    )
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LocalShotEditingCheck-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: directory) }

do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let baseURL = directory.appendingPathComponent("base.png")
    let projectURL = directory.appendingPathComponent("project.localshot.json")
    let outputURL = directory.appendingPathComponent("rendered.png")
    let croppedOutputURL = directory.appendingPathComponent("cropped.png")
    let rotatedOutputURL = directory.appendingPathComponent("rotated.png")
    let effectBaseURL = directory.appendingPathComponent("effect-base.png")
    let effectOutputURL = directory.appendingPathComponent("effect-rendered.png")
    let rectangleOutputURL = directory.appendingPathComponent("rectangle-rendered.png")
    let stepOutputURL = directory.appendingPathComponent("step-rendered.png")
    let arrowOutputURL = directory.appendingPathComponent("arrow-rendered.png")
    try writeBaseImage(to: baseURL, width: 320, height: 180)
    try writeEffectBaseImage(to: effectBaseURL, width: 160, height: 100)

    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let rotatedAnnotationID = UUID()
    let project = AnnotationProject(
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        annotations: [
            .rectangle(RectangleAnnotation(
                rect: AnnotationRect(x: 12, y: 12, width: 120, height: 70)
            )),
            .ellipse(EllipseAnnotation(
                rect: AnnotationRect(x: 130, y: 90, width: 70, height: 50),
                color: AnnotationColor(red: 0.2, green: 0.5, blue: 0.95)
            )),
            .arrow(ArrowAnnotation(
                start: AnnotationPoint(x: 20, y: 140),
                end: AnnotationPoint(x: 150, y: 80)
            )),
            .line(LineAnnotation(
                start: AnnotationPoint(x: 30, y: 160),
                end: AnnotationPoint(x: 250, y: 160),
                isDashed: true
            )),
            .pen(PenAnnotation(points: [
                AnnotationPoint(x: 160, y: 30),
                AnnotationPoint(x: 180, y: 45),
                AnnotationPoint(x: 210, y: 35)
            ])),
            .highlight(HighlightAnnotation(points: [
                AnnotationPoint(x: 120, y: 72),
                AnnotationPoint(x: 190, y: 72),
                AnnotationPoint(x: 240, y: 74)
            ])),
            .text(TextAnnotation(
                position: AnnotationPoint(x: 170, y: 120),
                text: "LocalShot"
            )),
            .pixelate(PixelateAnnotation(
                rect: AnnotationRect(x: 20, y: 20, width: 80, height: 50)
            )),
            .redaction(RedactionAnnotation(
                id: rotatedAnnotationID,
                rect: AnnotationRect(x: 230, y: 20, width: 70, height: 40)
            )),
            .step(StepAnnotation(
                center: AnnotationPoint(x: 255, y: 145),
                number: 1,
                note: "完成"
            )),
            .spotlight(SpotlightAnnotation(
                focusRect: AnnotationRect(x: 0, y: 0, width: 320, height: 180),
                dimOpacity: 0.2
            ))
        ],
        annotationRotations: [rotatedAnnotationID: .pi / 6],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )

    let store = AnnotationProjectStore()
    try store.save(project, to: projectURL)
    let loaded = try store.load(from: projectURL)
    try require(loaded == project, "项目保存和读取结果不一致")
    try require(
        abs(loaded.rotation(for: rotatedAnnotationID) - .pi / 6) < 0.000_001,
        "旋转角度保存和读取结果不一致"
    )

    let legacyProject = LegacyAnnotationProject(
        id: UUID(),
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        cropRect: nil,
        annotations: [],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let legacyEncoder = JSONEncoder()
    legacyEncoder.dateEncodingStrategy = .iso8601
    let legacyData = try legacyEncoder.encode(legacyProject)
    let legacyDecoder = JSONDecoder()
    legacyDecoder.dateDecodingStrategy = .iso8601
    let decodedLegacy = try legacyDecoder.decode(AnnotationProject.self, from: legacyData)
    try require(decodedLegacy.annotationRotations.isEmpty, "旧项目缺少旋转字段时没有安全回退")

    let legacyPixelate = PixelateAnnotation(
        rect: AnnotationRect(x: 10, y: 10, width: 40, height: 30),
        effect: .blur
    )
    let pixelateData = try JSONEncoder().encode(legacyPixelate)
    guard var pixelateObject = try JSONSerialization.jsonObject(with: pixelateData) as? [String: Any] else {
        throw EditingCheckError.failed("无法构造旧马赛克项目数据")
    }
    pixelateObject.removeValue(forKey: "effect")
    let oldPixelateData = try JSONSerialization.data(withJSONObject: pixelateObject)
    let decodedOldPixelate = try JSONDecoder().decode(PixelateAnnotation.self, from: oldPixelateData)
    try require(decodedOldPixelate.effect == .mosaic, "旧马赛克项目缺少效果字段时没有回退为马赛克")
    let decodedBlur = try JSONDecoder().decode(PixelateAnnotation.self, from: pixelateData)
    try require(decodedBlur == legacyPixelate, "模糊效果保存和读取结果不一致")

    let stepWithNote = StepAnnotation(
        center: AnnotationPoint(x: 60, y: 130),
        number: 2,
        note: "  检查结果  "
    )
    try require(stepWithNote.note == "检查结果", "步骤备注没有去除首尾空白")
    let stepData = try JSONEncoder().encode(stepWithNote)
    let decodedStep = try JSONDecoder().decode(StepAnnotation.self, from: stepData)
    try require(decodedStep == stepWithNote, "步骤备注保存和读取结果不一致")
    guard var stepObject = try JSONSerialization.jsonObject(with: stepData) as? [String: Any] else {
        throw EditingCheckError.failed("无法构造旧步骤编号项目数据")
    }
    stepObject.removeValue(forKey: "note")
    let oldStepData = try JSONSerialization.data(withJSONObject: stepObject)
    let decodedOldStep = try JSONDecoder().decode(StepAnnotation.self, from: oldStepData)
    try require(decodedOldStep.note == nil, "旧步骤编号缺少备注字段时没有安全回退")
    try require(
        StepAnnotation(
            center: AnnotationPoint(x: 20, y: 20),
            number: 1,
            note: "  \n "
        ).note == nil,
        "空步骤备注没有回退为纯编号"
    )

    let arrowWithNote = ArrowAnnotation(
        start: AnnotationPoint(x: 160, y: 100),
        end: AnnotationPoint(x: 260, y: 130),
        lineWidth: 4,
        note: "  重点  ",
        noteFontSize: 22
    )
    try require(arrowWithNote.note == "重点", "箭头备注没有去除首尾空白")
    let arrowData = try JSONEncoder().encode(arrowWithNote)
    let decodedArrow = try JSONDecoder().decode(ArrowAnnotation.self, from: arrowData)
    try require(decodedArrow == arrowWithNote, "箭头备注保存和读取结果不一致")
    guard var arrowObject = try JSONSerialization.jsonObject(with: arrowData) as? [String: Any] else {
        throw EditingCheckError.failed("无法构造旧箭头项目数据")
    }
    arrowObject.removeValue(forKey: "note")
    arrowObject.removeValue(forKey: "noteFontSize")
    let oldArrowData = try JSONSerialization.data(withJSONObject: arrowObject)
    let decodedOldArrow = try JSONDecoder().decode(ArrowAnnotation.self, from: oldArrowData)
    try require(decodedOldArrow.note == nil, "旧箭头缺少备注字段时没有安全回退")
    try require(decodedOldArrow.noteFontSize == 18, "旧箭头缺少备注字号时没有安全回退")
    try require(
        ArrowAnnotation(
            start: AnnotationPoint(x: 0, y: 0),
            end: AnnotationPoint(x: 20, y: 20),
            note: "  \n "
        ).note == nil,
        "空箭头备注没有回退为纯箭头"
    )

    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: loaded,
        outputURL: outputURL
    )
    guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
          let rendered = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw EditingCheckError.failed("无法读取渲染结果")
    }
    try require(rendered.width == 320 && rendered.height == 180, "渲染尺寸错误")
    try require(FileManager.default.fileExists(atPath: outputURL.path), "渲染文件不存在")

    let stepProject = AnnotationProject(
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        annotations: [.step(stepWithNote)],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: stepProject,
        outputURL: stepOutputURL
    )
    guard let baseSource = CGImageSourceCreateWithURL(baseURL as CFURL, nil),
          let baseImage = CGImageSourceCreateImageAtIndex(baseSource, 0, nil),
          let stepSource = CGImageSourceCreateWithURL(stepOutputURL as CFURL, nil),
          let stepImage = CGImageSourceCreateImageAtIndex(stepSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取步骤备注渲染结果")
    }
    let stepNoteDifference = try meanPixelDifference(
        baseImage,
        stepImage,
        rect: CGRect(x: 82, y: 0, width: 170, height: 180)
    )
    try require(
        stepNoteDifference > 0.05,
        "步骤备注没有绘制到编号右侧，像素差：\(stepNoteDifference)"
    )

    let arrowProject = AnnotationProject(
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        annotations: [.arrow(arrowWithNote)],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: arrowProject,
        outputURL: arrowOutputURL
    )
    guard let arrowSource = CGImageSourceCreateWithURL(arrowOutputURL as CFURL, nil),
          let arrowImage = CGImageSourceCreateImageAtIndex(arrowSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取箭头备注渲染结果")
    }
    let arrowNoteDifference = try meanPixelDifference(
        baseImage,
        arrowImage,
        rect: CGRect(x: 104, y: 0, width: 54, height: 180)
    )
    try require(
        arrowNoteDifference > 0.05,
        "箭头备注没有绘制到箭头尾部后方，像素差：\(arrowNoteDifference)"
    )
    let arrowShape = ArrowShapeGeometry(arrowWithNote)
    try require(arrowShape.points.count == 7, "实心箭头轮廓点数量错误")
    let headCenter = AnnotationPoint(
        x: (arrowShape.points[2].x + arrowShape.points[3].x + arrowShape.points[4].x) / 3,
        y: (arrowShape.points[2].y + arrowShape.points[3].y + arrowShape.points[4].y) / 3
    )
    let arrowHeadPixel = try samplePixel(
        arrowImage,
        x: Int(headCenter.x.rounded()),
        y: Int(headCenter.y.rounded())
    )
    try require(
        arrowHeadPixel.red > 0.7
            && arrowHeadPixel.green < 0.4
            && arrowHeadPixel.blue < 0.4,
        "箭头三角头没有完整实心填充"
    )

    var croppedProject = loaded
    croppedProject.cropRect = AnnotationRect(x: 40, y: 30, width: 200, height: 100)
    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: croppedProject,
        outputURL: croppedOutputURL
    )
    guard let croppedSource = CGImageSourceCreateWithURL(croppedOutputURL as CFURL, nil),
          let croppedImage = CGImageSourceCreateImageAtIndex(croppedSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取裁剪渲染结果")
    }
    try require(croppedImage.width == 200 && croppedImage.height == 100, "裁剪渲染尺寸错误")
    let croppedBluePixel = try samplePixel(croppedImage, x: 10, y: 10)
    try require(
        croppedBluePixel.blue > 0.75 && croppedBluePixel.red < 0.35,
        "裁剪区域像素偏移错误"
    )

    let rotatedRedaction = AnnotationItem.redaction(RedactionAnnotation(
        rect: AnnotationRect(x: 160, y: 80, width: 100, height: 20)
    ))
    var rotatedProject = AnnotationProject(
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        annotations: [rotatedRedaction],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    rotatedProject.setRotation(.pi / 2, for: rotatedRedaction.id)
    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: rotatedProject,
        outputURL: rotatedOutputURL
    )
    guard let rotatedSource = CGImageSourceCreateWithURL(rotatedOutputURL as CFURL, nil),
          let rotatedImage = CGImageSourceCreateImageAtIndex(rotatedSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取旋转渲染结果")
    }
    let rotatedInsidePixel = try samplePixel(rotatedImage, x: 210, y: 50)
    let formerInsidePixel = try samplePixel(rotatedImage, x: 170, y: 90)
    try require(
        rotatedInsidePixel.red < 0.1
            && rotatedInsidePixel.green < 0.1
            && rotatedInsidePixel.blue < 0.1,
        "旋转后的安全遮挡没有出现在目标位置"
    )
    try require(
        formerInsidePixel.red > 0.9
            && formerInsidePixel.green > 0.9
            && formerInsidePixel.blue > 0.9,
        "旋转导出仍保留未旋转位置的内容"
    )

    let effectProject = AnnotationProject(
        imageFilename: effectBaseURL.lastPathComponent,
        canvasWidth: 160,
        canvasHeight: 100,
        annotations: [
            .pixelate(PixelateAnnotation(
                rect: AnnotationRect(x: 8, y: 8, width: 64, height: 84),
                scale: 14,
                effect: .mosaic
            )),
            .pixelate(PixelateAnnotation(
                rect: AnnotationRect(x: 88, y: 8, width: 64, height: 84),
                scale: 8,
                effect: .blur
            ))
        ],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    try AnnotationRenderer.render(
        baseImageURL: effectBaseURL,
        project: effectProject,
        outputURL: effectOutputURL
    )
    guard let effectBaseSource = CGImageSourceCreateWithURL(effectBaseURL as CFURL, nil),
          let effectBaseImage = CGImageSourceCreateImageAtIndex(effectBaseSource, 0, nil),
          let effectOutputSource = CGImageSourceCreateWithURL(effectOutputURL as CFURL, nil),
          let effectOutputImage = CGImageSourceCreateImageAtIndex(effectOutputSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取马赛克或模糊渲染结果")
    }
    let mosaicDifference = try meanPixelDifference(
        effectBaseImage,
        effectOutputImage,
        rect: CGRect(x: 12, y: 12, width: 56, height: 76)
    )
    let blurDifference = try meanPixelDifference(
        effectBaseImage,
        effectOutputImage,
        rect: CGRect(x: 92, y: 12, width: 56, height: 76)
    )
    try require(mosaicDifference > 10, "马赛克导出没有真实改变底图")
    try require(blurDifference > 10, "模糊导出没有真实改变底图")
    let blurredColor = try samplePixel(effectOutputImage, x: 120, y: 50)
    let blurredChannels = [blurredColor.red, blurredColor.green, blurredColor.blue]
    try require(
        (blurredChannels.max() ?? 0) - (blurredChannels.min() ?? 0) > 0.05,
        "模糊效果丢失原内容底色，退化成白色蒙版"
    )

    let rectangleProject = AnnotationProject(
        imageFilename: baseURL.lastPathComponent,
        canvasWidth: 320,
        canvasHeight: 180,
        annotations: [.rectangle(RectangleAnnotation(
            rect: AnnotationRect(x: 20, y: 20, width: 80, height: 50),
            lineWidth: 4
        ))],
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    try AnnotationRenderer.render(
        baseImageURL: baseURL,
        project: rectangleProject,
        outputURL: rectangleOutputURL
    )
    guard let rectangleSource = CGImageSourceCreateWithURL(rectangleOutputURL as CFURL, nil),
          let rectangleImage = CGImageSourceCreateImageAtIndex(rectangleSource, 0, nil) else {
        throw EditingCheckError.failed("无法读取直角矩形渲染结果")
    }
    let rectangleCorner = try samplePixel(rectangleImage, x: 21, y: 21)
    try require(
        rectangleCorner.red > 0.65 && rectangleCorner.green < 0.55,
        "矩形角点没有描边，导出仍可能使用圆角"
    )

    let rectangle = AnnotationItem.rectangle(RectangleAnnotation(
        rect: AnnotationRect(x: 10, y: 20, width: 80, height: 40)
    ))
    try require(
        rectangle.hitTest(AnnotationPoint(x: 40, y: 35)),
        "矩形命中测试失败"
    )
    let moved = rectangle.translated(dx: 25, dy: 10)
    try require(
        moved.bounds == AnnotationRect(x: 35, y: 30, width: 80, height: 40),
        "标注移动结果错误"
    )
    let scaled = rectangle.scaled(
        from: rectangle.bounds,
        to: AnnotationRect(x: 5, y: 6, width: 160, height: 90)
    )
    try require(
        scaled.bounds == AnnotationRect(x: 5, y: 6, width: 160, height: 90),
        "标注缩放结果错误"
    )
    let rotatedBounds = rectangle.bounds(rotation: .pi / 2)
    try require(
        abs(rotatedBounds.x - 30) < 0.000_001
            && abs(rotatedBounds.y) < 0.000_001
            && abs(rotatedBounds.width - 40) < 0.000_001
            && abs(rotatedBounds.height - 80) < 0.000_001,
        "旋转后的外接边界错误：\(rotatedBounds)"
    )
    try require(
        rotatedRedaction.hitTest(
            AnnotationPoint(x: 210, y: 50),
            tolerance: 1,
            rotation: .pi / 2
        ),
        "旋转后的命中测试失败"
    )
    try require(
        !rotatedRedaction.hitTest(
            AnnotationPoint(x: 170, y: 90),
            tolerance: 1,
            rotation: .pi / 2
        ),
        "旋转命中测试仍命中旧位置"
    )

    let arrow = AnnotationItem.arrow(ArrowAnnotation(
        start: AnnotationPoint(x: 10, y: 10),
        end: AnnotationPoint(x: 110, y: 60)
    ))
    try require(
        arrow.hitTest(AnnotationPoint(x: 60, y: 35), tolerance: 3),
        "箭头线段命中测试失败"
    )
    let arrowGeometry = ArrowShapeGeometry(
        start: AnnotationPoint(x: 10, y: 10),
        end: AnnotationPoint(x: 110, y: 60),
        lineWidth: 4
    )
    try require(
        arrow.bounds == arrowGeometry.bounds,
        "箭头边界没有使用完整实心轮廓"
    )
    try require(
        arrow.hitTest(arrowGeometry.points[2], tolerance: 0.5),
        "箭头三角头无法命中选中"
    )
    let enlargedArrow = ArrowShapeGeometry(
        start: AnnotationPoint(x: 0, y: 0),
        end: AnnotationPoint(x: 100, y: 0),
        lineWidth: 4
    )
    try require(
        enlargedArrow.bounds.height >= 22.5,
        "箭头头部没有按目标放大"
    )
    try require(
        abs(enlargedArrow.points[1].y - enlargedArrow.points[5].y) >= 7.5,
        "箭头箭身没有按目标加粗"
    )
    let shortArrow = ArrowShapeGeometry(
        start: AnnotationPoint(x: 10, y: 20),
        end: AnnotationPoint(x: 14, y: 20),
        lineWidth: 9
    )
    try require(
        shortArrow.points.allSatisfy { $0.x >= 10 && $0.x <= 14 },
        "短箭头轮廓反超起点或终点"
    )
    let notedArrow = AnnotationItem.arrow(arrowWithNote)
    try require(
        notedArrow.bounds.minX < arrowWithNote.start.x,
        "箭头边界没有包含尾部后方备注"
    )
    try require(
        notedArrow.hitTest(AnnotationPoint(x: 130, y: 98), tolerance: 2),
        "箭头备注文字区域无法命中选中"
    )
    let movedArrow = notedArrow.translated(dx: 12, dy: -8)
    try require(
        abs(movedArrow.bounds.minX - (notedArrow.bounds.minX + 12)) < 0.000_001
            && abs(movedArrow.bounds.minY - (notedArrow.bounds.minY - 8)) < 0.000_001,
        "带备注箭头移动结果错误"
    )

    let dashedLine = AnnotationItem.line(LineAnnotation(
        start: AnnotationPoint(x: 20, y: 20),
        end: AnnotationPoint(x: 180, y: 20),
        isDashed: true
    ))
    try require(
        dashedLine.hitTest(AnnotationPoint(x: 90, y: 22), tolerance: 3),
        "直线命中测试失败"
    )
    let step = AnnotationItem.step(StepAnnotation(
        center: AnnotationPoint(x: 60, y: 60),
        number: 3,
        diameter: 30
    ))
    let scaledStep = step.scaled(
        from: step.bounds,
        to: AnnotationRect(x: 80, y: 70, width: 50, height: 50)
    )
    try require(
        scaledStep.bounds == AnnotationRect(x: 80, y: 70, width: 50, height: 50),
        "步骤编号缩放结果错误"
    )
    let notedStep = AnnotationItem.step(stepWithNote)
    try require(
        notedStep.bounds.maxX > stepWithNote.center.x + stepWithNote.diameter / 2,
        "步骤编号边界没有包含右侧备注"
    )

    print("LocalShotEditingCheck: PASS")
} catch {
    fputs("LocalShotEditingCheck: FAIL - \(error)\n", stderr)
    exit(1)
}
