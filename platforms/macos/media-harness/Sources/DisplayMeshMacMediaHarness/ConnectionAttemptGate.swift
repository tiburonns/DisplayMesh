import Foundation

final class ConnectionAttemptGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    /// Returns true exactly once for the lifetime of this attempt.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !resolved else { return false }
        resolved = true
        return true
    }
}
