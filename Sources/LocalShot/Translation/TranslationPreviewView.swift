import AppKit
import LocalShotTranslation
import SwiftUI

@available(macOS 15.0, *)
struct TranslationPreviewView: View {
    @ObservedObject var model: TranslationResultModel

    private var image: NSImage {
        NSImage(contentsOf: model.asset.url) ?? NSImage()
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = imageFrame(in: proxy.size)
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                if model.showsTranslation {
                    ForEach(model.translatedBlocks) { block in
                        let rect = viewRect(for: block, imageFrame: frame)
                        Text(block.targetText)
                            .font(.system(size: max(8, min(28, rect.height * 0.56)), weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .minimumScaleFactor(0.35)
                            .padding(3)
                            .frame(width: max(12, rect.width), height: max(12, rect.height))
                            .background(.white, in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(.black.opacity(0.16), lineWidth: 1)
                            }
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }

    private func imageFrame(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }
        let inset: CGFloat = 24
        let available = CGSize(
            width: max(1, size.width - inset * 2),
            height: max(1, size.height - inset * 2)
        )
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func viewRect(for block: TranslationTextBlock, imageFrame: CGRect) -> CGRect {
        let box = block.boundingBox
        return CGRect(
            x: imageFrame.minX + box.x * imageFrame.width,
            y: imageFrame.maxY - (box.y + box.height) * imageFrame.height,
            width: box.width * imageFrame.width,
            height: box.height * imageFrame.height
        ).insetBy(dx: -4, dy: -2)
    }
}
