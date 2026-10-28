//
//  VideoLibraryViewModel.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import Foundation
import Observation
import Photos

@MainActor
@Observable
final class VideoLibraryViewModel {
    var videos: [VideoAssetItem] = []
    var selectedVideoIDs: Set<String> = []
    var selectedFilter: VideoListFilter = .all
    var selectedBitRateFilter: VideoBitRateFilter = .all
    var compressionRecords: [String: CompressionRecord]
    var selectedPreset: VideoCompressionPreset = .hevc
    var selectedProfile: CompressionProfile = .medium
    var targetMode: CompressionTargetMode = .ratio
    var targetSizeRatio = 0.35
    var targetMegabitsPerSecond = 5.0
    var authorizationState: PhotoLibraryAccessState = .notDetermined
    var isLoading = false
    var isCompressing = false
    var loadingProgress = 0.0
    var statusText = "Checking Photos access"
    var compressionText: String?
    var scanFailureCount = 0

    private let videoStore: PhotoLibraryVideoStore
    private let compressionWorkflow: VideoCompressionWorkflow
    private let scanner: VideoLibraryScanner
    private let stateRepository: any LibraryStateRepository
    private var compressionTask: Task<Void, Never>?
    private var locallyDeletedAssetIDs: Set<String>

    init(
        videoStore: PhotoLibraryVideoStore? = nil,
        compressor: VideoCompressor? = nil,
        metadataCacheStore: VideoMetadataCacheStore? = nil,
        stateRepository: (any LibraryStateRepository)? = nil,
        scanner: VideoLibraryScanner? = nil
    ) {
        let repository = stateRepository ?? UserDefaultsLibraryStateRepository()
        let resolvedVideoStore = videoStore ?? PhotoLibraryVideoStore()
        let resolvedCacheStore = metadataCacheStore ?? VideoMetadataCacheStore()
        let resolvedCompressor = compressor ?? VideoCompressor()
        self.videoStore = resolvedVideoStore
        self.compressionWorkflow = VideoCompressionWorkflow(
            compressor: resolvedCompressor,
            repository: repository
        )
        self.scanner = scanner ?? VideoLibraryScanner(
            videoStore: resolvedVideoStore,
            cacheStore: resolvedCacheStore
        )
        self.stateRepository = repository
        compressionRecords = repository.compressionRecords(for: .video)
        locallyDeletedAssetIDs = repository.locallyDeletedVideoAssetIDs()
    }

    func reloadAfterBackupImport() async {
        compressionRecords = stateRepository.compressionRecords(for: .video)
        locallyDeletedAssetIDs = stateRepository.locallyDeletedVideoAssetIDs()
        await loadVideos()
    }

    var needsAuthorization: Bool {
        authorizationState == .notDetermined || authorizationState == .denied
    }

    var emptyStateMessage: String {
        if needsAuthorization {
            return "Allow Photos access to scan videos."
        }

        if isLoading {
            return "Scanning your video library."
        }

        return "No videos were found in the current Photos selection."
    }

    var statusIconName: String {
        switch authorizationState {
        case .authorized:
            "checkmark.circle"
        case .limited:
            "exclamationmark.circle"
        case .denied:
            "lock.circle"
        case .notDetermined:
            "photo.circle"
        }
    }

    var selectedItems: [VideoAssetItem] {
        videos.filter { selectedVideoIDs.contains($0.id) }
    }

    var filteredVideoEntries: [VideoListEntry] {
        let roleFiltered: [VideoAssetItem] = switch selectedFilter {
        case .all:
            videos
        case .originals:
            videos.filter { compressionRole(for: $0) != .compressedCopy }
        case .compressed:
            videos.filter { compressionRole(for: $0) == .compressedCopy }
        }
        let bitrateFiltered = roleFiltered
            .filter { selectedBitRateFilter.contains(bitsPerSecond: $0.bitRate) }

        guard selectedFilter == .all else {
            return bitrateFiltered
                .sorted { $0.byteSize > $1.byteSize }
                .map { VideoListEntry(video: $0, isCompressedChild: false) }
        }

        let visibleIDs = Set(bitrateFiltered.map(\.id))
        let compressedByOriginalID = Dictionary(grouping: bitrateFiltered.filter {
            compressionRole(for: $0) == .compressedCopy
        }) { item in
            compressionRecords[item.id]?.originalAssetID ?? ""
        }
        let roots = bitrateFiltered.filter { item in
            guard compressionRole(for: item) == .compressedCopy,
                  let originalID = compressionRecords[item.id]?.originalAssetID else {
                return true
            }
            return !visibleIDs.contains(originalID)
        }.sorted { $0.byteSize > $1.byteSize }

        return roots.flatMap { root in
            var entries = [VideoListEntry(video: root, isCompressedChild: false)]
            guard compressionRole(for: root) != .compressedCopy else { return entries }
            let children = (compressedByOriginalID[root.id] ?? [])
                .sorted { $0.byteSize > $1.byteSize }
            entries.append(contentsOf: children.map {
                VideoListEntry(video: $0, isCompressedChild: true)
            })
            return entries
        }
    }

    var filteredVideos: [VideoAssetItem] {
        filteredVideoEntries.map(\.video)
    }

    func compressionRole(for item: VideoAssetItem) -> VideoCompressionRole {
        guard let record = compressionRecords[item.id] else {
            return .original
        }

        if record.compressedAssetID == item.id {
            return .compressedCopy
        }

        if record.originalAssetID == item.id,
           let compressedID = record.compressedAssetID,
           videos.contains(where: { $0.id == compressedID }) {
            return .originalWithCompressedCopy
        }

        return .original
    }

    func canDeleteOriginal(_ item: VideoAssetItem) -> Bool {
        compressionRole(for: item) == .originalWithCompressedCopy
    }

    func canDeleteCompressedCopy(_ item: VideoAssetItem) -> Bool {
        compressionRole(for: item) == .compressedCopy
    }

    var deletableSelectedOriginals: [VideoAssetItem] {
        selectedItems.filter(canDeleteOriginal)
    }

    func deleteOriginal(_ item: VideoAssetItem) async {
        guard canDeleteOriginal(item) else {
            compressionText = "The compressed copy must be present before the original can be deleted."
            return
        }

        do {
            try await videoStore.deleteAsset(item.asset)
            locallyDeletedAssetIDs.insert(item.id)
            persistLocallyDeletedAssetIDs()
            videos.removeAll { $0.id == item.id }
            selectedVideoIDs.remove(item.id)
            compressionRecords.removeValue(forKey: item.id)
            persistCompressionRecords()
            statusText = "Original moved to Recently Deleted"
            compressionText = "The compressed copy remains in Photos. You can recover the original from Recently Deleted."
        } catch {
            statusText = "Could not delete original"
            compressionText = error.localizedDescription
        }
    }

    func deleteCompressedCopy(_ item: VideoAssetItem) async {
        guard canDeleteCompressedCopy(item) else {
            compressionText = "This video is not a recognized compressed copy."
            return
        }

        do {
            let record = compressionRecords[item.id]
            try await videoStore.deleteAsset(item.asset)
            locallyDeletedAssetIDs.insert(item.id)
            persistLocallyDeletedAssetIDs()
            videos.removeAll { $0.id == item.id }
            selectedVideoIDs.remove(item.id)
            compressionRecords.removeValue(forKey: item.id)

            if let originalID = record?.originalAssetID {
                refreshOriginalCompressionRecord(for: originalID)
            }
            persistCompressionRecords()
            statusText = "Compressed copy moved to Recently Deleted"
            compressionText = "The original video remains in Photos."
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
            try await videoStore.deleteAssets(items.map(\.asset))
            let deletedIDs = Set(items.map(\.id))
            locallyDeletedAssetIDs.formUnion(deletedIDs)
            persistLocallyDeletedAssetIDs()
            videos.removeAll { deletedIDs.contains($0.id) }
            selectedVideoIDs.subtract(deletedIDs)
            for id in deletedIDs {
                compressionRecords.removeValue(forKey: id)
            }
            persistCompressionRecords()
            statusText = "\(items.count) originals moved to Recently Deleted"
            compressionText = "Their compressed copies remain in Photos. The originals can still be recovered from Recently Deleted."
        } catch {
            statusText = "Could not delete selected originals"
            compressionText = error.localizedDescription
        }
    }

    var selectionSizeText: String {
        let totalSize = selectedItems.reduce(Int64(0)) { $0 + $1.byteSize }
        let estimatedSize = selectedItems.reduce(Int64(0)) { $0 + targetByteSize(for: $1) }
        let from = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: totalSize)
        let to = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: estimatedSize)
        return "\(from) → ~\(to)"
    }

    var targetPercentageText: String {
        "\(Int((targetSizeRatio * 100).rounded()))%"
    }

    var targetRatioSliderPosition: Double {
        get {
            CompressionTargetCalculator.sliderPosition(for: targetSizeRatio)
        }
        set {
            updateCustomTargetSizeRatio(
                CompressionTargetCalculator.ratio(forSliderPosition: newValue)
            )
        }
    }

    func selectProfile(_ profile: CompressionProfile) {
        selectedProfile = profile
        targetMode = .ratio
        if let ratio = profile.targetSizeRatio {
            targetSizeRatio = ratio
        }
    }

    func updateCustomTargetSizeRatio(_ ratio: Double) {
        selectedProfile = .custom
        targetMode = .ratio
        targetSizeRatio = min(max(ratio, 0.01), 1)
    }

    func selectTargetMode(_ mode: CompressionTargetMode) {
        targetMode = mode
        if mode == .bitRate {
            selectedProfile = .custom
        }
    }

    func targetByteSize(for item: VideoAssetItem) -> Int64 {
        switch targetMode {
        case .ratio:
            return CompressionTargetCalculator.targetByteSize(
                originalByteSize: item.byteSize,
                ratio: targetSizeRatio
            )
        case .bitRate:
            return CompressionTargetCalculator.targetByteSize(
                megabitsPerSecond: targetMegabitsPerSecond,
                duration: item.asset.duration
            )
        }
    }

    func targetDescription(for item: VideoAssetItem) -> String {
        switch targetMode {
        case .ratio:
            return "\(selectedPreset.title) \(targetPercentageText)"
        case .bitRate:
            let bitRate = targetMegabitsPerSecond.formatted(
                .number.precision(.fractionLength(0...1))
            )
            return "\(selectedPreset.title) \(bitRate) Mbps"
        }
    }

    var canCompress: Bool {
        selectedItems.contains { item in
            let target = targetByteSize(for: item)
            return target > 0 && target < item.byteSize
        } && !isLoading && !isCompressing
    }

    var lowBitRateWarning: String? {
        let riskyItems = selectedItems.filter { item in
            let target = targetByteSize(for: item)
            guard target > 0, item.asset.duration > 0 else { return false }
            let targetMbps = Double(target) * 8 / item.asset.duration / 1_000_000
            let minimum = CompressionTargetCalculator.recommendedMinimumMegabitsPerSecond(
                pixelWidth: item.asset.pixelWidth,
                pixelHeight: item.asset.pixelHeight,
                usesHEVC: selectedPreset == .hevc
            )
            return targetMbps < minimum
        }

        guard !riskyItems.isEmpty else { return nil }
        let examples = riskyItems.prefix(3).map(\.displayName).joined(separator: ", ")
        let remainder = riskyItems.count > 3 ? " and \(riskyItems.count - 3) more" : ""
        return "The target bitrate is unusually low for the resolution of \(riskyItems.count) selected video(s): \(examples)\(remainder). Compression may cause blur, blocking, or loss of fine detail. Continue anyway?"
    }

    func start() async {
        authorizationState = videoStore.authorizationState()
        updateStatusForAuthorization()

        if authorizationState.canReadAndWrite {
            await loadVideos()
        }
    }

    func requestAccessAndLoad() async {
        authorizationState = await videoStore.requestAuthorization()
        updateStatusForAuthorization()

        if authorizationState.canReadAndWrite {
            await loadVideos()
        }
    }

    func loadVideos() async {
        guard authorizationState.canReadAndWrite else {
            updateStatusForAuthorization()
            return
        }

        isLoading = true
        loadingProgress = 0
        compressionText = nil
        scanFailureCount = 0
        statusText = "Scanning video sizes"
        let result = await scanner.scan(
            existingItems: videos,
            locallyDeletedAssetIDs: locallyDeletedAssetIDs
        ) { [weak self] update in
            self?.videos = update.items
            self?.loadingProgress = update.progress
            self?.statusText = update.statusText
        }
        videos = result.items
        scanFailureCount = result.failureCount
        if locallyDeletedAssetIDs != result.remainingLocallyDeletedAssetIDs {
            locallyDeletedAssetIDs = result.remainingLocallyDeletedAssetIDs
            persistLocallyDeletedAssetIDs()
        }
        selectedVideoIDs = selectedVideoIDs.intersection(Set(videos.map(\.id)))
        isLoading = false
        loadingProgress = 1
        statusText = result.statusText
    }

    func toggleSelection(for video: VideoAssetItem) {
        if selectedVideoIDs.contains(video.id) {
            selectedVideoIDs.remove(video.id)
        } else {
            selectedVideoIDs.insert(video.id)
        }
    }

    func startCompression() {
        guard canCompress else {
            return
        }

        compressionTask?.cancel()
        let itemCount = selectedItems.count
        compressionText = "Waiting for background processing"
        compressionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await ContinuousCompressionCoordinator.shared.begin(
                    kind: .video,
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
            await compressSelectedVideos()
        }
    }

    func cancelCompression() {
        compressionTask?.cancel()
        ContinuousCompressionCoordinator.shared.cancel(kind: .video)
        compressionTask = nil
        isCompressing = false
        isLoading = false
        loadingProgress = 0
        statusText = "Compression cancelled"
        compressionText = "Cancelled before changing original videos."
    }

    private func compressSelectedVideos() async {
        let workItems = selectedItems.compactMap { item -> VideoCompressionWorkItem? in
            let target = targetByteSize(for: item)
            guard target > 0, target < item.byteSize else { return nil }
            return VideoCompressionWorkItem(
                item: item,
                targetByteSize: target,
                targetDescription: targetDescription(for: item)
            )
        }
        guard !workItems.isEmpty else {
            ContinuousCompressionCoordinator.shared.complete(kind: .video, success: false)
            return
        }

        isCompressing = true
        isLoading = true
        loadingProgress = 0
        compressionText = "Checking available storage"
        let outcome = await compressionWorkflow.run(
            workItems: workItems,
            preset: selectedPreset,
            existingRecords: compressionRecords
        ) { [weak self] update in
            self?.loadingProgress = update.progress
            self?.statusText = update.statusText
            self?.compressionText = update.detailText
        }
        compressionRecords = outcome.records
        selectedVideoIDs.subtract(outcome.successfulItemIDs)
        isCompressing = false
        isLoading = false
        compressionTask = nil
        loadingProgress = outcome.preparationFailed ? 0 : loadingProgress
        ContinuousCompressionCoordinator.shared.complete(
            kind: .video,
            success: !outcome.wasCancelled && !outcome.preparationFailed
        )

        if !outcome.successfulItemIDs.isEmpty {
            await loadVideos()
        }
        statusText = outcome.statusText
        compressionText = outcome.detailText
    }

    private func updateStatusForAuthorization() {
        switch authorizationState {
        case .authorized:
            statusText = "Photos access granted"
        case .limited:
            statusText = "Limited Photos access"
        case .denied:
            statusText = "Photos access denied"
        case .notDetermined:
            statusText = "Photos access needed"
        }
    }

    private func persistCompressionRecords() {
        try? stateRepository.saveCompressionRecords(compressionRecords, for: .video)
    }

    private func persistLocallyDeletedAssetIDs() {
        stateRepository.saveLocallyDeletedVideoAssetIDs(locallyDeletedAssetIDs)
    }

    private func refreshOriginalCompressionRecord(for originalID: String) {
        let remainingRecord = compressionRecords.values
            .filter { record in
                record.originalAssetID == originalID
                    && record.compressedAssetID != nil
                    && videos.contains { $0.id == record.compressedAssetID }
            }
            .max { $0.compressedAt < $1.compressedAt }

        if let remainingRecord {
            compressionRecords[originalID] = remainingRecord
        } else {
            compressionRecords.removeValue(forKey: originalID)
        }
    }
}
