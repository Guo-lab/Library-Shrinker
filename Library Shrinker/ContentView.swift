//
//  ContentView.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = VideoLibraryViewModel()
    @State private var pendingOriginalDeletion: VideoAssetItem?
    @State private var isConfirmingSelectedDeletion = false
    @State private var lowBitRateWarning: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                listHeader

                List(viewModel.filteredVideos) { video in
                    VideoAssetRow(
                        video: video,
                        isSelected: viewModel.selectedVideoIDs.contains(video.id),
                        compressionRecord: viewModel.compressionRecords[video.id],
                        compressionRole: viewModel.compressionRole(for: video),
                        targetByteSize: viewModel.targetByteSize(for: video),
                        showsIndividualRatio: viewModel.targetMode == .bitRate,
                        action: {
                            viewModel.toggleSelection(for: video)
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        if viewModel.canDeleteOriginal(video) {
                            Button("Delete Original", systemImage: "trash", role: .destructive) {
                                pendingOriginalDeletion = video
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if viewModel.filteredVideos.isEmpty {
                        emptyState
                    }
                }

                CompressionControlsView(
                    viewModel: viewModel,
                    deleteSelectedAction: {
                        isConfirmingSelectedDeletion = true
                    },
                    compressAction: {
                        if let warning = viewModel.lowBitRateWarning {
                            lowBitRateWarning = warning
                        } else {
                            viewModel.startCompression()
                        }
                    }
                )
            }
            .navigationTitle("Video Shrinker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadVideos()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh photo library")
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.start()
            }
            .confirmationDialog(
                "Delete the original video?",
                isPresented: Binding(
                    get: { pendingOriginalDeletion != nil },
                    set: { if !$0 { pendingOriginalDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingOriginalDeletion
            ) { video in
                Button("Delete Original", role: .destructive) {
                    pendingOriginalDeletion = nil
                    Task {
                        await viewModel.deleteOriginal(video)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingOriginalDeletion = nil
                }
            } message: { video in
                Text("\(video.displayName) will move to Recently Deleted. Its compressed copy will remain in Photos.")
            }
            .confirmationDialog(
                "Delete \(viewModel.deletableSelectedOriginals.count) selected originals?",
                isPresented: $isConfirmingSelectedDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Selected Originals", role: .destructive) {
                    Task {
                        await viewModel.deleteSelectedOriginals()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only originals with verified compressed copies will move to Recently Deleted. Other selected videos will not be changed.")
            }
            .confirmationDialog(
                "Very low bitrate",
                isPresented: Binding(
                    get: { lowBitRateWarning != nil },
                    set: { if !$0 { lowBitRateWarning = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Compress Anyway") {
                    lowBitRateWarning = nil
                    viewModel.startCompression()
                }
                Button("Cancel", role: .cancel) {
                    lowBitRateWarning = nil
                }
            } message: {
                Text(lowBitRateWarning ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(viewModel.statusText, systemImage: viewModel.statusIconName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(viewModel.videos.count) videos")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Picker("Videos", selection: $viewModel.selectedFilter) {
                ForEach(VideoListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Bitrate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Bitrate", selection: $viewModel.selectedBitRateFilter) {
                    ForEach(VideoBitRateFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if viewModel.isLoading {
                ProgressView(value: viewModel.loadingProgress)
                    .progressViewStyle(.linear)
            }

            if viewModel.needsAuthorization {
                Button {
                    Task {
                        await viewModel.requestAccessAndLoad()
                    }
                } label: {
                    Label("Allow Photos Access", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("Video")
                .frame(width: 78, alignment: .leading)

            Text("Info")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("MB")
                .frame(width: 34, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.thinMaterial)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Videos",
            systemImage: "video.slash",
            description: Text(
                viewModel.videos.isEmpty
                    ? viewModel.emptyStateMessage
                    : "No videos match the selected filter."
            )
        )
        .padding()
    }
}

#Preview {
    ContentView()
}
