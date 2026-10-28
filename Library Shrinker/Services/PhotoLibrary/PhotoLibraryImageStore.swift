import Foundation
import Photos

final class PhotoLibraryImageStore {
    func authorizationState() -> PhotoLibraryAccessState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .limited: .limited
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> PhotoLibraryAccessState {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                let state: PhotoLibraryAccessState = switch status {
                case .authorized: .authorized
                case .limited: .limited
                case .notDetermined: .notDetermined
                case .denied, .restricted: .denied
                @unknown default: .denied
                }
                continuation.resume(returning: state)
            }
        }
    }

    func fetchScreenshotAssets() async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumScreenshots,
                options: nil
            )
            guard let screenshots = collections.firstObject else { return [] }

            let options = PHFetchOptions()
            options.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            let result = PHAsset.fetchAssets(in: screenshots, options: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            return assets
        }.value
    }

    func fetchAssets(withLocalIdentifiers identifiers: [String]) async -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            return assets
        }.value
    }

    func makeImageItem(from asset: PHAsset) async throws -> ImageAssetItem {
        try await Task.detached(priority: .userInitiated) {
            guard let resource = Self.preferredImageResource(for: asset) else {
                throw PhotoLibraryImageStoreError.missingImageResource
            }
            let size = try await Self.byteSize(for: resource)
            return ImageAssetItem(
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
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    nonisolated static func imageData(for asset: PHAsset) async throws -> Data {
        guard let resource = preferredImageResource(for: asset) else {
            throw PhotoLibraryImageStoreError.missingImageResource
        }

        let accumulator = ImageDataAccumulator()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    accumulator.append(data)
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: accumulator.data)
                    }
                }
            )
        }
    }

    nonisolated private static func preferredImageResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = [.fullSizePhoto, .photo]
        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }
        return resources.first
    }

    nonisolated private static func byteSize(for resource: PHAssetResource) async throws -> Int64 {
        let counter = ImageByteCounter()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { counter.add($0.count) },
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

enum PhotoLibraryImageStoreError: LocalizedError {
    case missingImageResource

    var errorDescription: String? {
        "Photos could not provide this screenshot."
    }
}

nonisolated private final class ImageByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total: Int64 = 0

    var value: Int64 {
        lock.withLock { total }
    }

    func add(_ count: Int) {
        lock.withLock { total += Int64(count) }
    }
}

nonisolated private final class ImageDataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.withLock { storage }
    }

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }
}
