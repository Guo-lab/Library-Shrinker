import AVFoundation
import AVKit
import Photos
import SwiftUI

struct VideoPreviewView: View {
    let video: VideoAssetItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Unable to Play Video",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Loading video…")
                }
            }
            .background(Color.black)
            .navigationTitle(video.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                let asset = try await VideoPreviewAssetLoader.load(asset: video.asset)
                try Task.checkCancellation()
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private enum VideoPreviewAssetLoader {
    static func load(asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) {
                avAsset,
                _,
                info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if info?[PHImageCancelledKey] as? Bool == true {
                    continuation.resume(throwing: CancellationError())
                } else if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: VideoPreviewError.unavailable)
                }
            }
        }
    }
}

private enum VideoPreviewError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Photos could not provide this video. It may still be downloading from iCloud."
    }
}
