import AppKit
import SwiftUI

@MainActor
final class ScrollingCaptureProgressController {
    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    func show(
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> ScrollingCaptureProgressModel {
        dismiss()
        let model = ScrollingCaptureProgressModel(
            onFinish: onFinish,
            onCancel: onCancel
        )
        let hostingController = NSHostingController(
            rootView: ScrollingCaptureProgressView(model: model)
        )
        let size = NSSize(width: 300, height: 560)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - size.width - 24,
                y: screen.visibleFrame.midY - size.height / 2
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                onCancel()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    onCancel()
                }
            }
        }
        return model
    }

    func dismiss() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        panel?.close()
        panel = nil
    }
}

@MainActor
final class ScrollingCaptureProgressModel: ObservableObject {
    @Published var pageCount = 1
    @Published var status = "请用鼠标或触控板慢慢向下滚动"
    @Published var previewImage: NSImage?
    let onFinish: () -> Void
    let onCancel: () -> Void

    init(
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }
}

private struct ScrollingCaptureProgressView: View {
    @ObservedObject var model: ScrollingCaptureProgressModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("区域长截图 · 已采集 \(model.pageCount) 段")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            preview

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("完成", systemImage: "checkmark") {
                    model.onFinish()
                }
                .buttonStyle(.borderedProminent)

                Button("取消", systemImage: "xmark") {
                    model.onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 300, height: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var preview: some View {
        ZStack {
            if let previewImage = model.previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 26))
                    Text("正在准备实时拼接预览…")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
