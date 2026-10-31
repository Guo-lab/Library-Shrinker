import AppKit
import Observation
import Photos
import SwiftUI

enum MacLibrarySection: String, CaseIterable, Identifiable {
    case videos
    case screenshots

    var id: Self { self }

    var title: String {
        switch self {
        case .videos: "Videos"
        case .screenshots: "Screenshots"
        }
    }

    var systemImage: String {
        switch self {
        case .videos: "video"
        case .screenshots: "photo.on.rectangle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .videos: "No Videos in Photos"
        case .screenshots: "No Screenshots in Photos"
        }
    }

    var emptyDescription: String {
        switch self {
        case .videos:
            "Videos stored in the Mac Photos library will appear here."
        case .screenshots:
            "Mac screenshots must be imported into Photos before they appear here."
        }
    }
}

struct MacPhotoItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let creationDate: Date?

    var dimensionsText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var durationText: String? {
        guard duration > 0 else { return nil }
        return Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
    }
}

@MainActor
@Observable
final class MacPhotoLibraryModel {
    var section: MacLibrarySection = .videos {
        didSet {
            selection.removeAll()
            Task { await loadAuthorizedLibrary() }
        }
    }
    var items: [MacPhotoItem] = []
    var selection: Set<String> = []
    var isLoading = false
    var statusText = "Ready"
    var authorizationDenied = false
    var targetRatio = 0.35
    var videoCodec: MacVideoCodec = .hevc

    var targetPercent: Int {
        Int((targetRatio * 100).rounded())
    }

    func load() async {
        let status = await requestAuthorizationIfNeeded()
        authorizationDenied = status == .denied || status == .restricted
        guard status == .authorized || status == .limited else {
            items = []
            statusText = "Photos access is unavailable"
            return
        }
        await loadAuthorizedLibrary()
    }

    func deleteSelection() async {
        let identifiers = Array(selection)
        guard !identifiers.isEmpty else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        isLoading = true
        statusText = "Deleting \(identifiers.count) item(s)…"
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            selection.removeAll()
            await loadAuthorizedLibrary()
        } catch {
            isLoading = false
            statusText = "Delete failed: \(error.localizedDescription)"
        }
    }

    func startCompression() {
        guard !selection.isEmpty, !isLoading else { return }
        let identifiers = Array(selection)
        let selectedSection = section
        let ratio = targetRatio
        let codec = videoCodec

        Task {
            isLoading = true
            statusText = "Preparing \(identifiers.count) item(s)…"
            var successCount = 0
            var failureMessages: [String] = []

            for (index, identifier) in identifiers.enumerated() {
                guard !Task.isCancelled else { break }
                statusText = "Compressing \(index + 1) of \(identifiers.count)…"
                do {
                    try await MacPhotoCompressor.compress(
                        identifier: identifier,
                        section: selectedSection,
                        targetRatio: ratio,
                        videoCodec: codec
                    )
                    successCount += 1
                } catch {
                    failureMessages.append(error.localizedDescription)
                }
            }

            isLoading = false
            selection.removeAll()
            if failureMessages.isEmpty {
                statusText = "Saved \(successCount) compressed copy/copies to Photos"
            } else {
                statusText = "Saved \(successCount) of \(identifiers.count): \(failureMessages[0])"
            }
            await loadAuthorizedLibrary()
        }
    }

    func openPhotoPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func loadAuthorizedLibrary() async {
        isLoading = true
        statusText = "Reading \(section.title.lowercased())…"

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let mediaType: PHAssetMediaType = section == .videos ? .video : .image
        let result = PHAsset.fetchAssets(with: mediaType, options: options)
        var loadedItems: [MacPhotoItem] = []
        loadedItems.reserveCapacity(result.count)

        result.enumerateObjects { [section] asset, _, _ in
            if section == .screenshots && !asset.mediaSubtypes.contains(.photoScreenshot) {
                return
            }
            loadedItems.append(MacPhotoItem(
                id: asset.localIdentifier,
                displayName: Self.displayName(for: asset, section: section),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                creationDate: asset.creationDate
            ))
        }

        items = loadedItems
        selection.formIntersection(Set(loadedItems.map(\.id)))
        isLoading = false
        statusText = "\(loadedItems.count) \(section.title.lowercased())"
    }

    private static func displayName(
        for asset: PHAsset,
        section: MacLibrarySection
    ) -> String {
        let kind = section == .videos ? "Video" : "Screenshot"
        guard let creationDate = asset.creationDate else { return kind }
        return "\(kind) — \(creationDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct MacPhotoThumbnail: View {
    let assetIdentifier: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: assetIdentifier) {
            image = await Self.loadImage(for: assetIdentifier)
        }
    }

    private static func loadImage(for identifier: String) async -> NSImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            let gate = ThumbnailContinuationGate()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 192, height: 120),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded || image == nil {
                    gate.resume(continuation, with: image)
                }
            }
        }
    }
}

private final class ThumbnailContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ continuation: CheckedContinuation<NSImage?, Never>, with image: NSImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: image)
    }
}
