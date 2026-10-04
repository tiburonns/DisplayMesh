import XCTest
@testable import DisplayMeshReceiver

final class DMPFrameTests: XCTestCase {
    func testFrameRoundTrip() throws {
        let frame = DMPFrame(
            type: .telemetry,
            flags: 0x0102,
            sequence: 42,
            payload: Data("hello".utf8)
        )

        let encoded = try frame.encoded()
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
        decoder.append(encoded)

        XCTAssertEqual(try decoder.nextFrame(), frame)
        XCTAssertNil(try decoder.nextFrame())
    }

    func testDecoderWaitsForFragmentedPayload() throws {
        let frame = DMPFrame(
            type: .hello,
            flags: 0,
            sequence: 1,
            payload: Data([1, 2, 3, 4, 5])
        )
        let encoded = try frame.encoded()

        var decoder = DMPFrameDecoder()
        decoder.append(encoded.prefix(10))
        XCTAssertNil(try decoder.nextFrame())

        decoder.append(encoded.dropFirst(10))
        XCTAssertEqual(try decoder.nextFrame(), frame)
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

    func testSequenceTrackerRequiresReconnectBeforeWrap() throws {
        var tracker = DMPSequenceTracker(expected: UInt32.max)
        try tracker.accept(UInt32.max)
        XCTAssertTrue(tracker.isExhausted)
        XCTAssertEqual(tracker.expected, UInt32.max)
        XCTAssertThrowsError(try tracker.accept(0)) { error in
            XCTAssertEqual(error as? DMPFrameError, .sequenceExhausted)
        }
        tracker.reset()
        XCTAssertFalse(tracker.isExhausted)
        XCTAssertEqual(tracker.expected, 1)
        XCTAssertNoThrow(try tracker.accept(1))
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
                error as? DMPFrameError,
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

        for type in [DMPMessageType.ping, .pong] {
            XCTAssertNoThrow(
                try DMPFrame(
                    type: type,
                    flags: 0,
                    sequence: 1,
                    payload: Data(repeating: 0, count: 8)
                ).encoded()
            )
            XCTAssertThrowsError(
                try DMPFrame(
                    type: type,
                    flags: 0,
                    sequence: 1,
                    payload: Data(repeating: 0, count: 7)
                ).encoded()
            )
        }
    }

    func testTelemetryRoundTrip() throws {
        let source = ReceiverTelemetry(
            metrics: ReceiverVideoMetrics(
                receivedFrames: 12,
                decodedFrames: 10,
                droppedFrames: 2,
                framesPerSecond: 59.4,
                megabitsPerSecond: 18.2,
                averageDecodeMilliseconds: 3.1,
                hardwareAccelerated: true,
                lastSequence: 99,
                decodeQueueDepth: 2,
                presentationQueueDepth: 1
            )
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(
            ReceiverTelemetry.self,
            from: encoded
        )
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.decodeQueueDepth, 2)
        XCTAssertEqual(decoded.presentationQueueDepth, 1)
    }

    func testReceiverHelloHasExpectedChallengeSize() throws {
        let hello = try ReceiverHello.make()

        XCTAssertTrue(hello.isValid)
        XCTAssertEqual(
            hello.challenge.count,
            ReceiverHello.challengeSize
        )
    }
}
