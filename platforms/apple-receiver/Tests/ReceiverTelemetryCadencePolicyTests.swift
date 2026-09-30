import XCTest
@testable import DisplayMeshReceiver

final class ReceiverTelemetryCadencePolicyTests:
    XCTestCase {
    func testNormalTelemetryRemainsOneHertz() {
        XCTAssertFalse(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: 10.9,
                    lastSentAt: 10,
                    decodeQueueDepth: 1
                )
        )
        XCTAssertTrue(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: 11,
                    lastSentAt: 10,
                    decodeQueueDepth: 1
                )
        )
    }

    func testSaturatedDecodeQueueCanReportAtFourHertz() {
        XCTAssertFalse(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: 10.24,
                    lastSentAt: 10,
                    decodeQueueDepth: 3
                )
        )
        XCTAssertTrue(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: 10.25,
                    lastSentAt: 10,
                    decodeQueueDepth: 3
                )
        )
    }

    func testInvalidClockStateFailsClosed() {
        XCTAssertFalse(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: .nan,
                    lastSentAt: 1,
                    decodeQueueDepth: 3
                )
        )
        XCTAssertFalse(
            ReceiverTelemetryCadencePolicy
                .shouldSend(
                    now: 1,
                    lastSentAt: 2,
                    decodeQueueDepth: 3
                )
        )
    }
}
