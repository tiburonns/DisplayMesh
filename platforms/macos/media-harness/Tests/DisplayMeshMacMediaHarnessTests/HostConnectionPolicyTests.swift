import XCTest
@testable import DisplayMeshMacMediaHarness

final class HostConnectionPolicyTests: XCTestCase {
    func testEveryNegotiationDeadlineIsFiniteAndPositive() {
        for timeout in HostConnectionPolicy.allTimeouts {
            XCTAssertTrue(timeout.isFinite)
            XCTAssertGreaterThan(timeout, 0)
            XCTAssertLessThanOrEqual(timeout, 30)
        }
    }

    func testHumanPairingWindowIsLongerThanMachinePhases() {
        XCTAssertGreaterThan(
            HostConnectionPolicy.pairingTimeoutSeconds,
            HostConnectionPolicy.connectTimeoutSeconds
        )
        XCTAssertGreaterThan(
            HostConnectionPolicy.pairingTimeoutSeconds,
            HostConnectionPolicy.helloTimeoutSeconds
        )
        XCTAssertGreaterThan(
            HostConnectionPolicy.pairingTimeoutSeconds,
            HostConnectionPolicy.capabilitiesTimeoutSeconds
        )
        XCTAssertGreaterThan(
            HostConnectionPolicy.pairingTimeoutSeconds,
            HostConnectionPolicy.panelTimeoutSeconds
        )
    }
}
