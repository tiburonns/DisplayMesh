import XCTest
@testable import DisplayMeshReceiver

final class ReceiverAwakePolicyTests: XCTestCase {
    func testListeningWithoutAuthorizedSessionAllowsAutoLock() {
        XCTAssertFalse(
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: .ready(port: 49_655),
                sessionAuthorized: false
            )
        )

        XCTAssertFalse(
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: .connected("Mac"),
                sessionAuthorized: false
            )
        )
    }

    func testAuthorizedConnectedSessionKeepsScreenAwake() {
        XCTAssertTrue(
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: .connected("Mac"),
                sessionAuthorized: true
            )
        )
    }

    func testDisconnectRestoresAutoLockEvenIfAuthorizationFlagIsStale() {
        XCTAssertFalse(
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: .ready(port: 49_655),
                sessionAuthorized: true
            )
        )
        XCTAssertFalse(
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: .failed("network"),
                sessionAuthorized: true
            )
        )
    }
}
