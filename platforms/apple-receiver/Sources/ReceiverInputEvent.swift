import Foundation

struct ReceiverInputEvent: Codable, Equatable {
    enum Phase: String, Codable {
        case began
        case moved
        case ended
        case cancelled
    }

    struct PencilData: Codable, Equatable {
        let pressure: Double
        let altitude: Double
        let azimuth: Double
    }

    let contactID: UInt32
    let phase: Phase
    let normalizedX: Double
    let normalizedY: Double
    let timestamp: TimeInterval
    let pencil: PencilData?
}
