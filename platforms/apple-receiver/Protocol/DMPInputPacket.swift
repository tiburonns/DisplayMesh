import Foundation

enum DMPInputPacketError: Error, LocalizedError, Equatable {
    case invalidCoordinate
    case invalidPressure
    case invalidStylusData

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "Touch coordinates are outside the normalized display surface"
        case .invalidPressure:
            return "Touch pressure is outside the normalized range"
        case .invalidStylusData:
            return "Stylus data contains a non-finite value"
        }
    }
}

struct DMPInputSample {
    static let version: UInt8 = 1
    static let encodedSize = 40

    enum Kind: UInt8 {
        case touch = 1
        case pencil = 2
    }

    enum Phase: UInt8 {
        case began = 1
        case moved = 2
        case ended = 3
        case cancelled = 4
        case hover = 5
    }

    let kind: Kind
    let phase: Phase
    let flags: UInt8
    let contactID: UInt32
    let normalizedX: Float
    let normalizedY: Float
    let pressure: Float
    let altitude: Float
    let azimuth: Float
    let barrelRoll: Float
    let timestampMicroseconds: UInt64

    init(event: ReceiverInputEvent) throws {
        normalizedX = Float(event.normalizedX)
        normalizedY = Float(event.normalizedY)

        guard normalizedX.isFinite,
              normalizedY.isFinite,
              (0...1).contains(normalizedX),
              (0...1).contains(normalizedY) else {
            throw DMPInputPacketError.invalidCoordinate
        }

        contactID = event.contactID
        flags = 0
        timestampMicroseconds = UInt64(
            max(0, event.timestamp * 1_000_000)
        )

        switch event.phase {
        case .began: phase = .began
        case .moved: phase = .moved
        case .ended: phase = .ended
        case .cancelled: phase = .cancelled
        }

        if let pencil = event.pencil {
            kind = .pencil
            pressure = Float(pencil.pressure)
            altitude = Float(pencil.altitude)
            azimuth = Float(pencil.azimuth)
            barrelRoll = 0
        } else {
            kind = .touch
            pressure = 0
            altitude = 0
            azimuth = 0
            barrelRoll = 0
        }

        guard pressure.isFinite, (0...1).contains(pressure) else {
            throw DMPInputPacketError.invalidPressure
        }

        guard altitude.isFinite, azimuth.isFinite, barrelRoll.isFinite else {
            throw DMPInputPacketError.invalidStylusData
        }
    }

    func encoded() -> Data {
        var data = Data(capacity: Self.encodedSize)
        data.append(Self.version)
        data.append(kind.rawValue)
        data.append(phase.rawValue)
        data.append(flags)
        data.appendInputUInt32(contactID)
        data.appendInputFloat(normalizedX)
        data.appendInputFloat(normalizedY)
        data.appendInputFloat(pressure)
        data.appendInputFloat(altitude)
        data.appendInputFloat(azimuth)
        data.appendInputFloat(barrelRoll)
        data.appendInputUInt64(timestampMicroseconds)
        return data
    }
}

private extension Data {
    mutating func appendInputUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendInputUInt64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendInputFloat(_ value: Float) {
        appendInputUInt32(value.bitPattern)
    }
}
