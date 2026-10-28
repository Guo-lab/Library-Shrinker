//
//  CompressionControlsView.swift
//  Library Shrinker
//

import SwiftUI

struct CompressionControlsView: View {
    @Bindable var viewModel: VideoLibraryViewModel
    let deleteSelectedAction: () -> Void
    let compressAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 12

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Codec")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Codec", selection: $viewModel.selectedPreset) {
                            ForEach(VideoCompressionPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .frame(width: availableWidth * 0.4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Profile", selection: Binding(
                            get: { viewModel.selectedProfile },
                            set: { viewModel.selectProfile($0) }
                        )) {
                            ForEach(CompressionProfile.allCases) { profile in
                                Text(profile.title).tag(profile)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .frame(width: availableWidth * 0.6)
                }
            }
            .frame(height: 55)

            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 12

                HStack(spacing: 12) {
                    Picker("Target Type", selection: Binding(
                        get: { viewModel.targetMode },
                        set: { viewModel.selectTargetMode($0) }
                    )) {
                        ForEach(CompressionTargetMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: availableWidth * 0.4)

                    HStack(spacing: 8) {
                        Text("Target")
                            .font(.caption.weight(.semibold))

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
                                .frame(width: 34, alignment: .trailing)
                        } else {
                            Spacer()
                            TextField("5", value: $viewModel.targetMegabitsPerSecond, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                            Text("Mbps")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: availableWidth * 0.6)
                }
            }
            .frame(height: 32)

            SelectionActionBar(
                selectedCount: viewModel.selectedVideoIDs.count,
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
