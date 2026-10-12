import LocalShotBeautification
import SwiftUI

struct ImageBeautifierView: View {
    @ObservedObject var model: ImageBeautifierModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("图片美化")
                        .font(.headline)
                    Text("原截图保持不变，仅导出新图片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("恢复默认", systemImage: "arrow.counterclockwise") {
                    model.reset()
                }

                Button("导出 PNG", systemImage: "square.and.arrow.down") {
                    model.exportAs()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)

            Divider()

            HSplitView {
                ImageBeautificationPreview(model: model)
                    .frame(minWidth: 560)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        controlSection("背景") {
                            Picker("背景样式", selection: $model.backgroundPreset) {
                                ForEach(BeautificationBackgroundPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        controlSection("输出比例") {
                            Picker("输出比例", selection: $model.aspectRatio) {
                                ForEach(BeautificationAspectRatio.allCases) { ratio in
                                    Text(ratio.displayName).tag(ratio)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        sliderControl(
                            title: "边距",
                            value: $model.padding,
                            range: 0...160,
                            step: 4,
                            formattedValue: "\(Int(model.padding)) px"
                        )

                        sliderControl(
                            title: "圆角",
                            value: $model.cornerRadius,
                            range: 0...80,
                            step: 2,
                            formattedValue: "\(Int(model.cornerRadius)) px"
                        )

                        sliderControl(
                            title: "阴影大小",
                            value: $model.shadowRadius,
                            range: 0...48,
                            step: 2,
                            formattedValue: "\(Int(model.shadowRadius)) px"
                        )

                        sliderControl(
                            title: "阴影强度",
                            value: $model.shadowOpacity,
                            range: 0...0.6,
                            step: 0.05,
                            formattedValue: "\(Int(model.shadowOpacity * 100))%"
                        )

                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(18)
                }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private func controlSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func sliderControl(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formattedValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formattedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
        }
    }
}

private struct ImageBeautificationPreview: View {
    @ObservedObject var model: ImageBeautifierModel

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = ImageBeautificationRenderer.outputSize(
                imageSize: model.sourcePixelSize,
                options: model.options
            )
            let available = CGSize(
                width: max(1, proxy.size.width - 48),
                height: max(1, proxy.size.height - 48)
            )
            let scale = min(
                available.width / canvasSize.width,
                available.height / canvasSize.height
            )
            let previewCanvas = CGSize(
                width: canvasSize.width * scale,
                height: canvasSize.height * scale
            )
            let previewImage = CGSize(
                width: model.sourcePixelSize.width * scale,
                height: model.sourcePixelSize.height * scale
            )

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ZStack {
                    backgroundView(model.backgroundPreset.background)

                    Image(nsImage: model.image)
                        .resizable()
                        .frame(width: previewImage.width, height: previewImage.height)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: model.cornerRadius * scale,
                                style: .continuous
                            )
                        )
                        .shadow(
                            color: .black.opacity(model.shadowOpacity),
                            radius: min(model.shadowRadius, model.padding) * scale,
                            y: max(1, model.shadowRadius * 0.18 * scale)
                        )
                }
                .frame(width: previewCanvas.width, height: previewCanvas.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.black.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            }
        }
    }

    @ViewBuilder
    private func backgroundView(_ background: BeautificationBackground) -> some View {
        switch background {
        case let .solid(color):
            swiftUIColor(color)
        case let .linearGradient(start, end):
            LinearGradient(
                colors: [swiftUIColor(start), swiftUIColor(end)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func swiftUIColor(_ color: BeautificationColor) -> Color {
        Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }
}
