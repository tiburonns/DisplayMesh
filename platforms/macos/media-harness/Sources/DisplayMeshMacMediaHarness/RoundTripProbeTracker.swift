import Foundation

struct RoundTripProbeTracker {
    private(set) var outstandingToken: UInt64?
    private var sentAt: TimeInterval?
    private var nextToken: UInt64 = 1

    mutating func begin(now: TimeInterval) -> UInt64? {
        guard now.isFinite,
              now >= 0,
              outstandingToken == nil else {
            return nil
        }

        let token = nextToken
        nextToken = token == .max ? 1 : token + 1
        outstandingToken = token
        sentAt = now
        return token
    }

    mutating func complete(
        token: UInt64,
        now: TimeInterval
    ) -> Double? {
        guard now.isFinite,
              now >= 0,
              let outstandingToken,
              let sentAt,
              token == outstandingToken,
              now >= sentAt else {
            return nil
        }

        self.outstandingToken = nil
        self.sentAt = nil
        return (now - sentAt) * 1_000
    }

    mutating func reset() {
        outstandingToken = nil
        sentAt = nil
        nextToken = 1
    }
}
