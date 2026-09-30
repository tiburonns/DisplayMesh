import Foundation

enum HostConnectionPolicy {
    static let connectTimeoutSeconds: TimeInterval = 10
    static let helloTimeoutSeconds: TimeInterval = 10
    static let pairingTimeoutSeconds: TimeInterval = 30
    static let capabilitiesTimeoutSeconds: TimeInterval = 10
    static let panelTimeoutSeconds: TimeInterval = 15

    static var allTimeouts: [TimeInterval] {
        [
            connectTimeoutSeconds,
            helloTimeoutSeconds,
            pairingTimeoutSeconds,
            capabilitiesTimeoutSeconds,
            panelTimeoutSeconds,
        ]
    }
}
