import SwiftUI

struct ImageShrinkerView: View {
    @Binding var mode: ShrinkerMode
    @State private var viewModel = ImageLibraryViewModel()
    @State private var previewItem: ImageAssetItem?
    @State private var pendingOriginalDeletion: ImageAssetItem?
    @State private var pendingCompressedDeletion: ImageAssetItem?
    @State private var isConfirmingSelectedDeletion = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                listHeader

                List(viewModel.imageEntries) { entry in
                    let item = entry.image
                    ImageAssetRow(
                        item: item,
                        isSelected: viewModel.selectedImageIDs.contains(item.id),
                        targetByteSize: min(
                            item.byteSize,
                            viewModel.targetByteSize(for: item)
                        ),
                        compressionRecord: viewModel.compressionRecords[item.id],
                        compressionRole: viewModel.compressionRole(for: item),
                        isCompressedChild: entry.isCompressedChild,
                        selectionAction: {
                            viewModel.toggleSelection(for: item)
                        },
                        previewAction: {
                            previewItem = item
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        if viewModel.canDeleteOriginal(item) {
                            Button("Delete Original", systemImage: "trash", role: .destructive) {
                                pendingOriginalDeletion = item
                            }
                        } else if viewModel.canDeleteCompressedCopy(item) {
                            Button("Delete Compressed", systemImage: "trash", role: .destructive) {
                                pendingCompressedDeletion = item
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if viewModel.images.isEmpty {
                        emptyState
                    }
                }

                ImageCompressionControlsView(
                    viewModel: viewModel,
                    deleteSelectedAction: {
                        isConfirmingSelectedDeletion = true
                    },
                    compressAction: {
                        viewModel.startCompression()
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ShrinkerModeMenu(mode: $mode)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadImages()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh screenshots")
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.start()
            }
            .sheet(item: $previewItem) { item in
                ImagePreviewView(item: item)
            }
            .confirmationDialog(
                "Delete the original screenshot?",
                isPresented: Binding(
                    get: { pendingOriginalDeletion != nil },
                    set: { if !$0 { pendingOriginalDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingOriginalDeletion
            ) { item in
                Button("Delete Original", role: .destructive) {
                    pendingOriginalDeletion = nil
                    Task {
                        await viewModel.deleteOriginal(item)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingOriginalDeletion = nil
                }
            } message: { item in
                Text("\(item.displayName) will move to Recently Deleted. Its compressed copy will remain in Photos.")
            }
            .confirmationDialog(
                "Delete this compressed copy?",
                isPresented: Binding(
                    get: { pendingCompressedDeletion != nil },
                    set: { if !$0 { pendingCompressedDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingCompressedDeletion
            ) { item in
                Button("Delete Compressed Copy", role: .destructive) {
                    pendingCompressedDeletion = nil
                    Task {
                        await viewModel.deleteCompressedCopy(item)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingCompressedDeletion = nil
                }
            } message: { item in
                Text("\(item.displayName) will move to Recently Deleted. Its original screenshot will remain in Photos.")
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
                Text("Only originals with verified compressed copies will move to Recently Deleted. Other selected screenshots will not be changed.")
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

                Text("\(viewModel.images.count) screenshots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Picker("Images", selection: $viewModel.selectedFilter) {
                ForEach(ImageListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

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
            Text("Screenshot")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.thinMaterial)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Screenshots",
            systemImage: "photo.badge.magnifyingglass",
            description: Text(viewModel.emptyStateMessage)
        )
        .padding()
    }
}

#Preview {
    ImageShrinkerView(mode: .constant(.image))
}
