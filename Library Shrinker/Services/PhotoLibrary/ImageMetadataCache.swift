import Foundation
import Photos

struct CachedImageMetadata: Codable, Equatable {
    let assetID: String
    let byteSize: Int64
    let resourceFilename: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let modificationTimestamp: TimeInterval?

    init(item: ImageAssetItem) {
        assetID = item.id
        byteSize = item.byteSize
        resourceFilename = item.resourceFilename
        pixelWidth = item.asset.pixelWidth
        pixelHeight = item.asset.pixelHeight
        modificationTimestamp = item.asset.modificationDate?.timeIntervalSinceReferenceDate
    }

    func matches(_ asset: PHAsset) -> Bool {
        assetID == asset.localIdentifier
            && pixelWidth == asset.pixelWidth
            && pixelHeight == asset.pixelHeight
            && modificationTimestamp == asset.modificationDate?.timeIntervalSinceReferenceDate
    }

    func makeItem(asset: PHAsset) -> ImageAssetItem {
        ImageAssetItem(
            asset: asset,
            byteSize: byteSize,
            resourceFilename: resourceFilename
        )
    }
}

struct ImageMetadataCacheSnapshot: Codable {
    static let fullScanInterval: TimeInterval = 7 * 24 * 60 * 60

    let lastFullScanAt: Date
    let records: [String: CachedImageMetadata]

    func requiresFullScan(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastFullScanAt) >= Self.fullScanInterval
    }
}

struct ImageMetadataCacheStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryShrinker", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("image-metadata-cache.json")
    }

    func load() -> ImageMetadataCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ImageMetadataCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: ImageMetadataCacheSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
