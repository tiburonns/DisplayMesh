import Foundation

enum ReceiverTelemetryCadencePolicy {
    static let normalIntervalSeconds:
        TimeInterval = 1
    static let saturatedIntervalSeconds:
        TimeInterval = 0.25
    static let saturatedDecodeQueueDepth = 3

    static func shouldSend(
        now: TimeInterval,
        lastSentAt: TimeInterval,
        decodeQueueDepth: Int
    ) -> Bool {
        guard now.isFinite,
              lastSentAt.isFinite,
              now >= lastSentAt else {
            return false
        }

        let interval =
            decodeQueueDepth >=
                saturatedDecodeQueueDepth
            ? saturatedIntervalSeconds
            : normalIntervalSeconds

        return now - lastSentAt >= interval
    }
}
