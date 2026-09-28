import XCTest
@testable import DisplayMeshReceiver

final class PanelDescriptorTests: XCTestCase {
    func testReasonablePanelDescriptorIsValid() {
        XCTAssertTrue(
            PanelDescriptor(
                pixelWidth: 2_796,
                pixelHeight: 1_290,
                nativeScale: 3,
                maximumFramesPerSecond: 120,
                orientation: .landscape,
                maximumTouchPoints: 10,
                supportsPencil: false
            ).isValid
        )
    }

    func testUnreasonablePanelDescriptorIsRejected() {
        XCTAssertFalse(
            PanelDescriptor(
                pixelWidth: 100_000,
                pixelHeight: 1_080,
                nativeScale: .infinity,
                maximumFramesPerSecond: 1_000,
                orientation: .unknown,
                maximumTouchPoints: 100,
                supportsPencil: true
            ).isValid
        )
    }
}
