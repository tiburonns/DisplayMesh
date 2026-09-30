import Foundation

struct LatestFramePresentationDecision: Equatable {
    let shouldScheduleDrain: Bool
    let replacedPendingFrame: Bool
}

struct LatestFramePresentationGate {
    private(set) var hasPendingFrame = false
    private(set) var drainScheduled = false

    mutating func enqueue() -> LatestFramePresentationDecision {
        let replacedPendingFrame = hasPendingFrame
        hasPendingFrame = true

        guard !drainScheduled else {
            return LatestFramePresentationDecision(
                shouldScheduleDrain: false,
                replacedPendingFrame: replacedPendingFrame
            )
        }

        drainScheduled = true
        return LatestFramePresentationDecision(
            shouldScheduleDrain: true,
            replacedPendingFrame: replacedPendingFrame
        )
    }

    mutating func takePending() -> Bool {
        guard drainScheduled, hasPendingFrame else {
            return false
        }

        hasPendingFrame = false
        return true
    }

    mutating func completePresentation() -> Bool {
        if hasPendingFrame {
            return true
        }

        drainScheduled = false
        return false
    }

    mutating func reset() {
        hasPendingFrame = false
        drainScheduled = false
    }
}
