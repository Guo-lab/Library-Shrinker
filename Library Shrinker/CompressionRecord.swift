//
//  CompressionRecord.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import Foundation

struct CompressionRecord: Codable {
    let originalAssetID: String
    let compressedAssetID: String?
    let originalByteSize: Int64
    let compressedByteSize: Int64
    let presetName: String
    let compressedAt: Date

    var savedByteSize: Int64 {
        max(0, originalByteSize - compressedByteSize)
    }
}

enum VideoCompressionRole {
    case original
    case originalWithCompressedCopy
    case compressedCopy
}

struct VideoListEntry: Identifiable {
    let video: VideoAssetItem
    let isCompressedChild: Bool

    var id: String { video.id }
}

enum ImageCompressionRole {
    case original
    case originalWithCompressedCopy
    case compressedCopy
}

struct ImageListEntry: Identifiable {
    let image: ImageAssetItem
    let isCompressedChild: Bool

    var id: String { image.id }
}

enum VideoListFilter: String, CaseIterable, Identifiable {
    case all
    case originals
    case compressed

    var id: String { rawValue }

    var title: String {
        return switch self {
        case .all: "All"
        case .originals: "Originals"
        case .compressed: "Compressed"
        }
    }
}

enum VideoBitRateFilter: String, CaseIterable, Identifiable {
    case all
    case below1Point5
    case onePoint5To2
    case twoTo2Point5
    case twoPoint5To5
    case fiveTo10
    case tenTo20
    case twentyAndAbove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Mbps"
        case .below1Point5: "< 1.5 Mbps"
        case .onePoint5To2: "1.5–2 Mbps"
        case .twoTo2Point5: "2–2.5 Mbps"
        case .twoPoint5To5: "2.5–5 Mbps"
        case .fiveTo10: "5–10 Mbps"
        case .tenTo20: "10–20 Mbps"
        case .twentyAndAbove: "20+ Mbps"
        }
    }

    func contains(bitsPerSecond: Double) -> Bool {
        let mbps = bitsPerSecond / 1_000_000
        return switch self {
        case .all: true
        case .below1Point5: mbps < 1.5
        case .onePoint5To2: mbps >= 1.5 && mbps < 2
        case .twoTo2Point5: mbps >= 2 && mbps < 2.5
        case .twoPoint5To5: mbps >= 2.5 && mbps < 5
        case .fiveTo10: mbps >= 5 && mbps < 10
        case .tenTo20: mbps >= 10 && mbps < 20
        case .twentyAndAbove: mbps >= 20
        }
    }
}
