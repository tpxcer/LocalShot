import CoreGraphics
import Foundation
import ImageIO
import LocalShotCore
import LocalShotSystemScreenshot

enum CheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            message
        }
    }
}

enum SimulatedExportError: Error {
    case failed
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CheckError.failed(message)
    }
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("LocalShotCoreCheck-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: directory) }

do {
    let store = try CaptureFileStore(capturesDirectory: directory)
    guard let imageContext = CGContext(
        data: nil,
        width: 64,
        height: 32,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CheckError.failed("无法创建图片编码自检画布")
    }
    imageContext.setFillColor(CGColor(red: 0.08, green: 0.42, blue: 0.76, alpha: 1))
    imageContext.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
    guard let fixtureImage = imageContext.makeImage() else {
        throw CheckError.failed("无法生成图片编码自检图")
    }
    let encodedPNGURL = directory.appendingPathComponent("encoded.png")
    let encodedJPEGURL = directory.appendingPathComponent("encoded.jpg")
    try CaptureImageWriter.write(fixtureImage, to: encodedPNGURL, format: .png)
    try CaptureImageWriter.write(
        fixtureImage,
        to: encodedJPEGURL,
        format: .jpeg,
        jpegQuality: 0.8
    )
    for encodedURL in [encodedPNGURL, encodedJPEGURL] {
        guard let source = CGImageSourceCreateWithURL(encodedURL as CFURL, nil),
              let encodedImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CheckError.failed("无法读取编码自检文件：\(encodedURL.lastPathComponent)")
        }
        try require(
            encodedImage.width == 64 && encodedImage.height == 32,
            "编码自检尺寸错误：\(encodedURL.lastPathComponent)"
        )
    }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let utc = TimeZone(secondsFromGMT: 0)!
    let windowURL = store.nextCaptureURL(mode: .window, date: date, timeZone: utc)
    try require(
        windowURL.lastPathComponent == "LocalShot-20231114-221320-000-window.png",
        "窗口截图文件名不符合预期：\(windowURL.lastPathComponent)"
    )
    let jpegURL = store.nextCaptureURL(
        mode: .area,
        date: date,
        format: .jpeg,
        filenamePrefix: "My/Shot",
        timeZone: utc
    )
    try require(
        jpegURL.lastPathComponent == "My-Shot-20231114-221320-000-area.jpg",
        "JPEG 文件名或前缀清理错误：\(jpegURL.lastPathComponent)"
    )
    try Data([0xFF, 0xD8, 0xFF]).write(to: jpegURL)

    let recordingStore = try ScreenRecordingFileStore(recordingsDirectory: directory)
    let recordingURL = recordingStore.nextRecordingURL(
        date: date,
        filenamePrefix: "My/Shot",
        timeZone: utc
    )
    try require(
        recordingURL.lastPathComponent == "My-Shot-20231114-221320-000-recording.mp4",
        "录屏文件名或前缀清理错误：\(recordingURL.lastPathComponent)"
    )
    let laterRecordingURL = recordingStore.nextRecordingURL(
        date: date.addingTimeInterval(1),
        timeZone: utc
    )
    let personalVideoURL = directory.appendingPathComponent("personal-video.mp4")
    let recordingPartURL = directory.appendingPathComponent(
        "LocalShot-20231114-221320-000-recording-part-1.mp4"
    )
    for url in [recordingURL, laterRecordingURL, personalVideoURL, recordingPartURL] {
        try Data("video".utf8).write(to: url)
    }
    try FileManager.default.setAttributes(
        [.modificationDate: date],
        ofItemAtPath: recordingURL.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: date.addingTimeInterval(1)],
        ofItemAtPath: laterRecordingURL.path
    )
    let recentRecordings = try recordingStore.recentRecordings(limit: nil)
    try require(recentRecordings.count == 2, "最近录屏错误识别个人视频或临时分段")
    try require(
        recentRecordings.first?.url.lastPathComponent == laterRecordingURL.lastPathComponent,
        "最近录屏没有按修改时间倒序排列"
    )
    let limitedRecentRecordings = try recordingStore.recentRecordings(limit: 1)
    try require(
        limitedRecentRecordings.map(\.url.lastPathComponent)
            == [laterRecordingURL.lastPathComponent],
        "最近录屏数量限制错误"
    )
    let removedRecordingCount = try recordingStore.removeAllRecordings()
    try require(removedRecordingCount == 2, "清空录屏文件数量错误")
    try require(
        !FileManager.default.fileExists(atPath: recordingURL.path)
            && !FileManager.default.fileExists(atPath: laterRecordingURL.path),
        "清空录屏文件没有删除受管理 MP4"
    )
    try require(
        FileManager.default.fileExists(atPath: personalVideoURL.path)
            && FileManager.default.fileExists(atPath: recordingPartURL.path),
        "清空录屏文件误删个人视频或临时分段"
    )

    let missingAsset = CaptureAsset(
        url: store.nextCaptureURL(
            mode: .area,
            date: date.addingTimeInterval(-1)
        ),
        createdAt: .now,
        mode: .area
    )
    let missingProjectURL = missingAsset.url
        .deletingPathExtension()
        .appendingPathExtension("localshot.json")
    try Data("orphan project".utf8).write(to: missingProjectURL)
    try store.delete(missingAsset)
    try require(
        !FileManager.default.fileExists(atPath: missingProjectURL.path),
        "图片缺失时关联标注项目未清理"
    )

    let areaArguments = SystemScreenshotCommand.arguments(
        for: .area,
        outputURL: directory.appendingPathComponent("area.png")
    )
    try require(areaArguments.starts(with: ["-i", "-s"]), "区域截图参数错误")
    let windowArguments = SystemScreenshotCommand.arguments(
        for: .window,
        outputURL: directory.appendingPathComponent("window.png")
    )
    try require(windowArguments.starts(with: ["-i", "-W"]), "窗口截图参数错误")
    let screenArguments = SystemScreenshotCommand.arguments(
        for: .fullScreen,
        outputURL: directory.appendingPathComponent("screen.png")
    )
    try require(screenArguments.starts(with: ["-m"]), "全屏截图参数错误")
    let jpegArguments = SystemScreenshotCommand.arguments(
        for: .fullScreen,
        outputURL: directory.appendingPathComponent("screen.jpg"),
        format: .jpeg
    )
    try require(jpegArguments.contains("-tjpg"), "JPEG 系统截图参数错误")
    let noShadowArguments = SystemScreenshotCommand.arguments(
        for: .window,
        outputURL: directory.appendingPathComponent("window.png"),
        showsCursor: true,
        includesWindowShadow: false
    )
    try require(noShadowArguments.contains("-C"), "光标截图参数错误")
    try require(noShadowArguments.contains("-o"), "窗口无阴影参数错误")

    let convertedRect = ScreenCoordinateConverter.screenCaptureKitSourceRect(
        fromAppKitSelection: CGRect(x: 20, y: 100, width: 300, height: 200),
        screenHeight: 900
    )
    try require(convertedRect == CGRect(x: 20, y: 600, width: 300, height: 200), "坐标转换错误")

    let appKitWindowRect = ScreenCoordinateConverter.appKitWindowRect(
        fromScreenCaptureKitFrame: CGRect(x: 50, y: 120, width: 480, height: 320),
        primaryScreenHeight: 900
    )
    try require(
        appKitWindowRect == CGRect(x: 50, y: 460, width: 480, height: 320),
        "窗口坐标转换错误"
    )

    let leftDisplayWindowRect = ScreenCoordinateConverter.appKitWindowRect(
        fromScreenCaptureKitFrame: CGRect(x: -1280, y: 100, width: 900, height: 700),
        primaryScreenHeight: 900
    )
    try require(
        leftDisplayWindowRect == CGRect(x: -1280, y: 100, width: 900, height: 700),
        "左侧显示器窗口坐标转换错误"
    )

    let upperDisplayWindowRect = ScreenCoordinateConverter.appKitWindowRect(
        fromScreenCaptureKitFrame: CGRect(x: 120, y: -600, width: 800, height: 600),
        primaryScreenHeight: 900
    )
    try require(
        upperDisplayWindowRect == CGRect(x: 120, y: 900, width: 800, height: 600),
        "上方显示器窗口坐标转换错误"
    )

    let lowerDisplayWindowRect = ScreenCoordinateConverter.appKitWindowRect(
        fromScreenCaptureKitFrame: CGRect(x: 80, y: 900, width: 1000, height: 800),
        primaryScreenHeight: 900
    )
    try require(
        lowerDisplayWindowRect == CGRect(x: 80, y: -800, width: 1000, height: 800),
        "下方显示器窗口坐标转换错误"
    )

    let windowRelativeRect = ScreenCoordinateConverter.windowRelativeRect(
        forGlobalSelection: CGRect(x: 150, y: 180, width: 300, height: 200),
        inside: CGRect(x: 100, y: 100, width: 800, height: 600)
    )
    try require(
        windowRelativeRect == CGRect(x: 50, y: 80, width: 300, height: 200),
        "窗口相对选区转换错误"
    )
    try require(
        ScreenCoordinateConverter.windowRelativeRect(
            forGlobalSelection: CGRect(x: 80, y: 180, width: 300, height: 200),
            inside: CGRect(x: 100, y: 100, width: 800, height: 600)
        ) == nil,
        "越出窗口的区域长截图选区未被拒绝"
    )
    let pixelCropRect = windowRelativeRect.flatMap {
        ScreenCoordinateConverter.pixelCropRect(
            forWindowRelativeRect: $0,
            windowSize: CGSize(width: 800, height: 600),
            imageSize: CGSize(width: 1600, height: 1200)
        )
    }
    try require(
        pixelCropRect == CGRect(x: 100, y: 160, width: 600, height: 400),
        "区域长截图像素裁剪坐标错误"
    )
    guard let cropOrientationContext = CGContext(
        data: nil,
        width: 10,
        height: 10,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CheckError.failed("无法创建裁剪方向自检画布")
    }
    cropOrientationContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    cropOrientationContext.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
    cropOrientationContext.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    cropOrientationContext.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
    guard let cropOrientationImage = cropOrientationContext.makeImage(),
          let topCrop = ScreenCoordinateConverter.croppedImage(
              cropOrientationImage,
              logicalRect: CGRect(x: 0, y: 0, width: 10, height: 5),
              logicalSize: CGSize(width: 10, height: 10)
          ),
          let topCropData = topCrop.dataProvider?.data as Data? else {
        throw CheckError.failed("无法生成裁剪方向自检图片")
    }
    let topCropSampleOffset = topCrop.bytesPerRow * 2 + 2 * 4
    try require(
        topCropData[topCropSampleOffset + 2] > topCropData[topCropSampleOffset],
        "CGImage 顶部裁剪方向错误"
    )
    let annotationTranslation = ScreenCoordinateConverter.annotationTranslationKeepingScreenPosition(
        from: CGRect(x: 100, y: 80, width: 400, height: 300),
        to: CGRect(x: 70, y: 50, width: 430, height: 330),
        scaleFactor: 2
    )
    try require(
        annotationTranslation == CGSize(width: 60, height: 60),
        "缩放选区后的标注坐标补偿错误"
    )
    let centeredMagnifierRect = ScreenCoordinateConverter.magnifierMappedRect(
        overlayRect: CGRect(x: 50, y: 50, width: 30, height: 20),
        sourcePixelRect: CGRect(x: 80, y: 80, width: 40, height: 40),
        viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        scaleFactor: 2,
        destinationRect: CGRect(x: 0, y: 0, width: 100, height: 100)
    )
    try require(
        centeredMagnifierRect == CGRect(x: 50, y: 50, width: 150, height: 100),
        "放大镜中心取样的选区轮廓映射错误"
    )
    let edgeMagnifierRect = ScreenCoordinateConverter.magnifierMappedRect(
        overlayRect: CGRect(x: 0, y: 90, width: 10, height: 10),
        sourcePixelRect: CGRect(x: 0, y: 0, width: 34, height: 34),
        viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        scaleFactor: 2,
        destinationRect: CGRect(x: 0, y: 0, width: 119, height: 119)
    )
    try require(
        edgeMagnifierRect.map {
            abs($0.minX) < 0.000_001
                && abs($0.minY - 49) < 0.000_001
                && abs($0.width - 70) < 0.000_001
                && abs($0.height - 70) < 0.000_001
        } ?? false,
        "放大镜屏幕边缘取样的选区轮廓映射错误"
    )

    let unorderedWindows = [
        WindowCaptureCandidate(
            id: 101,
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            processID: 1,
            applicationName: "后方",
            title: "A"
        ),
        WindowCaptureCandidate(
            id: 102,
            frame: CGRect(x: 20, y: 20, width: 400, height: 300),
            processID: 2,
            applicationName: "未知层级",
            title: "B"
        ),
        WindowCaptureCandidate(
            id: 103,
            frame: CGRect(x: 40, y: 40, width: 400, height: 300),
            processID: 3,
            applicationName: "前方",
            title: "C"
        )
    ]
    let orderedWindows = WindowCaptureOrdering.frontToBack(
        unorderedWindows,
        zOrderByWindowID: [103: 2, 101: 8]
    )
    try require(
        orderedWindows.map(\.id) == [103, 101, 102],
        "窗口候选没有按系统 z-order 排序"
    )

    let areaURL = store.nextCaptureURL(mode: .area, date: date.addingTimeInterval(1))
    let screenURL = store.nextCaptureURL(mode: .fullScreen, date: date.addingTimeInterval(2))
    let scrollingURL = store.nextCaptureURL(mode: .scrolling, date: date.addingTimeInterval(3))
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: areaURL)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenURL)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: scrollingURL)

    let captures = try store.recentCaptures(limit: 10)
    try require(captures.count == 4, "历史数量不符合预期：\(captures.count)")
    try require(captures.contains { $0.mode == .area }, "未识别区域截图模式")
    try require(captures.contains { $0.mode == .fullScreen }, "未识别全屏截图模式")
    try require(captures.contains { $0.mode == .scrolling }, "未识别滚动截图模式")

    let oldURL = store.nextCaptureURL(
        mode: .area,
        date: Date(timeIntervalSince1970: 100)
    )
    let oldProjectURL = oldURL
        .deletingPathExtension()
        .appendingPathExtension("localshot.json")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: oldURL)
    try Data("old project".utf8).write(to: oldProjectURL)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)],
        ofItemAtPath: oldURL.path
    )
    let removed = try store.removeCaptures(olderThan: Date(timeIntervalSince1970: 200))
    try require(removed == 1, "过期截图清理数量错误：\(removed)")
    try require(!FileManager.default.fileExists(atPath: oldURL.path), "过期截图未删除")
    try require(
        !FileManager.default.fileExists(atPath: oldProjectURL.path),
        "过期截图的关联标注项目未删除"
    )

    let personalImageURL = directory.appendingPathComponent("personal-photo.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: personalImageURL)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)],
        ofItemAtPath: personalImageURL.path
    )
    let removedAfterPersonalImage = try store.removeCaptures(
        olderThan: Date(timeIntervalSince1970: 200)
    )
    try require(removedAfterPersonalImage == 0, "个人图片被误计入过期清理")
    try require(
        FileManager.default.fileExists(atPath: personalImageURL.path),
        "个人图片被过期清理误删"
    )
    let capturesWithoutPersonalImage = try store.recentCaptures(limit: nil)
    try require(
        !capturesWithoutPersonalImage.contains { $0.url == personalImageURL },
        "个人图片被误加入截图历史"
    )

    let deletedURL = store.nextCaptureURL(
        mode: .area,
        date: date.addingTimeInterval(4)
    )
    let deletedProjectURL = deletedURL
        .deletingPathExtension()
        .appendingPathExtension("localshot.json")
    try Data("capture".utf8).write(to: deletedURL)
    try Data("project".utf8).write(to: deletedProjectURL)
    try store.delete(CaptureAsset(url: deletedURL, createdAt: .now, mode: .area))
    try require(!FileManager.default.fileExists(atPath: deletedURL.path), "单张截图未删除")
    try require(
        !FileManager.default.fileExists(atPath: deletedProjectURL.path),
        "单张截图的关联标注项目未删除"
    )

    let exportSourceURL = directory.appendingPathComponent("export-source.png")
    let exportDestinationURL = directory.appendingPathComponent("export-destination.png")
    let exportNewURL = directory.appendingPathComponent("export-new.png")
    let sourceData = Data("new image".utf8)
    try sourceData.write(to: exportSourceURL)
    try Data("old image".utf8).write(to: exportDestinationURL)
    try LocalFileExporter.exportCopy(from: exportSourceURL, to: exportDestinationURL)
    let replacedData = try Data(contentsOf: exportDestinationURL)
    let preservedSourceData = try Data(contentsOf: exportSourceURL)
    try require(
        replacedData == sourceData,
        "覆盖另存为没有写入新内容"
    )
    try require(
        preservedSourceData == sourceData,
        "覆盖另存为破坏了源文件"
    )
    try LocalFileExporter.exportCopy(from: exportSourceURL, to: exportSourceURL)
    let samePathData = try Data(contentsOf: exportSourceURL)
    try require(
        samePathData == sourceData,
        "同路径另存为破坏了源文件"
    )
    try LocalFileExporter.exportCopy(from: exportSourceURL, to: exportNewURL)
    let copiedData = try Data(contentsOf: exportNewURL)
    try require(
        copiedData == sourceData,
        "另存为新文件失败"
    )
    let generatedDestinationURL = directory.appendingPathComponent("generated.png")
    let originalGeneratedData = Data("existing export".utf8)
    try originalGeneratedData.write(to: generatedDestinationURL)
    do {
        try LocalFileExporter.exportGeneratedFile(to: generatedDestinationURL) { temporaryURL in
            try Data("partial export".utf8).write(to: temporaryURL)
            throw SimulatedExportError.failed
        }
        throw CheckError.failed("生成导出失败没有向上抛出")
    } catch SimulatedExportError.failed {
        let preservedGeneratedData = try Data(contentsOf: generatedDestinationURL)
        try require(
            preservedGeneratedData == originalGeneratedData,
            "生成导出失败破坏了已有目标文件"
        )
    }
    let completedGeneratedData = Data("completed export".utf8)
    try LocalFileExporter.exportGeneratedFile(to: generatedDestinationURL) { temporaryURL in
        try completedGeneratedData.write(to: temporaryURL)
    }
    let generatedDataAfterSuccess = try Data(contentsOf: generatedDestinationURL)
    try require(
        generatedDataAfterSuccess == completedGeneratedData,
        "生成导出成功后没有原子替换目标文件"
    )

    let replacementFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.contains(".localshot-output-") }
    try require(replacementFiles.isEmpty, "导出后遗留临时输出文件")

    let orphanCaptureURL = store.nextCaptureURL(
        mode: .window,
        date: date.addingTimeInterval(50)
    )
    let orphanProjectURL = orphanCaptureURL
        .deletingPathExtension()
        .appendingPathExtension("localshot.json")
    let unrelatedProjectURL = directory.appendingPathComponent("notes.localshot.json")
    try Data("orphan".utf8).write(to: orphanProjectURL)
    try Data("personal notes".utf8).write(to: unrelatedProjectURL)

    _ = try store.removeAllCaptures()
    try require(
        FileManager.default.fileExists(atPath: personalImageURL.path),
        "清空截图历史误删个人图片"
    )
    try require(
        !FileManager.default.fileExists(atPath: orphanProjectURL.path),
        "清空截图历史没有清理 LocalShot 孤儿项目"
    )
    try require(
        FileManager.default.fileExists(atPath: unrelatedProjectURL.path),
        "清空截图历史误删普通 JSON 文件"
    )

    let defaultHotKeys = HotKeyConfiguration.default
    try require(
        defaultHotKeys.shortcut(for: .area)?.displayString == "⌘⌃A",
        "默认区域截图快捷键显示错误"
    )
    try require(
        defaultHotKeys.shortcut(for: .recognizeText)?.displayString == "⌘⇧O",
        "默认识别文字快捷键显示错误"
    )
    try require(defaultHotKeys.invalidActions.isEmpty, "默认快捷键包含无效配置")
    try require(defaultHotKeys.conflicts.isEmpty, "默认快捷键存在内部冲突")
    try require(
        HotKeyConfiguration.conflictSafe.shortcut(for: .area)?.displayString == "⌃⌥1",
        "冲突安全区域截图快捷键显示错误"
    )
    try require(
        HotKeyConfiguration.migratingLegacyDefaultIfNeeded(
            .conflictSafe,
            didMigrate: false
        ) == .default,
        "旧默认快捷键没有迁移到当前默认组合"
    )
    try require(
        HotKeyConfiguration.migratingLegacyDefaultIfNeeded(
            .conflictSafe,
            didMigrate: true
        ) == .conflictSafe,
        "已完成迁移后仍重复改写冲突安全快捷键"
    )

    var legacyHotKeys = defaultHotKeys
    legacyHotKeys.recognizeText = nil
    try require(
        HotKeyConfiguration.addingDefaultTextRecognitionIfNeeded(
            legacyHotKeys,
            didMigrate: false
        ).recognizeText == defaultHotKeys.recognizeText,
        "旧快捷键配置没有补充默认识别文字快捷键"
    )
    try require(
        HotKeyConfiguration.addingDefaultTextRecognitionIfNeeded(
            legacyHotKeys,
            didMigrate: true
        ).recognizeText == nil,
        "用户清除识别文字快捷键后被重复恢复"
    )
    var preOCRConflictSafeHotKeys = HotKeyConfiguration.conflictSafe
    preOCRConflictSafeHotKeys.recognizeText = nil
    let conflictSafeWithTextRecognition = HotKeyConfiguration.addingDefaultTextRecognitionIfNeeded(
        preOCRConflictSafeHotKeys,
        didMigrate: false
    )
    try require(
        HotKeyConfiguration.migratingLegacyDefaultIfNeeded(
            conflictSafeWithTextRecognition,
            didMigrate: false
        ) == defaultHotKeys,
        "新增识别文字字段后破坏了旧区域快捷键迁移"
    )

    var commandOHotKeys = defaultHotKeys
    commandOHotKeys.recognizeText = HotKeyShortcut(keyCode: 31, modifiers: [.command])
    try require(
        HotKeyConfiguration.migratingLegacyTextRecognitionShortcutIfNeeded(
            commandOHotKeys,
            didMigrate: false
        ).recognizeText == defaultHotKeys.recognizeText,
        "旧版识别文字快捷键没有迁移为 ⌘⇧O"
    )
    try require(
        HotKeyConfiguration.migratingLegacyTextRecognitionShortcutIfNeeded(
            commandOHotKeys,
            didMigrate: true
        ).recognizeText == commandOHotKeys.recognizeText,
        "已完成迁移后仍重复改写识别文字快捷键"
    )

    var duplicatedHotKeys = defaultHotKeys
    duplicatedHotKeys.setShortcut(defaultHotKeys.area, for: .window)
    try require(
        duplicatedHotKeys.conflicts.count == 1
            && duplicatedHotKeys.conflicts[0].first == .area
            && duplicatedHotKeys.conflicts[0].second == .window,
        "快捷键内部冲突检测错误"
    )

    var invalidHotKeys = defaultHotKeys
    invalidHotKeys.setShortcut(
        HotKeyShortcut(keyCode: 0, modifiers: [.shift]),
        for: .fullScreen
    )
    try require(
        invalidHotKeys.invalidActions == [.fullScreen],
        "无主修饰键的快捷键没有被判定为无效"
    )

    var customizedHotKeys = defaultHotKeys
    customizedHotKeys.setShortcut(
        HotKeyShortcut(keyCode: 8, modifiers: [.command, .shift]),
        for: .area
    )
    customizedHotKeys.setShortcut(nil, for: .recognizeText)
    let hotKeyData = try JSONEncoder().encode(customizedHotKeys)
    let decodedHotKeys = try JSONDecoder().decode(HotKeyConfiguration.self, from: hotKeyData)
    try require(decodedHotKeys == customizedHotKeys, "自定义快捷键保存和读取结果不一致")
    try require(
        decodedHotKeys.shortcut(for: .area)?.displayString == "⌘⇧C",
        "自定义快捷键显示错误"
    )
    try require(
        decodedHotKeys.shortcut(for: .recognizeText) == nil,
        "清除快捷键后仍存在注册配置"
    )

    try require(
        ScreenRecordingQuality.standard.outputSize(
            for: CGSize(width: 2_560, height: 1_440)
        ) == CGSize(width: 1_280, height: 720),
        "标准录制画质缩放尺寸错误"
    )
    try require(
        ScreenRecordingQuality.high.outputSize(
            for: CGSize(width: 3_840, height: 2_160)
        ) == CGSize(width: 1_920, height: 1_080),
        "高清录制画质缩放尺寸错误"
    )
    try require(
        ScreenRecordingQuality.original.outputSize(
            for: CGSize(width: 3_840, height: 2_160)
        ) == CGSize(width: 3_840, height: 2_160),
        "原画录制尺寸被错误缩放"
    )
    let estimate30 = ScreenRecordingSizeEstimator.estimatePerMinute(
        pixelSize: CGSize(width: 1_920, height: 1_080),
        frameRate: .fps30,
        capturesAudio: false
    )
    let estimate60 = ScreenRecordingSizeEstimator.estimatePerMinute(
        pixelSize: CGSize(width: 1_920, height: 1_080),
        frameRate: .fps60,
        capturesAudio: true
    )
    try require(
        estimate30.lowerBytesPerMinute > 0
            && estimate30.upperBytesPerMinute > estimate30.lowerBytesPerMinute,
        "30 FPS 文件大小估算范围无效"
    )
    try require(
        estimate60.lowerBytesPerMinute > estimate30.lowerBytesPerMinute
            && estimate60.upperBytesPerMinute > estimate30.upperBytesPerMinute,
        "60 FPS 文件大小估算没有随帧率提高"
    )

    print("LocalShotCoreCheck: PASS")
} catch {
    fputs("LocalShotCoreCheck: FAIL - \(error)\n", stderr)
    exit(1)
}
