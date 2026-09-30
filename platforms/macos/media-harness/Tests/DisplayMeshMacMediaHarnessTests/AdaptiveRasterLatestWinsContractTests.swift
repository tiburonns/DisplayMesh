import XCTest
@testable import DisplayMeshMacMediaHarness

final class AdaptiveRasterLatestWinsContractTests: XCTestCase {
    func testControllerRasterStepsAreStrictlyDescending() {
        let steps = ReceiverAdaptiveController.rasterSteps
        XCTAssertEqual(steps, [1.0, 0.85, 0.75, 0.67])

        for pair in zip(steps, steps.dropFirst()) {
            XCTAssertGreaterThan(pair.0, pair.1)
        }
    }
}
