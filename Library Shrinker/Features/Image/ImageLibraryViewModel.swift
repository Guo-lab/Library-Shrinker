import Foundation
import Observation
import Photos

@MainActor
@Observable
final class ImageLibraryViewModel {
    var images: [ImageAssetItem] = []
    var selectedImageIDs: Set<String> = []
    var authorizationState: PhotoLibraryAccessState = .notDetermined
    var targetSizeRatio = 0.5
    var targetMode: ImageCompressionTargetMode = .ratio
    var targetMegabytes = 1.0
    var selectedFilter: ImageListFilter = .all
    var isLoading = false
    var isCompressing = false
    var loadingProgress = 0.0
    var statusText = "Checking Photos access"
    var compressionText: String?
    var compressionRecords: [String: CompressionRecord]

    private let imageStore: PhotoLibraryImageStore
    private let compressionWorkflow: ImageCompressionWorkflow
    private let scanner: ImageLibraryScanner
    private let stateRepository: any LibraryStateRepository
    private var compressionTask: Task<Void, Never>?

    init(
        imageStore: PhotoLibraryImageStore? = nil,
        compressor: ImageCompressor? = nil,
        metadataCacheStore: ImageMetadataCacheStore? = nil,
        stateRepository: (any LibraryStateRepository)? = nil,
        scanner: ImageLibraryScanner? = nil
    ) {
        let repository = stateRepository ?? UserDefaultsLibraryStateRepository()
        let resolvedImageStore = imageStore ?? PhotoLibraryImageStore()
        let resolvedCacheStore = metadataCacheStore ?? ImageMetadataCacheStore()
        let resolvedCompressor = compressor ?? ImageCompressor()
        self.imageStore = resolvedImageStore
        self.compressionWorkflow = ImageCompressionWorkflow(
            compressor: resolvedCompressor,
            repository: repository
        )
        self.scanner = scanner ?? ImageLibraryScanner(
            imageStore: resolvedImageStore,
            cacheStore: resolvedCacheStore
        )
        self.stateRepository = repository
        compressionRecords = repository.compressionRecords(for: .image)
    }

    func reloadAfterBackupImport() async {
        compressionRecords = stateRepository.compressionRecords(for: .image)
        await loadImages()
    }

    var needsAuthorization: Bool {
        authorizationState == .notDetermined || authorizationState == .denied
    }

    var statusIconName: String {
        switch authorizationState {
        case .authorized: "checkmark.circle"
        case .limited: "exclamationmark.circle"
        case .denied: "lock.circle"
        case .notDetermined: "photo.circle"
        }
    }

    var selectedItems: [ImageAssetItem] {
        images.filter {
            selectedImageIDs.contains($0.id) && compressionRole(for: $0) != .compressedCopy
        }
    }

    var imageEntries: [ImageListEntry] {
        let visibleIDs = Set(images.map(\.id))
        let originals = images
            .filter { compressionRole(for: $0) != .compressedCopy }
            .sorted { $0.byteSize > $1.byteSize }

        var entries = originals.flatMap { original in
            var entries = [ImageListEntry(image: original, isCompressedChild: false)]
            if let compressedID = compressionRecords[original.id]?.compressedAssetID,
               let compressed = images.first(where: { $0.id == compressedID }) {
                entries.append(ImageListEntry(image: compressed, isCompressedChild: true))
            }
            return entries
        }
        let orphanedCompressedCopies = images
            .filter { image in
                guard compressionRole(for: image) == .compressedCopy,
                      let originalID = compressionRecords[image.id]?.originalAssetID else {
                    return false
                }
                return !visibleIDs.contains(originalID)
            }
            .sorted { $0.byteSize > $1.byteSize }
        entries.append(contentsOf: orphanedCompressedCopies.map {
            ImageListEntry(image: $0, isCompressedChild: false)
        })
        return switch selectedFilter {
        case .all:
            entries
        case .originals:
            originals.map { ImageListEntry(image: $0, isCompressedChild: false) }
        case .compressed:
            images
                .filter { compressionRole(for: $0) == .compressedCopy }
                .sorted { $0.byteSize > $1.byteSize }
                .map { ImageListEntry(image: $0, isCompressedChild: false) }
        }
    }

    func compressionRole(for item: ImageAssetItem) -> ImageCompressionRole {
        guard let record = compressionRecords[item.id] else { return .original }
        if record.compressedAssetID == item.id {
            return .compressedCopy
        }
        if record.originalAssetID == item.id,
           let compressedID = record.compressedAssetID,
           images.contains(where: { $0.id == compressedID }) {
            return .originalWithCompressedCopy
        }
        return .original
    }

    func canDeleteOriginal(_ item: ImageAssetItem) -> Bool {
        compressionRole(for: item) == .originalWithCompressedCopy
    }

    func canDeleteCompressedCopy(_ item: ImageAssetItem) -> Bool {
        compressionRole(for: item) == .compressedCopy
    }

    var deletableSelectedOriginals: [ImageAssetItem] {
        selectedItems.filter(canDeleteOriginal)
    }

    func deleteOriginal(_ item: ImageAssetItem) async {
        guard canDeleteOriginal(item) else {
            compressionText = "The compressed copy must be present before the original can be deleted."
            return
        }

        do {
            try await imageStore.deleteAsset(item.asset)
            images.removeAll { $0.id == item.id }
            selectedImageIDs.remove(item.id)
            compressionRecords.removeValue(forKey: item.id)
            persistCompressionRecords()
            statusText = "Original moved to Recently Deleted"
            compressionText = "The compressed copy remains in Photos. You can recover the original from Recently Deleted."
        } catch {
            statusText = "Could not delete original"
            compressionText = error.localizedDescription
        }
    }

    func deleteCompressedCopy(_ item: ImageAssetItem) async {
        guard canDeleteCompressedCopy(item) else {
            compressionText = "This image is not a recognized compressed copy."
            return
        }

        do {
            let record = compressionRecords[item.id]
            try await imageStore.deleteAsset(item.asset)
            images.removeAll { $0.id == item.id }
            selectedImageIDs.remove(item.id)
            compressionRecords.removeValue(forKey: item.id)
            if let originalID = record?.originalAssetID {
                compressionRecords.removeValue(forKey: originalID)
            }
            persistCompressionRecords()
            statusText = "Compressed copy moved to Recently Deleted"
            compressionText = "The original screenshot remains in Photos."
        } catch {
            statusText = "Could not delete compressed copy"
            compressionText = error.localizedDescription
        }
    }

    func deleteSelectedOriginals() async {
        let items = deletableSelectedOriginals
        guard !items.isEmpty else {
            compressionText = "No selected originals have a verified compressed copy."
            return
        }

        do {
            try await imageStore.deleteAssets(items.map(\.asset))
            let deletedIDs = Set(items.map(\.id))
            images.removeAll { deletedIDs.contains($0.id) }
            selectedImageIDs.subtract(deletedIDs)
            for id in deletedIDs {
                compressionRecords.removeValue(forKey: id)
            }
            persistCompressionRecords()
            statusText = "\(items.count) originals moved to Recently Deleted"
            compressionText = "Their compressed copies remain in Photos. The originals can be recovered from Recently Deleted."
        } catch {
            statusText = "Could not delete selected originals"
            compressionText = error.localizedDescription
        }
    }

    var targetRatioSliderPosition: Double {
        get { CompressionTargetCalculator.sliderPosition(for: targetSizeRatio) }
        set { targetSizeRatio = CompressionTargetCalculator.ratio(forSliderPosition: newValue) }
    }

    var targetPercentageText: String {
        targetSizeRatio.formatted(.percent.precision(.fractionLength(0)))
    }

    func targetByteSize(for item: ImageAssetItem) -> Int64 {
        switch targetMode {
        case .ratio:
            CompressionTargetCalculator.targetByteSize(
                originalByteSize: item.byteSize,
                ratio: targetSizeRatio
            )
        case .fileSize:
            max(1, Int64(targetMegabytes * 1_000_000))
        }
    }

    var selectionSizeText: String {
        let originalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.byteSize }
        guard originalBytes > 0 else { return "Select screenshots to compress" }
        let targetBytes = selectedItems.reduce(Int64(0)) {
            $0 + min($1.byteSize, targetByteSize(for: $1))
        }
        let original = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: originalBytes)
        let target = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: targetBytes)
        return "\(original) → about \(target)"
    }

    var canCompress: Bool {
        !isLoading
            && !isCompressing
            && selectedItems.contains { targetByteSize(for: $0) < $0.byteSize }
    }

    var emptyStateMessage: String {
        if needsAuthorization {
            return "Allow Photos access to scan screenshots."
        }
        if isLoading {
            return "Scanning your screenshots."
        }
        return "No screenshots were found in the current Photos selection."
    }

    func start() async {
        authorizationState = imageStore.authorizationState()
        updateStatus()
        if authorizationState.canReadAndWrite {
            await loadImages()
        }
    }

    func requestAccessAndLoad() async {
        authorizationState = await imageStore.requestAuthorization()
        updateStatus()
        if authorizationState.canReadAndWrite {
            await loadImages()
        }
    }

    func loadImages() async {
        guard authorizationState.canReadAndWrite, !isLoading else { return }

        isLoading = true
        loadingProgress = 0
        statusText = "Scanning screenshots"
        let result = await scanner.scan(
            existingItems: images,
            compressionRecords: compressionRecords
        ) { [weak self] update in
            self?.images = update.items
            self?.loadingProgress = update.progress
            self?.statusText = update.statusText
        }
        images = result.items
        selectedImageIDs.formIntersection(Set(images.map(\.id)))
        isLoading = false
        loadingProgress = 1
        statusText = result.statusText
    }

    func toggleSelection(for item: ImageAssetItem) {
        if selectedImageIDs.contains(item.id) {
            selectedImageIDs.remove(item.id)
        } else {
            selectedImageIDs.insert(item.id)
        }
    }

    func startCompression() {
        guard canCompress else { return }
        compressionTask?.cancel()
        let itemCount = selectedItems.count
        compressionText = "Waiting for background processing"
        compressionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await ContinuousCompressionCoordinator.shared.begin(
                    kind: .image,
                    itemCount: itemCount,
                    expirationAction: { [weak self] in
                        self?.compressionTask?.cancel()
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                compressionText = "Background continuation is unavailable: \(error.localizedDescription). Compression will continue while the app remains active."
            }

            guard !Task.isCancelled else { return }
            await compressSelectedImages()
        }
    }

    func cancelCompression() {
        compressionTask?.cancel()
        ContinuousCompressionCoordinator.shared.cancel(kind: .image)
        compressionTask = nil
        isCompressing = false
        isLoading = false
        statusText = "Compression cancelled"
        compressionText = "No original screenshots were changed."
    }

    private func compressSelectedImages() async {
        let workItems = selectedItems.compactMap { item -> ImageCompressionWorkItem? in
            let target = targetByteSize(for: item)
            return target < item.byteSize
                ? ImageCompressionWorkItem(item: item, targetByteSize: target)
                : nil
        }
        guard !workItems.isEmpty else {
            ContinuousCompressionCoordinator.shared.complete(kind: .image, success: false)
            return
        }

        isCompressing = true
        isLoading = true
        loadingProgress = 0
        let outcome = await compressionWorkflow.run(
            workItems: workItems,
            existingRecords: compressionRecords
        ) { [weak self] update in
            self?.loadingProgress = update.progress
            self?.statusText = update.statusText
            self?.compressionText = update.detailText
        }
        compressionRecords = outcome.records
        selectedImageIDs.subtract(outcome.successfulItemIDs)
        isCompressing = false
        isLoading = false
        compressionTask = nil
        statusText = outcome.statusText
        compressionText = outcome.detailText
        ContinuousCompressionCoordinator.shared.complete(
            kind: .image,
            success: !outcome.wasCancelled
        )
        await loadImages()
    }

    private func persistCompressionRecords() {
        try? stateRepository.saveCompressionRecords(compressionRecords, for: .image)
    }

    private func updateStatus() {
        switch authorizationState {
        case .authorized:
            statusText = "Photos access granted"
        case .limited:
            statusText = "Limited Photos access"
        case .denied:
            statusText = "Photos access denied"
        case .notDetermined:
            statusText = "Photos access required"
        }
    }
}
