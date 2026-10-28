import SwiftUI
import UniformTypeIdentifiers

struct LibraryShrinkerBackup: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let videoMetadata: VideoMetadataCacheSnapshot?
    let imageMetadata: ImageMetadataCacheSnapshot?
    let videoCompressionRecords: [String: CompressionRecord]
    let imageCompressionRecords: [String: CompressionRecord]
    let locallyDeletedVideoAssetIDs: [String]
}

struct LibraryShrinkerBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct LibraryShrinkerBackupStore {
    private let videoMetadataStore = VideoMetadataCacheStore()
    private let imageMetadataStore = ImageMetadataCacheStore()
    private let stateRepository: any LibraryStateRepository = UserDefaultsLibraryStateRepository()

    func makeDocument() throws -> LibraryShrinkerBackupDocument {
        let backup = LibraryShrinkerBackup(
            formatVersion: LibraryShrinkerBackup.currentFormatVersion,
            exportedAt: Date(),
            videoMetadata: videoMetadataStore.load(),
            imageMetadata: imageMetadataStore.load(),
            videoCompressionRecords: stateRepository.compressionRecords(for: .video),
            imageCompressionRecords: stateRepository.compressionRecords(for: .image),
            locallyDeletedVideoAssetIDs: Array(stateRepository.locallyDeletedVideoAssetIDs())
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return LibraryShrinkerBackupDocument(data: try encoder.encode(backup))
    }

    func restore(from url: URL) throws {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryShrinkerBackup.self, from: data)

        guard backup.formatVersion == LibraryShrinkerBackup.currentFormatVersion else {
            throw LibraryShrinkerBackupError.unsupportedFormat
        }

        if let videoMetadata = backup.videoMetadata {
            videoMetadataStore.save(VideoMetadataCacheSnapshot(
                lastFullScanAt: Date(),
                records: videoMetadata.records
            ))
        }
        if let imageMetadata = backup.imageMetadata {
            imageMetadataStore.save(ImageMetadataCacheSnapshot(
                lastFullScanAt: Date(),
                records: imageMetadata.records
            ))
        }

        try stateRepository.saveCompressionRecords(
            backup.videoCompressionRecords,
            for: .video
        )
        try stateRepository.saveCompressionRecords(
            backup.imageCompressionRecords,
            for: .image
        )
        stateRepository.saveLocallyDeletedVideoAssetIDs(
            Set(backup.locallyDeletedVideoAssetIDs)
        )
    }

}

enum LibraryShrinkerBackupError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "This backup was created by an unsupported version of Library Shrinker."
        }
    }
}

struct BackupControls: View {
    let restoreAction: () -> Void

    @State private var isShowingBackup = false

    var body: some View {
        Button {
            isShowingBackup = true
        } label: {
            Image(systemName: "archivebox")
        }
        .accessibilityLabel("Backup and restore")
        .sheet(isPresented: $isShowingBackup) {
            BackupSheet(restoreAction: restoreAction)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct BackupSheet: View {
    let restoreAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: LibraryShrinkerBackupDocument?
    @State private var resultMessage: BackupResultMessage?

    private let backupStore = LibraryShrinkerBackupStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .font(.system(size: 38))
                            .foregroundStyle(.blue)

                        Text("Keep Your Scan Results")
                            .font(.headline)

                        Text("Save the library metadata and compression relationships to Files or iCloud Drive, then restore them after reinstalling the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Backup Includes") {
                    Label("Video and image scan metadata", systemImage: "photo.stack")
                    Label("Original and compressed copy relationships", systemImage: "arrow.triangle.branch")
                    Label("Local deletion records", systemImage: "trash")
                }

                Section {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)

                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Backups contain metadata only. Your photos and videos are never copied into the backup file.")
                }
            }
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Library-Shrinker-Backup"
        ) { result in
            handleExport(result)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            importBackup(result)
        }
        .alert(item: $resultMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func prepareExport() {
        do {
            exportDocument = try backupStore.makeDocument()
            isExporting = true
        } catch {
            resultMessage = BackupResultMessage(
                title: "Could Not Prepare Backup",
                message: error.localizedDescription
            )
        }
    }

    private func handleExport(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            resultMessage = BackupResultMessage(
                title: "Backup Exported",
                message: "Keep the JSON file in Files or iCloud Drive so it remains available after reinstalling the app."
            )
        case .failure(let error):
            resultMessage = BackupResultMessage(
                title: "Could Not Export Backup",
                message: error.localizedDescription
            )
        }
        exportDocument = nil
    }

    private func importBackup(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            try backupStore.restore(from: url)
            restoreAction()
            resultMessage = BackupResultMessage(
                title: "Backup Imported",
                message: "The saved cache and compression records have been restored."
            )
        } catch {
            resultMessage = BackupResultMessage(
                title: "Could Not Import Backup",
                message: error.localizedDescription
            )
        }
    }
}

private struct BackupResultMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
