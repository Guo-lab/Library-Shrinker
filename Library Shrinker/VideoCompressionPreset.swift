//
//  VideoCompressionPreset.swift
//  Library Shrinker
//
//  Created by Guo Siqi on 7/8/26.
//

import AVFoundation
import Foundation

enum VideoCompressionPreset: String, CaseIterable, Identifiable {
    case hevc
    case h264

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .hevc:
            "HEVC"
        case .h264:
            "H.264"
        }
    }

    var exportPresetName: String {
        switch self {
        case .hevc:
            AVAssetExportPresetHEVCHighestQuality
        case .h264:
            AVAssetExportPresetHighestQuality
        }
    }

}

enum CompressionProfile: String, CaseIterable, Identifiable {
    case medium
    case small
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .medium:
            "Medium"
        case .small:
            "Small"
        case .custom:
            "Custom"
        }
    }

    var targetSizeRatio: Double? {
        switch self {
        case .medium:
            0.35
        case .small:
            0.20
        case .custom:
            nil
        }
    }
}

enum CompressionTargetMode: String, CaseIterable, Identifiable {
    case ratio
    case bitRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ratio:
            "Ratio"
        case .bitRate:
            "Bitrate"
        }
    }
}
