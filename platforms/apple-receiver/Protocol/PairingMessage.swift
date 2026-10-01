import CryptoKit
import Foundation
import Security

enum PairingMessageError: Error, LocalizedError {
    case randomGenerationFailed(OSStatus)
    case invalidIdentityKey
    case invalidSignature

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "Could not create DisplayMesh pairing challenge: \(status)"
        case .invalidIdentityKey:
            return "DisplayMesh host identity key is invalid"
        case .invalidSignature:
            return "DisplayMesh pairing signature is invalid"
        }
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

    static func make() throws -> ReceiverHello {
        var bytes = [UInt8](repeating: 0, count: challengeSize)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                baseAddress
            )
        }
        guard status == errSecSuccess else {
            throw PairingMessageError.randomGenerationFailed(status)
        }

        return ReceiverHello(
            challenge: Data(bytes),
            protocolVersion: Int(DMPFrame.version)
        )
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

