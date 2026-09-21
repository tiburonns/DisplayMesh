import Foundation

enum DMPVideoCodec: UInt8, Codable {
    case h264 = 0x01
    case hevc = 0x02
    case av1 = 0x03
}

struct DMPVideoPacketFlags: OptionSet, Equatable {
    let rawValue: UInt8

    static let keyframe = DMPVideoPacketFlags(rawValue: 1 << 0)
}

enum DMPVideoPacketError: Error, Equatable, LocalizedError {
    case headerTooShort(Int)
    case unsupportedCodec(UInt8)
    case unsupportedFlags(UInt8)
    case reservedHeaderNonZero(UInt16)
    case emptyBitstream

    var errorDescription: String? {
        switch self {
        case .headerTooShort(let size):
            return "DMP video header is too short: \(size) bytes"
        case .unsupportedCodec(let rawValue):
            return String(format: "Unsupported DMP video codec: 0x%02X", rawValue)
        case .unsupportedFlags(let rawValue):
            return String(format: "Unsupported DMP video flags: 0x%02X", rawValue)
        case .reservedHeaderNonZero(let value):
            return String(format: "DMP video reserved header must be zero: 0x%04X", value)
        case .emptyBitstream:
            return "DMP video packet has an empty bitstream"
        }
    }
}

struct DMPVideoPacket: Equatable {
    static let headerSize = 16

    let codec: DMPVideoCodec
    let flags: DMPVideoPacketFlags
    let presentationTimeMicroseconds: UInt64
    let durationMicroseconds: UInt32
    let bitstream: Data

    var isKeyframe: Bool {
        flags.contains(.keyframe)
    }

    func encoded() throws -> Data {
        guard !bitstream.isEmpty else {
            throw DMPVideoPacketError.emptyBitstream
        }

        var data = Data(capacity: Self.headerSize + bitstream.count)
        data.append(codec.rawValue)
        data.append(flags.rawValue)
        data.appendBigEndian(UInt16(0))
        data.appendBigEndian(presentationTimeMicroseconds)
        data.appendBigEndian(durationMicroseconds)
        data.append(bitstream)
        return data
    }

    static func decode(_ payload: Data) throws -> DMPVideoPacket {
        guard payload.count >= headerSize else {
            throw DMPVideoPacketError.headerTooShort(payload.count)
        }

        let bytes = [UInt8](payload.prefix(headerSize))

        guard let codec = DMPVideoCodec(rawValue: bytes[0]) else {
            throw DMPVideoPacketError.unsupportedCodec(bytes[0])
        }

        let unknownFlags = bytes[1] & ~DMPVideoPacketFlags.keyframe.rawValue
        guard unknownFlags == 0 else {
            throw DMPVideoPacketError.unsupportedFlags(bytes[1])
        }

        let reserved = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        guard reserved == 0 else {
            throw DMPVideoPacketError.reservedHeaderNonZero(reserved)
        }

        let presentationTime =
            UInt64(bytes[4]) << 56 |
            UInt64(bytes[5]) << 48 |
            UInt64(bytes[6]) << 40 |
            UInt64(bytes[7]) << 32 |
            UInt64(bytes[8]) << 24 |
            UInt64(bytes[9]) << 16 |
            UInt64(bytes[10]) << 8 |
            UInt64(bytes[11])

        let duration =
            UInt32(bytes[12]) << 24 |
            UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 |
            UInt32(bytes[15])

        let bitstream = payload.subdata(in: headerSize..<payload.count)
        guard !bitstream.isEmpty else {
            throw DMPVideoPacketError.emptyBitstream
        }

        return DMPVideoPacket(
            codec: codec,
            flags: DMPVideoPacketFlags(rawValue: bytes[1]),
            presentationTimeMicroseconds: presentationTime,
            durationMicroseconds: duration,
            bitstream: bitstream
        )
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendBigEndian(_ value: UInt64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }
}
