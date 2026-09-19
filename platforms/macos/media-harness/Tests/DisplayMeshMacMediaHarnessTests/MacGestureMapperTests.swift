import CoreGraphics
import XCTest
@testable import DisplayMeshMacMediaHarness

final class MacGestureMapperTests: XCTestCase {
    private let bounds = CGRect(x: 100, y: 50, width: 1000, height: 500)

    func testSingleFingerMapsToSafeMouseDragLifecycle() {
        var mapper = MacGestureMapper()

        let began = mapper.apply(
            sample(id: 1, phase: .began, x: 0.25, y: 0.5),
            targetBounds: bounds
        )
        XCTAssertEqual(began.count, 2)

        guard case .move(let movePoint) = began[0],
              case .down(let downPoint) = began[1] else {
            return XCTFail("Expected move + down")
        }

        XCTAssertEqual(movePoint.x, downPoint.x, accuracy: 0.001)
        XCTAssertEqual(movePoint.y, downPoint.y, accuracy: 0.001)

        let moved = mapper.apply(
            sample(id: 1, phase: .moved, x: 0.5, y: 0.5),
            targetBounds: bounds
        )

        guard moved.count == 1,
              case .drag(let dragPoint) = moved[0] else {
            return XCTFail("Expected one drag action")
        }
        XCTAssertGreaterThan(dragPoint.x, downPoint.x)

        let ended = mapper.apply(
            sample(id: 1, phase: .ended, x: 0.5, y: 0.5),
            targetBounds: bounds
        )

        guard ended.count == 1,
              case .up(let upPoint) = ended[0] else {
            return XCTFail("Expected one mouse-up action")
        }
        XCTAssertEqual(upPoint.x, dragPoint.x, accuracy: 0.001)
        XCTAssertEqual(upPoint.y, dragPoint.y, accuracy: 0.001)
    }

    func testSecondFingerReleasesMouseBeforeEnteringScrollMode() {
        var mapper = MacGestureMapper()

        _ = mapper.apply(
            sample(id: 1, phase: .began, x: 0.4, y: 0.4),
            targetBounds: bounds
        )

        let secondFinger = mapper.apply(
            sample(id: 2, phase: .began, x: 0.6, y: 0.6),
            targetBounds: bounds
        )

        guard secondFinger.count == 1,
              case .up = secondFinger[0] else {
            return XCTFail("Second finger must release the active mouse drag")
        }

        let scroll = mapper.apply(
            sample(id: 2, phase: .moved, x: 0.6, y: 0.7),
            targetBounds: bounds
        )

        guard scroll.count == 1,
              case .scroll(_, let vertical) = scroll[0] else {
            return XCTFail("Expected a scroll action")
        }
        XCTAssertNotEqual(vertical, 0)
    }

    func testRemainingFingerAfterScrollDoesNotBecomeUnexpectedClick() {
        var mapper = MacGestureMapper()

        _ = mapper.apply(
            sample(id: 1, phase: .began, x: 0.4, y: 0.4),
            targetBounds: bounds
        )
        _ = mapper.apply(
            sample(id: 2, phase: .began, x: 0.6, y: 0.6),
            targetBounds: bounds
        )
        _ = mapper.apply(
            sample(id: 2, phase: .ended, x: 0.6, y: 0.6),
            targetBounds: bounds
        )

        let remainingMove = mapper.apply(
            sample(id: 1, phase: .moved, x: 0.45, y: 0.45),
            targetBounds: bounds
        )
        XCTAssertTrue(remainingMove.isEmpty)

        _ = mapper.apply(
            sample(id: 1, phase: .ended, x: 0.45, y: 0.45),
            targetBounds: bounds
        )

        let newGesture = mapper.apply(
            sample(id: 3, phase: .began, x: 0.2, y: 0.2),
            targetBounds: bounds
        )
        XCTAssertEqual(newGesture.count, 2)
    }

    func testResetReleasesActiveMouseDrag() {
        var mapper = MacGestureMapper()
        _ = mapper.apply(
            sample(id: 1, phase: .began, x: 0.5, y: 0.5),
            targetBounds: bounds
        )

        let reset = mapper.reset(targetBounds: bounds)

        guard reset.count == 1,
              case .up = reset[0] else {
            return XCTFail("Reset must release an active mouse button")
        }
    }

    private func sample(
        id: UInt32,
        phase: DMPInputSample.Phase,
        x: Float,
        y: Float
    ) -> DMPInputSample {
        DMPInputSample(
            kind: .touch,
            phase: phase,
            flags: 0,
            contactID: id,
            normalizedX: x,
            normalizedY: y,
            pressure: 0.5,
            altitude: 0,
            azimuth: 0,
            barrelRoll: 0,
            timestampMicroseconds: 1
        )
    }
}
