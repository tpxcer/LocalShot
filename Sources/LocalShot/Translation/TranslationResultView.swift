import LocalShotTranslation
import SwiftUI
@preconcurrency import Translation

@available(macOS 15.0, *)
struct TranslationResultView: View {
    @ObservedObject var model: TranslationResultModel

    private let languageOptions: [(String, String)] = [
        ("zh-Hans", "简体中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("原位置翻译")
                        .font(.headline)
                    Text(model.asset.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("目标语言", selection: $model.targetLanguageIdentifier) {
                    ForEach(languageOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .frame(width: 170)

                Toggle("显示译文", isOn: $model.showsTranslation)
                    .toggleStyle(.switch)

                Button("复制原文", systemImage: "doc.on.doc") {
                    model.copySourceText()
                }
                .disabled(model.combinedSourceText.isEmpty)

                Button("复制译文", systemImage: "doc.on.doc") {
                    model.copyTargetText()
                }
                .disabled(model.combinedTargetText.isEmpty)

                Button("导出图片", systemImage: "square.and.arrow.down") {
                    model.exportAs()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.translatedBlocks.isEmpty)
            }
            .padding(14)

            Divider()

            HSplitView {
                TranslationPreviewView(model: model)
                    .frame(minWidth: 560)

                VStack(alignment: .leading, spacing: 8) {
                    if model.isRecognizing {
                        ProgressView("正在识别文字…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.isTranslating {
                        ProgressView("正在使用系统翻译…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(model.translatedBlocks) { block in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(block.sourceText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                            Spacer(minLength: 6)
                                            Button {
                                                model.copy(block.sourceText)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("复制此原文块")
                                            .accessibilityLabel("复制此原文块")
                                        }
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(block.targetText)
                                                .textSelection(.enabled)
                                            Spacer(minLength: 6)
                                            Button {
                                                model.copy(block.targetText)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("复制此译文块")
                                            .accessibilityLabel("复制此译文块")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(12)
                        }
                    }
                }
                .frame(minWidth: 280, idealWidth: 330)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .translationTask(model.configuration) { session in
            await translate(using: session)
        }
    }

    nonisolated private func translate(using session: TranslationSession) async {
        let ocrBlocks = await MainActor.run { model.ocrBlocks }
        guard !ocrBlocks.isEmpty else {
            return
        }
        await MainActor.run { model.beginTranslation() }

        if session.sourceLanguage != nil {
            do {
                try await session.prepareTranslation()
            } catch {
                await MainActor.run {
                    model.failTranslation("准备系统语言资源失败：\(error.localizedDescription)")
                }
                return
            }
        }

        do {
            let requests = ocrBlocks.map {
                TranslationSession.Request(
                    sourceText: $0.text,
                    clientIdentifier: $0.id.uuidString
                )
            }
            let responses = try await session.translations(from: requests)
            let ocrByID = Dictionary(uniqueKeysWithValues: ocrBlocks.map { ($0.id.uuidString, $0) })
            let blocks = responses.compactMap { response -> TranslationTextBlock? in
                guard let identifier = response.clientIdentifier,
                      let sourceBlock = ocrByID[identifier] else {
                    return nil
                }
                return TranslationTextBlock(
                    id: sourceBlock.id,
                    sourceText: sourceBlock.text,
                    targetText: response.targetText,
                    boundingBox: sourceBlock.boundingBox
                )
            }
            await MainActor.run { model.completeTranslation(blocks) }
        } catch {
            await MainActor.run {
                model.failTranslation("系统翻译失败：\(error.localizedDescription)")
            }
        }
    }
}
