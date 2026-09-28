import XCTest
@testable import DisplayMeshMacMediaHarness

final class HostProtocolGateTests: XCTestCase {
    func testPairingCannotArriveBeforeHelloPhaseCompletes() {
        XCTAssertTrue(
            HostProtocolGate.permits(.hello, phase: .awaitingHello)
        )
        XCTAssertFalse(
            HostProtocolGate.permits(.pairing, phase: .awaitingHello)
        )
        XCTAssertTrue(
            HostProtocolGate.permits(.hello, phase: .readyToPair)
        )
        XCTAssertFalse(
            HostProtocolGate.permits(.panelDescriptor, phase: .readyToPair)
        )
    }

    func testPairingResponseIsOnlyAcceptedInPairingPhase() {
        XCTAssertTrue(
            HostProtocolGate.permits(
                .pairing,
                phase: .awaitingPairingResponse
            )
        )
        XCTAssertFalse(
            HostProtocolGate.permits(
                .video,
                phase: .awaitingPairingResponse
            )
        )
    }

    func testAuthorizedReceiverTrafficIsDirectionallyRestricted() {
        for type in [
            DMPMessageType.panelDescriptor,
            .capabilities,
            .keyframeRequest,
            .input,
            .telemetry,
            .error,
        ] {
            XCTAssertTrue(
                HostProtocolGate.permits(type, phase: .streaming),
                "Expected receiver traffic to be allowed: \(type)"
            )
        }

        for type in [
            DMPMessageType.hello,
            .pairing,
            .video,
        ] {
            XCTAssertFalse(
                HostProtocolGate.permits(type, phase: .streaming),
                "Unexpected receiver direction: \(type)"
            )
        }
    }

    func testErrorIsPermittedForExplicitFailureReporting() {
        for phase in [
            HostReceiverPhase.awaitingHello,
            .readyToPair,
            .awaitingPairingResponse,
            .awaitingPanel,
            .streaming,
        ] {
            XCTAssertTrue(
                HostProtocolGate.permits(.error, phase: phase)
            )
        }
    }
}
