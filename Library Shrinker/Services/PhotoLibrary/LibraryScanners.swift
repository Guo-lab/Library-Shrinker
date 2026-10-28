import Foundation
import Photos

struct ImageScanUpdate {
    let items: [ImageAssetItem]
    let progress: Double
    let statusText: String
}

struct ImageScanResult {
    let items: [ImageAssetItem]
    let failureCount: Int
    let scannedCount: Int
    let requiredFullScan: Bool

    var statusText: String {
        if items.isEmpty {
            return "No readable screenshots found"
        }
        if failureCount > 0 {
            return "Updated, \(failureCount) image(s) skipped"
        }
        if scannedCount == 0 {
            return "Loaded from cache"
        }
        return requiredFullScan
            ? "Weekly metadata scan complete"
            : "Updated \(scannedCount) changed image(s)"
    }
}

@MainActor
final class ImageLibraryScanner {
    private let imageStore: PhotoLibraryImageStore
    private let cacheStore: ImageMetadataCacheStore

    init(
        imageStore: PhotoLibraryImageStore,
        cacheStore: ImageMetadataCacheStore
    ) {
        self.imageStore = imageStore
        self.cacheStore = cacheStore
    }

    func scan(
        existingItems: [ImageAssetItem],
        compressionRecords: [String: CompressionRecord],
        onUpdate: (ImageScanUpdate) -> Void
    ) async -> ImageScanResult {
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
        let existingByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        let cacheSnapshot = cacheStore.load()
        let requiresFullScan = cacheSnapshot?.requiresFullScan() ?? true
        var loadedItems: [ImageAssetItem] = []
        var assetsToScan: [PHAsset] = []
        var cacheHitCount = 0
        var failureCount = 0
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

        onUpdate(ImageScanUpdate(
            items: sorted(loadedItems),
            progress: 0,
            statusText: assetsToScan.isEmpty
                ? "Loaded \(cacheHitCount) cached image(s)"
                : "Reading \(assetsToScan.count) changed image(s)"
        ))

        for (index, asset) in assetsToScan.enumerated() {
            do {
                loadedItems.append(try await imageStore.makeImageItem(from: asset))
            } catch {
                failureCount += 1
            }

            let progress = Double(index + 1) / Double(assetsToScan.count)
            onUpdate(ImageScanUpdate(
                items: sorted(loadedItems),
                progress: progress,
                statusText: "Reading changed image \(index + 1) of \(assetsToScan.count)"
            ))
        }

        let items = sorted(loadedItems)
        let records = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, CachedImageMetadata(item: $0))
        })
        cacheStore.save(ImageMetadataCacheSnapshot(
            lastFullScanAt: requiresFullScan
                ? Date()
                : (cacheSnapshot?.lastFullScanAt ?? Date()),
            records: records
        ))

        return ImageScanResult(
            items: items,
            failureCount: failureCount,
            scannedCount: assetsToScan.count,
            requiredFullScan: requiresFullScan
        )
    }

    private func sorted(_ items: [ImageAssetItem]) -> [ImageAssetItem] {
        items.sorted { $0.byteSize > $1.byteSize }
    }
}

struct VideoScanUpdate {
    let items: [VideoAssetItem]
    let progress: Double
    let statusText: String
}

struct VideoScanResult {
    let items: [VideoAssetItem]
    let failureCount: Int
    let scannedCount: Int
    let requiredFullScan: Bool
    let remainingLocallyDeletedAssetIDs: Set<String>

    var statusText: String {
        if items.isEmpty {
            return "No readable videos found"
        }
        if failureCount > 0 {
            return "Updated, \(failureCount) new video(s) skipped"
        }
        if scannedCount == 0 {
            return "Loaded from cache"
        }
        return requiredFullScan
            ? "Weekly metadata scan complete"
            : "Updated \(scannedCount) changed video(s)"
    }
}

@MainActor
final class VideoLibraryScanner {
    private let videoStore: PhotoLibraryVideoStore
    private let cacheStore: VideoMetadataCacheStore

    init(
        videoStore: PhotoLibraryVideoStore,
        cacheStore: VideoMetadataCacheStore
    ) {
        self.videoStore = videoStore
        self.cacheStore = cacheStore
    }

    func scan(
        existingItems: [VideoAssetItem],
        locallyDeletedAssetIDs: Set<String>,
        onUpdate: (VideoScanUpdate) -> Void
    ) async -> VideoScanResult {
        let fetchedAssets = await videoStore.fetchVideoAssets()
        let fetchedIDs = Set(fetchedAssets.map(\.localIdentifier))
        let remainingDeletedIDs = locallyDeletedAssetIDs.intersection(fetchedIDs)
        let assets = fetchedAssets.filter {
            !remainingDeletedIDs.contains($0.localIdentifier)
        }
        let existingByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        let cacheSnapshot = cacheStore.load()
        let requiresFullScan = cacheSnapshot?.requiresFullScan() ?? true
        var loadedItems: [VideoAssetItem] = []
        var assetsToScan: [PHAsset] = []
        var cacheHitCount = 0
        var failureCount = 0

        for asset in assets {
            if let existingItem = existingByID[asset.localIdentifier],
               !requiresFullScan,
               CachedVideoMetadata(item: existingItem).matches(asset) {
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

        onUpdate(VideoScanUpdate(
            items: sorted(loadedItems),
            progress: 0,
            statusText: assetsToScan.isEmpty
                ? "Loaded \(cacheHitCount) cached video(s)"
                : "Reading \(assetsToScan.count) changed video(s)"
        ))

        for (index, asset) in assetsToScan.enumerated() {
            do {
                loadedItems.append(try await videoStore.makeVideoItem(from: asset))
            } catch {
                failureCount += 1
            }

            let progress = Double(index + 1) / Double(assetsToScan.count)
            onUpdate(VideoScanUpdate(
                items: sorted(loadedItems),
                progress: progress,
                statusText: "Reading changed video \(index + 1) of \(assetsToScan.count)"
            ))
        }

        let items = sorted(loadedItems)
        let records = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, CachedVideoMetadata(item: $0))
        })
        cacheStore.save(VideoMetadataCacheSnapshot(
            lastFullScanAt: requiresFullScan
                ? Date()
                : (cacheSnapshot?.lastFullScanAt ?? Date()),
            records: records
        ))

        return VideoScanResult(
            items: items,
            failureCount: failureCount,
            scannedCount: assetsToScan.count,
            requiredFullScan: requiresFullScan,
            remainingLocallyDeletedAssetIDs: remainingDeletedIDs
        )
    }

    private func sorted(_ items: [VideoAssetItem]) -> [VideoAssetItem] {
        items.sorted { $0.byteSize > $1.byteSize }
    }
}
