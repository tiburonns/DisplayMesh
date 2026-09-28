import CryptoKit
import XCTest
@testable import DisplayMeshMacMediaHarness

final class DMPProtocolTests: XCTestCase {
    func testFrameRoundTripAcrossFragments() throws {
        let original = DMPFrame(
            type: .telemetry,
            flags: 0x1020,
            sequence: 42,
            payload: Data("hello".utf8)
        )
        let encoded = try original.encoded()

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


extension DMPProtocolTests {
    func testReceiverTelemetryRejectsImpossibleCountersAndNumbers() {
        let impossibleCounters = ReceiverTelemetry(
            protocolVersion: ReceiverTelemetry.version,
            receivedFrames: 10,
            decodedFrames: 11,
            droppedFrames: 0,
            framesPerSecond: 60,
            megabitsPerSecond: 20,
            averageDecodeMilliseconds: 3,
            hardwareAccelerated: true,
            lastVideoSequence: 10
        )
        XCTAssertFalse(impossibleCounters.isValid)

        let invalidNumber = ReceiverTelemetry(
            protocolVersion: ReceiverTelemetry.version,
            receivedFrames: 10,
            decodedFrames: 10,
            droppedFrames: 0,
            framesPerSecond: .nan,
            megabitsPerSecond: 20,
            averageDecodeMilliseconds: 3,
            hardwareAccelerated: true,
            lastVideoSequence: 10
        )
        XCTAssertFalse(invalidNumber.isValid)
    }

    func testPanelDescriptorBounds() {
        let valid = ReceiverPanelDescriptor(
            pixelWidth: 2796,
            pixelHeight: 1290,
            nativeScale: 3,
            maximumFramesPerSecond: 120,
            orientation: .landscape,
            maximumTouchPoints: 10,
            supportsPencil: false
        )
        XCTAssertTrue(valid.isValid)

        let absurd = ReceiverPanelDescriptor(
            pixelWidth: 100_000,
            pixelHeight: 1290,
            nativeScale: 3,
            maximumFramesPerSecond: 1_000,
            orientation: .landscape,
            maximumTouchPoints: 100,
            supportsPencil: false
        )
        XCTAssertFalse(absurd.isValid)
    }

    func testPairingResponseBoundsReceiverName() {
        let valid = PairingResponse(
            accepted: true,
            receiverName: "iPad",
            protocolVersion: Int(DMPFrame.version)
        )
        XCTAssertTrue(valid.hasValidShape)

        let empty = PairingResponse(
            accepted: true,
            receiverName: "",
            protocolVersion: Int(DMPFrame.version)
        )
        XCTAssertFalse(empty.hasValidShape)

        let oversized = PairingResponse(
            accepted: true,
            receiverName: String(repeating: "x", count: 129),
            protocolVersion: Int(DMPFrame.version)
        )
        XCTAssertFalse(oversized.hasValidShape)
    }
}
