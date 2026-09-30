import CryptoKit
import XCTest
@testable import DisplayMeshMacMediaHarness

final class SecureSessionTests: XCTestCase {
    func testDirectionalKeysInteroperate() throws {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()
        let hostSecret = try hostPrivate.sharedSecretFromKeyAgreement(
            with: receiverPrivate.publicKey
        )
        let receiverSecret = try receiverPrivate.sharedSecretFromKeyAgreement(
            with: hostPrivate.publicKey
        )

        let receiverChallenge = Data(repeating: 0x31, count: 32)
        let hostChallenge = Data(repeating: 0x42, count: 32)
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

        let payload = Data("DisplayMesh secure payload".utf8)
        let encrypted = try host.seal(
            payload,
            type: .video,
            flags: 0,
            sequence: 99
        )

        XCTAssertEqual(
            try receiver.open(
                encrypted,
                type: .video,
                flags: DMPSecureSession.encryptedPayloadFlag,
                sequence: 99
            ),
            payload
        )
    }

    func testAuthenticatedHeaderMetadataCannotBeChanged() throws {
        let pair = try makePair()
        let encrypted = try pair.host.seal(
            Data("payload".utf8),
            type: .input,
            flags: 0,
            sequence: 5
        )

        XCTAssertThrowsError(
            try pair.receiver.open(
                encrypted,
                type: .input,
                flags: DMPSecureSession.encryptedPayloadFlag,
                sequence: 6
            )
        )
        XCTAssertThrowsError(
            try pair.receiver.open(
                encrypted,
                type: .video,
                flags: DMPSecureSession.encryptedPayloadFlag,
                sequence: 5
            )
        )
    }

    func testCiphertextTamperingFails() throws {
        let pair = try makePair()
        let encrypted = try pair.host.seal(
            Data("payload".utf8),
            type: .video,
            flags: 0,
            sequence: 1
        )
        var tampered = encrypted
        tampered[0] ^= 0x80

        XCTAssertThrowsError(
            try pair.receiver.open(
                tampered,
                type: .video,
                flags: DMPSecureSession.encryptedPayloadFlag,
                sequence: 1
            )
        )
    }

    private func makePair() throws -> (
        host: DMPSecureSession,
        receiver: DMPSecureSession
    ) {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()
        let receiverChallenge = Data(repeating: 0x51, count: 32)
        let hostChallenge = Data(repeating: 0x62, count: 32)

        return (
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: try hostPrivate.sharedSecretFromKeyAgreement(
                    with: receiverPrivate.publicKey
                ),
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            ),
            try DMPSecureSession.derive(
                role: .receiver,
                sharedSecret: try receiverPrivate.sharedSecretFromKeyAgreement(
                    with: hostPrivate.publicKey
                ),
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )
    }
}
