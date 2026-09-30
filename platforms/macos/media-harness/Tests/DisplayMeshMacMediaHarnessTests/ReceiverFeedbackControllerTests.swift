import XCTest
@testable import DisplayMeshMacMediaHarness

final class ReceiverFeedbackControllerTests: XCTestCase {
    func testWarmupDoesNotChangeBitrate() {
        let controller = ReceiverFeedbackController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        XCTAssertNil(
            controller.update(
                telemetry(
                    decoded: 20,
                    dropped: 0,
                    fps: 25,
                    decodeMilliseconds: 30
                )
            )
        )
        XCTAssertEqual(controller.currentBitrateMbps, 24)
    }

    func testPersistentStressReducesBitrate() {
        let controller = ReceiverFeedbackController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        XCTAssertNil(
            controller.update(
                telemetry(
                    decoded: 100,
                    dropped: 0,
                    fps: 50,
                    decodeMilliseconds: 8
                )
            )
        )

        XCTAssertEqual(
            controller.update(
                telemetry(
                    decoded: 160,
                    dropped: 0,
                    fps: 50,
                    decodeMilliseconds: 8
                )
            ),
            21
        )
    }

    func testSevereDropPressureReducesImmediately() {
        let controller = ReceiverFeedbackController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(
                decoded: 100,
                dropped: 2,
                fps: 60,
                decodeMilliseconds: 3
            )
        )

        XCTAssertEqual(
            controller.update(
                telemetry(
                    decoded: 150,
                    dropped: 7,
                    fps: 60,
                    decodeMilliseconds: 3
                )
            ),
            19
        )
    }

    func testHealthySamplesRecoverGraduallyWithoutOvershootingInitialBitrate() {
        let controller = ReceiverFeedbackController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        XCTAssertEqual(
            controller.update(
                telemetry(
                    decoded: 100,
                    dropped: 5,
                    fps: 35,
                    decodeMilliseconds: 20
                )
            ),
            19
        )

        var decision: Int?
        for index in 0..<8 {
            decision = controller.update(
                telemetry(
                    decoded: UInt64(200 + index * 60),
                    dropped: 5,
                    fps: 60,
                    decodeMilliseconds: 3
                )
            )
        }

        XCTAssertEqual(decision, 20)
        XCTAssertLessThanOrEqual(
            controller.currentBitrateMbps,
            24
        )
    }

    func testInvalidTelemetryIsIgnored() {
        let controller = ReceiverFeedbackController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        XCTAssertNil(
            controller.update(
                telemetry(
                    decoded: 100,
                    dropped: 0,
                    fps: -1,
                    decodeMilliseconds: 3
                )
            )
        )
        XCTAssertEqual(controller.currentBitrateMbps, 24)
    }

    private func telemetry(
        decoded: UInt64,
        dropped: UInt64,
        fps: Double,
        decodeMilliseconds: Double
    ) -> ReceiverTelemetry {
        ReceiverTelemetry(
            protocolVersion: ReceiverTelemetry.version,
            receivedFrames: decoded + dropped,
            decodedFrames: decoded,
            droppedFrames: dropped,
            framesPerSecond: fps,
            megabitsPerSecond: 20,
            averageDecodeMilliseconds: decodeMilliseconds,
            hardwareAccelerated: true,
            lastVideoSequence: 100
        )
    }
}
