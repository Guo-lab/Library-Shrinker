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

    private let videoStore = PhotoLibraryVideoStore()
    private let compressor = VideoCompressor()
    private let metadataCacheStore = VideoMetadataCacheStore()
    private let defaults = UserDefaults.standard
    private let compressionRecordsKey = "compressionRecords"
    private let locallyDeletedAssetIDsKey = "locallyDeletedAssetIDs"
    private var compressionTask: Task<Void, Never>?
    private var locallyDeletedAssetIDs: Set<String>

    init() {
        if let data = defaults.data(forKey: compressionRecordsKey),
           let records = try? JSONDecoder().decode([String: CompressionRecord].self, from: data) {
            compressionRecords = records
        } else {
            compressionRecords = [:]
        }
        locallyDeletedAssetIDs = Set(
            UserDefaults.standard.stringArray(forKey: "locallyDeletedAssetIDs") ?? []
        )
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

        let fetchedAssets = await videoStore.fetchVideoAssets()
        let rawFetchedIDs = Set(fetchedAssets.map(\.localIdentifier))
        let confirmedAbsentDeletedIDs = locallyDeletedAssetIDs.subtracting(rawFetchedIDs)
        if !confirmedAbsentDeletedIDs.isEmpty {
            locallyDeletedAssetIDs.subtract(confirmedAbsentDeletedIDs)
            persistLocallyDeletedAssetIDs()
        }
        let assets = fetchedAssets.filter { !locallyDeletedAssetIDs.contains($0.localIdentifier) }
        let existingByID = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        let cacheSnapshot = metadataCacheStore.load()
        let requiresFullScan = cacheSnapshot?.requiresFullScan() ?? true
        var loadedVideos: [VideoAssetItem] = []
        var assetsToScan: [PHAsset] = []
        var cacheHitCount = 0

        for asset in assets {
            if let existingItem = existingByID[asset.localIdentifier],
               !requiresFullScan,
               CachedVideoMetadata(item: existingItem).matches(asset) {
                loadedVideos.append(existingItem)
            } else if !requiresFullScan,
                      let cached = cacheSnapshot?.records[asset.localIdentifier],
                      cached.matches(asset) {
                loadedVideos.append(cached.makeItem(asset: asset))
                cacheHitCount += 1
            } else {
                assetsToScan.append(asset)
            }
        }

        videos = loadedVideos.sorted { $0.byteSize > $1.byteSize }
        statusText = assetsToScan.isEmpty
            ? "Loaded \(cacheHitCount) cached video(s)"
            : "Reading \(assetsToScan.count) changed video(s)"

        for (index, asset) in assetsToScan.enumerated() {
            do {
                let item = try await videoStore.makeVideoItem(from: asset)
                loadedVideos.append(item)
                videos = loadedVideos.sorted { $0.byteSize > $1.byteSize }
            } catch {
                scanFailureCount += 1
            }

            loadingProgress = assetsToScan.isEmpty ? 1 : Double(index + 1) / Double(assetsToScan.count)
            statusText = "Reading changed video \(index + 1) of \(assetsToScan.count)"
        }

        let records = Dictionary(uniqueKeysWithValues: videos.map {
            ($0.id, CachedVideoMetadata(item: $0))
        })
        metadataCacheStore.save(VideoMetadataCacheSnapshot(
            lastFullScanAt: requiresFullScan ? Date() : (cacheSnapshot?.lastFullScanAt ?? Date()),
            records: records
        ))

        selectedVideoIDs = selectedVideoIDs.intersection(Set(videos.map(\.id)))
        isLoading = false
        loadingProgress = 1
        if videos.isEmpty {
            statusText = "No readable videos found"
        } else if scanFailureCount > 0 {
            statusText = "Updated, \(scanFailureCount) new video(s) skipped"
        } else if assetsToScan.isEmpty {
            statusText = "Loaded from cache"
        } else {
            statusText = requiresFullScan
                ? "Weekly metadata scan complete"
                : "Updated \(assetsToScan.count) changed video(s)"
        }
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
        do {
            try ContinuousCompressionCoordinator.shared.submit(
                kind: .video,
                itemCount: itemCount,
                expirationAction: { [weak self] in
                    self?.compressionTask?.cancel()
                }
            )
        } catch {
            compressionText = "Background continuation is unavailable: \(error.localizedDescription). Compression will continue while the app remains active."
        }
        compressionTask = Task {
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
        let items = selectedItems
        guard !items.isEmpty else {
            ContinuousCompressionCoordinator.shared.complete(kind: .video, success: false)
            return
        }

        isCompressing = true
        isLoading = true
        loadingProgress = 0
        compressionText = "Checking available storage"

        guard hasEnoughSpace(for: items) else {
            finishCompressionPreparationFailure()
            ContinuousCompressionCoordinator.shared.complete(kind: .video, success: false)
            return
        }

        var successCount = 0
        var processedCount = 0
        var failureMessages: [String] = []
        var savedBytes: Int64 = 0
        var successfulItemIDs: Set<String> = []
        var storageStopMessage: String?

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                break
            }

            if index > 0 {
                let remainingItems = Array(items[index...])
                guard hasEnoughSpace(for: remainingItems) else {
                    storageStopMessage = compressionText
                    break
                }
            }

            do {
                let completedItemsBeforeCurrent = processedCount
                let totalItemCount = items.count
                let viewModel = self
                compressionText = "Compressing \(processedCount + 1) of \(items.count): \(item.displayName)"
                let result = try await compressor.compress(
                    item,
                    using: selectedPreset,
                    targetByteSize: targetByteSize(for: item),
                    progressHandler: { itemProgress in
                        Task { @MainActor [viewModel] in
                            viewModel.updateCompressionProgress(
                                completedItems: completedItemsBeforeCurrent,
                                totalItems: totalItemCount,
                                currentItemProgress: itemProgress
                            )
                        }
                    }
                )
                successCount += 1
                savedBytes += result.savedByteSize
                successfulItemIDs.insert(item.id)
                let record = CompressionRecord(
                    originalAssetID: result.originalAssetID,
                    compressedAssetID: result.compressedAssetID,
                    originalByteSize: result.originalByteSize,
                    compressedByteSize: result.compressedByteSize,
                    presetName: targetDescription(for: item),
                    compressedAt: Date()
                )
                compressionRecords[result.originalAssetID] = record
                if let compressedAssetID = result.compressedAssetID {
                    compressionRecords[compressedAssetID] = record
                }
                persistCompressionRecords()
            } catch is CancellationError {
                compressionText = "Cancelled before changing original videos."
                break
            } catch {
                let message = "\(item.displayName): \(error.localizedDescription)"
                failureMessages.append(message)
                if error.isOutOfDiskSpaceError {
                    storageStopMessage = "Storage became full while processing \(item.displayName)."
                    break
                }
            }

            processedCount += 1
            loadingProgress = Double(processedCount) / Double(items.count)
        }

        selectedVideoIDs.subtract(successfulItemIDs)
        isCompressing = false
        isLoading = false
        compressionTask = nil

        if Task.isCancelled {
            statusText = "Compression cancelled"
            compressionText = completionSummary(
                successCount: successCount,
                totalCount: items.count,
                savedBytes: savedBytes,
                failureMessages: failureMessages,
                ending: "Cancelled. Videos already saved remain in Photos."
            )
        } else if let storageStopMessage {
            statusText = "Compression stopped: low storage"
            compressionText = completionSummary(
                successCount: successCount,
                totalCount: items.count,
                savedBytes: savedBytes,
                failureMessages: failureMessages,
                ending: "\(storageStopMessage) Videos already saved remain in Photos."
            )
        } else {
            statusText = "Compression finished"
            compressionText = completionSummary(
                successCount: successCount,
                totalCount: items.count,
                savedBytes: savedBytes,
                failureMessages: failureMessages
            )
        }
        ContinuousCompressionCoordinator.shared.complete(
            kind: .video,
            success: !Task.isCancelled
        )
    }

    private func hasEnoughSpace(for items: [VideoAssetItem]) -> Bool {
        let targets = items.compactMap { item -> Int64? in
            let target = targetByteSize(for: item)
            return target > 0 && target < item.byteSize ? target : nil
        }

        do {
            let estimate = try DiskSpaceMonitor.estimate(for: targets)
            guard estimate.hasEnoughSpace else {
                let available = ByteCountFormatter.libraryShrinkerFormatter.string(
                    fromByteCount: estimate.availableByteSize
                )
                let required = ByteCountFormatter.libraryShrinkerFormatter.string(
                    fromByteCount: estimate.requiredByteSize
                )
                compressionText = "Not enough storage: about \(required) required, \(available) available."
                return false
            }
        } catch {
            // If iOS cannot report capacity, let the export proceed and rely on its error handling.
        }

        return true
    }

    private func finishCompressionPreparationFailure() {
        isCompressing = false
        isLoading = false
        loadingProgress = 0
        compressionTask = nil
        statusText = "Compression not started: low storage"
    }

    private func completionSummary(
        successCount: Int,
        totalCount: Int,
        savedBytes: Int64,
        failureMessages: [String],
        ending: String? = nil
    ) -> String {
        let saved = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: savedBytes)
        var parts = ["Compressed \(successCount) of \(totalCount), saved \(saved)."]

        if !failureMessages.isEmpty {
            parts.append("Failed: \(failureMessages.joined(separator: "; "))")
        }
        if let ending {
            parts.append(ending)
        }

        return parts.joined(separator: " ")
    }

    private func updateCompressionProgress(
        completedItems: Int,
        totalItems: Int,
        currentItemProgress: Double
    ) {
        guard totalItems > 0 else {
            loadingProgress = 0
            return
        }

        let clampedProgress = min(max(currentItemProgress, 0), 1)
        loadingProgress = (Double(completedItems) + clampedProgress) / Double(totalItems)
        ContinuousCompressionCoordinator.shared.report(
            kind: .video,
            fractionCompleted: loadingProgress,
            subtitle: "Compressing \(completedItems + 1) of \(totalItems)"
        )
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
        guard let data = try? JSONEncoder().encode(compressionRecords) else {
            return
        }

        defaults.set(data, forKey: compressionRecordsKey)
    }

    private func persistLocallyDeletedAssetIDs() {
        defaults.set(Array(locallyDeletedAssetIDs), forKey: locallyDeletedAssetIDsKey)
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
