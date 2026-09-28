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

struct PairingRequest: Codable, Equatable {
    let peerName: String
    let peerID: String
    let verificationCode: String
    let protocolVersion: Int
    let challenge: Data
    let identityPublicKey: Data
    let signature: Data

    var normalizedVerificationCode: String {
        verificationCode.filter(\.isNumber)
    }

    var identityFingerprint: String {
        SHA256.hash(data: identityPublicKey)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var hasValidShape: Bool {
        let peerNameBytes = peerName.utf8.count
        return protocolVersion == Int(DMPFrame.version)
            && (1...128).contains(peerNameBytes)
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
}
