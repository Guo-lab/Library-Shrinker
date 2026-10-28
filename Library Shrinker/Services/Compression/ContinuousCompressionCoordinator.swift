import BackgroundTasks
import Foundation

@MainActor
final class ContinuousCompressionCoordinator {
    enum Kind: Hashable, CaseIterable {
        case video
        case image

        var identifierPrefix: String {
            let bundleID = Bundle.main.bundleIdentifier ?? "gsq.Library-Shrinker"
            let component = self == .video ? "video" : "image"
            return "\(bundleID).continued-processing.\(component)"
        }

        var permittedIdentifier: String {
            "\(identifierPrefix).*"
        }

        var title: String {
            self == .video ? "Compressing Videos" : "Compressing Screenshots"
        }
    }

    static let shared = ContinuousCompressionCoordinator()

    private struct State {
        let identifier: String
        var task: BGContinuedProcessingTask?
        var expirationAction: (@MainActor () -> Void)?
        var launchContinuation: CheckedContinuation<Void, any Error>?
    }

    private var states: [Kind: State] = [:]
    private var registeredKinds: Set<Kind> = []
    private var didRegisterLaunchHandlers = false

    private init() {}

    func registerLaunchHandlers() {
        guard !didRegisterLaunchHandlers else { return }
        didRegisterLaunchHandlers = true

        for kind in Kind.allCases {
            let didRegister = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: kind.permittedIdentifier,
                using: nil
            ) { [weak self] task in
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }

                Task { @MainActor in
                    self?.attach(continuedTask, to: kind)
                }
            }

            if didRegister {
                registeredKinds.insert(kind)
            }
        }
    }

    func begin(
        kind: Kind,
        itemCount: Int,
        expirationAction: @escaping @MainActor () -> Void
    ) async throws {
        guard registeredKinds.contains(kind) else {
            throw ContinuousCompressionError.registrationRejected
        }
        guard states[kind] == nil else {
            throw ContinuousCompressionError.alreadyRunning
        }

        let identifier = "\(kind.identifierPrefix).\(UUID().uuidString)"
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                states[kind] = State(
                    identifier: identifier,
                    expirationAction: expirationAction,
                    launchContinuation: continuation
                )

                let itemDescription = itemCount == 1 ? "1 item" : "\(itemCount) items"
                let request = BGContinuedProcessingTaskRequest(
                    identifier: identifier,
                    title: kind.title,
                    subtitle: "Preparing \(itemDescription)"
                )
                request.strategy = .queue

                do {
                    try BGTaskScheduler.shared.submit(request)
                } catch {
                    states.removeValue(forKey: kind)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(kind: kind)
            }
        }
    }

    func report(
        kind: Kind,
        fractionCompleted: Double,
        subtitle: String
    ) {
        guard let task = states[kind]?.task else { return }
        task.progress.totalUnitCount = 1_000
        let fraction = min(max(fractionCompleted, 0), 1)
        task.progress.completedUnitCount = Int64((fraction * 1_000).rounded())
        task.updateTitle(kind.title, subtitle: subtitle)
    }

    func complete(kind: Kind, success: Bool) {
        guard let state = states.removeValue(forKey: kind) else { return }
        state.launchContinuation?.resume(
            throwing: ContinuousCompressionError.endedBeforeLaunch
        )
        state.task?.setTaskCompleted(success: success)
    }

    func cancel(kind: Kind) {
        guard let state = states.removeValue(forKey: kind) else { return }
        state.launchContinuation?.resume(throwing: CancellationError())
        state.expirationAction?()
        state.task?.setTaskCompleted(success: false)
    }

    private func attach(_ task: BGContinuedProcessingTask, to kind: Kind) {
        guard var state = states[kind] else {
            task.setTaskCompleted(success: false)
            return
        }

        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = 0
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancel(kind: kind)
            }
        }

        state.task = task
        let continuation = state.launchContinuation
        state.launchContinuation = nil
        states[kind] = state
        continuation?.resume()
    }
}

enum ContinuousCompressionError: LocalizedError {
    case registrationRejected
    case alreadyRunning
    case endedBeforeLaunch

    var errorDescription: String? {
        switch self {
        case .registrationRejected:
            "The system rejected background task registration."
        case .alreadyRunning:
            "A compression task of this type is already running."
        case .endedBeforeLaunch:
            "The background task ended before compression could begin."
        }
    }
}
