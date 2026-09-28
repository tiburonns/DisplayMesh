import CryptoKit
import XCTest
@testable import DisplayMeshReceiver

final class PairingIdentityTests: XCTestCase {
    func testSignedPairingAuthenticatesAgainstConnectionChallenge() throws {
        let privateKey = P256.Signing.PrivateKey()
        let hello = try ReceiverHello.make()
        let peerID = UUID().uuidString

        let request = try PairingRequest.signed(
            peerName: "Test Mac",
            peerID: peerID,
            verificationCode: "123456",
            challenge: hello.challenge,
            privateKey: privateKey
        )

        XCTAssertTrue(request.hasValidShape)
        XCTAssertTrue(
            request.isAuthentic(expectedChallenge: hello.challenge)
        )

        var wrongChallenge = Data(repeating: 0xA5, count: 32)
        if wrongChallenge == hello.challenge {
            wrongChallenge[0] ^= 0xFF
        }
        XCTAssertFalse(
            request.isAuthentic(expectedChallenge: wrongChallenge)
        )
    }

    func testTamperedPairingCodeInvalidatesSignature() throws {
        let privateKey = P256.Signing.PrivateKey()
        let hello = try ReceiverHello.make()

        let valid = try PairingRequest.signed(
            peerName: "Test Mac",
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: hello.challenge,
            privateKey: privateKey
        )

        let tampered = PairingRequest(
            peerName: valid.peerName,
            peerID: valid.peerID,
            verificationCode: "654321",
            protocolVersion: valid.protocolVersion,
            challenge: valid.challenge,
            identityPublicKey: valid.identityPublicKey,
            signature: valid.signature
        )

        XCTAssertFalse(
            tampered.isAuthentic(expectedChallenge: hello.challenge)
        )
    }

    func testTrustedPeerRejectsIdentityChange() throws {
        let suite = "DisplayMesh.PairingIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TrustedPeerStore(defaults: defaults)
        let hello = try ReceiverHello.make()
        let peerID = UUID().uuidString

        let first = try PairingRequest.signed(
            peerName: "Mac",
            peerID: peerID,
            verificationCode: "123456",
            challenge: hello.challenge,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertEqual(store.status(for: first), .new)
        XCTAssertTrue(store.trust(first))
        XCTAssertEqual(store.status(for: first), .trusted)

        let changed = try PairingRequest.signed(
            peerName: "Mac",
            peerID: peerID,
            verificationCode: "123456",
            challenge: hello.challenge,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertEqual(store.status(for: changed), .identityChanged)
    }
}
