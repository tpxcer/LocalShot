import AppKit
import LocalShotCore
import SwiftUI

@MainActor
final class PinnedScreenshotController {
    var onWindowsChanged: ((Bool) -> Void)?

    private var windowControllers: [UUID: PinnedScreenshotWindowController] = [:]

    func open(asset: CaptureAsset, onError: @escaping (String) -> Void) {
        guard let image = NSImage(contentsOf: asset.url),
              image.size.width > 0,
              image.size.height > 0 else {
            onError("置顶截图失败：无法读取图片。")
            return
        }

        let id = UUID()
        let controller = PinnedScreenshotWindowController(
            image: image,
            filename: asset.url.lastPathComponent,
            initialSize: initialWindowSize(for: image.size)
        ) { [weak self] in
            self?.windowControllers[id] = nil
            self?.notifyChange()
        }
        windowControllers[id] = controller
        controller.show()
        notifyChange()
    }

    func restoreInteraction() {
        for controller in windowControllers.values {
            controller.restoreInteraction()
        }
    }

    func closeAll() {
        let controllers = Array(windowControllers.values)
        windowControllers.removeAll()
        for controller in controllers {
            controller.close()
        }
        notifyChange()
    }

    private func initialWindowSize(for imageSize: CGSize) -> NSSize {
        let toolbarHeight = 44.0
        let scale = min(
            1,
            720 / imageSize.width,
            (520 - toolbarHeight) / imageSize.height
        )
        return NSSize(
            width: max(260, imageSize.width * scale),
            height: max(180, imageSize.height * scale + toolbarHeight)
        )
    }

    private func notifyChange() {
        onWindowsChanged?(!windowControllers.isEmpty)
    }
}

@MainActor
private final class PinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    private let model: PinnedScreenshotModel
    private let onClose: () -> Void

    init(
        image: NSImage,
        filename: String,
        initialSize: NSSize,
        onClose: @escaping () -> Void
    ) {
        model = PinnedScreenshotModel(
            image: image,
            filename: filename,
            initialContentSize: initialSize
        )
        self.onClose = onClose

        let hostingController = NSHostingController(rootView: PinnedScreenshotView(model: model))
        hostingController.preferredContentSize = initialSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = filename
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 320, height: 150)
        window.setContentSize(initialSize)
        window.center()

        super.init(window: window)
        window.delegate = self
        model.attach(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func restoreInteraction() {
        model.isClickThrough = false
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class PinnedScreenshotModel: ObservableObject {
    private static let minimumScale = 0.5
    private static let maximumScale = 1.5

    @Published var opacity = 1.0 {
        didSet {
            window?.alphaValue = min(max(opacity, 0.3), 1)
        }
    }
    @Published var isClickThrough = false {
        didSet {
            window?.ignoresMouseEvents = isClickThrough
        }
    }
    @Published private(set) var scale = 1.0

    let image: NSImage
    let filename: String
    private let initialContentSize: NSSize
    private weak var window: NSWindow?

    init(image: NSImage, filename: String, initialContentSize: NSSize) {
        self.image = image
        self.filename = filename
        self.initialContentSize = initialContentSize
    }

    var canScaleDown: Bool {
        scale > Self.minimumScale
    }

    var canScaleUp: Bool {
        scale < Self.maximumScale
    }

    func attach(window: NSWindow) {
        self.window = window
        window.alphaValue = opacity
        window.ignoresMouseEvents = isClickThrough
    }

    func close() {
        window?.performClose(nil)
    }

    func scaleDown() {
        setScale(scale - 0.1)
    }

    func scaleUp() {
        setScale(scale + 0.1)
    }

    private func setScale(_ value: Double) {
        let steppedValue = (value * 10).rounded() / 10
        let nextScale = min(max(steppedValue, Self.minimumScale), Self.maximumScale)
        guard nextScale != scale else {
            return
        }

        scale = nextScale
        let contentSize = NSSize(
            width: initialContentSize.width * nextScale,
            height: initialContentSize.height * nextScale
        )
        window?.contentViewController?.preferredContentSize = contentSize
        window?.setContentSize(contentSize)
    }
}

private struct PinnedScreenshotView: View {
    @ObservedObject var model: PinnedScreenshotModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                Text(model.filename)
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    model.scaleDown()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canScaleDown)
                .help("缩小置顶截图")
                .accessibilityLabel("缩小置顶截图")

                Text("\(Int((model.scale * 100).rounded()))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34)

                Button {
                    model.scaleUp()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canScaleUp)
                .help("放大置顶截图")
                .accessibilityLabel("放大置顶截图")

                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $model.opacity, in: 0.3...1, step: 0.05)
                    .frame(width: 82)
                    .help("透明度")
                    .accessibilityLabel("置顶截图透明度")
                    .accessibilityValue("\(Int(model.opacity * 100))%")

                Button {
                    model.isClickThrough = true
                } label: {
                    Image(systemName: "cursorarrow.slash")
                }
                .buttonStyle(.borderless)
                .disabled(model.isClickThrough)
                .help(
                    model.isClickThrough
                        ? "点击穿透已开启；可从 LocalShot 设置或菜单栏恢复"
                        : "开启点击穿透；可从 LocalShot 设置或菜单栏恢复"
                )
                .accessibilityLabel(model.isClickThrough ? "点击穿透已开启" : "开启点击穿透")

                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭置顶截图")
                .accessibilityLabel("关闭置顶截图")
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(.regularMaterial)

            Divider()

            Image(nsImage: model.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
