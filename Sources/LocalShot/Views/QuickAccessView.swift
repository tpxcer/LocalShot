import AppKit
import LocalShotCore
import SwiftUI

struct QuickAccessView: View {
    let asset: CaptureAsset
    let actions: QuickAccessActions

    private var previewImage: NSImage {
        CaptureThumbnail.image(for: asset.url, maxPixelSize: 360)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LocalShotTheme.card, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .onDrag {
                    NSItemProvider(contentsOf: asset.url) ?? NSItemProvider()
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(asset.mode.displayName)
                        .font(.headline)
                    LocalShotTag(text: asset.createdAt.formatted(date: .omitted, time: .standard))
                    Spacer(minLength: 0)
                    iconButton("xmark", label: "关闭", action: actions.dismiss)
                }

                HStack(spacing: 6) {
                    Button(action: actions.copy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(LocalShotIconButtonStyle(isSelected: true, horizontalPadding: 9))
                    .help("复制")

                    Button(action: actions.annotate) {
                        Label("标注", systemImage: "pencil.and.outline")
                    }
                    .buttonStyle(LocalShotIconButtonStyle(horizontalPadding: 9))
                    .help("标注")

                    iconButton("sparkles", label: "图片美化", action: actions.beautify)
                    iconButton("pin", label: "置顶截图", action: actions.pin)
                    iconButton("text.viewfinder", label: "识别文字", action: actions.recognizeText)
                    iconButton("character.bubble", label: "原位置翻译", action: actions.translate)

                    Menu {
                        Button("另存为…", systemImage: "square.and.arrow.down", action: actions.saveAs)
                        Button("在 Finder 中显示", systemImage: "folder", action: actions.reveal)
                        Divider()
                        Button("删除", systemImage: "trash", role: .destructive, action: actions.delete)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 26)
                    .background(
                        LocalShotTheme.card,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .help("更多")
                    .accessibilityLabel("更多")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 456, height: 112)
        .background {
            LocalShotBackground()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LocalShotTheme.cardStroke, lineWidth: 1)
        }
        .tint(LocalShotTheme.accent)
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(LocalShotIconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
