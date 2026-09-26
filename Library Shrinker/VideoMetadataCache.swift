import Foundation
import Photos

struct CachedVideoMetadata: Codable, Equatable {
    let assetID: String
    let byteSize: Int64
    let resourceFilename: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let modificationTimestamp: TimeInterval?

    init(item: VideoAssetItem) {
        assetID = item.id
        byteSize = item.byteSize
        resourceFilename = item.resourceFilename
        pixelWidth = item.asset.pixelWidth
        pixelHeight = item.asset.pixelHeight
        duration = item.asset.duration
        modificationTimestamp = item.asset.modificationDate?.timeIntervalSinceReferenceDate
    }

    func matches(_ asset: PHAsset) -> Bool {
        assetID == asset.localIdentifier
            && pixelWidth == asset.pixelWidth
            && pixelHeight == asset.pixelHeight
            && abs(duration - asset.duration) < 0.001
            && modificationTimestamp == asset.modificationDate?.timeIntervalSinceReferenceDate
    }

    func makeItem(asset: PHAsset) -> VideoAssetItem {
        VideoAssetItem(
            asset: asset,
            byteSize: byteSize,
            resourceFilename: resourceFilename
        )
    }
}

struct VideoMetadataCacheSnapshot: Codable {
    static let fullScanInterval: TimeInterval = 7 * 24 * 60 * 60

    let lastFullScanAt: Date
    let records: [String: CachedVideoMetadata]

    func requiresFullScan(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastFullScanAt) >= Self.fullScanInterval
    }
}

struct VideoMetadataCacheStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryShrinker", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("video-metadata-cache.json")
    }

    func load() -> VideoMetadataCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(VideoMetadataCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: VideoMetadataCacheSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
