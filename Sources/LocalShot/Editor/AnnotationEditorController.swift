import AppKit
import CryptoKit
import LocalShotCore
import SwiftUI

@MainActor
final class AnnotationEditorController {
    private let windowCoordinator = SingleWindowCoordinator()

    func open(asset: CaptureAsset, onError: @escaping (String) -> Void) {
        open(
            imageURL: asset.url,
            projectURL: nil,
            title: asset.url.lastPathComponent,
            onError: onError
        )
    }

    func openImportedImage(
        imageURL: URL,
        onError: @escaping (String) -> Void
    ) {
        do {
            let projectURL = try importedProjectURL(for: imageURL)
            open(
                imageURL: imageURL,
                projectURL: projectURL,
                title: imageURL.lastPathComponent,
                onError: onError
            )
        } catch {
            onError("准备外部图片项目失败：\(error.localizedDescription)")
        }
    }

    private func open(
        imageURL: URL,
        projectURL: URL?,
        title: String,
        onError: @escaping (String) -> Void
    ) {
        do {
            let model = try AnnotationEditorModel(
                imageURL: imageURL,
                projectURL: projectURL
            )
            let rootView = AnnotationEditorView(model: model)
            let initialSize = NSSize(width: 1040, height: 720)
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.preferredContentSize = initialSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "标注 — \(title)"
            window.contentViewController = hostingController
            window.contentMinSize = NSSize(width: 760, height: 520)
            window.setContentSize(initialSize)
            window.center()
            window.isReleasedWhenClosed = false

            windowCoordinator.show(window)
        } catch {
            onError("打开标注编辑器失败：\(error.localizedDescription)")
        }
    }

    private func importedProjectURL(for imageURL: URL) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("LocalShot", isDirectory: true)
            .appendingPathComponent("ImportedProjects", isDirectory: true)
        let digest = SHA256.hash(data: Data(imageURL.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory
            .appendingPathComponent(digest)
            .appendingPathExtension("localshot.json")
    }
}
