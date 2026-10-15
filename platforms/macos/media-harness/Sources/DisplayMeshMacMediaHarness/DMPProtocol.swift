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
    case ping = 0x32
    case pong = 0x33
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
        case .ping, .pong: 8
        case .error: 8 * 1024
        }
    }

    var exactPayloadSize: Int? {
        switch self {
        case .input: 40
        case .keyframeRequest: 0
        case .ping, .pong: 8
        default: nil
        }
    }

    func validatePayloadSize(
        _ size: Int,
        flags: UInt16 = 0
    ) throws {
        let encrypted =
            flags & DMPFrame.encryptedPayloadFlag != 0
        let overhead = encrypted
            ? DMPFrame.authenticatedEncryptionOverhead
            : 0

        if let exactPayloadSize {
            let expected = exactPayloadSize + overhead
            guard size == expected else {
                throw DMPProtocolError.invalidPayloadLength(
                    type: rawValue,
                    size: size,
                    expected: expected
                )
            }
            return
        }

        let maximum = maximumPayloadSize + overhead
        guard size <= maximum else {
            throw DMPProtocolError.payloadTooLargeForMessage(
                type: rawValue,
                size: size,
                maximum: maximum
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
    case sequenceExhausted
    case timeout(String)
    case invalidReceiverHello
    case invalidReceiverTelemetry
    case invalidReceiverCapabilities
    case incompatibleReceiverCapabilities
    case invalidPanelDescriptor
    case invalidPairingResponse
    case receiverIdentityChanged
    case receiverTrustStoreUnavailable(String)
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
        case .sequenceExhausted:
            return "DMP sequence space exhausted; reconnect is required"
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
            return "The receiver pairing response failed identity or challenge verification"
        case .receiverIdentityChanged:
            return "The receiver identity changed for a previously trusted DisplayMesh receiver"
        case .receiverTrustStoreUnavailable(let detail):
            return "DisplayMesh cannot verify receiver trust: \(detail)"
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
    static let authenticatedEncryptionOverhead = 28
    static let encryptedPayloadFlag: UInt16 = 0x0001
    static let maximumWirePayloadSize =
        maximumPayloadSize + authenticatedEncryptionOverhead

    let type: DMPMessageType
    let flags: UInt16
    let sequence: UInt32
    let payload: Data

    func encoded() throws -> Data {
        guard payload.count <= Self.maximumWirePayloadSize else {
            throw DMPProtocolError.payloadTooLarge(payload.count)
        }
        try type.validatePayloadSize(
            payload.count,
            flags: flags
        )

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
    private(set) var expected: UInt32
    private(set) var isExhausted: Bool

    init(expected: UInt32 = 1, isExhausted: Bool = false) {
        self.expected = expected == 0 ? 1 : expected
        self.isExhausted = isExhausted || expected == 0
    }

    mutating func accept(_ sequence: UInt32) throws {
        guard !isExhausted else { throw DMPProtocolError.sequenceExhausted }
        guard sequence == expected else {
            throw DMPProtocolError.unexpectedSequence(expected: expected, received: sequence)
        }
        if expected == UInt32.max { isExhausted = true } else { expected += 1 }
    }

    mutating func reset() {
        expected = 1
        isExhausted = false
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
            && encryptedTransport
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
    let decodeQueueDepth: Int?
    let presentationQueueDepth: Int?

    init(
        protocolVersion: Int,
        receivedFrames: UInt64,
        decodedFrames: UInt64,
        droppedFrames: UInt64,
        framesPerSecond: Double,
        megabitsPerSecond: Double,
        averageDecodeMilliseconds: Double,
        hardwareAccelerated: Bool?,
        lastVideoSequence: UInt32?,
        decodeQueueDepth: Int? = nil,
        presentationQueueDepth: Int? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.receivedFrames = receivedFrames
        self.decodedFrames = decodedFrames
        self.droppedFrames = droppedFrames
        self.framesPerSecond = framesPerSecond
        self.megabitsPerSecond = megabitsPerSecond
        self.averageDecodeMilliseconds = averageDecodeMilliseconds
        self.hardwareAccelerated = hardwareAccelerated
        self.lastVideoSequence = lastVideoSequence
        self.decodeQueueDepth = decodeQueueDepth
        self.presentationQueueDepth = presentationQueueDepth
    }

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
            && decodeQueueDepth.map { (0...64).contains($0) } != false
            && presentationQueueDepth.map { (0...8).contains($0) } != false
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
        guard payloadSize <= DMPFrame.maximumWirePayloadSize else {
            throw DMPProtocolError.payloadTooLarge(payloadSize)
        }
        try type.validatePayloadSize(
            payloadSize,
            flags: flags
        )

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

private enum P256WireValidation {
    static func accepts(
        identityPublicKey: Data,
        keyAgreementPublicKey: Data,
        signature: Data
    ) -> Bool {
        // Pairing JSON is already bounded by the DMP pairing-frame budget.
        // Keep an additional local bound before asking CryptoKit to parse.
        guard (1...256).contains(identityPublicKey.count),
              (1...256).contains(keyAgreementPublicKey.count),
              (1...256).contains(signature.count) else {
            return false
        }

        do {
            _ = try P256.Signing.PublicKey(
                rawRepresentation: identityPublicKey
            )
            _ = try P256.KeyAgreement.PublicKey(
                rawRepresentation: keyAgreementPublicKey
            )
            _ = try P256.Signing.ECDSASignature(
                rawRepresentation: signature
            )
            return true
        } catch {
            return false
        }
    }
}

struct PairingRequest: Codable, Equatable {
    let peerName: String
    let peerID: String
    let verificationCode: String
    let protocolVersion: Int
    let challenge: Data
    let hostChallenge: Data
    let identityPublicKey: Data
    let keyAgreementPublicKey: Data
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
            && hostChallenge.count == ReceiverHello.challengeSize
            && P256WireValidation.accepts(
                identityPublicKey: identityPublicKey,
                keyAgreementPublicKey: keyAgreementPublicKey,
                signature: signature
            )
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

    static func makeHostChallenge() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data(
            (0..<ReceiverHello.challengeSize).map { _ in
                UInt8.random(
                    in: UInt8.min...UInt8.max,
                    using: &generator
                )
            }
        )
    }

    static func signed(
        peerName: String,
        peerID: String,
        verificationCode: String,
        challenge: Data,
        hostChallenge: Data,
        keyAgreementPublicKey: Data,
        privateKey: P256.Signing.PrivateKey
    ) throws -> PairingRequest {
        let unsigned = PairingRequest(
            peerName: peerName,
            peerID: peerID,
            verificationCode: verificationCode,
            protocolVersion: Int(DMPFrame.version),
            challenge: challenge,
            hostChallenge: hostChallenge,
            identityPublicKey: privateKey.publicKey.rawRepresentation,
            keyAgreementPublicKey: keyAgreementPublicKey,
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
            hostChallenge: unsigned.hostChallenge,
            identityPublicKey: unsigned.identityPublicKey,
            keyAgreementPublicKey: unsigned.keyAgreementPublicKey,
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
            hostChallenge.base64EncodedString(),
            identityPublicKey.base64EncodedString(),
            keyAgreementPublicKey.base64EncodedString(),
        ]
        return Data(fields.joined(separator: "\u{1F}").utf8)
    }
}

struct PairingResponse: Codable, Equatable {
    let accepted: Bool
    let receiverName: String
    let receiverID: String
    let protocolVersion: Int
    let challenge: Data
    let hostChallenge: Data
    let identityPublicKey: Data
    let keyAgreementPublicKey: Data
    let signature: Data

    var identityFingerprint: String {
        SHA256.hash(data: identityPublicKey)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var hasValidShape: Bool {
        let nameBytes = receiverName.utf8.count
        let hasControlCharacters = receiverName.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }

        return protocolVersion == Int(DMPFrame.version)
            && (1...128).contains(nameBytes)
            && !receiverName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !hasControlCharacters
            && UUID(uuidString: receiverID) != nil
            && challenge.count == ReceiverHello.challengeSize
            && hostChallenge.count == ReceiverHello.challengeSize
            && P256WireValidation.accepts(
                identityPublicKey: identityPublicKey,
                keyAgreementPublicKey: keyAgreementPublicKey,
                signature: signature
            )
    }

    func isAuthentic(
        expectedReceiverChallenge: Data,
        expectedHostChallenge: Data
    ) -> Bool {
        guard hasValidShape,
              challenge == expectedReceiverChallenge,
              hostChallenge == expectedHostChallenge else {
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
        accepted: Bool,
        receiverName: String,
        receiverID: String,
        challenge: Data,
        hostChallenge: Data,
        keyAgreementPublicKey: Data,
        privateKey: P256.Signing.PrivateKey
    ) throws -> PairingResponse {
        let unsigned = PairingResponse(
            accepted: accepted,
            receiverName: receiverName,
            receiverID: receiverID,
            protocolVersion: Int(DMPFrame.version),
            challenge: challenge,
            hostChallenge: hostChallenge,
            identityPublicKey: privateKey.publicKey.rawRepresentation,
            keyAgreementPublicKey: keyAgreementPublicKey,
            signature: Data()
        )

        let signature = try privateKey.signature(
            for: unsigned.signingPayload
        )

        return PairingResponse(
            accepted: unsigned.accepted,
            receiverName: unsigned.receiverName,
            receiverID: unsigned.receiverID,
            protocolVersion: unsigned.protocolVersion,
            challenge: unsigned.challenge,
            hostChallenge: unsigned.hostChallenge,
            identityPublicKey: unsigned.identityPublicKey,
            keyAgreementPublicKey: unsigned.keyAgreementPublicKey,
            signature: signature.rawRepresentation
        )
    }

    private var signingPayload: Data {
        let fields = [
            "DMP1-PAIRING-RESPONSE",
            String(protocolVersion),
            accepted ? "1" : "0",
            receiverID,
            receiverName,
            challenge.base64EncodedString(),
            hostChallenge.base64EncodedString(),
            identityPublicKey.base64EncodedString(),
            keyAgreementPublicKey.base64EncodedString(),
        ]
        return Data(fields.joined(separator: "\u{1F}").utf8)
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
