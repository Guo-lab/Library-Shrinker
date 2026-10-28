import Foundation
import Photos

struct ImageAssetItem: Identifiable {
    let asset: PHAsset
    let byteSize: Int64
    let resourceFilename: String?

    var id: String { asset.localIdentifier }

    var displayName: String {
        resourceFilename ?? "Screenshot"
    }

    var detailText: String {
        "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }

    var fileSizeText: String {
        guard byteSize > 0 else { return "--" }
        return ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: byteSize)
    }

    func estimatedByteSize(ratio: Double) -> Int64 {
        CompressionTargetCalculator.targetByteSize(originalByteSize: byteSize, ratio: ratio)
    }
}

enum ImageCompressionTargetMode: String, CaseIterable, Identifiable {
    case ratio
    case fileSize

    var id: Self { self }

    var title: String {
        switch self {
        case .ratio: "Ratio"
        case .fileSize: "File Size"
        }
    }
}

enum ImageListFilter: String, CaseIterable, Identifiable {
    case all
    case originals
    case compressed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .originals: "Originals"
        case .compressed: "Compressed"
        }
    }
}
