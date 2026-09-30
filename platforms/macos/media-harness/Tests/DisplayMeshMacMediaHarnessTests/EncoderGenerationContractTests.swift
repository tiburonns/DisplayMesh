import XCTest
@testable import DisplayMeshMacMediaHarness

final class EncoderGenerationContractTests: XCTestCase {
    func testGenerationWrapKeepsDifferentAdjacentValues() {
        var generation = UInt64.max
        let old = generation
        generation &+= 1
        XCTAssertNotEqual(old, generation)
        XCTAssertEqual(generation, 0)
    }
}
