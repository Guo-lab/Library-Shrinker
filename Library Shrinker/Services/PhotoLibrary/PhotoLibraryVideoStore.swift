//
//  PhotoLibraryVideoStore.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import Foundation
import Photos

enum PhotoLibraryAccessState {
    case notDetermined
    case authorized
    case limited
    case denied

    var canReadAndWrite: Bool {
        self == .authorized || self == .limited
    }
}

final class PhotoLibraryVideoStore {
    func authorizationState() -> PhotoLibraryAccessState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .limited:
            .limited
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async -> PhotoLibraryAccessState {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                let state: PhotoLibraryAccessState
                switch status {
                case .authorized:
                    state = .authorized
                case .limited:
                    state = .limited
                case .notDetermined:
                    state = .notDetermined
                case .denied, .restricted:
                    state = .denied
                @unknown default:
                    state = .denied
                }

                continuation.resume(returning: state)
            }
        }
    }

    func fetchVideoAssets() async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]

            let result = PHAsset.fetchAssets(with: .video, options: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)

            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            return assets
        }.value
    }

    func makeVideoItem(from asset: PHAsset) async throws -> VideoAssetItem {
        try await Task.detached(priority: .userInitiated) {
            guard let resource = Self.preferredVideoResource(for: asset) else {
                throw PhotoLibraryVideoStoreError.missingVideoResource
            }

            let size = (try? await Self.byteSize(for: resource)) ?? 0
            return VideoAssetItem(
                asset: asset,
                byteSize: size,
                resourceFilename: resource.originalFilename
            )
        }.value
    }

    func deleteAsset(_ asset: PHAsset) async throws {
        try await deleteAssets([asset])
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else {
            return
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    nonisolated private static func preferredVideoResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = [
            .fullSizeVideo,
            .video,
            .pairedVideo,
            .fullSizePairedVideo
        ]

        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }

        return resources.first
    }

    nonisolated private static func byteSize(for resource: PHAssetResource) async throws -> Int64 {
        let counter = ByteCounter()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    counter.add(data.count)
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: counter.value)
                    }
                }
            )
        }
    }
}

enum PhotoLibraryVideoStoreError: LocalizedError {
    case missingVideoResource

    var errorDescription: String? {
        switch self {
        case .missingVideoResource:
            "The selected video does not have a readable Photos resource."
        }
    }
}

nonisolated private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total: Int64 = 0

    var value: Int64 {
        lock.withLock {
            total
        }
    }

    func add(_ byteCount: Int) {
        lock.withLock {
            total += Int64(byteCount)
        }
    }
}
