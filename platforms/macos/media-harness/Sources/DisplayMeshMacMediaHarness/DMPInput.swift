import CoreGraphics
import Foundation

enum DMPInputDecodeError: Error, LocalizedError, Equatable {
    case invalidLength(Int)
    case unsupportedVersion(UInt8)
    case unsupportedKind(UInt8)
    case unsupportedPhase(UInt8)
    case invalidCoordinates
    case invalidPressure
    case invalidStylusData

    var errorDescription: String? {
        switch self {
        case .invalidLength(let size):
            return "DMP input sample must be 40 bytes, got \(size)"
        case .unsupportedVersion(let version):
            return "Unsupported DMP input version: \(version)"
        case .unsupportedKind(let kind):
            return "Unsupported DMP input kind: \(kind)"
        case .unsupportedPhase(let phase):
            return "Unsupported DMP input phase: \(phase)"
        case .invalidCoordinates:
            return "DMP input coordinates are outside the normalized display surface"
        case .invalidPressure:
            return "DMP input pressure is outside the normalized range"
        case .invalidStylusData:
            return "DMP stylus values contain a non-finite number"
        }
    }
}

struct DMPInputSample: Equatable {
    static let version: UInt8 = 1
    static let encodedSize = 40

    enum Kind: UInt8, Equatable {
        case touch = 1
        case pencil = 2
    }

    enum Phase: UInt8, Equatable {
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

    var normalizedPoint: CGPoint {
        CGPoint(x: CGFloat(normalizedX), y: CGFloat(normalizedY))
    }

    static func decode(_ payload: Data) throws -> DMPInputSample {
        guard payload.count == encodedSize else {
            throw DMPInputDecodeError.invalidLength(payload.count)
        }

        let bytes = [UInt8](payload)

        guard bytes[0] == version else {
            throw DMPInputDecodeError.unsupportedVersion(bytes[0])
        }

        guard let kind = Kind(rawValue: bytes[1]) else {
            throw DMPInputDecodeError.unsupportedKind(bytes[1])
        }

        guard let phase = Phase(rawValue: bytes[2]) else {
            throw DMPInputDecodeError.unsupportedPhase(bytes[2])
        }

        let sample = DMPInputSample(
            kind: kind,
            phase: phase,
            flags: bytes[3],
            contactID: readUInt32(bytes, offset: 4),
            normalizedX: readFloat(bytes, offset: 8),
            normalizedY: readFloat(bytes, offset: 12),
            pressure: readFloat(bytes, offset: 16),
            altitude: readFloat(bytes, offset: 20),
            azimuth: readFloat(bytes, offset: 24),
            barrelRoll: readFloat(bytes, offset: 28),
            timestampMicroseconds: readUInt64(bytes, offset: 32)
        )

        try sample.validate()
        return sample
    }

    private func validate() throws {
        guard normalizedX.isFinite,
              normalizedY.isFinite,
              (0...1).contains(normalizedX),
              (0...1).contains(normalizedY) else {
            throw DMPInputDecodeError.invalidCoordinates
        }

        guard pressure.isFinite, (0...1).contains(pressure) else {
            throw DMPInputDecodeError.invalidPressure
        }

        guard altitude.isFinite,
              azimuth.isFinite,
              barrelRoll.isFinite else {
            throw DMPInputDecodeError.invalidStylusData
        }
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        offset: Int
    ) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
        UInt32(bytes[offset + 1]) << 16 |
        UInt32(bytes[offset + 2]) << 8 |
        UInt32(bytes[offset + 3])
    }

    private static func readUInt64(
        _ bytes: [UInt8],
        offset: Int
    ) -> UInt64 {
        var value: UInt64 = 0
        for index in offset..<(offset + 8) {
            value = (value << 8) | UInt64(bytes[index])
        }
        return value
    }

    private static func readFloat(
        _ bytes: [UInt8],
        offset: Int
    ) -> Float {
        Float(
            bitPattern: readUInt32(
                bytes,
                offset: offset
            )
        )
    }
}
