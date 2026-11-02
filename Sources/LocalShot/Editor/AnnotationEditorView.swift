import LocalShotEditing
import SwiftUI

struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationEditorModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AnnotationCanvasView(model: model)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .tint(LocalShotTheme.accent)
    }

    private let toolGroups: [[AnnotationEditorTool]] = [
        [.select, .crop],
        [.arrow, .line, .rectangle, .ellipse],
        [.pen, .highlight],
        [.text, .step],
        [.spotlight, .pixelate, .redaction]
    ]

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(toolGroups, id: \.self) { group in
                            HStack(spacing: 2) {
                                ForEach(group) { tool in
                                    Button {
                                        model.selectedTool = tool
                                    } label: {
                                        Image(systemName: tool.symbolName)
                                    }
                                    .buttonStyle(
                                        LocalShotIconButtonStyle(
                                            isSelected: model.selectedTool == tool,
                                            isGrouped: true
                                        )
                                    )
                                    .help(tool.label)
                                    .accessibilityLabel(tool.label)
                                }
                            }
                            .padding(3)
                            .background(
                                LocalShotTheme.card,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(LocalShotTheme.cardStroke, lineWidth: 1)
                            }
                        }
                    }
                    .padding(1)
                }

                Button("导出", systemImage: "square.and.arrow.down") {
                    model.exportAs()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                ForEach(EditorColorPreset.allCases) { preset in
                    Button {
                        model.selectedColor = preset
                    } label: {
                        Circle()
                            .fill(preset.swiftUIColor)
                            .overlay {
                                Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                            }
                            .frame(width: 20, height: 20)
                            .padding(3)
                            .overlay {
                                if model.selectedColor == preset {
                                    Circle().stroke(LocalShotTheme.accent, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("颜色 \(preset.rawValue)")
                }

                Slider(value: $model.lineWidth, in: 2...12, step: 1)
                    .frame(width: 100)
                    .help("线宽或工具大小")
                    .accessibilityLabel("线宽或工具大小")

                Text("\(Int(model.lineWidth)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                if model.selectedTool == .line {
                    Button {
                        model.lineIsDashed.toggle()
                    } label: {
                        Image(systemName: "line.diagonal")
                    }
                    .buttonStyle(LocalShotIconButtonStyle(isSelected: model.lineIsDashed))
                    .help(model.lineIsDashed ? "使用虚线" : "使用实线")
                    .accessibilityLabel("切换实线或虚线")
                    .accessibilityValue(model.lineIsDashed ? "虚线" : "实线")
                }

                if model.selectedTool == .text {
                    TextField("文字内容", text: $model.textDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                if model.selectedTool == .pixelate {
                    Picker("效果", selection: $model.pixelateEffect) {
                        Text("马赛克").tag(PixelateEffect.mosaic)
                        Text("模糊").tag(PixelateEffect.blur)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                Spacer(minLength: 8)

                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .help("撤销")
                .accessibilityLabel("撤销")

                Button {
                    model.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .help("重做")
                .accessibilityLabel("重做")

                Button(role: .destructive) {
                    model.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(model.selectedAnnotationID == nil)
                .help("删除所选标注")
                .accessibilityLabel("删除所选标注")

                if let rotationDegrees = model.selectedRotationDegrees {
                    Button {
                        model.rotateSelected(by: .pi / 2)
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .help("向左旋转 90°")
                    .accessibilityLabel("所选标注向左旋转 90 度")

                    Text("\(rotationDegrees)°")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 34)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("当前旋转角度 \(rotationDegrees) 度")

                    Button {
                        model.rotateSelected(by: -.pi / 2)
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .help("向右旋转 90°")
                    .accessibilityLabel("所选标注向右旋转 90 度")

                    Button {
                        model.resetSelectedRotation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(rotationDegrees == 0)
                    .help("重置旋转")
                    .accessibilityLabel("重置所选标注旋转")
                }

                Button(role: .destructive) {
                    model.clear()
                } label: {
                    Image(systemName: "trash.slash")
                }
                .help("清除全部标注")
                .accessibilityLabel("清除全部标注")

                if model.hasCrop {
                    Button {
                        model.resetCrop()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("恢复完整图片范围")
                    .accessibilityLabel("重置裁剪")
                }
            }
            .buttonStyle(LocalShotIconButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 100)
        .background(LocalShotTheme.background)
    }
}
