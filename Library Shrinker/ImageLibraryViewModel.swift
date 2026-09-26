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

    private let imageStore = PhotoLibraryImageStore()
    private let compressor = ImageCompressor()
    private let metadataCacheStore = ImageMetadataCacheStore()
    private let defaults = UserDefaults.standard
    private let compressionRecordsKey = "imageCompressionRecords"
    private var compressionTask: Task<Void, Never>?

    init() {
        if let data = defaults.data(forKey: compressionRecordsKey),
           let records = try? JSONDecoder().decode([String: CompressionRecord].self, from: data) {
            compressionRecords = records
        } else {
            compressionRecords = [:]
        }
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

        let screenshotAssets = await imageStore.fetchScreenshotAssets()
        let compressedIDs = Set(compressionRecords.values.compactMap(\.compressedAssetID))
        let compressedAssets = await imageStore.fetchAssets(
            withLocalIdentifiers: Array(compressedIDs)
        )
        var assetsByID = Dictionary(
            uniqueKeysWithValues: screenshotAssets.map { ($0.localIdentifier, $0) }
        )
        for asset in compressedAssets {
            assetsByID[asset.localIdentifier] = asset
        }
        let assets = Array(assetsByID.values)
        let existingByID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
        let cacheSnapshot = metadataCacheStore.load()
        let requiresFullScan = cacheSnapshot?.requiresFullScan() ?? true
        var loadedItems: [ImageAssetItem] = []
        var assetsToScan: [PHAsset] = []
        var cacheHitCount = 0
        var scanFailureCount = 0
        loadedItems.reserveCapacity(assets.count)

        for asset in assets {
            if let existingItem = existingByID[asset.localIdentifier],
               !requiresFullScan,
               CachedImageMetadata(item: existingItem).matches(asset) {
                loadedItems.append(existingItem)
            } else if !requiresFullScan,
                      let cached = cacheSnapshot?.records[asset.localIdentifier],
                      cached.matches(asset) {
                loadedItems.append(cached.makeItem(asset: asset))
                cacheHitCount += 1
            } else {
                assetsToScan.append(asset)
            }
        }

        images = loadedItems.sorted { $0.byteSize > $1.byteSize }
        statusText = assetsToScan.isEmpty
            ? "Loaded \(cacheHitCount) cached image(s)"
            : "Reading \(assetsToScan.count) changed image(s)"

        for (index, asset) in assetsToScan.enumerated() {
            do {
                let item = try await imageStore.makeImageItem(from: asset)
                loadedItems.append(item)
                images = loadedItems.sorted { $0.byteSize > $1.byteSize }
            } catch {
                scanFailureCount += 1
            }

            loadingProgress = assetsToScan.isEmpty
                ? 1
                : Double(index + 1) / Double(assetsToScan.count)
            statusText = "Reading changed image \(index + 1) of \(assetsToScan.count)"
        }

        images = loadedItems.sorted { $0.byteSize > $1.byteSize }
        let cacheRecords = Dictionary(uniqueKeysWithValues: images.map {
            ($0.id, CachedImageMetadata(item: $0))
        })
        metadataCacheStore.save(ImageMetadataCacheSnapshot(
            lastFullScanAt: requiresFullScan
                ? Date()
                : (cacheSnapshot?.lastFullScanAt ?? Date()),
            records: cacheRecords
        ))

        selectedImageIDs.formIntersection(Set(images.map(\.id)))
        isLoading = false
        loadingProgress = 1
        if images.isEmpty {
            statusText = "No readable screenshots found"
        } else if scanFailureCount > 0 {
            statusText = "Updated, \(scanFailureCount) image(s) skipped"
        } else if assetsToScan.isEmpty {
            statusText = "Loaded from cache"
        } else {
            statusText = requiresFullScan
                ? "Weekly metadata scan complete"
                : "Updated \(assetsToScan.count) changed image(s)"
        }
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
        do {
            try ContinuousCompressionCoordinator.shared.submit(
                kind: .image,
                itemCount: itemCount,
                expirationAction: { [weak self] in
                    self?.compressionTask?.cancel()
                }
            )
        } catch {
            compressionText = "Background continuation is unavailable: \(error.localizedDescription). Compression will continue while the app remains active."
        }
        compressionTask = Task {
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
        let items = selectedItems.filter {
            targetByteSize(for: $0) < $0.byteSize
        }
        guard !items.isEmpty else {
            ContinuousCompressionCoordinator.shared.complete(kind: .image, success: false)
            return
        }

        isCompressing = true
        isLoading = true
        loadingProgress = 0
        var successCount = 0
        var savedBytes: Int64 = 0
        var failures: [String] = []

        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { break }
            statusText = "Compressing \(index + 1) of \(items.count)"
            compressionText = item.displayName

            do {
                let result = try await compressor.compress(
                    item,
                    targetByteSize: targetByteSize(for: item)
                )
                let record = CompressionRecord(
                    originalAssetID: item.id,
                    compressedAssetID: result.compressedAssetID,
                    originalByteSize: item.byteSize,
                    compressedByteSize: result.compressedByteSize,
                    presetName: "JPEG",
                    compressedAt: Date()
                )
                if let previousID = compressionRecords[item.id]?.compressedAssetID {
                    compressionRecords.removeValue(forKey: previousID)
                }
                compressionRecords[item.id] = record
                if let compressedID = result.compressedAssetID {
                    compressionRecords[compressedID] = record
                }
                persistCompressionRecords()
                successCount += 1
                savedBytes += max(0, item.byteSize - result.compressedByteSize)
                selectedImageIDs.remove(item.id)
            } catch {
                failures.append("\(item.displayName): \(error.localizedDescription)")
            }
            loadingProgress = Double(index + 1) / Double(items.count)
            ContinuousCompressionCoordinator.shared.report(
                kind: .image,
                fractionCompleted: loadingProgress,
                subtitle: "Compressing \(index + 1) of \(items.count)"
            )
        }

        isCompressing = false
        isLoading = false
        compressionTask = nil

        if Task.isCancelled {
            statusText = "Compression cancelled"
        } else {
            statusText = successCount == items.count ? "Compression complete" : "Compression finished"
        }

        let saved = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: savedBytes)
        if failures.isEmpty {
            compressionText = "Saved \(successCount) compressed copy/copies in the Image Shrinker album • about \(saved) saved."
        } else {
            compressionText = "Saved \(successCount) of \(items.count). \(failures.first ?? "")"
        }

        ContinuousCompressionCoordinator.shared.complete(
            kind: .image,
            success: !Task.isCancelled
        )
        await loadImages()
    }

    private func persistCompressionRecords() {
        guard let data = try? JSONEncoder().encode(compressionRecords) else { return }
        defaults.set(data, forKey: compressionRecordsKey)
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
