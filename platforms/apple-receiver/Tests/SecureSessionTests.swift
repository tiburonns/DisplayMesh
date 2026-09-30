import CryptoKit
import XCTest
@testable import DisplayMeshReceiver

final class SecureSessionTests: XCTestCase {
    func testHostToReceiverAndReceiverToHostRoundTrip() throws {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()

        let hostSecret = try hostPrivate.sharedSecretFromKeyAgreement(
            with: receiverPrivate.publicKey
        )
        let receiverSecret = try receiverPrivate.sharedSecretFromKeyAgreement(
            with: hostPrivate.publicKey
        )

        let receiverChallenge = Data(repeating: 0x11, count: 32)
        let hostChallenge = Data(repeating: 0x22, count: 32)

        let host = try DMPSecureSession.derive(
            role: .host,
            sharedSecret: hostSecret,
            receiverChallenge: receiverChallenge,
            hostChallenge: hostChallenge
        )
        let receiver = try DMPSecureSession.derive(
            role: .receiver,
            sharedSecret: receiverSecret,
            receiverChallenge: receiverChallenge,
            hostChallenge: hostChallenge
        )

        let flags = DMPSecureSession.encryptedPayloadFlag
        let hostPayload = Data("host payload".utf8)
        let encryptedHost = try host.seal(
            hostPayload,
            type: .video,
            flags: 0,
            sequence: 7
        )
        XCTAssertEqual(
            try receiver.open(
                encryptedHost,
                type: .video,
                flags: flags,
                sequence: 7
            ),
            hostPayload
        )

        let receiverPayload = Data("receiver payload".utf8)
        let encryptedReceiver = try receiver.seal(
            receiverPayload,
            type: .telemetry,
            flags: 0,
            sequence: 8
        )
        XCTAssertEqual(
            try host.open(
                encryptedReceiver,
                type: .telemetry,
                flags: flags,
                sequence: 8
            ),
            receiverPayload
        )
    }

    func testSequenceAndTypeAreAuthenticated() throws {
        let pair = try makePair()
        let encrypted = try pair.host.seal(
            Data("payload".utf8),
            type: .video,
            flags: 0,
            sequence: 42
        )
        let flags = DMPSecureSession.encryptedPayloadFlag

        XCTAssertThrowsError(
            try pair.receiver.open(
                encrypted,
                type: .video,
                flags: flags,
                sequence: 43
            )
        )
        XCTAssertThrowsError(
            try pair.receiver.open(
                encrypted,
                type: .telemetry,
                flags: flags,
                sequence: 42
            )
        )
    }

    func testTamperingAndWrongTranscriptFailClosed() throws {
        let pair = try makePair()
        let flags = DMPSecureSession.encryptedPayloadFlag
        let encrypted = try pair.host.seal(
            Data("payload".utf8),
            type: .video,
            flags: 0,
            sequence: 1
        )

        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01

        XCTAssertThrowsError(
            try pair.receiver.open(
                tampered,
                type: .video,
                flags: flags,
                sequence: 1
            )
        )

        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()
        let hostSecret = try hostPrivate.sharedSecretFromKeyAgreement(
            with: receiverPrivate.publicKey
        )
        let receiverSecret = try receiverPrivate.sharedSecretFromKeyAgreement(
            with: hostPrivate.publicKey
        )

        let host = try DMPSecureSession.derive(
            role: .host,
            sharedSecret: hostSecret,
            receiverChallenge: Data(repeating: 0x11, count: 32),
            hostChallenge: Data(repeating: 0x22, count: 32)
        )
        let wrongReceiver = try DMPSecureSession.derive(
            role: .receiver,
            sharedSecret: receiverSecret,
            receiverChallenge: Data(repeating: 0x11, count: 32),
            hostChallenge: Data(repeating: 0x23, count: 32)
        )

        let transcriptBound = try host.seal(
            Data("bound".utf8),
            type: .capabilities,
            flags: 0,
            sequence: 2
        )

        XCTAssertThrowsError(
            try wrongReceiver.open(
                transcriptBound,
                type: .capabilities,
                flags: flags,
                sequence: 2
            )
        )
    }

    func testInvalidChallengeLengthIsRejected() throws {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let peerKey = P256.KeyAgreement.PrivateKey()
        let secret = try privateKey.sharedSecretFromKeyAgreement(
            with: peerKey.publicKey
        )

        XCTAssertThrowsError(
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: secret,
                receiverChallenge: Data(repeating: 0, count: 31),
                hostChallenge: Data(repeating: 0, count: 32)
            )
        )
    }

    private func makePair() throws -> (
        host: DMPSecureSession,
        receiver: DMPSecureSession
    ) {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()

        let hostSecret = try hostPrivate.sharedSecretFromKeyAgreement(
            with: receiverPrivate.publicKey
        )
        let receiverSecret = try receiverPrivate.sharedSecretFromKeyAgreement(
            with: hostPrivate.publicKey
        )

        let receiverChallenge = Data(repeating: 0xA1, count: 32)
        let hostChallenge = Data(repeating: 0xB2, count: 32)

        return (
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: hostSecret,
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            ),
            try DMPSecureSession.derive(
                role: .receiver,
                sharedSecret: receiverSecret,
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )
    }
}
