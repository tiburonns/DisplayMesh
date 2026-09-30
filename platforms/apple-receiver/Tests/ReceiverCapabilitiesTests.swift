import XCTest
@testable import DisplayMeshReceiver

final class ReceiverCapabilitiesTests: XCTestCase {
    func testDevelopmentCapabilitiesMatchImplementedPath() {
        let panel = PanelDescriptor(
            pixelWidth: 2732,
            pixelHeight: 2048,
            nativeScale: 2,
            maximumFramesPerSecond: 120,
            orientation: .landscape,
            maximumTouchPoints: 10,
            supportsPencil: true
        )

        let capabilities = ReceiverCapabilities.development(
            panel: panel,
            encryptedTransport: true
        )

        XCTAssertTrue(capabilities.isValid)
        XCTAssertTrue(capabilities.supportsDevelopmentHost)
        XCTAssertEqual(capabilities.codecs, ["h264"])
        XCTAssertEqual(capabilities.connectionBindings, ["tcp"])
        XCTAssertEqual(capabilities.inputKinds, ["touch", "pencil"])
        XCTAssertTrue(capabilities.telemetrySupported)
        XCTAssertTrue(capabilities.encryptedTransport)
    }

    func testInvalidCapabilitiesAreRejected() {
        let capabilities = ReceiverCapabilities(
            schemaVersion: ReceiverCapabilities.schemaVersion,
            protocolVersion: Int(DMPFrame.version),
            codecs: [],
            connectionBindings: ["tcp"],
            inputKinds: ["touch"],
            telemetrySupported: true,
            maximumVideoPayloadBytes: DMPFrame.maximumPayloadSize + 1,
            encryptedTransport: false
        )

        XCTAssertFalse(capabilities.isValid)
        XCTAssertFalse(capabilities.supportsDevelopmentHost)
    }
}
