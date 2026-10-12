#if !APP_STORE
import AppKit
import Foundation
import LocalShotUpdater
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(LocalShotVersion)
        case available(LocalShotUpdateRelease)
        case downloading(LocalShotUpdateRelease)
        case downloaded(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var availableRelease: LocalShotUpdateRelease?

    var onUpdateAvailable: ((LocalShotUpdateRelease) -> Void)?

    private let service: LocalShotUpdateService
    private let defaults: UserDefaults
    private let bundle: Bundle
    private let now: () -> Date
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        service: LocalShotUpdateService = LocalShotUpdateService(),
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.defaults = defaults
        self.bundle = bundle
        self.now = now
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading:
            true
        default:
            false
        }
    }

    var statusMessage: String {
        switch state {
        case .idle:
            "尚未检查更新。"
        case .checking:
            "正在检查 GitHub 上的新版本…"
        case let .upToDate(version):
            "当前已是最新版本 \(version.displayName)。"
        case let .available(release):
            "发现新版本 \(release.version.displayName)。"
        case let .downloading(release):
            "正在下载并校验 \(release.asset.name)…"
        case let .downloaded(url):
            "已下载并打开 \(url.lastPathComponent)，请把新版拖入“应用程序”覆盖旧版。"
        case let .failed(message):
            message
        }
    }

    var statusIsError: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    var canDownloadAvailableRelease: Bool {
        guard availableRelease != nil else {
            return false
        }
        if case .downloaded = state {
            return false
        }
        return true
    }

    func checkAutomaticallyIfNeeded(isEnabled: Bool) {
        guard isEnabled, !isBusy else {
            return
        }
        let currentDate = now()
        if let lastCheck = defaults.object(forKey: Keys.lastAutomaticCheck) as? Date,
           currentDate.timeIntervalSince(lastCheck) < automaticCheckInterval {
            return
        }
        defaults.set(currentDate, forKey: Keys.lastAutomaticCheck)
        performCheck(notifiesWhenAvailable: true)
    }

    func checkManually() {
        defaults.set(now(), forKey: Keys.lastAutomaticCheck)
        performCheck(notifiesWhenAvailable: false)
    }

    func downloadAvailableRelease() {
        guard let availableRelease else {
            return
        }
        downloadAndOpen(availableRelease)
    }

    func downloadAndOpen(_ release: LocalShotUpdateRelease) {
        guard !isBusy else {
            return
        }
        state = .downloading(release)
        Task {
            do {
                let downloadsDirectory = try FileManager.default.url(
                    for: .downloadsDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let downloadedURL = try await service.download(release, to: downloadsDirectory)
                guard NSWorkspace.shared.open(downloadedURL) else {
                    state = .failed("安装包已下载，但 macOS 无法自动打开。请到“下载”文件夹手动打开。")
                    return
                }
                state = .downloaded(downloadedURL)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func performCheck(notifiesWhenAvailable: Bool) {
        guard !isBusy else {
            return
        }
        guard let currentVersion else {
            state = .failed("无法读取当前 LocalShot 版本。")
            return
        }
        state = .checking
        Task {
            do {
                let release = try await service.latestRelease()
                guard release.version > currentVersion else {
                    availableRelease = nil
                    state = .upToDate(currentVersion)
                    return
                }
                availableRelease = release
                state = .available(release)
                if notifiesWhenAvailable {
                    onUpdateAvailable?(release)
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private var currentVersion: LocalShotVersion? {
        guard let info = bundle.infoDictionary,
              let marketingVersion = info["CFBundleShortVersionString"] as? String,
              let buildString = info["CFBundleVersion"] as? String,
              let build = Int(buildString) else {
            return nil
        }
        return LocalShotVersion(marketingVersion: marketingVersion, build: build)
    }

    private enum Keys {
        static let lastAutomaticCheck = "updates.lastAutomaticCheck"
    }
}
#endif
