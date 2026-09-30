import CryptoKit
import XCTest
@testable import DisplayMeshMacMediaHarness

final class ProtectedFrameCodecTests: XCTestCase {
    func testPostPairingFramesRoundTripEncrypted() throws {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()
        let receiverChallenge = Data(repeating: 0x61, count: 32)
        let hostChallenge = Data(repeating: 0x72, count: 32)

        var host = DMPProtectedFrameCodec()
        var receiver = DMPProtectedFrameCodec()
        host.install(
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: try hostPrivate.sharedSecretFromKeyAgreement(
                    with: receiverPrivate.publicKey
                ),
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )
        receiver.install(
            try DMPSecureSession.derive(
                role: .receiver,
                sharedSecret: try receiverPrivate.sharedSecretFromKeyAgreement(
                    with: hostPrivate.publicKey
                ),
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )

        let payload = Data("receiver telemetry".utf8)
        let encrypted = try receiver.outboundFrame(
            type: .telemetry,
            payload: payload,
            sequence: 14
        )
        XCTAssertNotEqual(encrypted.payload, payload)
        XCTAssertEqual(
            encrypted.flags & DMPFrame.encryptedPayloadFlag,
            DMPFrame.encryptedPayloadFlag
        )
        XCTAssertEqual(
            try host.inboundFrame(encrypted).payload,
            payload
        )
    }

    func testSecureCodecRejectsHandshakeAfterInstallation() throws {
        let privateA = P256.KeyAgreement.PrivateKey()
        let privateB = P256.KeyAgreement.PrivateKey()
        var codec = DMPProtectedFrameCodec()
        codec.install(
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: try privateA.sharedSecretFromKeyAgreement(
                    with: privateB.publicKey
                ),
                receiverChallenge: Data(repeating: 0x11, count: 32),
                hostChallenge: Data(repeating: 0x22, count: 32)
            )
        )

        XCTAssertThrowsError(
            try codec.outboundFrame(
                type: .pairing,
                payload: Data(),
                sequence: 2
            )
        )
    }
}
