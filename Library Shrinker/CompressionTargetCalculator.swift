//
//  CompressionTargetCalculator.swift
//  Library Shrinker
//

import Foundation

enum CompressionTargetCalculator {
    static let minimumRatio = 0.01

    static func targetByteSize(originalByteSize: Int64, ratio: Double) -> Int64 {
        guard originalByteSize > 0 else { return 0 }
        return max(1, Int64(Double(originalByteSize) * min(max(ratio, minimumRatio), 1)))
    }

    static func targetByteSize(megabitsPerSecond: Double, duration: TimeInterval) -> Int64 {
        guard megabitsPerSecond > 0, duration > 0 else { return 0 }
        return max(1, Int64(megabitsPerSecond * 1_000_000 * duration / 8))
    }

    static func sliderPosition(for ratio: Double) -> Double {
        let clampedRatio = min(max(ratio, minimumRatio), 1)
        return log(clampedRatio / minimumRatio) / log(1 / minimumRatio)
    }

    static func ratio(forSliderPosition position: Double) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        let rawRatio = minimumRatio * pow(1 / minimumRatio, clampedPosition)
        return quantizedRatio(rawRatio)
    }

    static func quantizedRatio(_ ratio: Double) -> Double {
        let percentage = min(max(ratio, minimumRatio), 1) * 100
        let step: Double
        switch percentage {
        case ..<40: step = 1
        case ..<80: step = 5
        default: step = 10
        }
        return min(max((percentage / step).rounded() * step / 100, minimumRatio), 1)
    }

    static func requiredStorage(
        for targetByteSizes: [Int64],
        safetyReserve: Int64 = 256_000_000
    ) -> Int64 {
        let positiveTargets = targetByteSizes.filter { $0 > 0 }
        return positiveTargets.reduce(Int64(0), +)
            + (positiveTargets.max() ?? 0)
            + safetyReserve
    }

    static func recommendedMinimumMegabitsPerSecond(
        pixelWidth: Int,
        pixelHeight: Int,
        usesHEVC: Bool
    ) -> Double {
        let pixels = pixelWidth * pixelHeight
        let h264Minimum: Double

        switch pixels {
        case 8_000_000...: h264Minimum = 20
        case 3_500_000...: h264Minimum = 12
        case 2_000_000...: h264Minimum = 7
        case 900_000...: h264Minimum = 3.5
        default: h264Minimum = 1.8
        }

        return usesHEVC ? h264Minimum * 0.6 : h264Minimum
    }
}
