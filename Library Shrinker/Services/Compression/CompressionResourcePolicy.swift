import Foundation

enum CompressionResourcePolicy {
    static func prepareForNextItem() async throws {
        try Task.checkCancellation()

        while ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical {
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            try await Task.sleep(for: .milliseconds(500))
        } else {
            await Task.yield()
        }
    }
}
