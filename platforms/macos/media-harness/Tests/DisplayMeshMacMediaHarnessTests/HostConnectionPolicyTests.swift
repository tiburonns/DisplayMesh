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

    func testReconnectBackoffIsBoundedAndExponential() {
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 0),
            0
        )
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 1),
            0.5
        )
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 2),
            1
        )
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 3),
            2
        )
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 4),
            4
        )
        XCTAssertEqual(
            HostReconnectPolicy.delaySeconds(forRetryNumber: 8),
            4
        )
    }

    func testReconnectOnlyRetriesTransientProtocolFailures() {
        XCTAssertTrue(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.connectionClosed
            )
        )
        XCTAssertTrue(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.timeout("transport connection")
            )
        )
        XCTAssertTrue(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.timeout("receiver capabilities")
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.timeout("pairing approval")
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.pairingRejected
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.incompatibleReceiverCapabilities
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.isRetryable(
                DMPProtocolError.unexpectedSequence(
                    expected: 4,
                    received: 9
                )
            )
        )
    }

    func testReconnectRespectsRetryBudget() {
        let error = DMPProtocolError.connectionClosed

        XCTAssertTrue(
            HostReconnectPolicy.shouldRetry(
                error,
                completedRetries: 0,
                maximumRetries: 3
            )
        )
        XCTAssertTrue(
            HostReconnectPolicy.shouldRetry(
                error,
                completedRetries: 2,
                maximumRetries: 3
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.shouldRetry(
                error,
                completedRetries: 3,
                maximumRetries: 3
            )
        )
        XCTAssertFalse(
            HostReconnectPolicy.shouldRetry(
                error,
                completedRetries: 0,
                maximumRetries: 0
            )
        )
    }

    func testBonjourDiscoveryCardinalityIsFailClosed() {
        XCTAssertEqual(
            ReceiverDiscoveryPolicy
                .classify(count: 0),
            .none
        )
        XCTAssertEqual(
            ReceiverDiscoveryPolicy
                .classify(count: 1),
            .one
        )
        XCTAssertEqual(
            ReceiverDiscoveryPolicy
                .classify(count: 2),
            .multiple(2)
        )
        XCTAssertEqual(
            ReceiverDiscoveryPolicy
                .classify(count: 8),
            .multiple(8)
        )
        XCTAssertEqual(
            ReceiverDiscoveryPolicy
                .serviceType,
            "_displaymesh._tcp"
        )
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
