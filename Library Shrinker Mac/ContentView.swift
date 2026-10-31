import SwiftUI

struct ContentView: View {
    @State private var model = MacPhotoLibraryModel()
    @State private var isConfirmingDeletion = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            libraryContent
        }
        .navigationTitle("Library Shrinker")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isLoading)

                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(model.selection.isEmpty || model.isLoading)

                Button {
                    model.startCompression()
                } label: {
                    Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selection.isEmpty || model.isLoading)
            }
        }
        .alert(
            "Delete \(model.selection.count) selected item(s)?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteSelection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected items will move to Recently Deleted in Photos.")
        }
        .task {
            await model.load()
        }
    }

    private var sidebar: some View {
        List(MacLibrarySection.allCases, selection: $model.section) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .navigationTitle("Library")
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.authorizationDenied {
            ContentUnavailableView {
                Label("Photos Access Required", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("Allow Library Shrinker to access Photos in System Settings.")
            } actions: {
                Button("Open System Settings") {
                    model.openPhotoPrivacySettings()
                }
            }
        } else if model.isLoading && model.items.isEmpty {
            ProgressView("Reading Photos Library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            ContentUnavailableView(
                model.section.emptyTitle,
                systemImage: model.section.systemImage,
                description: Text(model.section.emptyDescription)
            )
        } else {
            VStack(spacing: 0) {
                List(model.items, selection: $model.selection) { item in
                    MacPhotoRow(item: item)
                        .tag(item.id)
                }

                Divider()

                HStack {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.section == .videos {
                        Picker("Codec", selection: $model.videoCodec) {
                            ForEach(MacVideoCodec.allCases) { codec in
                                Text(codec.title).tag(codec)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    Text("Target \(model.targetPercent)%")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $model.targetRatio,
                        in: 0.1...0.8,
                        step: 0.05
                    )
                    .frame(width: 130)
                    .disabled(model.isLoading)
                    Text("\(model.selection.count) selected")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .frame(height: 34)
            }
        }
    }
}

private struct MacPhotoRow: View {
    let item: MacPhotoItem

    var body: some View {
        HStack(spacing: 12) {
            MacPhotoThumbnail(assetIdentifier: item.id)
                .frame(width: 96, height: 60)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label(item.dimensionsText, systemImage: "rectangle.inset.filled")
                    if let durationText = item.durationText {
                        Label(durationText, systemImage: "clock")
                    }
                    if let creationDate = item.creationDate {
                        Text(creationDate, format: .dateTime.year().month().day())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .frame(width: 960, height: 640)
}
