import XCTest
@testable import DisplayMeshMacMediaHarness

final class RoundTripProbeTrackerTests: XCTestCase {
    func testMatchingProbeMeasuresMillisecondsAndClearsPendingState() {
        var tracker = RoundTripProbeTracker()
        let token = tracker.begin(now: 10)

        XCTAssertEqual(token, 1)
        XCTAssertNil(tracker.begin(now: 10.1))
        let measured =
            tracker.complete(token: 1, now: 10.025)
        XCTAssertNotNil(measured)
        XCTAssertEqual(
            measured ?? -1,
            25,
            accuracy: 0.001
        )
        XCTAssertNil(tracker.outstandingToken)
        XCTAssertEqual(tracker.begin(now: 11), 2)
    }

    func testMismatchedTokenDoesNotConsumeOutstandingProbe() {
        var tracker = RoundTripProbeTracker()
        XCTAssertEqual(tracker.begin(now: 1), 1)

        XCTAssertNil(
            tracker.complete(token: 2, now: 1.1)
        )
        XCTAssertEqual(tracker.outstandingToken, 1)
        XCTAssertNotNil(
            tracker.complete(token: 1, now: 1.2)
        )
    }

    func testInvalidClockStateFailsClosed() {
        var tracker = RoundTripProbeTracker()
        XCTAssertNil(tracker.begin(now: .nan))
        XCTAssertEqual(tracker.begin(now: 2), 1)
        XCTAssertNil(
            tracker.complete(token: 1, now: 1.9)
        )
        XCTAssertEqual(tracker.outstandingToken, 1)
    }

    func testResetClearsOutstandingProbeAndTokenSequence() {
        var tracker = RoundTripProbeTracker()
        XCTAssertEqual(tracker.begin(now: 1), 1)

        tracker.reset()

        XCTAssertNil(tracker.outstandingToken)
        XCTAssertEqual(tracker.begin(now: 2), 1)
    }
}
