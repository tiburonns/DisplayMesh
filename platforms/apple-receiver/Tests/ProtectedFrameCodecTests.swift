import CryptoKit
import XCTest
@testable import DisplayMeshReceiver

final class ProtectedFrameCodecTests: XCTestCase {
    func testHandshakeIsPlaintextBeforeSecureSession() throws {
        let codec = DMPProtectedFrameCodec()
        let frame = try codec.outboundFrame(
            type: .hello,
            payload: Data("hello".utf8),
            sequence: 1
        )
        XCTAssertEqual(frame.flags, 0)
        XCTAssertEqual(frame.payload, Data("hello".utf8))
    }

    func testPostPairingTrafficRequiresSecureSession() throws {
        let codec = DMPProtectedFrameCodec()
        XCTAssertThrowsError(
            try codec.outboundFrame(
                type: .telemetry,
                payload: Data("metrics".utf8),
                sequence: 2
            )
        )
    }

    func testEncryptedInputRoundTripAndWireSize() throws {
        var pair = try makePair()
        let payload = Data(repeating: 0x44, count: 40)
        let frame = try pair.host.outboundFrame(
            type: .input,
            payload: payload,
            sequence: 8
        )
        XCTAssertEqual(
            frame.payload.count,
            payload.count + DMPFrame.authenticatedEncryptionOverhead
        )
        XCTAssertNoThrow(try frame.encoded())

        let opened = try pair.receiver.inboundFrame(frame)
        XCTAssertEqual(opened.payload, payload)
        XCTAssertEqual(opened.flags, 0)
    }

    func testEncryptedEmptyKeyframeRequestHasValidWireSize() throws {
        var pair = try makePair()
        let frame = try pair.receiver.outboundFrame(
            type: .keyframeRequest,
            payload: Data(),
            sequence: 11
        )
        XCTAssertEqual(
            frame.payload.count,
            DMPFrame.authenticatedEncryptionOverhead
        )
        XCTAssertNoThrow(try frame.encoded())
        XCTAssertEqual(
            try pair.host.inboundFrame(frame).payload,
            Data()
        )
    }

    func testPlaintextPostPairingFrameIsRejected() throws {
        var pair = try makePair()
        let plaintext = DMPFrame(
            type: .telemetry,
            flags: 0,
            sequence: 3,
            payload: Data("metrics".utf8)
        )
        XCTAssertThrowsError(
            try pair.host.inboundFrame(plaintext)
        )
    }

    private func makePair() throws -> (
        host: DMPProtectedFrameCodec,
        receiver: DMPProtectedFrameCodec
    ) {
        let hostPrivate = P256.KeyAgreement.PrivateKey()
        let receiverPrivate = P256.KeyAgreement.PrivateKey()
        let receiverChallenge = Data(repeating: 0x21, count: 32)
        let hostChallenge = Data(repeating: 0x32, count: 32)

        let hostSecret = try hostPrivate.sharedSecretFromKeyAgreement(
            with: receiverPrivate.publicKey
        )
        let receiverSecret = try receiverPrivate.sharedSecretFromKeyAgreement(
            with: hostPrivate.publicKey
        )

        var host = DMPProtectedFrameCodec()
        var receiver = DMPProtectedFrameCodec()
        host.install(
            try DMPSecureSession.derive(
                role: .host,
                sharedSecret: hostSecret,
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )
        receiver.install(
            try DMPSecureSession.derive(
                role: .receiver,
                sharedSecret: receiverSecret,
                receiverChallenge: receiverChallenge,
                hostChallenge: hostChallenge
            )
        )
        return (host, receiver)
    }
}
