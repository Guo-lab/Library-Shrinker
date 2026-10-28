import Foundation

enum LibraryMediaKind {
    case video
    case image
}

protocol LibraryStateRepository {
    func compressionRecords(for kind: LibraryMediaKind) -> [String: CompressionRecord]
    func saveCompressionRecords(
        _ records: [String: CompressionRecord],
        for kind: LibraryMediaKind
    ) throws
    func locallyDeletedVideoAssetIDs() -> Set<String>
    func saveLocallyDeletedVideoAssetIDs(_ assetIDs: Set<String>)
}

struct UserDefaultsLibraryStateRepository: LibraryStateRepository {
    private enum Key {
        static let videoCompressionRecords = "compressionRecords"
        static let imageCompressionRecords = "imageCompressionRecords"
        static let locallyDeletedVideoAssetIDs = "locallyDeletedAssetIDs"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func compressionRecords(for kind: LibraryMediaKind) -> [String: CompressionRecord] {
        let key = compressionRecordsKey(for: kind)
        guard let data = defaults.data(forKey: key),
              let records = try? decoder.decode([String: CompressionRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    func saveCompressionRecords(
        _ records: [String: CompressionRecord],
        for kind: LibraryMediaKind
    ) throws {
        let data = try encoder.encode(records)
        defaults.set(data, forKey: compressionRecordsKey(for: kind))
    }

    func locallyDeletedVideoAssetIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.locallyDeletedVideoAssetIDs) ?? [])
    }

    func saveLocallyDeletedVideoAssetIDs(_ assetIDs: Set<String>) {
        defaults.set(Array(assetIDs), forKey: Key.locallyDeletedVideoAssetIDs)
    }

    private func compressionRecordsKey(for kind: LibraryMediaKind) -> String {
        switch kind {
        case .video:
            Key.videoCompressionRecords
        case .image:
            Key.imageCompressionRecords
        }
    }
}
