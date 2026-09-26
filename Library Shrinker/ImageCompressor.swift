import Foundation
import Photos
import UIKit

struct ImageCompressionResult {
    let compressedAssetID: String?
    let compressedByteSize: Int64
}

final class ImageCompressor {
    private let albumTitle = "Image Shrinker"

    func compress(_ item: ImageAssetItem, targetByteSize: Int64) async throws -> ImageCompressionResult {
        let originalData = try await PhotoLibraryImageStore.imageData(for: item.asset)
        guard let image = UIImage(data: originalData) else {
            throw ImageCompressorError.cannotDecodeImage
        }

        guard targetByteSize > 0, targetByteSize < originalData.count else {
            throw ImageCompressorError.invalidTargetSize
        }
        let compressedData = try Self.jpegData(for: image, targetByteSize: targetByteSize)
        guard compressedData.count < originalData.count else {
            throw ImageCompressorError.outputNotSmaller
        }

        let assetID = try await save(
            compressedData,
            originalAsset: item.asset,
            originalFilename: item.resourceFilename
        )
        return ImageCompressionResult(
            compressedAssetID: assetID,
            compressedByteSize: Int64(compressedData.count)
        )
    }

    nonisolated private static func jpegData(for image: UIImage, targetByteSize: Int64) throws -> Data {
        var lowerQuality = 0.05
        var upperQuality = 1.0
        var bestData: Data?

        for _ in 0..<9 {
            let quality = (lowerQuality + upperQuality) / 2
            guard let candidate = image.jpegData(compressionQuality: quality) else {
                throw ImageCompressorError.cannotEncodeImage
            }

            if candidate.count <= targetByteSize {
                bestData = candidate
                lowerQuality = quality
            } else {
                upperQuality = quality
            }
        }

        if let bestData {
            return bestData
        }
        guard let minimumData = image.jpegData(compressionQuality: 0.05) else {
            throw ImageCompressorError.cannotEncodeImage
        }
        return minimumData
    }

    private func save(
        _ data: Data,
        originalAsset: PHAsset,
        originalFilename: String?
    ) async throws -> String? {
        let existingAlbum = fetchAlbum()
        let originalAlbums = fetchWritableAlbums(containing: originalAsset)
        var createdAssetID: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = Self.compressedFilename(from: originalFilename)
            request.addResource(with: .photo, data: data, options: options)
            request.creationDate = originalAsset.creationDate
            request.location = originalAsset.location
            request.isFavorite = originalAsset.isFavorite
            request.isHidden = originalAsset.isHidden
            createdAssetID = request.placeholderForCreatedAsset?.localIdentifier

            guard let placeholder = request.placeholderForCreatedAsset else { return }
            for album in originalAlbums where album.localIdentifier != existingAlbum?.localIdentifier {
                PHAssetCollectionChangeRequest(for: album)?
                    .addAssets([placeholder] as NSArray)
            }
            if let existingAlbum {
                PHAssetCollectionChangeRequest(for: existingAlbum)?
                    .addAssets([placeholder] as NSArray)
            } else {
                let albumRequest = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(withTitle: self.albumTitle)
                albumRequest.addAssets([placeholder] as NSArray)
            }
        }

        return createdAssetID
    }

    private func fetchWritableAlbums(containing asset: PHAsset) -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollectionsContaining(
            asset,
            with: .album,
            options: nil
        )
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { album, _, _ in
            if album.canPerform(.addContent) {
                albums.append(album)
            }
        }
        return albums
    }

    nonisolated private static func compressedFilename(from originalFilename: String?) -> String {
        let baseName = (originalFilename as NSString?)?.deletingPathExtension ?? "Screenshot"
        return "\(baseName)-shrunk.jpg"
    }

    private func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        ).firstObject
    }
}

enum ImageCompressorError: LocalizedError {
    case cannotDecodeImage
    case cannotEncodeImage
    case invalidTargetSize
    case outputNotSmaller

    var errorDescription: String? {
        switch self {
        case .cannotDecodeImage:
            "The screenshot could not be decoded."
        case .cannotEncodeImage:
            "The screenshot could not be compressed."
        case .invalidTargetSize:
            "The target size must be smaller than the original screenshot."
        case .outputNotSmaller:
            "The compressed image was not smaller, so it was not saved."
        }
    }
}
