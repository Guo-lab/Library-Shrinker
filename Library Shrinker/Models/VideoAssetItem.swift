//
//  VideoAssetItem.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import Foundation
import Photos

struct VideoAssetItem: Identifiable {
    let asset: PHAsset
    let byteSize: Int64
    let resourceFilename: String?

    var id: String {
        asset.localIdentifier
    }

    var displayName: String {
        resourceFilename ?? "Video"
    }

    var fileSizeText: String {
        guard byteSize > 0 else {
            return "Size unavailable"
        }

        return ByteCountFormatter.libraryShrinkerFormatter.string(fromByteCount: byteSize)
    }

    var fileSizeMegabytesText: String {
        guard byteSize > 0 else {
            return "--"
        }

        let megabytes = Double(byteSize) / 1_000_000
        if megabytes >= 100 {
            return String(format: "%.0f", megabytes)
        }

        return String(format: "%.1f", megabytes)
    }

    var bitRate: Double {
        guard byteSize > 0, asset.duration > 0 else {
            return 0
        }

        return Double(byteSize) * 8 / asset.duration
    }

    var bitRateText: String {
        bitRate.formattedBitRate
    }

    var detailText: String {
        let resolution = "\(asset.pixelWidth) x \(asset.pixelHeight)"
        return "\(durationText) • \(resolution) • \(bitRateText)"
    }

    func estimatedCompressedByteSize(targetSizeRatio: Double) -> Int64 {
        guard byteSize > 0 else {
            return 0
        }

        return max(1, Int64(Double(byteSize) * targetSizeRatio))
    }

    func estimatedCompressionText(targetSizeRatio: Double) -> String {
        estimatedCompressionText(
            targetByteSize: estimatedCompressedByteSize(targetSizeRatio: targetSizeRatio),
            showsIndividualRatio: false
        )
    }

    func estimatedCompressionText(targetByteSize: Int64, showsIndividualRatio: Bool) -> String {
        let estimatedSize = max(0, targetByteSize)
        guard estimatedSize > 0 else {
            return "Estimate unavailable"
        }

        let from = compactMegabytesText(for: byteSize)
        let to = compactMegabytesText(for: estimatedSize)
        let estimatedBitRate = asset.duration > 0 ? Double(estimatedSize) * 8 / asset.duration : 0
        let ratioText: String
        if showsIndividualRatio, byteSize > 0 {
            let percentage = Double(estimatedSize) / Double(byteSize) * 100
            ratioText = " • \(percentage.formatted(.number.precision(.fractionLength(0))))%"
        } else {
            ratioText = ""
        }
        return "\(from) → ~\(to) MB\(ratioText) • \(bitRate.compactMegabitsText) → ~\(estimatedBitRate.compactMegabitsText) Mbps"
    }

    private func compactMegabytesText(for byteSize: Int64) -> String {
        let megabytes = Double(byteSize) / 1_000_000
        if megabytes >= 100 {
            return String(format: "%.0f", megabytes)
        }

        return String(format: "%.1f", megabytes)
    }

    private var durationText: String {
        let duration = Int(asset.duration.rounded())
        let hours = duration / 3_600
        let minutes = (duration % 3_600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m \(seconds)s"
    }
}

extension ByteCountFormatter {
    static let libraryShrinkerFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

extension Double {
    var formattedBitRate: String {
        guard self > 0 else {
            return "Bitrate unavailable"
        }

        let megabitsPerSecond = self / 1_000_000
        if megabitsPerSecond >= 1 {
            return String(format: "%.1f Mbps", megabitsPerSecond)
        }

        return String(format: "%.0f Kbps", self / 1_000)
    }

    var compactMegabitsText: String {
        guard self > 0 else {
            return "--"
        }

        let megabitsPerSecond = self / 1_000_000
        if megabitsPerSecond >= 10 {
            return String(format: "%.0f", megabitsPerSecond)
        }

        return String(format: "%.1f", megabitsPerSecond)
    }
}
