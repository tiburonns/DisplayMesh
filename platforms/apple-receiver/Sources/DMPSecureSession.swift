import CryptoKit
import Foundation

enum DMPSecureRole {
    case host
    case receiver
}

enum DMPSecureSessionError: Error, LocalizedError {
    case invalidChallengeLength
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .invalidChallengeLength:
            return "DisplayMesh secure-session challenges are invalid"
        case .invalidCiphertext:
            return "DisplayMesh secure-session payload authentication failed"
        }
    }
}

struct DMPSecureSession {
    static let encryptedPayloadFlag = DMPFrame.encryptedPayloadFlag
    static let challengeSize = 32

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey

    static func derive(
        role: DMPSecureRole,
        sharedSecret: SharedSecret,
        receiverChallenge: Data,
        hostChallenge: Data
    ) throws -> DMPSecureSession {
        guard receiverChallenge.count == Self.challengeSize,
              hostChallenge.count == Self.challengeSize else {
            throw DMPSecureSessionError.invalidChallengeLength
        }

        var transcript = Data("DMP1-SECURE-SESSION".utf8)
        transcript.append(receiverChallenge)
        transcript.append(hostChallenge)
        let salt = Data(SHA256.hash(data: transcript))

        let hostToReceiver = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("DMP1-HOST-TO-RECEIVER".utf8),
            outputByteCount: 32
        )

        let receiverToHost = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("DMP1-RECEIVER-TO-HOST".utf8),
            outputByteCount: 32
        )

        switch role {
        case .host:
            return DMPSecureSession(
                sendKey: hostToReceiver,
                receiveKey: receiverToHost
            )
        case .receiver:
            return DMPSecureSession(
                sendKey: receiverToHost,
                receiveKey: hostToReceiver
            )
        }
    }

    func seal(
        _ plaintext: Data,
        type: DMPMessageType,
        flags: UInt16,
        sequence: UInt32
    ) throws -> Data {
        let authenticatedFlags =
            flags | Self.encryptedPayloadFlag
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: sendKey,
            authenticating: Self.additionalAuthenticatedData(
                type: type,
                flags: authenticatedFlags,
                sequence: sequence
            )
        )

        return sealed.combined
    }

    func open(
        _ ciphertext: Data,
        type: DMPMessageType,
        flags: UInt16,
        sequence: UInt32
    ) throws -> Data {
        guard flags & Self.encryptedPayloadFlag != 0 else {
            throw DMPSecureSessionError.invalidCiphertext
        }

        do {
            let sealed = try ChaChaPoly.SealedBox(
                combined: ciphertext
            )
            return try ChaChaPoly.open(
                sealed,
                using: receiveKey,
                authenticating: Self.additionalAuthenticatedData(
                    type: type,
                    flags: flags,
                    sequence: sequence
                )
            )
        } catch {
            throw DMPSecureSessionError.invalidCiphertext
        }
    }

    private static func additionalAuthenticatedData(
        type: DMPMessageType,
        flags: UInt16,
        sequence: UInt32
    ) -> Data {
        var data = Data([
            DMPFrame.version,
            type.rawValue,
        ])

        var bigFlags = flags.bigEndian
        Swift.withUnsafeBytes(of: &bigFlags) {
            data.append(contentsOf: $0)
        }

        var bigSequence = sequence.bigEndian
        Swift.withUnsafeBytes(of: &bigSequence) {
            data.append(contentsOf: $0)
        }

        return data
    }
}
