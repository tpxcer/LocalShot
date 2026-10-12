import AVFoundation
import CoreMedia
import LocalShotCore
import ScreenCaptureKit

enum ScreenRecordingServiceError: LocalizedError {
    case displayUnavailable
    case windowUnavailable
    case alreadyRecording
    case recordingOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "无法找到要录制的显示器。"
        case .windowUnavailable:
            "锁定的窗口已关闭或不可录制。"
        case .alreadyRecording:
            "已经有一项屏幕录制正在进行。"
        case .recordingOutputUnavailable:
            "无法创建屏幕录制输出。"
        }
    }
}

@available(macOS 15.0, *)
final class ScreenRecordingService: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    var onFailure: (@Sendable (Error) -> Void)?
    private(set) var outputSize: CGSize = .zero

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let delegateLock = NSLock()
    private var startResult: Result<Void, Error>?
    private var finishResult: Result<Void, Error>?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    static func windowFrame(
        windowID: CGWindowID,
        processID: pid_t
    ) async throws -> CGRect? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        return content.windows.first(where: {
            $0.windowID == windowID
                && $0.owningApplication?.processID == processID
        })?.frame
    }

    func start(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect,
        scaleFactor: CGFloat,
        outputURL: URL,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool,
        targetWindowID: CGWindowID? = nil,
        fixedOutputSize: CGSize? = nil,
        quality: ScreenRecordingQuality = .original,
        frameRate: ScreenRecordingFrameRate = .fps60
    ) async throws {
        guard stream == nil else {
            throw ScreenRecordingServiceError.alreadyRecording
        }
        resetDelegateState()
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: targetWindowID == nil
        )
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter
        if let targetWindowID {
            guard let window = content.windows.first(where: { $0.windowID == targetWindowID }) else {
                throw ScreenRecordingServiceError.windowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let windowScale = CGFloat(filter.pointPixelScale)
            configuration.width = Self.evenPixelCount(filter.contentRect.width * windowScale)
            configuration.height = Self.evenPixelCount(filter.contentRect.height * windowScale)
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
        } else {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenRecordingServiceError.displayUnavailable
            }
            let bundleIdentifier = Bundle.main.bundleIdentifier
            let excludedWindows = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                    || $0.owningApplication?.bundleIdentifier == bundleIdentifier
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            configuration.sourceRect = sourceRect
            configuration.width = Self.evenPixelCount(sourceRect.width * scaleFactor)
            configuration.height = Self.evenPixelCount(sourceRect.height * scaleFactor)
        }
        let requestedOutputSize: CGSize
        if let fixedOutputSize {
            requestedOutputSize = fixedOutputSize
        } else {
            requestedOutputSize = quality.outputSize(for: CGSize(
                width: configuration.width,
                height: configuration.height
            ))
        }
        configuration.width = Self.evenPixelCount(requestedOutputSize.width)
        configuration.height = Self.evenPixelCount(requestedOutputSize.height)
        outputSize = CGSize(width: configuration.width, height: configuration.height)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(frameRate.rawValue)
        )
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.captureResolution = .best
        configuration.capturesAudio = capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = capturesMicrophone

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4
        let recordingOutput = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: self
        )
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addRecordingOutput(recordingOutput)
        self.stream = stream
        self.recordingOutput = recordingOutput

        do {
            try await stream.startCapture()
            try await waitForRecordingToStart()
        } catch {
            try? await stream.stopCapture()
            self.stream = nil
            self.recordingOutput = nil
            throw error
        }
    }

    func stop() async throws {
        guard let stream, let recordingOutput else {
            return
        }
        do {
            try stream.removeRecordingOutput(recordingOutput)
            try await waitForRecordingToFinish()
            try await stream.stopCapture()
            self.stream = nil
            self.recordingOutput = nil
        } catch {
            try? await stream.stopCapture()
            self.stream = nil
            self.recordingOutput = nil
            throw error
        }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        resolveStart(.success(()))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resolveFinish(.success(()))
    }

    func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        resolveStart(.failure(error))
        resolveFinish(.failure(error))
        onFailure?(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        resolveStart(.failure(error))
        resolveFinish(.failure(error))
        onFailure?(error)
    }

    private func resetDelegateState() {
        delegateLock.lock()
        startResult = nil
        finishResult = nil
        startContinuation = nil
        finishContinuation = nil
        delegateLock.unlock()
    }

    private func waitForRecordingToStart() async throws {
        try await withCheckedThrowingContinuation { continuation in
            delegateLock.lock()
            if let result = startResult {
                delegateLock.unlock()
                continuation.resume(with: result)
            } else {
                startContinuation = continuation
                delegateLock.unlock()
            }
        }
    }

    private func waitForRecordingToFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            delegateLock.lock()
            if let result = finishResult {
                delegateLock.unlock()
                continuation.resume(with: result)
            } else {
                finishContinuation = continuation
                delegateLock.unlock()
            }
        }
    }

    private func resolveStart(_ result: Result<Void, Error>) {
        delegateLock.lock()
        guard startResult == nil else {
            delegateLock.unlock()
            return
        }
        startResult = result
        let continuation = startContinuation
        startContinuation = nil
        delegateLock.unlock()
        continuation?.resume(with: result)
    }

    private func resolveFinish(_ result: Result<Void, Error>) {
        delegateLock.lock()
        guard finishResult == nil else {
            delegateLock.unlock()
            return
        }
        finishResult = result
        let continuation = finishContinuation
        finishContinuation = nil
        delegateLock.unlock()
        continuation?.resume(with: result)
    }

    private static func evenPixelCount(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }
}
