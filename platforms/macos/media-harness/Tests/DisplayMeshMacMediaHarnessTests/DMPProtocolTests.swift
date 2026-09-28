import CryptoKit
import XCTest
@testable import DisplayMeshMacMediaHarness

final class DMPProtocolTests: XCTestCase {
    func testFrameRoundTripAcrossFragments() throws {
        let original = DMPFrame(
            type: .telemetry,
            flags: 0x0102,
            sequence: 42,
            payload: Data("hello".utf8)
        )
        let encoded = try original.encoded()
        XCTAssertEqual(
            encoded,
            Data([
                0x44, 0x4D, 0x50, 0x31,
                0x01, 0x30, 0x01, 0x02,
                0x00, 0x00, 0x00, 0x2A,
                0x00, 0x00, 0x00, 0x05,
                0x68, 0x65, 0x6C, 0x6C, 0x6F,
            ])
        )

        var decoder = DMPFrameDecoder()
        decoder.append(encoded.prefix(7))
        XCTAssertNil(try decoder.nextFrame())

        decoder.append(encoded.dropFirst(7))
        XCTAssertEqual(try decoder.nextFrame(), original)
        XCTAssertNil(try decoder.nextFrame())
    }

    func testSequenceTrackerRejectsReplayAndGap() throws {
        var tracker = DMPSequenceTracker()

        try tracker.accept(1)
        try tracker.accept(2)

        XCTAssertThrowsError(try tracker.accept(2))
        tracker.reset()
        try tracker.accept(1)
        XCTAssertThrowsError(try tracker.accept(3))
    }

    func testPairingPayloadBudgetRejectsHeaderBeforeBodyArrives() {
        let header = Data([
            0x44, 0x4D, 0x50, 0x31,
            DMPFrame.version,
            DMPMessageType.pairing.rawValue,
            0, 0,
            0, 0, 0, 1,
            0, 0, 0x80, 0,
        ])

        var decoder = DMPFrameDecoder()
        decoder.append(header)

        XCTAssertThrowsError(try decoder.nextFrame()) { error in
            XCTAssertEqual(
                error as? DMPProtocolError,
                .payloadTooLargeForMessage(
                    type: DMPMessageType.pairing.rawValue,
                    size: 32 * 1024,
                    maximum: 16 * 1024
                )
            )
        }
    }

    func testExactPayloadBudgetsRejectMalformedInteractiveFrames() {
        XCTAssertThrowsError(
            try DMPFrame(
                type: .input,
                flags: 0,
                sequence: 1,
                payload: Data(repeating: 0, count: 39)
            ).encoded()
        )
        XCTAssertThrowsError(
            try DMPFrame(
                type: .keyframeRequest,
                flags: 0,
                sequence: 1,
                payload: Data([1])
            ).encoded()
        )
    }

    func testInputDecoderRejectsReservedFlags() {
        var payload = Data(repeating: 0, count: DMPInputSample.encodedSize)
        payload[0] = DMPInputSample.version
        payload[1] = DMPInputSample.Kind.touch.rawValue
        payload[2] = DMPInputSample.Phase.began.rawValue
        payload[3] = 0x01

        XCTAssertThrowsError(try DMPInputSample.decode(payload)) { error in
            XCTAssertEqual(
                error as? DMPInputDecodeError,
                .unsupportedFlags(0x01)
            )
        }
    }

    func testPanelDescriptorValidationRejectsUnreasonableValues() {
        XCTAssertTrue(
            ReceiverPanelDescriptor(
                pixelWidth: 2732,
                pixelHeight: 2048,
                nativeScale: 2,
                maximumFramesPerSecond: 120,
                orientation: .landscape,
                maximumTouchPoints: 10,
                supportsPencil: true
            ).isValid
        )

        XCTAssertFalse(
            ReceiverPanelDescriptor(
                pixelWidth: 32,
                pixelHeight: 32,
                nativeScale: .nan,
                maximumFramesPerSecond: 0,
                orientation: .unknown,
                maximumTouchPoints: 100,
                supportsPencil: false
            ).isValid
        )
    }

    func testReceiverTelemetryRoundTrip() throws {
        let source = ReceiverTelemetry(
            protocolVersion: ReceiverTelemetry.version,
            receivedFrames: 120,
            decodedFrames: 118,
            droppedFrames: 2,
            framesPerSecond: 59.2,
            megabitsPerSecond: 21.4,
            averageDecodeMilliseconds: 2.8,
            hardwareAccelerated: true,
            lastVideoSequence: 500
        )

        let encoded = try JSONEncoder().encode(source)
        XCTAssertEqual(
            try JSONDecoder().decode(ReceiverTelemetry.self, from: encoded),
            source
        )
    }

    func testSignedPairingAuthenticatesForReceiverChallenge() throws {
        let privateKey = P256.Signing.PrivateKey()
        let challenge = Data(repeating: 0xA5, count: ReceiverHello.challengeSize)
        let request = try PairingRequest.signed(
            peerName: "Test Mac",
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: challenge,
            privateKey: privateKey
        )

        XCTAssertTrue(request.hasValidShape)
        XCTAssertTrue(
            request.isAuthentic(expectedChallenge: challenge)
        )

        var wrongChallenge = challenge
        wrongChallenge[0] ^= 0xFF
        XCTAssertFalse(
            request.isAuthentic(expectedChallenge: wrongChallenge)
        )
    }

    func testPairingShapeRejectsControlCharactersAndUnicodeDigits() throws {
        let privateKey = P256.Signing.PrivateKey()
        let challenge = Data(
            repeating: 0x5A,
            count: ReceiverHello.challengeSize
        )

        let controlName = try PairingRequest.signed(
            peerName: "Mac\nInjected",
            peerID: UUID().uuidString,
            verificationCode: "123456",
            challenge: challenge,
            privateKey: privateKey
        )
        XCTAssertFalse(controlName.hasValidShape)

        let unicodeCode = try PairingRequest.signed(
            peerName: "Mac",
            peerID: UUID().uuidString,
            verificationCode: "١٢٣٤٥٦",
            challenge: challenge,
            privateKey: privateKey
        )
        XCTAssertFalse(unicodeCode.hasValidShape)
    }

    func testPairingShapeRejectsFormattedCode() throws {
        let privateKey = P256.Signing.PrivateKey()
        let challenge = Data(
            repeating: 0x5A,
            count: ReceiverHello.challengeSize
        )
        let request = try PairingRequest.signed(
            peerName: "Mac",
            peerID: UUID().uuidString,
            verificationCode: "123 456",
            challenge: challenge,
            privateKey: privateKey
        )

        XCTAssertFalse(request.hasValidShape)
    }

    func testVideoPacketHeaderMatchesDMPContract() throws {
        let packet = DMPVideoPacket(
            presentationTimeMicroseconds: 1_234_567,
            durationMicroseconds: 16_667,
            keyframe: true,
            annexB: Data([0, 0, 0, 1, 0x65])
        )

        let encoded = try packet.encoded()

        XCTAssertEqual(encoded.count, DMPVideoPacket.headerSize + 5)
        XCTAssertEqual(encoded[0], DMPVideoPacket.codecH264)
        XCTAssertEqual(
            encoded[1] & DMPVideoPacket.keyframeFlag,
            DMPVideoPacket.keyframeFlag
        )
    }

    func testOversizedFrameIsRejected() {
        let frame = DMPFrame(
            type: .video,
            flags: 0,
            sequence: 1,
            payload: Data(repeating: 0, count: DMPFrame.maximumPayloadSize + 1)
        )

        XCTAssertThrowsError(try frame.encoded())
    }
}
