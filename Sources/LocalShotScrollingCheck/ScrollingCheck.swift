import CoreGraphics
import Foundation
import ImageIO
import LocalShotScrolling
import UniformTypeIdentifiers

enum ScrollingCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct LocalShotScrollingCheck {
    @MainActor
    static func main() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotScrollingCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = try makeLongImage(width: 240, height: 600)
            let sourceURL = directory.appendingPathComponent("source.png")
            try writePNG(source, to: sourceURL)

            let slices = [
                CGRect(x: 0, y: 0, width: 240, height: 260),
                CGRect(x: 0, y: 160, width: 240, height: 260),
                CGRect(x: 0, y: 340, width: 240, height: 260)
            ]
            var segmentURLs: [URL] = []
            for (index, rect) in slices.enumerated() {
                guard let segment = source.cropping(to: rect) else {
                    throw ScrollingCheckError.failed("无法生成测试片段")
                }
                let url = directory.appendingPathComponent("segment-\(index).png")
                try writePNG(segment, to: url)
                segmentURLs.append(url)
            }

            let outputURL = directory.appendingPathComponent("stitched.png")
            let result = try VerticalImageStitcher.stitch(
                imageURLs: segmentURLs,
                outputURL: outputURL,
                maximumDifference: 4
            )
            guard result.width == 240, result.height == 600 else {
                throw ScrollingCheckError.failed("拼接尺寸错误：\(result.width)×\(result.height)")
            }
            guard result.overlaps == [100, 80] else {
                throw ScrollingCheckError.failed("重叠识别错误：\(result.overlaps)")
            }
            let transition = try VerticalImageStitcher.analyzeTransition(
                previousURL: segmentURLs[0],
                nextURL: segmentURLs[1],
                maximumDifference: 4
            )
            guard transition.overlap == 100, transition.frameDifference > 1 else {
                throw ScrollingCheckError.failed("滚动过渡分析结果错误")
            }
            let unchanged = try VerticalImageStitcher.analyzeTransition(
                previousURL: segmentURLs[0],
                nextURL: segmentURLs[0],
                maximumDifference: 4
            )
            guard unchanged.frameDifference == 0 else {
                throw ScrollingCheckError.failed("相同帧变化检测错误")
            }
            guard let nearEndSegment = source.cropping(
                to: CGRect(x: 0, y: 30, width: 240, height: 260)
            ) else {
                throw ScrollingCheckError.failed("无法生成小幅滚动测试片段")
            }
            let nearEndURL = directory.appendingPathComponent("near-end.png")
            try writePNG(nearEndSegment, to: nearEndURL)
            let nearEndTransition = try VerticalImageStitcher.analyzeTransition(
                previousURL: segmentURLs[0],
                nextURL: nearEndURL,
                maximumDifference: 4
            )
            guard nearEndTransition.overlap == 230 else {
                throw ScrollingCheckError.failed("接近页面底部的小幅滚动识别错误")
            }
            let unrelated = try makeUnrelatedImage(width: 240, height: 260)
            let unrelatedURL = directory.appendingPathComponent("unrelated.png")
            try writePNG(unrelated, to: unrelatedURL)
            let unrelatedTransition = try VerticalImageStitcher.analyzeTransition(
                previousURL: segmentURLs[0],
                nextURL: unrelatedURL,
                maximumDifference: 4
            )
            guard unrelatedTransition.overlap == nil else {
                throw ScrollingCheckError.failed("鲁棒差异错误地匹配了无关画面")
            }
            guard let outputSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let output = CGImageSourceCreateImageAtIndex(outputSource, 0, nil) else {
                throw ScrollingCheckError.failed("无法读取拼接结果")
            }
            guard output.width == source.width, output.height == source.height else {
                throw ScrollingCheckError.failed("拼接文件尺寸与原图不一致")
            }

            let previewComposer = ScrollingCapturePreviewComposer(previewWidth: 120)
            let firstPreview = try previewComposer.append(segmentURL: segmentURLs[0], transition: nil)
            let secondPreview = try previewComposer.append(
                segmentURL: segmentURLs[1],
                transition: ScrollTransitionAnalysis(frameDifference: 5, overlap: 100)
            )
            let finalPreview = try previewComposer.append(
                segmentURL: segmentURLs[2],
                transition: ScrollTransitionAnalysis(frameDifference: 5, overlap: 80)
            )
            guard firstPreview.width == 120,
                  firstPreview.height == 130,
                  secondPreview.height == 210,
                  finalPreview.height == 300 else {
                throw ScrollingCheckError.failed("长截图增量预览尺寸或重复区域裁剪错误")
            }

            try verifyStickyHeaderStitching(in: directory)
            try verifyStickyHeaderAndFooterStitching(in: directory)
            try verifyRepeatedCardStitching(in: directory)
            try verifyCapturePolicy()
            try await verifyCaptureSession(in: directory)

            print("LocalShotScrollingCheck: PASS")
        } catch {
            fputs("LocalShotScrollingCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func verifyCapturePolicy() throws {
        guard ScrollingCapturePolicy.effectiveSegmentLimit(1) == 2,
              ScrollingCapturePolicy.effectiveSegmentLimit(30) == 30 else {
            throw ScrollingCheckError.failed("滚动截图安全段数下限错误")
        }

        let reachedEnd = ScrollingCapturePolicy.transitionDecision(
            for: ScrollTransitionAnalysis(frameDifference: 0.8, overlap: nil)
        )
        guard reachedEnd == .reachedEnd else {
            throw ScrollingCheckError.failed("相同正文未触发滚动终止")
        }

        let append = ScrollingCapturePolicy.transitionDecision(
            for: ScrollTransitionAnalysis(frameDifference: 4, overlap: 120, topInset: 36)
        )
        guard append == .appendSegment else {
            throw ScrollingCheckError.failed("有效重叠画面未继续采集")
        }

        let appendWithFixedBars = ScrollingCapturePolicy.transitionDecision(
            for: ScrollTransitionAnalysis(
                frameDifference: 4,
                overlap: 64,
                topInset: 36,
                bottomInset: 52,
                frameHeight: 312
            )
        )
        guard appendWithFixedBars == .appendSegment else {
            throw ScrollingCheckError.failed("带固定顶部和底部的有效滚动未继续采集")
        }

        let waitForMoreMovement = ScrollingCapturePolicy.transitionDecision(
            for: ScrollTransitionAnalysis(
                frameDifference: 4,
                overlap: 230,
                topInset: 12,
                frameHeight: 260
            )
        )
        guard waitForMoreMovement == .waitForMoreMovement else {
            throw ScrollingCheckError.failed("小幅手动滚动被过早追加为新片段")
        }

        let unsupported = ScrollingCapturePolicy.transitionDecision(
            for: ScrollTransitionAnalysis(frameDifference: 20, overlap: nil)
        )
        guard unsupported == .unsupportedTransition else {
            throw ScrollingCheckError.failed("无重叠画面未被拒绝")
        }

        guard ScrollingCapturePolicy.finalizationDecision(
            capturedSegmentCount: 1,
            reachedEnd: true,
            requestedSegmentLimit: 30
        ) == .contentDidNotScroll else {
            throw ScrollingCheckError.failed("单段内容错误进入拼接")
        }

        guard ScrollingCapturePolicy.finalizationDecision(
            capturedSegmentCount: 10,
            reachedEnd: true,
            requestedSegmentLimit: 30
        ) == .stitch else {
            throw ScrollingCheckError.failed("正常到底的滚动截图未进入拼接")
        }

        guard ScrollingCapturePolicy.finalizationDecision(
            capturedSegmentCount: 30,
            reachedEnd: false,
            requestedSegmentLimit: 30
        ) == .segmentLimitReached(30) else {
            throw ScrollingCheckError.failed("30 段安全上限错误进入拼接")
        }
    }

    @MainActor
    private static func verifyCaptureSession(in directory: URL) async throws {
        let outputURL = directory.appendingPathComponent("session-output.png")
        var capturedIndices: [Int] = []
        var advancedIndices: [Int] = []
        var removedNames: [String] = []
        var progressCounts: [Int] = []
        var acceptedNames: [String] = []
        var acceptedOverlaps: [Int?] = []
        var transitionIndex = 0
        let transitions = [
            ScrollTransitionAnalysis(frameDifference: 5, overlap: 80),
            ScrollTransitionAnalysis(frameDifference: 4, overlap: 72, topInset: 36),
            ScrollTransitionAnalysis(frameDifference: 0.4, overlap: nil)
        ]
        var stitchedSegmentCount = 0

        let result = try await ScrollingCaptureSession.run(
            requestedSegmentLimit: 8,
            outputURL: outputURL,
            captureSegment: { index in
                capturedIndices.append(index)
                return directory.appendingPathComponent("session-segment-\(index).png")
            },
            advance: { index in
                advancedIndices.append(index)
            },
            analyzeTransition: { _, _ in
                defer { transitionIndex += 1 }
                return transitions[transitionIndex]
            },
            removeSegment: { removedNames.append($0.lastPathComponent) },
            stitch: { segmentURLs, _ in
                stitchedSegmentCount = segmentURLs.count
                return VerticalStitchResult(
                    width: 240,
                    height: 600,
                    overlaps: [80, 72],
                    topInsets: [0, 36]
                )
            },
            onAcceptedSegment: { url, transition in
                acceptedNames.append(url.lastPathComponent)
                acceptedOverlaps.append(transition?.overlap)
            },
            onProgress: { count, _ in progressCounts.append(count) }
        )
        guard result.capturedSegmentCount == 3,
              result.stitchResult.height == 600,
              capturedIndices == [0, 1, 2, 3],
              advancedIndices == [1, 2, 3],
              progressCounts == [1, 2, 3],
              acceptedNames == [
                "session-segment-0.png",
                "session-segment-1.png",
                "session-segment-2.png"
              ],
              acceptedOverlaps.count == 3,
              acceptedOverlaps[0] == nil,
              acceptedOverlaps[1] == 80,
              acceptedOverlaps[2] == 72,
              removedNames == ["session-segment-3.png"],
              stitchedSegmentCount == 3 else {
            throw ScrollingCheckError.failed("完整滚动采集会话未在页面到底后正确拼接")
        }

        var manualCapturedIndices: [Int] = []
        var manualAcceptedNames: [String] = []
        var manualAttempt = 0
        var manualTransition = 0
        let manualTransitions = [
            ScrollTransitionAnalysis(frameDifference: 0.2, overlap: nil),
            ScrollTransitionAnalysis(frameDifference: 5, overlap: 80),
            ScrollTransitionAnalysis(frameDifference: 0.2, overlap: nil)
        ]
        let manualResult = try await ScrollingCaptureSession.run(
            requestedSegmentLimit: 8,
            outputURL: outputURL,
            captureSegment: { index in
                manualCapturedIndices.append(index)
                return directory.appendingPathComponent("manual-segment-\(index).png")
            },
            advance: { _ in manualAttempt += 1 },
            analyzeTransition: { _, _ in
                defer { manualTransition += 1 }
                return manualTransitions[manualTransition]
            },
            removeSegment: { _ in },
            stitch: { segmentURLs, _ in
                VerticalStitchResult(
                    width: 240,
                    height: 440,
                    overlaps: Array(repeating: 80, count: segmentURLs.count - 1)
                )
            },
            onAcceptedSegment: { url, _ in
                manualAcceptedNames.append(url.lastPathComponent)
            },
            shouldFinishWhenUnchanged: { manualAttempt >= 3 }
        )
        guard manualCapturedIndices == [0, 1, 1, 2],
              manualAcceptedNames == ["manual-segment-0.png", "manual-segment-1.png"],
              manualResult.capturedSegmentCount == 2,
              manualResult.stitchResult.height == 440 else {
            throw ScrollingCheckError.failed("手动滚动采集未正确等待画面变化或完成信号")
        }

        var finalSmallTransition = 0
        var finalSmallAcceptedOverlaps: [Int?] = []
        let finalSmallTransitions = [
            ScrollTransitionAnalysis(
                frameDifference: 4,
                overlap: 230,
                topInset: 12,
                frameHeight: 260
            ),
            ScrollTransitionAnalysis(frameDifference: 0.2, overlap: nil, frameHeight: 260)
        ]
        let finalSmallResult = try await ScrollingCaptureSession.run(
            requestedSegmentLimit: 8,
            outputURL: outputURL,
            captureSegment: {
                directory.appendingPathComponent("final-small-segment-\($0).png")
            },
            advance: { _ in },
            analyzeTransition: { _, _ in
                defer { finalSmallTransition += 1 }
                return finalSmallTransitions[finalSmallTransition]
            },
            removeSegment: { _ in },
            stitch: { segmentURLs, _ in
                VerticalStitchResult(
                    width: 240,
                    height: 278,
                    overlaps: Array(repeating: 230, count: segmentURLs.count - 1),
                    topInsets: Array(repeating: 12, count: segmentURLs.count - 1)
                )
            },
            onAcceptedSegment: { _, transition in
                finalSmallAcceptedOverlaps.append(transition?.overlap)
            },
            shouldFinishWhenUnchanged: { true }
        )
        guard finalSmallResult.capturedSegmentCount == 2,
              finalSmallAcceptedOverlaps.count == 2,
              finalSmallAcceptedOverlaps[0] == nil,
              finalSmallAcceptedOverlaps[1] == 230,
              finalSmallResult.stitchResult.height == 278 else {
            throw ScrollingCheckError.failed("完成时丢失最后一段小幅滚动内容")
        }

        var limitStitchCount = 0
        var limitRejected = false
        do {
            _ = try await ScrollingCaptureSession.run(
                requestedSegmentLimit: 3,
                outputURL: outputURL,
                captureSegment: { directory.appendingPathComponent("limit-\($0).png") },
                advance: { _ in },
                analyzeTransition: { _, _ in
                    ScrollTransitionAnalysis(frameDifference: 5, overlap: 80)
                },
                removeSegment: { _ in },
                stitch: { _, _ in
                    limitStitchCount += 1
                    return VerticalStitchResult(width: 1, height: 1, overlaps: [])
                }
            )
        } catch let error as ScrollingCaptureSessionError {
            guard error == .segmentLimitReached(3) else {
                throw ScrollingCheckError.failed("滚动采集会话返回了错误的段数上限结果")
            }
            limitRejected = true
        }
        guard limitRejected, limitStitchCount == 0 else {
            throw ScrollingCheckError.failed("达到安全段数上限后仍执行了拼接")
        }

        var unsupportedRemoved = false
        var unsupportedRejected = false
        do {
            _ = try await ScrollingCaptureSession.run(
                requestedSegmentLimit: 8,
                outputURL: outputURL,
                captureSegment: { directory.appendingPathComponent("unsupported-\($0).png") },
                advance: { _ in },
                analyzeTransition: { _, _ in
                    ScrollTransitionAnalysis(frameDifference: 20, overlap: nil)
                },
                removeSegment: { _ in unsupportedRemoved = true },
                stitch: { _, _ in
                    throw ScrollingCheckError.failed("异常过渡不应执行拼接")
                }
            )
        } catch let error as ScrollingCaptureSessionError {
            guard error == .unsupportedTransition else {
                throw ScrollingCheckError.failed("异常过渡返回了错误结果")
            }
            unsupportedRejected = true
        }
        guard unsupportedRejected, unsupportedRemoved else {
            throw ScrollingCheckError.failed("异常过渡未拒绝或未清理临时片段")
        }

        var unchangedRejected = false
        do {
            _ = try await ScrollingCaptureSession.run(
                requestedSegmentLimit: 8,
                outputURL: outputURL,
                captureSegment: { directory.appendingPathComponent("unchanged-\($0).png") },
                advance: { _ in },
                analyzeTransition: { _, _ in
                    ScrollTransitionAnalysis(frameDifference: 0.2, overlap: nil)
                },
                removeSegment: { _ in },
                stitch: { _, _ in
                    throw ScrollingCheckError.failed("单段未滚动内容不应执行拼接")
                }
            )
        } catch let error as ScrollingCaptureSessionError {
            guard error == .contentDidNotScroll else {
                throw ScrollingCheckError.failed("未滚动内容返回了错误结果")
            }
            unchangedRejected = true
        }
        guard unchangedRejected else {
            throw ScrollingCheckError.failed("单段未滚动内容未被拒绝")
        }
    }

    private static func makeLongImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingCheckError.failed("无法创建长页面测试图")
        }

        for y in 0..<height {
            let normalized = CGFloat(y) / CGFloat(height)
            context.setFillColor(CGColor(
                red: normalized,
                green: 0.2 + normalized * 0.55,
                blue: 0.85 - normalized * 0.6,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
            if y % 37 == 0 {
                context.setFillColor(CGColor(gray: y % 74 == 0 ? 0.05 : 0.95, alpha: 1))
                context.fill(CGRect(x: 12, y: y, width: width - 24, height: 4))
            }
        }
        guard let image = context.makeImage() else {
            throw ScrollingCheckError.failed("无法生成长页面测试图")
        }
        return image
    }

    private static func verifyStickyHeaderStitching(in directory: URL) throws {
        let width = 240
        let bodyHeight = 544
        let viewportHeight = 224
        let headerHeight = 36
        let body = try makeLongImage(width: width, height: bodyHeight)
        let bodySlices = [
            CGRect(x: 0, y: 0, width: width, height: viewportHeight),
            CGRect(x: 0, y: 160, width: width, height: viewportHeight),
            CGRect(x: 0, y: 320, width: width, height: viewportHeight)
        ]
        var frameURLs: [URL] = []
        for (index, rect) in bodySlices.enumerated() {
            guard let bodySlice = body.cropping(to: rect) else {
                throw ScrollingCheckError.failed("无法生成固定标题栏正文片段")
            }
            let frame = try makeFrame(
                body: bodySlice,
                headerHeight: headerHeight,
                animationOffset: index * 22
            )
            let url = directory.appendingPathComponent("sticky-segment-\(index).png")
            try writePNG(frame, to: url)
            frameURLs.append(url)
        }

        let transition = try VerticalImageStitcher.analyzeTransition(
            previousURL: frameURLs[0],
            nextURL: frameURLs[1],
            maximumDifference: 4
        )
        guard transition.topInset == headerHeight, transition.overlap == 64 else {
            throw ScrollingCheckError.failed(
                "固定标题栏过渡识别错误：顶部 \(transition.topInset)，重叠 \(String(describing: transition.overlap))"
            )
        }

        guard let unchangedBody = body.cropping(to: bodySlices[0]) else {
            throw ScrollingCheckError.failed("无法生成动画终点测试正文")
        }
        let animatedUnchangedFrame = try makeFrame(
            body: unchangedBody,
            headerHeight: headerHeight,
            animationOffset: 66
        )
        let animatedUnchangedURL = directory.appendingPathComponent("animated-unchanged.png")
        try writePNG(animatedUnchangedFrame, to: animatedUnchangedURL)
        let animatedUnchangedTransition = try VerticalImageStitcher.analyzeTransition(
            previousURL: frameURLs[0],
            nextURL: animatedUnchangedURL,
            maximumDifference: 4
        )
        guard animatedUnchangedTransition.frameDifference <= 0.8 else {
            throw ScrollingCheckError.failed(
                "局部标题动画阻止了相同正文终止检测：\(animatedUnchangedTransition.frameDifference)"
            )
        }

        let outputURL = directory.appendingPathComponent("sticky-stitched.png")
        let result = try VerticalImageStitcher.stitch(
            imageURLs: frameURLs,
            outputURL: outputURL,
            maximumDifference: 4
        )
        guard result.width == width,
              result.height == bodyHeight + headerHeight,
              result.overlaps == [64, 64],
              result.topInsets == [headerHeight, headerHeight] else {
            throw ScrollingCheckError.failed(
                "固定标题栏拼接结果错误：\(result.width)×\(result.height)，顶部 \(result.topInsets)，重叠 \(result.overlaps)"
            )
        }
    }

    private static func verifyRepeatedCardStitching(in directory: URL) throws {
        let width = 240
        let sectionHeight = 120
        let sectionCount = 8
        let bodyHeight = sectionHeight * sectionCount
        let viewportHeight = 224
        let headerHeight = 36
        let body = try makeRepeatedCardBody(
            width: width,
            sectionHeight: sectionHeight,
            sectionCount: sectionCount
        )
        let offsets = [0, 200, 400, 600, bodyHeight - viewportHeight]
        var frameURLs: [URL] = []
        for (index, offset) in offsets.enumerated() {
            guard let bodySlice = body.cropping(to: CGRect(
                x: 0,
                y: offset,
                width: width,
                height: viewportHeight
            )) else {
                throw ScrollingCheckError.failed("无法生成重复卡片正文片段")
            }
            let frame = try makeFrame(
                body: bodySlice,
                headerHeight: headerHeight,
                animationOffset: index * 11
            )
            let url = directory.appendingPathComponent("repeated-card-segment-\(index).png")
            try writePNG(frame, to: url)
            frameURLs.append(url)
        }

        let outputURL = directory.appendingPathComponent("repeated-card-stitched.png")
        let result = try VerticalImageStitcher.stitch(
            imageURLs: frameURLs,
            outputURL: outputURL,
            maximumDifference: 4
        )
        let removedHeights = zip(result.topInsets, result.overlaps).map { $0.0 + $0.1 }
        let expectedRemovedHeights = [60, 60, 60, 124]
        guard result.width == width,
              abs(result.height - (bodyHeight + headerHeight)) <= 4,
              result.topInsets.allSatisfy({
                  (headerHeight...(headerHeight + 2)).contains($0)
              }),
              zip(removedHeights, expectedRemovedHeights).allSatisfy({
                  abs($0.0 - $0.1) <= 1
              }) else {
            throw ScrollingCheckError.failed(
                "重复卡片被错误裁成重叠区域：\(result.width)×\(result.height)，顶部 \(result.topInsets)，重叠 \(result.overlaps)"
            )
        }
    }

    private static func verifyStickyHeaderAndFooterStitching(in directory: URL) throws {
        let width = 240
        let bodyHeight = 544
        let viewportHeight = 224
        let headerHeight = 36
        let footerHeight = 52
        let body = try makeLongImage(width: width, height: bodyHeight)
        let bodySlices = [
            CGRect(x: 0, y: 0, width: width, height: viewportHeight),
            CGRect(x: 0, y: 160, width: width, height: viewportHeight),
            CGRect(x: 0, y: 320, width: width, height: viewportHeight)
        ]
        var frameURLs: [URL] = []
        for (index, rect) in bodySlices.enumerated() {
            guard let bodySlice = body.cropping(to: rect) else {
                throw ScrollingCheckError.failed("无法生成固定底栏正文片段")
            }
            let frame = try makeFrame(
                body: bodySlice,
                headerHeight: headerHeight,
                footerHeight: footerHeight,
                animationOffset: index * 7
            )
            let url = directory.appendingPathComponent("sticky-bars-segment-\(index).png")
            try writePNG(frame, to: url)
            frameURLs.append(url)
        }

        let transition = try VerticalImageStitcher.analyzeTransition(
            previousURL: frameURLs[0],
            nextURL: frameURLs[1],
            maximumDifference: 4
        )
        guard transition.topInset == headerHeight,
              transition.bottomInset == footerHeight,
              transition.overlap == 64 else {
            throw ScrollingCheckError.failed(
                "固定上下栏过渡识别错误：顶部 \(transition.topInset)，底部 \(transition.bottomInset)，重叠 \(String(describing: transition.overlap))"
            )
        }

        let outputURL = directory.appendingPathComponent("sticky-bars-stitched.png")
        let result = try VerticalImageStitcher.stitch(
            imageURLs: frameURLs,
            outputURL: outputURL,
            maximumDifference: 4
        )
        guard result.width == width,
              result.height == bodyHeight + headerHeight + footerHeight,
              result.overlaps == [64, 64],
              result.topInsets == [headerHeight, headerHeight],
              result.bottomInsets == [footerHeight, footerHeight] else {
            throw ScrollingCheckError.failed(
                "固定上下栏拼接错误：\(result.width)×\(result.height)，顶部 \(result.topInsets)，底部 \(result.bottomInsets)，重叠 \(result.overlaps)"
            )
        }

        let previewComposer = ScrollingCapturePreviewComposer(previewWidth: 120)
        _ = try previewComposer.append(segmentURL: frameURLs[0], transition: nil)
        _ = try previewComposer.append(segmentURL: frameURLs[1], transition: transition)
        let finalTransition = try VerticalImageStitcher.analyzeTransition(
            previousURL: frameURLs[1],
            nextURL: frameURLs[2],
            maximumDifference: 4
        )
        let preview = try previewComposer.append(
            segmentURL: frameURLs[2],
            transition: finalTransition
        )
        guard preview.width == 120, preview.height == 316 else {
            throw ScrollingCheckError.failed("固定底栏实时预览仍重复保留底栏")
        }
    }

    private static func makeRepeatedCardBody(
        width: Int,
        sectionHeight: Int,
        sectionCount: Int
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: sectionHeight * sectionCount,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingCheckError.failed("无法创建重复卡片测试图")
        }
        let colors: [(Int, Int, Int)] = [
            (220, 110, 40),
            (40, 145, 220),
            (180, 108, 180),
            (20, 172, 20),
            (240, 108, 0),
            (0, 155, 240),
            (200, 110, 100),
            (100, 130, 200)
        ]
        for section in 0..<sectionCount {
            let originY = section * sectionHeight
            context.setFillColor(CGColor(gray: 0.96, alpha: 1))
            context.fill(CGRect(x: 0, y: originY, width: width, height: sectionHeight))
            let color = colors[section % colors.count]
            context.setFillColor(CGColor(
                red: CGFloat(color.0) / 255,
                green: CGFloat(color.1) / 255,
                blue: CGFloat(color.2) / 255,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: originY + 18, width: width, height: 36))
            context.setFillColor(CGColor(gray: 0.28, alpha: 1))
            context.fill(CGRect(x: 16, y: originY + 76, width: width - 32, height: 8))
            context.fill(CGRect(x: 16, y: originY + 94, width: width * 2 / 3, height: 8))
        }
        guard let image = context.makeImage() else {
            throw ScrollingCheckError.failed("无法生成重复卡片测试图")
        }
        return image
    }

    private static func makeFrame(
        body: CGImage,
        headerHeight: Int,
        footerHeight: Int = 0,
        animationOffset: Int
    ) throws -> CGImage {
        let width = body.width
        let height = body.height + headerHeight + footerHeight
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingCheckError.failed("无法创建固定标题栏测试片段")
        }
        context.draw(body, in: CGRect(
            x: 0,
            y: footerHeight,
            width: width,
            height: body.height
        ))
        context.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1))
        context.fill(CGRect(
            x: 0,
            y: body.height + footerHeight,
            width: width,
            height: headerHeight
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.75, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 18, y: body.height + footerHeight + 10, width: 92, height: 14))
        context.setFillColor(CGColor(red: 1, green: 0.48, blue: 0.12, alpha: 1))
        context.fill(CGRect(
            x: 142 + animationOffset,
            y: body.height + footerHeight + 11,
            width: 10,
            height: 12
        ))
        if footerHeight > 0 {
            context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: footerHeight))
            context.setFillColor(CGColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1))
            context.fill(CGRect(x: 16, y: 12, width: width - 60, height: 8))
            context.setFillColor(CGColor(red: 0.18, green: 0.58, blue: 0.98, alpha: 1))
            context.fillEllipse(in: CGRect(
                x: width - 34,
                y: 10,
                width: 22,
                height: 22
            ))
        }
        guard let image = context.makeImage() else {
            throw ScrollingCheckError.failed("无法生成固定标题栏测试片段")
        }
        return image
    }

    private static func makeUnrelatedImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingCheckError.failed("无法创建无关画面测试图")
        }
        for y in 0..<height {
            for x in stride(from: 0, to: width, by: 12) {
                let isDark = ((x / 12) + (y / 10)) % 2 == 0
                context.setFillColor(CGColor(
                    red: isDark ? 0.02 : 0.95,
                    green: isDark ? 0.04 : 0.15,
                    blue: isDark ? 0.08 : 0.7,
                    alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: 12, height: 1))
            }
        }
        guard let image = context.makeImage() else {
            throw ScrollingCheckError.failed("无法生成无关画面测试图")
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScrollingCheckError.failed("无法创建测试图片文件")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScrollingCheckError.failed("无法写入测试图片")
        }
    }
}
