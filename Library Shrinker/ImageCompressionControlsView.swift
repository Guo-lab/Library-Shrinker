import SwiftUI

struct ImageCompressionControlsView: View {
    @Bindable var viewModel: ImageLibraryViewModel
    let deleteSelectedAction: () -> Void
    let compressAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker("Target Type", selection: $viewModel.targetMode) {
                    ForEach(ImageCompressionTargetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)

                if viewModel.targetMode == .ratio {
                    Slider(
                        value: Binding(
                            get: { viewModel.targetRatioSliderPosition },
                            set: { viewModel.targetRatioSliderPosition = $0 }
                        ),
                        in: 0...1
                    )
                    Text(viewModel.targetPercentageText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 42, alignment: .trailing)
                } else {
                    Spacer()
                    TextField(
                        "1",
                        value: $viewModel.targetMegabytes,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    Text("MB each")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.selectedImageIDs.count) selected")
                        .font(.caption.weight(.semibold))
                    Text(viewModel.selectionSizeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !viewModel.deletableSelectedOriginals.isEmpty && !viewModel.isCompressing {
                    Button(role: .destructive, action: deleteSelectedAction) {
                        Label(
                            "Delete \(viewModel.deletableSelectedOriginals.count)",
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.isCompressing {
                    Button(role: .cancel) {
                        viewModel.cancelCompression()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: compressAction) {
                        Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canCompress)
                }
            }

            if let compressionText = viewModel.compressionText {
                Text(compressionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
