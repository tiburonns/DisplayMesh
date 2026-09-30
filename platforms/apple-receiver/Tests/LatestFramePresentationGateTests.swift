import XCTest
@testable import DisplayMeshReceiver

final class LatestFramePresentationGateTests: XCTestCase {
    func testFirstFrameSchedulesSingleDrain() {
        var gate = LatestFramePresentationGate()

        let decision = gate.enqueue()

        XCTAssertTrue(decision.shouldScheduleDrain)
        XCTAssertFalse(decision.replacedPendingFrame)
        XCTAssertTrue(gate.hasPendingFrame)
        XCTAssertTrue(gate.drainScheduled)
    }

    func testNewFrameReplacesPendingWithoutSchedulingAnotherDrain() {
        var gate = LatestFramePresentationGate()
        _ = gate.enqueue()

        let replacement = gate.enqueue()

        XCTAssertFalse(replacement.shouldScheduleDrain)
        XCTAssertTrue(replacement.replacedPendingFrame)
        XCTAssertTrue(gate.hasPendingFrame)
        XCTAssertTrue(gate.drainScheduled)
    }

    func testFrameArrivingDuringPresentationIsDrainedNext() {
        var gate = LatestFramePresentationGate()
        _ = gate.enqueue()

        XCTAssertTrue(gate.takePending())
        XCTAssertFalse(gate.hasPendingFrame)

        let next = gate.enqueue()
        XCTAssertFalse(next.shouldScheduleDrain)
        XCTAssertFalse(next.replacedPendingFrame)

        XCTAssertTrue(gate.completePresentation())
        XCTAssertTrue(gate.drainScheduled)
        XCTAssertTrue(gate.takePending())
        XCTAssertFalse(gate.completePresentation())
        XCTAssertFalse(gate.drainScheduled)
    }

    func testIdleGateSchedulesAgainAfterDrainCompletes() {
        var gate = LatestFramePresentationGate()
        _ = gate.enqueue()
        XCTAssertTrue(gate.takePending())
        XCTAssertFalse(gate.completePresentation())

        let next = gate.enqueue()

        XCTAssertTrue(next.shouldScheduleDrain)
        XCTAssertFalse(next.replacedPendingFrame)
    }

    func testResetClearsPendingAndScheduledState() {
        var gate = LatestFramePresentationGate()
        _ = gate.enqueue()
        _ = gate.enqueue()

        gate.reset()

        XCTAssertFalse(gate.hasPendingFrame)
        XCTAssertFalse(gate.drainScheduled)
        XCTAssertFalse(gate.takePending())
    }
}
