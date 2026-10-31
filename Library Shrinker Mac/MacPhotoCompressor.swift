import AppKit
import AVFoundation
import Photos

enum MacVideoCodec: String, CaseIterable, Identifiable {
    case hevc
    case h264

    var id: Self { self }

    var title: String {
        switch self {
        case .hevc: "HEVC"
        case .h264: "H.264"
        }
    }

    var exportPresetName: String {
        switch self {
        case .hevc: AVAssetExportPresetHEVCHighestQuality
        case .h264: AVAssetExportPresetHighestQuality
        }
    }
}

enum MacPhotoCompressor {
    static func compress(
        identifier: String,
        section: MacLibrarySection,
        targetRatio: Double,
        videoCodec: MacVideoCodec
    ) async throws {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            throw MacCompressionError.assetUnavailable
        }

        switch section {
        case .videos:
            try await compressVideo(asset, targetRatio: targetRatio, codec: videoCodec)
        case .screenshots:
            try await compressImage(asset, targetRatio: targetRatio)
        }
    }

    private static func compressVideo(
        _ photoAsset: PHAsset,
        targetRatio: Double,
        codec: MacVideoCodec
    ) async throws {
        let asset = try await requestAVAsset(for: photoAsset)
        guard let urlAsset = asset as? AVURLAsset else {
            throw MacCompressionError.originalFileUnavailable
        }
        let originalSize = try urlAsset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let targetSize = Int64(Double(originalSize) * targetRatio)
        guard originalSize > 0, targetSize > 0 else {
            throw MacCompressionError.originalFileUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-shrinker-mac-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard await AVAssetExportSession.compatibility(
            ofExportPreset: codec.exportPresetName,
            with: asset,
            outputFileType: .mp4
        ) else {
            throw MacCompressionError.incompatibleVideo
        }
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: codec.exportPresetName
        ) else {
            throw MacCompressionError.incompatibleVideo
        }

        session.fileLengthLimit = targetSize
        session.shouldOptimizeForNetworkUse = true
        session.canPerformMultiplePassesOverSourceMediaData = false
        try await session.export(to: outputURL, as: .mp4)

        let compressedSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard compressedSize > 0, compressedSize < originalSize else {
            throw MacCompressionError.outputNotSmaller
        }
        try await saveResource(
            at: outputURL,
            type: .video,
            originalAsset: photoAsset
        )
    }

    private static func compressImage(
        _ photoAsset: PHAsset,
        targetRatio: Double
    ) async throws {
        let originalData = try await requestImageData(for: photoAsset)
        guard let representation = NSBitmapImageRep(data: originalData) else {
            throw MacCompressionError.imageDecodeFailed
        }
        let targetSize = max(1, Int(Double(originalData.count) * targetRatio))
        var lowerBound = 0.02
        var upperBound = 0.95
        var bestData: Data?

        for _ in 0..<9 {
            let quality = (lowerBound + upperBound) / 2
            guard let data = representation.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ) else {
                throw MacCompressionError.imageEncodeFailed
            }
            if data.count <= targetSize {
                bestData = data
                lowerBound = quality
            } else {
                upperBound = quality
            }
        }

        guard let compressedData = bestData, compressedData.count < originalData.count else {
            throw MacCompressionError.outputNotSmaller
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-shrinker-mac-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try compressedData.write(to: outputURL, options: .atomic)
        try await saveResource(
            at: outputURL,
            type: .photo,
            originalAsset: photoAsset
        )
    }

    private static func requestAVAsset(for asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: MacCompressionError.assetUnavailable)
                }
            }
        }
    }

    private static func requestImageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MacCompressionError.assetUnavailable)
                }
            }
        }
    }

    private static func saveResource(
        at fileURL: URL,
        type: PHAssetResourceType,
        originalAsset: PHAsset
    ) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = originalAsset.creationDate
            request.location = originalAsset.location
            request.addResource(with: type, fileURL: fileURL, options: nil)
        }
    }
}

enum MacCompressionError: LocalizedError {
    case assetUnavailable
    case originalFileUnavailable
    case incompatibleVideo
    case imageDecodeFailed
    case imageEncodeFailed
    case outputNotSmaller

    var errorDescription: String? {
        switch self {
        case .assetUnavailable:
            "Photos could not provide the selected item."
        case .originalFileUnavailable:
            "The original file is not currently available on this Mac."
        case .incompatibleVideo:
            "The selected video is not compatible with this codec."
        case .imageDecodeFailed:
            "The selected image could not be decoded."
        case .imageEncodeFailed:
            "The selected image could not be encoded as JPEG."
        case .outputNotSmaller:
            "The compressed result was not smaller, so it was not saved."
        }
    }
}
