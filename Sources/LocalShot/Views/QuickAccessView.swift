import AppKit
import LocalShotCore
import SwiftUI

struct QuickAccessView: View {
    let asset: CaptureAsset
    let actions: QuickAccessActions

    private var previewImage: NSImage {
        NSImage(contentsOf: asset.url) ?? NSImage()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }
                .onDrag {
                    NSItemProvider(contentsOf: asset.url) ?? NSItemProvider()
                }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.mode.displayName)
                        .font(.headline)
                    Text(asset.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    actionButton("doc.on.doc", label: "复制", action: actions.copy)
                    actionButton("pencil.and.outline", label: "标注", action: actions.annotate)
                    actionButton("sparkles", label: "图片美化", action: actions.beautify)
                    actionButton("pin", label: "置顶截图", action: actions.pin)
                    actionButton("text.viewfinder", label: "识别文字", action: actions.recognizeText)
                    actionButton("character.bubble", label: "原位置翻译", action: actions.translate)
                    actionButton("square.and.arrow.down", label: "另存为", action: actions.saveAs)
                    actionButton("folder", label: "在 Finder 中显示", action: actions.reveal)
                    actionButton("trash", label: "删除", role: .destructive, action: actions.delete)
                    Spacer(minLength: 0)
                    actionButton("xmark", label: "关闭", action: actions.dismiss)
                }
            }
        }
        .padding(12)
        .frame(width: 456, height: 112)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func actionButton(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}
