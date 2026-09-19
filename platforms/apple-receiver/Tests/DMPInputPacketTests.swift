import XCTest
@testable import DisplayMeshReceiver

final class DMPInputPacketTests: XCTestCase {
    func testTouchSampleHasStableFortyByteLayout() throws {
        let event = ReceiverInputEvent(
            contactID: 42,
            phase: .moved,
            normalizedX: 0.25,
            normalizedY: 0.75,
            timestamp: 12.5,
            pencil: nil
        )

        let encoded = try DMPInputSample(event: event).encoded()

        XCTAssertEqual(encoded.count, DMPInputSample.encodedSize)
        XCTAssertEqual(encoded[0], DMPInputSample.version)
        XCTAssertEqual(encoded[1], DMPInputSample.Kind.touch.rawValue)
        XCTAssertEqual(encoded[2], DMPInputSample.Phase.moved.rawValue)
    }

    func testPencilSampleCarriesPencilKind() throws {
        let event = ReceiverInputEvent(
            contactID: 9,
            phase: .began,
            normalizedX: 0.5,
            normalizedY: 0.5,
            timestamp: 1,
            pencil: ReceiverInputEvent.PencilData(
                pressure: 0.8,
                altitude: 0.7,
                azimuth: 1.1
            )
        )

        let encoded = try DMPInputSample(event: event).encoded()

        XCTAssertEqual(encoded[1], DMPInputSample.Kind.pencil.rawValue)
        XCTAssertEqual(encoded[2], DMPInputSample.Phase.began.rawValue)
    }

    func testRejectsOutOfBoundsCoordinate() {
        let event = ReceiverInputEvent(
            contactID: 1,
            phase: .moved,
            normalizedX: 1.2,
            normalizedY: 0.5,
            timestamp: 0,
            pencil: nil
        )

        XCTAssertThrowsError(try DMPInputSample(event: event))
    }
}
