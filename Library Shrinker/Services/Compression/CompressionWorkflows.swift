import Foundation

struct ImageCompressionWorkItem {
    let item: ImageAssetItem
    let targetByteSize: Int64
}

struct ImageCompressionUpdate: Sendable {
    let progress: Double
    let statusText: String
    let detailText: String
}

struct ImageCompressionOutcome {
    let records: [String: CompressionRecord]
    let successfulItemIDs: Set<String>
    let statusText: String
    let detailText: String
    let wasCancelled: Bool
}

@MainActor
final class ImageCompressionWorkflow {
    private let compressor: ImageCompressor
    private let repository: any LibraryStateRepository

    init(
        compressor: ImageCompressor,
        repository: any LibraryStateRepository
    ) {
        self.compressor = compressor
        self.repository = repository
    }

    func run(
        workItems: [ImageCompressionWorkItem],
        existingRecords: [String: CompressionRecord],
        onUpdate: @escaping @MainActor @Sendable (ImageCompressionUpdate) -> Void
    ) async -> ImageCompressionOutcome {
        var records = existingRecords
        var successfulIDs: Set<String> = []
        var savedBytes: Int64 = 0
        var failures: [String] = []
        var thermalStopMessage: String?

        for (index, workItem) in workItems.enumerated() {
            guard !Task.isCancelled else { break }
            do {
                try await CompressionResourcePolicy.prepareForNextItem {
                    onUpdate(ImageCompressionUpdate(
                        progress: Double(index) / Double(workItems.count),
                        statusText: "Paused while device cools down",
                        detailText: "Compression will resume automatically when the device temperature improves."
                    ))
                }
            } catch CompressionResourcePolicyError.thermalCooldownTimedOut {
                thermalStopMessage = "The device stayed too hot for 60 seconds. Try again after it cools down."
                break
            } catch {
                break
            }

            let item = workItem.item
            onUpdate(ImageCompressionUpdate(
                progress: Double(index) / Double(workItems.count),
                statusText: "Compressing \(index + 1) of \(workItems.count)",
                detailText: item.displayName
            ))

            do {
                let result = try await compressor.compress(
                    item,
                    targetByteSize: workItem.targetByteSize
                )
                let record = CompressionRecord(
                    originalAssetID: item.id,
                    compressedAssetID: result.compressedAssetID,
                    originalByteSize: item.byteSize,
                    compressedByteSize: result.compressedByteSize,
                    presetName: "JPEG",
                    compressedAt: Date()
                )
                if let previousID = records[item.id]?.compressedAssetID {
                    records.removeValue(forKey: previousID)
                }
                records[item.id] = record
                if let compressedID = result.compressedAssetID {
                    records[compressedID] = record
                }
                try? repository.saveCompressionRecords(records, for: .image)
                successfulIDs.insert(item.id)
                savedBytes += max(0, item.byteSize - result.compressedByteSize)
            } catch {
                failures.append("\(item.displayName): \(error.localizedDescription)")
            }

            let progress = Double(index + 1) / Double(workItems.count)
            onUpdate(ImageCompressionUpdate(
                progress: progress,
                statusText: "Compressing \(index + 1) of \(workItems.count)",
                detailText: item.displayName
            ))
            ContinuousCompressionCoordinator.shared.report(
                kind: .image,
                fractionCompleted: progress,
                subtitle: "Compressing \(index + 1) of \(workItems.count)"
            )
        }

        let cancelled = Task.isCancelled
        let status: String
        if cancelled {
            status = "Compression cancelled"
        } else if thermalStopMessage != nil {
            status = "Compression stopped: device too hot"
        } else {
            status = successfulIDs.count == workItems.count ? "Compression complete" : "Compression finished"
        }
        let saved = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: savedBytes)
        let detail: String
        if let thermalStopMessage {
            detail = "Saved \(successfulIDs.count) of \(workItems.count). \(thermalStopMessage)"
        } else if failures.isEmpty {
            detail = "Saved \(successfulIDs.count) compressed copy/copies in the Image Shrinker album • about \(saved) saved."
        } else {
            detail = "Saved \(successfulIDs.count) of \(workItems.count). \(failures.first ?? "")"
        }

        return ImageCompressionOutcome(
            records: records,
            successfulItemIDs: successfulIDs,
            statusText: status,
            detailText: detail,
            wasCancelled: cancelled
        )
    }
}

struct VideoCompressionWorkItem {
    let item: VideoAssetItem
    let targetByteSize: Int64
    let targetDescription: String
}

struct VideoCompressionUpdate: Sendable {
    let progress: Double
    let statusText: String
    let detailText: String
}

struct VideoCompressionOutcome {
    let records: [String: CompressionRecord]
    let successfulItemIDs: Set<String>
    let statusText: String
    let detailText: String
    let wasCancelled: Bool
    let preparationFailed: Bool
}

@MainActor
final class VideoCompressionWorkflow {
    private let compressor: VideoCompressor
    private let repository: any LibraryStateRepository

    init(
        compressor: VideoCompressor,
        repository: any LibraryStateRepository
    ) {
        self.compressor = compressor
        self.repository = repository
    }

    func run(
        workItems: [VideoCompressionWorkItem],
        preset: VideoCompressionPreset,
        existingRecords: [String: CompressionRecord],
        onUpdate: @escaping @MainActor @Sendable (VideoCompressionUpdate) -> Void
    ) async -> VideoCompressionOutcome {
        guard let initialStorageError = storageError(for: workItems) else {
            return await compress(
                workItems: workItems,
                preset: preset,
                existingRecords: existingRecords,
                onUpdate: onUpdate
            )
        }

        return VideoCompressionOutcome(
            records: existingRecords,
            successfulItemIDs: [],
            statusText: "Compression not started: low storage",
            detailText: initialStorageError,
            wasCancelled: false,
            preparationFailed: true
        )
    }

    private func compress(
        workItems: [VideoCompressionWorkItem],
        preset: VideoCompressionPreset,
        existingRecords: [String: CompressionRecord],
        onUpdate: @escaping @MainActor @Sendable (VideoCompressionUpdate) -> Void
    ) async -> VideoCompressionOutcome {
        var records = existingRecords
        var successfulIDs: Set<String> = []
        var processedCount = 0
        var failureMessages: [String] = []
        var savedBytes: Int64 = 0
        var storageStopMessage: String?
        var thermalStopMessage: String?

        for (index, workItem) in workItems.enumerated() {
            guard !Task.isCancelled else { break }
            let completedBeforeCooling = processedCount
            do {
                try await CompressionResourcePolicy.prepareForNextItem {
                    onUpdate(VideoCompressionUpdate(
                        progress: Double(completedBeforeCooling) / Double(workItems.count),
                        statusText: "Paused while device cools down",
                        detailText: "Compression will resume automatically when the device temperature improves."
                    ))
                }
            } catch CompressionResourcePolicyError.thermalCooldownTimedOut {
                thermalStopMessage = "The device stayed too hot for 60 seconds."
                break
            } catch {
                break
            }

            if index > 0,
               let error = storageError(for: Array(workItems[index...])) {
                storageStopMessage = error
                break
            }

            let item = workItem.item
            let detail = "Compressing \(processedCount + 1) of \(workItems.count): \(item.displayName)"
            onUpdate(VideoCompressionUpdate(
                progress: Double(processedCount) / Double(workItems.count),
                statusText: "Compressing \(processedCount + 1) of \(workItems.count)",
                detailText: detail
            ))

            do {
                let completedBeforeCurrent = processedCount
                let totalCount = workItems.count
                let result = try await compressor.compress(
                    item,
                    using: preset,
                    targetByteSize: workItem.targetByteSize,
                    progressHandler: { itemProgress in
                        Task { @MainActor in
                            let clamped = min(max(itemProgress, 0), 1)
                            let progress = (Double(completedBeforeCurrent) + clamped) / Double(totalCount)
                            onUpdate(VideoCompressionUpdate(
                                progress: progress,
                                statusText: "Compressing \(completedBeforeCurrent + 1) of \(totalCount)",
                                detailText: detail
                            ))
                            ContinuousCompressionCoordinator.shared.report(
                                kind: .video,
                                fractionCompleted: progress,
                                subtitle: "Compressing \(completedBeforeCurrent + 1) of \(totalCount)"
                            )
                        }
                    }
                )
                successfulIDs.insert(item.id)
                savedBytes += result.savedByteSize
                let record = CompressionRecord(
                    originalAssetID: result.originalAssetID,
                    compressedAssetID: result.compressedAssetID,
                    originalByteSize: result.originalByteSize,
                    compressedByteSize: result.compressedByteSize,
                    presetName: workItem.targetDescription,
                    compressedAt: Date()
                )
                records[result.originalAssetID] = record
                if let compressedID = result.compressedAssetID {
                    records[compressedID] = record
                }
                try? repository.saveCompressionRecords(records, for: .video)
            } catch is CancellationError {
                break
            } catch {
                failureMessages.append("\(item.displayName): \(error.localizedDescription)")
                if error.isOutOfDiskSpaceError {
                    storageStopMessage = "Storage became full while processing \(item.displayName)."
                    break
                }
            }

            processedCount += 1
        }

        let cancelled = Task.isCancelled
        let status: String
        let ending: String?
        if cancelled {
            status = "Compression cancelled"
            ending = "Cancelled. Videos already saved remain in Photos."
        } else if let storageStopMessage {
            status = "Compression stopped: low storage"
            ending = "\(storageStopMessage) Videos already saved remain in Photos."
        } else if let thermalStopMessage {
            status = "Compression stopped: device too hot"
            ending = "\(thermalStopMessage) Try again after it cools down. Videos already saved remain in Photos."
        } else {
            status = "Compression finished"
            ending = nil
        }

        return VideoCompressionOutcome(
            records: records,
            successfulItemIDs: successfulIDs,
            statusText: status,
            detailText: completionSummary(
                successCount: successfulIDs.count,
                totalCount: workItems.count,
                savedBytes: savedBytes,
                failureMessages: failureMessages,
                ending: ending
            ),
            wasCancelled: cancelled,
            preparationFailed: false
        )
    }

    private func storageError(for workItems: [VideoCompressionWorkItem]) -> String? {
        do {
            let estimate = try DiskSpaceMonitor.estimate(
                for: workItems.map(\.targetByteSize)
            )
            guard !estimate.hasEnoughSpace else { return nil }
            let available = ByteCountFormatter.libraryShrinkerFormatter.string(
                fromByteCount: estimate.availableByteSize
            )
            let required = ByteCountFormatter.libraryShrinkerFormatter.string(
                fromByteCount: estimate.requiredByteSize
            )
            return "Not enough storage: about \(required) required, \(available) available."
        } catch {
            return nil
        }
    }

    private func completionSummary(
        successCount: Int,
        totalCount: Int,
        savedBytes: Int64,
        failureMessages: [String],
        ending: String?
    ) -> String {
        let saved = ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: savedBytes)
        var parts = ["Compressed \(successCount) of \(totalCount), saved \(saved)."]
        if !failureMessages.isEmpty {
            parts.append("Failed: \(failureMessages.joined(separator: "; "))")
        }
        if let ending {
            parts.append(ending)
        }
        return parts.joined(separator: " ")
    }
}
