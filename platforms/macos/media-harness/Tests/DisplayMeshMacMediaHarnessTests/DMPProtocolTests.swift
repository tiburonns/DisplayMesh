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
