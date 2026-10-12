import Foundation
import LocalShotCore

@MainActor
final class AppSettings: ObservableObject {
    @Published var outputFormat: CaptureOutputFormat {
        didSet { defaults.set(outputFormat.rawValue, forKey: Keys.outputFormat) }
    }
    @Published var jpegQuality: Double {
        didSet { defaults.set(min(max(jpegQuality, 0.1), 1), forKey: Keys.jpegQuality) }
    }
    @Published var includesCursor: Bool {
        didSet { defaults.set(includesCursor, forKey: Keys.includesCursor) }
    }
    @Published var includesWindowShadow: Bool {
        didSet { defaults.set(includesWindowShadow, forKey: Keys.includesWindowShadow) }
    }
    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }
    @Published var quickAccessDuration: Double {
        didSet { defaults.set(quickAccessDuration, forKey: Keys.quickAccessDuration) }
    }
    @Published var filenamePrefix: String {
        didSet { defaults.set(filenamePrefix, forKey: Keys.filenamePrefix) }
    }
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: Keys.automaticallyChecksForUpdates) }
    }
    @Published var screenRecordingQuality: ScreenRecordingQuality {
        didSet { defaults.set(screenRecordingQuality.rawValue, forKey: Keys.screenRecordingQuality) }
    }
    @Published var screenRecordingFrameRate: ScreenRecordingFrameRate {
        didSet { defaults.set(screenRecordingFrameRate.rawValue, forKey: Keys.screenRecordingFrameRate) }
    }
    @Published private(set) var captureDirectoryPath: String? {
        didSet { defaults.set(captureDirectoryPath, forKey: Keys.captureDirectoryPath) }
    }
    @Published private(set) var hotKeyConfiguration: HotKeyConfiguration
    private(set) var hiddenCaptureHistoryPaths: Set<String>

    private let defaults: UserDefaults
    private var securityScopedCaptureDirectoryURL: URL?
    private var isAccessingSecurityScopedCaptureDirectory = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputFormat = CaptureOutputFormat(
            rawValue: defaults.string(forKey: Keys.outputFormat) ?? ""
        ) ?? .png
        jpegQuality = defaults.object(forKey: Keys.jpegQuality) == nil
            ? 0.9
            : defaults.double(forKey: Keys.jpegQuality)
        includesCursor = defaults.bool(forKey: Keys.includesCursor)
        includesWindowShadow = defaults.object(forKey: Keys.includesWindowShadow) == nil
            ? true
            : defaults.bool(forKey: Keys.includesWindowShadow)
        retentionDays = defaults.object(forKey: Keys.retentionDays) == nil
            ? 7
            : defaults.integer(forKey: Keys.retentionDays)
        quickAccessDuration = defaults.object(forKey: Keys.quickAccessDuration) == nil
            ? 15
            : defaults.double(forKey: Keys.quickAccessDuration)
        filenamePrefix = defaults.string(forKey: Keys.filenamePrefix) ?? "LocalShot"
        automaticallyChecksForUpdates = defaults.object(forKey: Keys.automaticallyChecksForUpdates) == nil
            ? true
            : defaults.bool(forKey: Keys.automaticallyChecksForUpdates)
        screenRecordingQuality = ScreenRecordingQuality(
            rawValue: defaults.string(forKey: Keys.screenRecordingQuality) ?? ""
        ) ?? .original
        screenRecordingFrameRate = ScreenRecordingFrameRate(
            rawValue: defaults.integer(forKey: Keys.screenRecordingFrameRate)
        ) ?? .fps60
        hiddenCaptureHistoryPaths = Set(
            defaults.stringArray(forKey: Keys.hiddenCaptureHistoryPaths) ?? []
        )
        captureDirectoryPath = nil
        if let bookmarkData = defaults.data(forKey: Keys.captureDirectoryBookmark),
           let resolved = Self.resolveCaptureDirectoryBookmark(bookmarkData) {
            captureDirectoryPath = resolved.url.path
            securityScopedCaptureDirectoryURL = resolved.url
            isAccessingSecurityScopedCaptureDirectory = resolved.url.startAccessingSecurityScopedResource()
            if resolved.isStale,
               let refreshedBookmark = try? Self.captureDirectoryBookmark(for: resolved.url) {
                defaults.set(refreshedBookmark, forKey: Keys.captureDirectoryBookmark)
            }
        } else {
            captureDirectoryPath = defaults.string(forKey: Keys.captureDirectoryPath)
        }
        if let data = defaults.data(forKey: Keys.hotKeyConfiguration),
           let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) {
            let textRecognitionConfiguration = HotKeyConfiguration.addingDefaultTextRecognitionIfNeeded(
                configuration,
                didMigrate: defaults.bool(forKey: Keys.didMigrateTextRecognitionHotKey)
            )
            let areaMigratedConfiguration = HotKeyConfiguration.migratingLegacyDefaultIfNeeded(
                textRecognitionConfiguration,
                didMigrate: defaults.bool(forKey: Keys.didMigrateQQStyleAreaHotKey)
            )
            let migratedConfiguration = HotKeyConfiguration.migratingLegacyTextRecognitionShortcutIfNeeded(
                areaMigratedConfiguration,
                didMigrate: defaults.bool(forKey: Keys.didMigrateShiftedTextRecognitionHotKey)
            )
            hotKeyConfiguration = migratedConfiguration
            if migratedConfiguration != configuration,
               let migrated = try? JSONEncoder().encode(migratedConfiguration) {
                defaults.set(migrated, forKey: Keys.hotKeyConfiguration)
            }
        } else {
            hotKeyConfiguration = .default
        }
        defaults.set(true, forKey: Keys.didMigrateQQStyleAreaHotKey)
        defaults.set(true, forKey: Keys.didMigrateTextRecognitionHotKey)
        defaults.set(true, forKey: Keys.didMigrateShiftedTextRecognitionHotKey)
    }

    var captureDirectoryURL: URL? {
        securityScopedCaptureDirectoryURL
            ?? captureDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func setCaptureDirectory(_ url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        let bookmarkData = try Self.captureDirectoryBookmark(for: standardizedURL)
        stopAccessingSecurityScopedCaptureDirectory()
        securityScopedCaptureDirectoryURL = standardizedURL
        isAccessingSecurityScopedCaptureDirectory = standardizedURL.startAccessingSecurityScopedResource()
        captureDirectoryPath = standardizedURL.path
        defaults.set(bookmarkData, forKey: Keys.captureDirectoryBookmark)
    }

    func resetCaptureDirectory() {
        stopAccessingSecurityScopedCaptureDirectory()
        captureDirectoryPath = nil
        defaults.removeObject(forKey: Keys.captureDirectoryPath)
        defaults.removeObject(forKey: Keys.captureDirectoryBookmark)
    }

    func setHotKeyConfiguration(_ configuration: HotKeyConfiguration) {
        hotKeyConfiguration = configuration
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Keys.hotKeyConfiguration)
        }
    }

    func resetHotKeyConfiguration() {
        setHotKeyConfiguration(.default)
    }

    func isHiddenFromRecentSaves(_ url: URL) -> Bool {
        hiddenCaptureHistoryPaths.contains(url.standardizedFileURL.path)
    }

    func hideRecentSaveRecords(_ urls: [URL]) {
        hiddenCaptureHistoryPaths.formUnion(
            urls.map { $0.standardizedFileURL.path }
        )
        persistHiddenCaptureHistoryPaths()
    }

    func removeHiddenRecentSaveRecords(in directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL
        hiddenCaptureHistoryPaths = hiddenCaptureHistoryPaths.filter { path in
            URL(fileURLWithPath: path)
                .deletingLastPathComponent()
                .standardizedFileURL != standardizedDirectory
        }
        persistHiddenCaptureHistoryPaths()
    }

    private func persistHiddenCaptureHistoryPaths() {
        defaults.set(hiddenCaptureHistoryPaths.sorted(), forKey: Keys.hiddenCaptureHistoryPaths)
    }

    private func stopAccessingSecurityScopedCaptureDirectory() {
        if isAccessingSecurityScopedCaptureDirectory {
            securityScopedCaptureDirectoryURL?.stopAccessingSecurityScopedResource()
        }
        securityScopedCaptureDirectoryURL = nil
        isAccessingSecurityScopedCaptureDirectory = false
    }

    private static func captureDirectoryBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveCaptureDirectoryBookmark(
        _ data: Data
    ) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (url, isStale)
    }

    private enum Keys {
        static let outputFormat = "capture.outputFormat"
        static let jpegQuality = "capture.jpegQuality"
        static let includesCursor = "capture.includesCursor"
        static let includesWindowShadow = "capture.includesWindowShadow"
        static let retentionDays = "history.retentionDays"
        static let quickAccessDuration = "quickAccess.duration"
        static let filenamePrefix = "capture.filenamePrefix"
        static let automaticallyChecksForUpdates = "updates.automaticallyChecks"
        static let screenRecordingQuality = "recording.quality"
        static let screenRecordingFrameRate = "recording.frameRate"
        static let captureDirectoryPath = "capture.directoryPath"
        static let captureDirectoryBookmark = "capture.directoryBookmark"
        static let hotKeyConfiguration = "hotkeys.configuration"
        static let hiddenCaptureHistoryPaths = "history.hiddenCapturePaths"
        static let didMigrateQQStyleAreaHotKey = "hotkeys.didMigrateQQStyleAreaHotKey"
        static let didMigrateTextRecognitionHotKey = "hotkeys.didMigrateTextRecognitionHotKey"
        static let didMigrateShiftedTextRecognitionHotKey = "hotkeys.didMigrateShiftedTextRecognitionHotKey"
    }
}
