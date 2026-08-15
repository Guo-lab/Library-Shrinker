//
//  DiskSpaceMonitor.swift
//  Library Shrinker
//

import Foundation

struct DiskSpaceEstimate {
    let availableByteSize: Int64
    let requiredByteSize: Int64

    var hasEnoughSpace: Bool {
        availableByteSize >= requiredByteSize
    }
}

enum DiskSpaceMonitor {
    static func estimate(for targetByteSizes: [Int64]) throws -> DiskSpaceEstimate {
        let required = CompressionTargetCalculator.requiredStorage(for: targetByteSizes)

        let values = try FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            throw DiskSpaceMonitorError.capacityUnavailable
        }

        return DiskSpaceEstimate(
            availableByteSize: available,
            requiredByteSize: required
        )
    }
}

enum DiskSpaceMonitorError: Error {
    case capacityUnavailable
}

extension Error {
    var isOutOfDiskSpaceError: Bool {
        var currentError: NSError? = self as NSError

        while let error = currentError {
            if error.domain == NSCocoaErrorDomain,
               error.code == CocoaError.fileWriteOutOfSpace.rawValue {
                return true
            }

            if error.domain == NSPOSIXErrorDomain, error.code == 28 {
                return true
            }

            let message = error.localizedDescription.lowercased()
            if message.contains("no space") || message.contains("storage is full") {
                return true
            }

            currentError = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return false
    }
}
