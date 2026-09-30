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
            hostChallenge: PairingRequest.makeHostChallenge(),
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

    func testPairingShapeRejectsFormattedOrOversizedFields() throws {
        let privateKey = P256.Signing.PrivateKey()
        let hello = try ReceiverHello.make()

        let formattedCode = try PairingRequest.signed(
            peerName: "Mac",
            peerID: UUID().uuidString,
            verificationCode: "123 456",
            challenge: hello.challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: privateKey
        )
        XCTAssertFalse(formattedCode.hasValidShape)

        let oversizedName = try PairingRequest.signed(
            peerName: String(repeating: "M", count: 129),
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: hello.challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: privateKey
        )
        XCTAssertFalse(oversizedName.hasValidShape)
    }

    func testTamperedPairingCodeInvalidatesSignature() throws {
        let privateKey = P256.Signing.PrivateKey()
        let hello = try ReceiverHello.make()

        let valid = try PairingRequest.signed(
            peerName: "Test Mac",
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: hello.challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: privateKey
        )

        let tampered = PairingRequest(
            peerName: valid.peerName,
            peerID: valid.peerID,
            verificationCode: "654321",
            protocolVersion: valid.protocolVersion,
            challenge: valid.challenge,
            hostChallenge: valid.hostChallenge,
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
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertTrue(store.isOperational)
        XCTAssertEqual(store.status(for: first), .new)
        XCTAssertTrue(store.trust(first))
        XCTAssertEqual(store.status(for: first), .trusted)

        let changed = try PairingRequest.signed(
            peerName: "Mac",
            peerID: peerID,
            verificationCode: "123456",
            challenge: hello.challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertEqual(store.status(for: changed), .identityChanged)
    }
}


extension PairingIdentityTests {
    func testPairingResponseIsBoundToActiveChallenge() throws {
        let challenge = try ReceiverHello.make().challenge
        let hostChallenge = PairingRequest.makeHostChallenge()
        let response = try PairingResponse.signed(
            accepted: true,
            receiverName: "Test iPad",
            receiverID: UUID().uuidString,
            challenge: challenge,
            hostChallenge: hostChallenge,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertTrue(
            response.isAuthentic(
                expectedReceiverChallenge: challenge,
                expectedHostChallenge: hostChallenge
            )
        )

        var different = challenge
        different[0] ^= 0xFF
        XCTAssertFalse(
            response.isAuthentic(
                expectedReceiverChallenge: different,
                expectedHostChallenge: hostChallenge
            )
        )

        var differentHost = hostChallenge
        differentHost[0] ^= 0xFF
        XCTAssertFalse(
            response.isAuthentic(
                expectedReceiverChallenge: challenge,
                expectedHostChallenge: differentHost
            )
        )
    }
}


extension PairingIdentityTests {
    func testPairingShapeRejectsControlCharactersAndNonASCIICode() throws {
        let privateKey = P256.Signing.PrivateKey()
        let challenge = try ReceiverHello.make().challenge

        let controlName = try PairingRequest.signed(
            peerName: "Mac\nInjected",
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: privateKey
        )
        XCTAssertFalse(controlName.hasValidShape)

        let unicodeCode = try PairingRequest.signed(
            peerName: "Mac",
            peerID: UUID().uuidString,
            verificationCode: "١٢٣٤٥٦",
            challenge: challenge,
            hostChallenge: PairingRequest.makeHostChallenge(),
            privateKey: privateKey
        )
        XCTAssertFalse(unicodeCode.hasValidShape)
    }
}
