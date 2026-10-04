import XCTest
@testable import DisplayMeshMacMediaHarness

final class ReceiverAdaptiveControllerTests: XCTestCase {
    private func telemetry(
        received: UInt64,
        dropped: UInt64,
        fps: Double = 60,
        decodeMilliseconds: Double = 3,
        decodeQueueDepth: Int? = nil,
        presentationQueueDepth: Int? = nil
    ) -> ReceiverTelemetry {
        ReceiverTelemetry(
            protocolVersion: ReceiverTelemetry.version,
            receivedFrames: received,
            decodedFrames: received - min(received, dropped),
            droppedFrames: dropped,
            framesPerSecond: fps,
            megabitsPerSecond: 20,
            averageDecodeMilliseconds: decodeMilliseconds,
            hardwareAccelerated: true,
            lastVideoSequence: UInt32(clamping: received),
            decodeQueueDepth: decodeQueueDepth,
            presentationQueueDepth: presentationQueueDepth
        )
    }

    func testFirstSampleOnlyEstablishesBaseline() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        XCTAssertNil(
            controller.update(
                telemetry(received: 60, dropped: 0)
            )
        )
        XCTAssertEqual(controller.bitrateMbps, 24)
    }

    func testPersistentModerateStressReducesBitrate() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )
        XCTAssertNil(
            controller.update(
                telemetry(
                    received: 120,
                    dropped: 2,
                    fps: 50,
                    decodeMilliseconds: 15
                )
            )
        )

        let decision = controller.update(
            telemetry(
                received: 180,
                dropped: 4,
                fps: 50,
                decodeMilliseconds: 15
            )
        )

        XCTAssertEqual(decision?.bitrateMbps, 21)
        XCTAssertEqual(decision?.rasterScale, 1.0)
        XCTAssertEqual(decision?.requestKeyframe, false)
    }

    func testFullDecodeQueueIsImmediateSevereStress() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 40,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        let decision = controller.update(
            telemetry(
                received: 120,
                dropped: 0,
                fps: 60,
                decodeMilliseconds: 3,
                decodeQueueDepth: 3,
                presentationQueueDepth: 0
            )
        )

        XCTAssertEqual(decision?.bitrateMbps, 30)
        XCTAssertEqual(decision?.requestKeyframe, true)
    }

    func testPresentationQueueStressUsesHysteresis() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        XCTAssertNil(
            controller.update(
                telemetry(
                    received: 120,
                    dropped: 0,
                    fps: 60,
                    decodeMilliseconds: 3,
                    decodeQueueDepth: 0,
                    presentationQueueDepth: 2
                )
            )
        )

        let decision = controller.update(
            telemetry(
                received: 180,
                dropped: 0,
                fps: 60,
                decodeMilliseconds: 3,
                decodeQueueDepth: 0,
                presentationQueueDepth: 2
            )
        )

        XCTAssertEqual(decision?.bitrateMbps, 21)
        XCTAssertEqual(decision?.requestKeyframe, false)
    }

    func testFullPresentationQueueIsImmediateSevereStress() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 40,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        let decision = controller.update(
            telemetry(
                received: 120,
                dropped: 0,
                fps: 60,
                decodeMilliseconds: 3,
                decodeQueueDepth: 0,
                presentationQueueDepth: 3
            )
        )

        XCTAssertEqual(decision?.bitrateMbps, 30)
        XCTAssertEqual(decision?.requestKeyframe, true)
    }

    func testSevereStressReducesImmediatelyAndRequestsKeyframe() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 40,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )
        let decision = controller.update(
            telemetry(
                received: 120,
                dropped: 8,
                fps: 35,
                decodeMilliseconds: 24
            )
        )

        XCTAssertEqual(decision?.bitrateMbps, 30)
        XCTAssertEqual(decision?.rasterScale, 1.0)
        XCTAssertEqual(decision?.requestKeyframe, true)
    }

    func testHealthyLinkRecoversGradually() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 12,
            maximumBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        var decision: ReceiverAdaptationDecision?
        for index in 1...6 {
            decision = controller.update(
                telemetry(
                    received: 60 + UInt64(index * 60),
                    dropped: 0,
                    fps: 60,
                    decodeMilliseconds: 3
                )
            )
        }

        XCTAssertEqual(decision?.bitrateMbps, 13)
        XCTAssertEqual(decision?.rasterScale, 1.0)
        XCTAssertEqual(decision?.requestKeyframe, false)
    }

    func testPersistentSevereStressStepsRasterDownWithHysteresis() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 40,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        var decision: ReceiverAdaptationDecision?
        for index in 1...3 {
            decision = controller.update(
                telemetry(
                    received: 60 + UInt64(index * 60),
                    dropped: UInt64(index * 8),
                    fps: 35,
                    decodeMilliseconds: 24
                )
            )
        }

        XCTAssertEqual(decision?.rasterScale, 0.85)
        XCTAssertEqual(controller.rasterScale, 0.85)
        XCTAssertEqual(decision?.requestKeyframe, true)
    }

    func testHealthyLinkRestoresRasterOnlyAfterBitrateRecovered() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            initialRasterScale: 0.75,
            maximumBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )

        var decision: ReceiverAdaptationDecision?
        for index in 1...12 {
            if let next = controller.update(
                telemetry(
                    received: 60 + UInt64(index * 60),
                    dropped: 0,
                    fps: 60,
                    decodeMilliseconds: 3
                )
            ) {
                decision = next
            }
        }

        XCTAssertEqual(controller.rasterScale, 0.85)
        XCTAssertEqual(decision?.rasterScale, 0.85)
        XCTAssertEqual(decision?.requestKeyframe, true)
    }

    func testRasterScaleInitializationSnapsToSupportedStep() {
        let controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            initialRasterScale: 0.81,
            targetFramesPerSecond: 60
        )

        XCTAssertEqual(controller.rasterScale, 0.85)
    }

    func testCounterResetDoesNotLookLikeCongestion() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 600, dropped: 20)
        )
        XCTAssertNil(
            controller.update(
                telemetry(received: 20, dropped: 0)
            )
        )
        XCTAssertEqual(controller.bitrateMbps, 24)
    }

    func testInvalidTelemetryIsIgnored() {
        var controller = ReceiverAdaptiveController(
            initialBitrateMbps: 24,
            targetFramesPerSecond: 60
        )

        _ = controller.update(
            telemetry(received: 60, dropped: 0)
        )
        XCTAssertNil(
            controller.update(
                telemetry(
                    received: 120,
                    dropped: 0,
                    fps: .nan,
                    decodeMilliseconds: 3
                )
            )
        )
        XCTAssertEqual(controller.bitrateMbps, 24)
    }
}
