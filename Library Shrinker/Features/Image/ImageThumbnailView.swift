import Foundation
import Photos
import SwiftUI

struct ImageThumbnailView: View {
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
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await ImageLoader.image(
                for: asset,
                targetSize: CGSize(width: 180, height: 140),
                contentMode: .aspectFill
            )
        }
    }
}

struct ImagePreviewView: View {
    let item: ImageAssetItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: item.id) {
            image = await ImageLoader.image(
                for: item.asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit
            )
        }
    }
}

private enum ImageLoader {
    static func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = ImageResultGate()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = targetSize == PHImageManagerMaximumSize ? .none : .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                let error = info?[PHImageErrorKey] as? Error
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if cancelled || error != nil {
                    gate.resume(continuation, with: nil)
                } else if !degraded {
                    gate.resume(continuation, with: image)
                }
            }
        }
    }
}

private final class ImageResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<UIImage?, Never>, with image: UIImage?) {
        lock.withLock {
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: image)
        }
    }
}
