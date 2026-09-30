import CryptoKit
import XCTest
@testable import DisplayMeshMacMediaHarness

final class ReceiverTrustStoreTests: XCTestCase {
    func testSignedReceiverResponseAuthenticatesBothChallenges() throws {
        let receiverChallenge =
            Data(repeating: 0x11, count: ReceiverHello.challengeSize)
        let hostChallenge =
            Data(repeating: 0x22, count: ReceiverHello.challengeSize)

        let response = try PairingResponse.signed(
            accepted: true,
            receiverName: "DisplayMesh Receiver",
            receiverID: UUID().uuidString,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey:
                P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertTrue(
            response.isAuthentic(
                expectedReceiverChallenge: receiverChallenge,
                expectedHostChallenge: hostChallenge
            )
        )

        var wrongHost = hostChallenge
        wrongHost[0] ^= 0xFF
        XCTAssertFalse(
            response.isAuthentic(
                expectedReceiverChallenge: receiverChallenge,
                expectedHostChallenge: wrongHost
            )
        )
    }

    func testTrustStoreRejectsChangedKeyForKnownReceiverID() throws {
        let suite =
            "DisplayMesh.ReceiverTrustStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReceiverTrustStore(defaults: defaults)
        let receiverID = UUID().uuidString
        let receiverChallenge =
            Data(repeating: 0x33, count: ReceiverHello.challengeSize)
        let hostChallenge =
            Data(repeating: 0x44, count: ReceiverHello.challengeSize)

        let first = try PairingResponse.signed(
            accepted: true,
            receiverName: "Receiver",
            receiverID: receiverID,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey:
                P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertEqual(store.status(for: first), .new)
        XCTAssertTrue(store.trust(first))
        XCTAssertEqual(store.status(for: first), .trusted)

        let changed = try PairingResponse.signed(
            accepted: true,
            receiverName: "Receiver",
            receiverID: receiverID,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey:
                P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            privateKey: P256.Signing.PrivateKey()
        )

        XCTAssertEqual(store.status(for: changed), .identityChanged)
    }

    func testAcceptedFlagIsCoveredByReceiverSignature() throws {
        let receiverChallenge =
            Data(repeating: 0x55, count: ReceiverHello.challengeSize)
        let hostChallenge =
            Data(repeating: 0x66, count: ReceiverHello.challengeSize)
        let valid = try PairingResponse.signed(
            accepted: true,
            receiverName: "Receiver",
            receiverID: UUID().uuidString,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey:
                P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            privateKey: P256.Signing.PrivateKey()
        )

        let tampered = PairingResponse(
            accepted: false,
            receiverName: valid.receiverName,
            receiverID: valid.receiverID,
            protocolVersion: valid.protocolVersion,
            challenge: valid.challenge,
            hostChallenge: valid.hostChallenge,
            identityPublicKey: valid.identityPublicKey,
            keyAgreementPublicKey: valid.keyAgreementPublicKey,
            signature: valid.signature
        )

        XCTAssertFalse(
            tampered.isAuthentic(
                expectedReceiverChallenge: receiverChallenge,
                expectedHostChallenge: hostChallenge
            )
        )
    }
}


extension ReceiverTrustStoreTests {
    func testTamperedReceiverEphemeralKeyInvalidatesSignature() throws {
        let receiverChallenge =
            Data(repeating: 0x77, count: ReceiverHello.challengeSize)
        let hostChallenge =
            Data(repeating: 0x88, count: ReceiverHello.challengeSize)

        let valid = try PairingResponse.signed(
            accepted: true,
            receiverName: "Receiver",
            receiverID: UUID().uuidString,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey:
                P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            privateKey: P256.Signing.PrivateKey()
        )

        var changedKey = valid.keyAgreementPublicKey
        changedKey[changedKey.startIndex] ^= 0x01

        let tampered = PairingResponse(
            accepted: valid.accepted,
            receiverName: valid.receiverName,
            receiverID: valid.receiverID,
            protocolVersion: valid.protocolVersion,
            challenge: valid.challenge,
            hostChallenge: valid.hostChallenge,
            identityPublicKey: valid.identityPublicKey,
            keyAgreementPublicKey: changedKey,
            signature: valid.signature
        )

        XCTAssertFalse(
            tampered.isAuthentic(
                expectedReceiverChallenge: receiverChallenge,
                expectedHostChallenge: hostChallenge
            )
        )
    }
}
