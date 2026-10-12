import AppKit
import LocalShotCore
import SwiftUI

private enum CaptureHistoryModeFilter: String, CaseIterable, Identifiable {
    case all
    case area
    case window
    case fullScreen
    case scrolling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "全部"
        case .area: "区域"
        case .window: "窗口"
        case .fullScreen: "全屏"
        case .scrolling: "滚动"
        }
    }

    func matches(_ mode: CaptureMode) -> Bool {
        switch self {
        case .all: true
        case .area: mode == .area
        case .window: mode == .window
        case .fullScreen: mode == .fullScreen
        case .scrolling: mode == .scrolling
        }
    }
}

@MainActor
final class CaptureHistoryFilterModel: ObservableObject {
    @Published var searchText = ""
    @Published fileprivate var mode: CaptureHistoryModeFilter = .all
}

struct CaptureHistoryView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var filterModel: CaptureHistoryFilterModel
    @ObservedObject var searchModel: CaptureHistorySearchModel

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("截图历史")
                    .font(.title2.weight(.semibold))

                Spacer()

                TextField("搜索文件名、日期或图片文字", text: $filterModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)

                Picker("截图类型", selection: $filterModel.mode) {
                    ForEach(CaptureHistoryModeFilter.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .frame(width: 120)

                Button("刷新", systemImage: "arrow.clockwise") {
                    appModel.refreshHistory()
                    searchModel.synchronize(assets: appModel.recentAssets)
                }
            }
            .padding(16)

            HStack(spacing: 8) {
                if searchModel.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                    Text(searchModel.statusMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("停止索引") {
                        searchModel.cancelIndexing()
                    }
                } else {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(.secondary)
                    Text(searchModel.errorMessage ?? searchModel.statusMessage)
                        .foregroundColor(
                            searchModel.errorMessage == nil ? Color.secondary : Color.red
                        )
                    Spacer()
                    Button("更新文字索引") {
                        searchModel.synchronize(assets: appModel.recentAssets)
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            if filteredAssets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(filterModel.searchText.isEmpty ? "暂无截图" : "没有匹配的截图")
                        .font(.headline)
                    Text("截图完成后会自动出现在这里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(filteredAssets) { asset in
                            historyCard(asset)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    private var filteredAssets: [CaptureAsset] {
        let query = filterModel.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase

        return appModel.recentAssets.filter { asset in
            guard filterModel.mode.matches(asset.mode) else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            let filename = asset.url.lastPathComponent.localizedLowercase
            let dateText = asset.createdAt.formatted(
                date: .numeric,
                time: .standard
            ).localizedLowercase
            let recognizedText = searchModel.recognizedText(for: asset).localizedLowercase
            return filename.contains(query)
                || dateText.contains(query)
                || recognizedText.contains(query)
        }
    }

    private func historyCard(_ asset: CaptureAsset) -> some View {
        Button {
            appModel.showQuickAccess(for: asset)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(nsImage: NSImage(contentsOf: asset.url) ?? NSImage())
                    .resizable()
                    .scaledToFill()
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                HStack(spacing: 6) {
                    Image(systemName: asset.mode.symbolName)
                        .foregroundStyle(.secondary)
                    Text(asset.mode.displayName)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Text(asset.url.pathExtension.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(asset.url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("打开快速操作")
        .accessibilityLabel("\(asset.mode.displayName)，\(asset.createdAt.formatted())")
    }
}
