import Foundation

enum CompressionResourcePolicy {
    static func prepareForNextItem(
        maximumWait: Duration = .seconds(60),
        onThermalWait: @escaping @MainActor () -> Void = {}
    ) async throws {
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumWait)
        var didReportThermalWait = false

        while ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical {
            if !didReportThermalWait {
                onThermalWait()
                didReportThermalWait = true
            }
            guard clock.now < deadline else {
                throw CompressionResourcePolicyError.thermalCooldownTimedOut
            }
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

enum CompressionResourcePolicyError: LocalizedError {
    case thermalCooldownTimedOut

    var errorDescription: String? {
        switch self {
        case .thermalCooldownTimedOut:
            "The device did not cool down within 60 seconds."
        }
    }
}
