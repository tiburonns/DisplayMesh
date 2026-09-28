import Foundation

enum DMPMessageType: UInt8 {
    case hello = 0x01
    case capabilities = 0x02
    case panelDescriptor = 0x03
    case pairing = 0x04
    case video = 0x10
    case input = 0x20
    case telemetry = 0x30
    case keyframeRequest = 0x31
    case error = 0x7f
}

enum DMPProtocolError: Error, LocalizedError, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unsupportedMessageType(UInt8)
    case payloadTooLarge(Int)
    case malformedVideoPacket
    case connectionClosed
    case pairingRejected
    case unexpectedSequence(expected: UInt32, received: UInt32)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid DMP frame magic"
        case .unsupportedVersion(let version):
            return "Unsupported DMP version: \(version)"
        case .unsupportedMessageType(let rawValue):
            return String(format: "Unsupported DMP message type: 0x%02X", rawValue)
        case .payloadTooLarge(let size):
            return "DMP payload exceeds the maximum size: \(size)"
        case .malformedVideoPacket:
            return "Malformed DMP video packet"
        case .connectionClosed:
            return "The receiver connection closed"
        case .pairingRejected:
            return "The receiver rejected pairing"
        case .unexpectedSequence(let expected, let received):
            return "Unexpected DMP sequence: expected \(expected), received \(received)"
        case .timeout(let operation):
            return "Timed out waiting for \(operation)"
        }
    }
}

struct DMPFrame: Equatable {
    static let magic = Data([0x44, 0x4d, 0x50, 0x31])
    static let version: UInt8 = 1
    static let headerSize = 16
    static let maximumPayloadSize = 16 * 1024 * 1024

    let type: DMPMessageType
    let flags: UInt16
    let sequence: UInt32
    let payload: Data

    func encoded() throws -> Data {
        guard payload.count <= Self.maximumPayloadSize else {
            throw DMPProtocolError.payloadTooLarge(payload.count)
        }

        var result = Data(capacity: Self.headerSize + payload.count)
        result.append(Self.magic)
        result.append(Self.version)
        result.append(type.rawValue)
        result.appendBigEndian(flags)
        result.appendBigEndian(sequence)
        result.appendBigEndian(UInt32(payload.count))
        result.append(payload)
        return result
    }
}

struct DMPSequenceTracker {
    private(set) var expected: UInt32 = 1

    mutating func accept(_ sequence: UInt32) throws {
        guard sequence == expected else {
            throw DMPProtocolError.unexpectedSequence(
                expected: expected,
                received: sequence
            )
        }
        expected &+= 1
    }

    mutating func reset() {
        expected = 1
    }
}

struct ReceiverTelemetry: Codable, Equatable {
    static let version = 1

    let protocolVersion: Int
    let receivedFrames: UInt64
    let decodedFrames: UInt64
    let droppedFrames: UInt64
    let framesPerSecond: Double
    let megabitsPerSecond: Double
    let averageDecodeMilliseconds: Double
    let hardwareAccelerated: Bool?
    let lastVideoSequence: UInt32?
}

struct DMPFrameDecoder {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextFrame() throws -> DMPFrame? {
        guard buffer.count >= DMPFrame.headerSize else { return nil }

        guard buffer.prefix(4) == DMPFrame.magic else {
            throw DMPProtocolError.invalidMagic
        }

        let header = [UInt8](buffer.prefix(DMPFrame.headerSize))
        guard header[4] == DMPFrame.version else {
            throw DMPProtocolError.unsupportedVersion(header[4])
        }

        guard let type = DMPMessageType(rawValue: header[5]) else {
            throw DMPProtocolError.unsupportedMessageType(header[5])
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
            throw DMPProtocolError.payloadTooLarge(payloadSize)
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

struct DMPVideoPacket: Equatable {
    static let headerSize = 16
    static let codecH264: UInt8 = 0x01
    static let keyframeFlag: UInt8 = 1 << 0

    let presentationTimeMicroseconds: UInt64
    let durationMicroseconds: UInt32
    let keyframe: Bool
    let annexB: Data

    func encoded() throws -> Data {
        guard !annexB.isEmpty else {
            throw DMPProtocolError.malformedVideoPacket
        }

        var result = Data(capacity: Self.headerSize + annexB.count)
        result.append(Self.codecH264)
        result.append(keyframe ? Self.keyframeFlag : 0)
        result.appendBigEndian(UInt16(0))
        result.appendBigEndian(presentationTimeMicroseconds)
        result.appendBigEndian(durationMicroseconds)
        result.append(annexB)
        return result
    }
}

struct PairingRequest: Codable {
    let peerName: String
    let verificationCode: String
    let protocolVersion: Int
}

struct PairingResponse: Codable {
    let accepted: Bool
    let receiverName: String
    let protocolVersion: Int
}

struct ReceiverPanelDescriptor: Codable {
    enum Orientation: String, Codable {
        case portrait
        case landscape
        case unknown
    }

    let pixelWidth: Int
    let pixelHeight: Int
    let nativeScale: Double
    let maximumFramesPerSecond: Int
    let orientation: Orientation
    let maximumTouchPoints: Int
    let supportsPencil: Bool
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt64) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
