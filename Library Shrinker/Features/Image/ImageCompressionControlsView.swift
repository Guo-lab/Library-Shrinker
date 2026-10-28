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

            SelectionActionBar(
                selectedCount: viewModel.selectedImageIDs.count,
                selectionSizeText: viewModel.selectionSizeText,
                deletableCount: viewModel.deletableSelectedOriginals.count,
                isWorking: viewModel.isCompressing,
                canStart: viewModel.canCompress,
                statusText: viewModel.compressionText,
                deleteAction: deleteSelectedAction,
                cancelAction: viewModel.cancelCompression,
                startAction: compressAction
            )
        }
        .padding()
        .background(.regularMaterial)
    }
}
