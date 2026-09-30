import XCTest
@testable import DisplayMeshMacMediaHarness

final class HostConnectionPolicyTests: XCTestCase {
    func testConnectionAttemptCanOnlyResolveOnce() {
        let gate = ConnectionAttemptGate()
        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testConcurrentConnectionAttemptHasSingleWinner() {
        let gate = ConnectionAttemptGate()
        let lock = NSLock()
        var wins = 0
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "displaymesh.connection-attempt-test",
            attributes: .concurrent
        )

        for _ in 0..<64 {
            group.enter()
            queue.async {
                if gate.claim() {
                    lock.lock()
                    wins += 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(wins, 1)
    }

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
