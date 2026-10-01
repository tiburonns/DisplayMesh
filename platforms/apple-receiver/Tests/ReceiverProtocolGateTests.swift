import XCTest
@testable import DisplayMeshReceiver

final class ReceiverProtocolGateTests: XCTestCase {
    func testOnlyPairingIsAcceptedBeforeAuthorization() {
        for type in DMPMessageType.allCases {
            XCTAssertEqual(
                ReceiverProtocolGate.permits(type, authorized: false),
                type == .pairing,
                "Unexpected pre-authorization permission for \(type)"
            )
        }
    }

    func testAuthorizedReceiverOnlyAcceptsHostDirectedTraffic() {
        XCTAssertTrue(
            ReceiverProtocolGate.permits(.video, authorized: true)
        )
        XCTAssertTrue(
            ReceiverProtocolGate.permits(.error, authorized: true)
        )
        XCTAssertTrue(
            ReceiverProtocolGate.permits(.ping, authorized: true)
        )

        for type in [
            DMPMessageType.hello,
            .capabilities,
            .panelDescriptor,
            .pairing,
            .input,
            .telemetry,
            .keyframeRequest,
            .pong,
        ] {
            XCTAssertFalse(
                ReceiverProtocolGate.permits(type, authorized: true),
                "Unexpected authorized host direction for \(type)"
            )
        }
    }
}
