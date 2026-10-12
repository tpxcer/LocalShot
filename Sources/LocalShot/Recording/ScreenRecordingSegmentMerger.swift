import AVFoundation
import Foundation

enum ScreenRecordingSegmentMergerError: LocalizedError {
    case videoTrackUnavailable
    case compositionTrackUnavailable
    case exportSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .videoTrackUnavailable:
            "录制分段缺少有效视频轨。"
        case .compositionTrackUnavailable:
            "无法创建录制分段合并轨道。"
        case .exportSessionUnavailable:
            "无法创建录制分段合并任务。"
        }
    }
}

@available(macOS 15.0, *)
enum ScreenRecordingSegmentMerger {
    static func merge(segmentURLs: [URL], outputURL: URL) async throws {
        guard segmentURLs.count > 1 else { return }

        let composition = AVMutableComposition()
        guard let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenRecordingSegmentMergerError.compositionTrackUnavailable
        }
        var audioCompositionTrack: AVMutableCompositionTrack?
        var insertionTime = CMTime.zero
        var preferredTransform: CGAffineTransform?

        for url in segmentURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isValid,
                  duration > .zero,
                  let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ScreenRecordingSegmentMergerError.videoTrackUnavailable
            }
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try videoCompositionTrack.insertTimeRange(
                timeRange,
                of: videoTrack,
                at: insertionTime
            )
            if preferredTransform == nil {
                preferredTransform = try await videoTrack.load(.preferredTransform)
            }

            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                if audioCompositionTrack == nil {
                    audioCompositionTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }
                try audioCompositionTrack?.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertionTime
                )
            }
            insertionTime = CMTimeAdd(insertionTime, duration)
        }
        if let preferredTransform {
            videoCompositionTrack.preferredTransform = preferredTransform
        }

        let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".\(outputURL.deletingPathExtension().lastPathComponent)-merged-\(UUID().uuidString).mp4"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ScreenRecordingSegmentMergerError.exportSessionUnavailable
        }
        try await exportSession.export(to: temporaryURL, as: .mp4)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: temporaryURL
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        }

        for url in segmentURLs where url != outputURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
