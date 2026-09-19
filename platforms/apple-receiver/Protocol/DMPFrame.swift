import Foundation

enum DMPMessageType: UInt8, Codable, CaseIterable {
    case hello = 0x01
    case capabilities = 0x02
    case panelDescriptor = 0x03
    case pairing = 0x04
    case video = 0x10
    case input = 0x20
    case telemetry = 0x30
    case keyframeRequest = 0x31
    case error = 0x7F
}

enum DMPFrameError: Error, Equatable, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unsupportedMessageType(UInt8)
    case payloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid DMP frame magic"
        case .unsupportedVersion(let version):
            return "Unsupported DMP version: \(version)"
        case .unsupportedMessageType(let rawValue):
            return "Unsupported DMP message type: \(rawValue)"
        case .payloadTooLarge(let size):
            return "DMP payload exceeds the maximum allowed size: \(size)"
        }
    }
}

struct DMPFrame: Equatable {
    static let magic: [UInt8] = [0x44, 0x4D, 0x50, 0x31]
    static let version: UInt8 = 1
    static let headerSize = 16
    static let maximumPayloadSize = 16 * 1024 * 1024

    let type: DMPMessageType
    let flags: UInt16
    let sequence: UInt32
    let payload: Data

    func encoded() throws -> Data {
        guard payload.count <= Self.maximumPayloadSize else {
            throw DMPFrameError.payloadTooLarge(payload.count)
        }

        var data = Data(capacity: Self.headerSize + payload.count)
        data.append(contentsOf: Self.magic)
        data.append(Self.version)
        data.append(type.rawValue)
        data.appendBigEndian(flags)
        data.appendBigEndian(sequence)
        data.appendBigEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

struct DMPFrameDecoder {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextFrame() throws -> DMPFrame? {
        guard buffer.count >= DMPFrame.headerSize else { return nil }

        let header = [UInt8](buffer.prefix(DMPFrame.headerSize))
        guard Array(header[0..<4]) == DMPFrame.magic else {
            throw DMPFrameError.invalidMagic
        }

        let version = header[4]
        guard version == DMPFrame.version else {
            throw DMPFrameError.unsupportedVersion(version)
        }

        guard let type = DMPMessageType(rawValue: header[5]) else {
            throw DMPFrameError.unsupportedMessageType(header[5])
        }

        let flags = UInt16(header[6]) << 8 | UInt16(header[7])
        let sequence =
            UInt32(header[8]) << 24 |
            UInt32(header[9]) << 16 |
            UInt32(header[10]) << 8 |
            UInt32(header[11])
        let payloadLength =
            UInt32(header[12]) << 24 |
            UInt32(header[13]) << 16 |
            UInt32(header[14]) << 8 |
            UInt32(header[15])

        let payloadSize = Int(payloadLength)
        guard payloadSize <= DMPFrame.maximumPayloadSize else {
            throw DMPFrameError.payloadTooLarge(payloadSize)
        }

        let totalSize = DMPFrame.headerSize + payloadSize
        guard buffer.count >= totalSize else { return nil }

        let payload = buffer.subdata(in: DMPFrame.headerSize..<totalSize)
        buffer.removeSubrange(0..<totalSize)

        return DMPFrame(
            type: type,
            flags: flags,
            sequence: sequence,
            payload: payload
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
}
