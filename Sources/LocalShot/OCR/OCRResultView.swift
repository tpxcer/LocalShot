import SwiftUI

struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("文字识别")
                        .font(.headline)
                    Text(model.asset.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("重新识别", systemImage: "arrow.clockwise") {
                    model.recognize()
                }
                .disabled(model.isLoading)
                Button("复制全部", systemImage: "doc.on.doc") {
                    model.copyAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.combinedText.isEmpty)
            }
            .padding(16)

            Divider()

            Group {
                if model.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在本地识别文字…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("没有识别到文字")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.blocks) { block in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(block.text)
                                            .textSelection(.enabled)
                                        Spacer(minLength: 8)
                                        Button {
                                            model.copy(block.text)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("复制此文字块")
                                        .accessibilityLabel("复制此文字块")
                                    }
                                    Text("置信度 \(Int(block.confidence * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
