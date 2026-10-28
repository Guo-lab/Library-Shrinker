//
//  VideoThumbnailView.swift
//  Library Shrinker
//

import Foundation
import Photos
import SwiftUI

struct VideoThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await VideoThumbnailLoader.image(
                for: asset,
                targetSize: CGSize(width: 160, height: 120)
            )
        }
    }
}

private enum VideoThumbnailLoader {
    static func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let resultGate = ThumbnailResultGate()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false

            var requestID = PHInvalidImageRequestID
            requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !isDegraded {
                    resultGate.resume(continuation, with: image)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(2))
                if resultGate.resume(continuation, with: nil) {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
            }
        }
    }
}

private final class ThumbnailResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<UIImage?, Never>, with image: UIImage?) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return false
        }

        didResume = true
        continuation.resume(returning: image)
        return true
    }
}
