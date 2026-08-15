//
//  VideoCompressor.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import AVFoundation
import Foundation
import Photos

struct VideoCompressionResult {
    let originalAssetID: String
    let compressedAssetID: String?
    let originalByteSize: Int64
    let compressedByteSize: Int64

    var savedByteSize: Int64 {
        max(0, originalByteSize - compressedByteSize)
    }
}

final class VideoCompressor {
    private let albumTitle = "Library Shrinker Compressed"

    func compress(
        _ item: VideoAssetItem,
        using preset: VideoCompressionPreset,
        targetByteSize: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> VideoCompressionResult {
        guard item.byteSize > 0 else {
            throw VideoCompressorError.missingOriginalSize
        }

        let avAsset = try await requestAVAsset(for: item.asset)
        guard targetByteSize > 0, targetByteSize < item.byteSize else {
            throw VideoCompressorError.invalidTargetSize
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-shrinker-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try Task.checkCancellation()
        try await export(
            avAsset,
            to: outputURL,
            using: preset,
            targetByteSize: targetByteSize,
            progressHandler: progressHandler
        )
        try Task.checkCancellation()
        let compressedSize = try outputURL.fileSize()
        guard compressedSize < item.byteSize else {
            throw VideoCompressorError.outputNotSmaller
        }

        let compressedAssetID = try await saveCompressedVideo(from: outputURL, originalAsset: item.asset)

        return VideoCompressionResult(
            originalAssetID: item.id,
            compressedAssetID: compressedAssetID,
            originalByteSize: item.byteSize,
            compressedByteSize: compressedSize
        )
    }

    private func requestAVAsset(for asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                if info?[PHImageCancelledKey] as? Bool == true {
                    continuation.resume(throwing: VideoCompressorError.cancelled)
                    return
                }

                guard let avAsset else {
                    continuation.resume(throwing: VideoCompressorError.missingAVAsset)
                    return
                }

                continuation.resume(returning: avAsset)
            }
        }
    }

    private func export(
        _ asset: AVAsset,
        to outputURL: URL,
        using preset: VideoCompressionPreset,
        targetByteSize: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset.exportPresetName,
            with: asset,
            outputFileType: .mp4
        ) else {
            throw VideoCompressorError.incompatiblePreset
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset.exportPresetName) else {
            throw VideoCompressorError.cannotCreateExportSession
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.canPerformMultiplePassesOverSourceMediaData = true
        exportSession.fileLengthLimit = targetByteSize
        exportSession.metadata = try? await asset.load(.metadata)

        let progressTask = Task {
            for await state in exportSession.states(updateInterval: 0.2) {
                guard !Task.isCancelled else {
                    return
                }

                if case .exporting(let progress) = state {
                    progressHandler(progress.fractionCompleted)
                }
            }
        }

        defer {
            progressTask.cancel()
        }

        try await exportSession.export(to: outputURL, as: .mp4)
        progressHandler(1)
    }

    private func saveCompressedVideo(from fileURL: URL, originalAsset: PHAsset) async throws -> String? {
        let existingAlbum = fetchCompressedAlbum()
        let originalAlbums = fetchWritableAlbums(containing: originalAsset)
        var createdAssetID: String?

        try await PHPhotoLibrary.shared().performChanges {
            guard let creationRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) else {
                return
            }

            creationRequest.creationDate = originalAsset.creationDate
            creationRequest.location = originalAsset.location
            creationRequest.isFavorite = originalAsset.isFavorite
            creationRequest.isHidden = originalAsset.isHidden
            createdAssetID = creationRequest.placeholderForCreatedAsset?.localIdentifier

            guard let placeholder = creationRequest.placeholderForCreatedAsset else {
                return
            }

            for album in originalAlbums where album.localIdentifier != existingAlbum?.localIdentifier {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }

            if let existingAlbum {
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: existingAlbum)
                albumChangeRequest?.addAssets([placeholder] as NSArray)
            } else {
                let albumChangeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumTitle)
                albumChangeRequest.addAssets([placeholder] as NSArray)
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

    private func fetchCompressedAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)

        let result = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )

        return result.firstObject
    }
}

enum VideoCompressorError: LocalizedError {
    case missingAVAsset
    case cannotCreateExportSession
    case incompatiblePreset
    case exportFailed
    case cancelled
    case missingOriginalSize
    case invalidTargetSize
    case outputNotSmaller

    var errorDescription: String? {
        switch self {
        case .missingAVAsset:
            "Photos could not provide the selected video."
        case .cannotCreateExportSession:
            "The system could not create a video export session."
        case .incompatiblePreset:
            "The selected compression preset is not compatible with this video."
        case .exportFailed:
            "The video export failed."
        case .cancelled:
            "The video export was cancelled."
        case .missingOriginalSize:
            "The original file size is unavailable, so target-size compression cannot run."
        case .invalidTargetSize:
            "The target size must be smaller than the original video."
        case .outputNotSmaller:
            "The exported video was not smaller than the original, so it was not saved."
        }
    }
}

private extension URL {
    func fileSize() throws -> Int64 {
        let values = try resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
