import CryptoKit
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

    var maximumPayloadSize: Int {
        switch self {
        case .hello: 4 * 1024
        case .capabilities: 64 * 1024
        case .panelDescriptor: 16 * 1024
        case .pairing: 16 * 1024
        case .video: DMPFrame.maximumPayloadSize
        case .input: 40
        case .telemetry: 16 * 1024
        case .keyframeRequest: 0
        case .error: 8 * 1024
        }
    }

    var exactPayloadSize: Int? {
        switch self {
        case .input: 40
        case .keyframeRequest: 0
        default: nil
        }
    }

    func validatePayloadSize(_ size: Int) throws {
        if let exactPayloadSize {
            guard size == exactPayloadSize else {
                throw DMPProtocolError.invalidPayloadLength(
                    type: rawValue,
                    size: size,
                    expected: exactPayloadSize
                )
            }
            return
        }

        guard size <= maximumPayloadSize else {
            throw DMPProtocolError.payloadTooLargeForMessage(
                type: rawValue,
                size: size,
                maximum: maximumPayloadSize
            )
        }
    }
}

enum DMPProtocolError: Error, LocalizedError, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unsupportedMessageType(UInt8)
    case payloadTooLarge(Int)
    case payloadTooLargeForMessage(type: UInt8, size: Int, maximum: Int)
    case invalidPayloadLength(type: UInt8, size: Int, expected: Int)
    case malformedVideoPacket
    case connectionClosed
    case pairingRejected
    case unexpectedSequence(expected: UInt32, received: UInt32)
    case timeout(String)
    case invalidReceiverHello
    case invalidReceiverTelemetry
    case invalidReceiverCapabilities
    case incompatibleReceiverCapabilities
    case invalidPanelDescriptor
    case invalidPairingResponse
    case invalidSessionPhase(String)
    case invalidPairingRequest

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
        case .payloadTooLargeForMessage(let type, let size, let maximum):
            return String(
                format: "DMP message 0x%02X payload is too large: %d bytes (max %d)",
                type,
                size,
                maximum
            )
        case .invalidPayloadLength(let type, let size, let expected):
            return String(
                format: "DMP message 0x%02X payload has invalid size: %d bytes (expected %d)",
                type,
                size,
                expected
            )
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
        case .invalidReceiverHello:
            return "The receiver sent an invalid DisplayMesh hello challenge"
        case .invalidReceiverTelemetry:
            return "The receiver sent invalid DisplayMesh telemetry"
        case .invalidReceiverCapabilities:
            return "The receiver sent invalid DisplayMesh capabilities"
        case .incompatibleReceiverCapabilities:
            return "The receiver does not support the current H.264/TCP development path"
        case .invalidPanelDescriptor:
            return "The receiver sent an invalid DisplayMesh panel descriptor"
        case .invalidPairingResponse:
            return "The receiver pairing response does not match the active challenge"
        case .invalidSessionPhase(let detail):
            return "Unexpected DMP frame for session phase: \(detail)"
        case .invalidPairingRequest:
            return "The DisplayMesh pairing request is invalid"
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
        try type.validatePayloadSize(payload.count)

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

struct ReceiverCapabilities: Codable, Equatable {
    static let schemaVersion = 1
    static let h264 = "h264"
    static let tcp = "tcp"

    let schemaVersion: Int
    let protocolVersion: Int
    let codecs: [String]
    let connectionBindings: [String]
    let inputKinds: [String]
    let telemetrySupported: Bool
    let maximumVideoPayloadBytes: Int
    let encryptedTransport: Bool

    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && protocolVersion == Int(DMPFrame.version)
            && !codecs.isEmpty
            && codecs.count <= 8
            && connectionBindings.count <= 8
            && inputKinds.count <= 8
            && Set(codecs).count == codecs.count
            && Set(connectionBindings).count == connectionBindings.count
            && Set(inputKinds).count == inputKinds.count
            && (1...DMPFrame.maximumPayloadSize)
                .contains(maximumVideoPayloadBytes)
    }

    var supportsDevelopmentHost: Bool {
        isValid
            && codecs.contains(Self.h264)
            && connectionBindings.contains(Self.tcp)
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

    var isValid: Bool {
        protocolVersion == Self.version
            && decodedFrames <= receivedFrames
            && droppedFrames <= receivedFrames
            && framesPerSecond.isFinite
            && (0...480).contains(framesPerSecond)
            && megabitsPerSecond.isFinite
            && (0...2_000).contains(megabitsPerSecond)
            && averageDecodeMilliseconds.isFinite
            && (0...10_000).contains(averageDecodeMilliseconds)
    }
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
        try type.validatePayloadSize(payloadSize)

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

struct ReceiverHello: Codable, Equatable {
    static let challengeSize = 32

    let challenge: Data
    let protocolVersion: Int

    var isValid: Bool {
        protocolVersion == Int(DMPFrame.version)
            && challenge.count == Self.challengeSize
    }
}

struct PairingRequest: Codable, Equatable {
    let peerName: String
    let peerID: String
    let verificationCode: String
    let protocolVersion: Int
    let challenge: Data
    let identityPublicKey: Data
    let signature: Data

    var normalizedVerificationCode: String {
        String(
            decoding: verificationCode.utf8.filter {
                (48...57).contains($0)
            },
            as: UTF8.self
        )
    }

    var identityFingerprint: String {
        SHA256.hash(data: identityPublicKey)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var hasValidShape: Bool {
        let peerNameBytes = peerName.utf8.count
        let hasControlCharacters = peerName.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        let trimmedName = peerName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return protocolVersion == Int(DMPFrame.version)
            && (1...128).contains(peerNameBytes)
            && !trimmedName.isEmpty
            && !hasControlCharacters
            && verificationCode == normalizedVerificationCode
            && normalizedVerificationCode.count == 6
            && UUID(uuidString: peerID) != nil
            && challenge.count == ReceiverHello.challengeSize
            && identityPublicKey.count == 65
            && signature.count == 64
    }

    func isAuthentic(expectedChallenge: Data) -> Bool {
        guard hasValidShape, challenge == expectedChallenge else {
            return false
        }

        do {
            let publicKey = try P256.Signing.PublicKey(
                rawRepresentation: identityPublicKey
            )
            let signature = try P256.Signing.ECDSASignature(
                rawRepresentation: signature
            )
            return publicKey.isValidSignature(
                signature,
                for: signingPayload
            )
        } catch {
            return false
        }
    }

    static func signed(
        peerName: String,
        peerID: String,
        verificationCode: String,
        challenge: Data,
        privateKey: P256.Signing.PrivateKey
    ) throws -> PairingRequest {
        let unsigned = PairingRequest(
            peerName: peerName,
            peerID: peerID,
            verificationCode: verificationCode,
            protocolVersion: Int(DMPFrame.version),
            challenge: challenge,
            identityPublicKey: privateKey.publicKey.rawRepresentation,
            signature: Data()
        )

        let signature = try privateKey.signature(
            for: unsigned.signingPayload
        )

        return PairingRequest(
            peerName: unsigned.peerName,
            peerID: unsigned.peerID,
            verificationCode: unsigned.verificationCode,
            protocolVersion: unsigned.protocolVersion,
            challenge: unsigned.challenge,
            identityPublicKey: unsigned.identityPublicKey,
            signature: signature.rawRepresentation
        )
    }

    private var signingPayload: Data {
        let fields = [
            "DMP1-PAIRING",
            String(protocolVersion),
            peerID,
            peerName,
            normalizedVerificationCode,
            challenge.base64EncodedString(),
            identityPublicKey.base64EncodedString(),
        ]
        return Data(fields.joined(separator: "\u{1F}").utf8)
    }
}

struct PairingResponse: Codable, Equatable {
    let accepted: Bool
    let receiverName: String
    let protocolVersion: Int
    let challenge: Data

    func isValid(expectedChallenge: Data) -> Bool {
        protocolVersion == Int(DMPFrame.version)
            && challenge.count == ReceiverHello.challengeSize
            && challenge == expectedChallenge
    }
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

    var isValid: Bool {
        (320...16_384).contains(pixelWidth)
            && (320...16_384).contains(pixelHeight)
            && nativeScale.isFinite
            && (0.5...8).contains(nativeScale)
            && (1...240).contains(maximumFramesPerSecond)
            && (0...32).contains(maximumTouchPoints)
    }
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
