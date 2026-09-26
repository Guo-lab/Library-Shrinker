import BackgroundTasks
import Foundation

@MainActor
final class ContinuousCompressionCoordinator {
    enum Kind: Hashable {
        case video
        case image

        var identifierPrefix: String {
            let bundleID = Bundle.main.bundleIdentifier ?? "gsq.Library-Shrinker"
            let component = self == .video ? "video" : "image"
            return "\(bundleID).continued-processing.\(component)"
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
        var pendingCompletion: Bool?
    }

    private var states: [Kind: State] = [:]

    private init() {}

    func submit(
        kind: Kind,
        itemCount: Int,
        expirationAction: @escaping @MainActor () -> Void
    ) throws {
        let identifier = "\(kind.identifierPrefix).\(UUID().uuidString)"
        var state = State(identifier: identifier)
        state.expirationAction = expirationAction
        states[kind] = state

        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                self.attach(continuedTask, to: kind)
            }
        }

        guard didRegister else {
            states.removeValue(forKey: kind)
            throw ContinuousCompressionError.registrationRejected
        }

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
            throw error
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
        guard var state = states[kind] else { return }
        if let task = state.task {
            task.setTaskCompleted(success: success)
            states.removeValue(forKey: kind)
        } else {
            state.pendingCompletion = success
            states[kind] = state
        }
    }

    func cancel(kind: Kind) {
        states[kind]?.expirationAction?()
        complete(kind: kind, success: false)
    }

    private func attach(_ task: BGContinuedProcessingTask, to kind: Kind) {
        guard var state = states[kind] else {
            task.setTaskCompleted(success: false)
            return
        }

        if let completion = state.pendingCompletion {
            task.setTaskCompleted(success: completion)
            states.removeValue(forKey: kind)
            return
        }

        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = 0
        task.expirationHandler = {
            Task { @MainActor in
                guard let state = self.states[kind] else { return }
                state.expirationAction?()
                task.setTaskCompleted(success: false)
                self.states.removeValue(forKey: kind)
            }
        }
        state.task = task
        states[kind] = state
    }
}

enum ContinuousCompressionError: LocalizedError {
    case registrationRejected

    var errorDescription: String? {
        "The system rejected background task registration."
    }
}
