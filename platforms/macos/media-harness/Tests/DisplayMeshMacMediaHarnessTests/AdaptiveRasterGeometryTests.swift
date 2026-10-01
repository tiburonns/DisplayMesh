import XCTest
@testable import DisplayMeshMacMediaHarness

final class AdaptiveRasterGeometryTests: XCTestCase {
    func testFullScalePreservesEvenBaseDimensions() {
        XCTAssertEqual(
            AdaptiveRasterGeometry.dimensions(
                baseWidth: 2560,
                baseHeight: 1440,
                scale: 1.0
            ),
            AdaptiveRasterDimensions(width: 2560, height: 1440)
        )
    }

    func testRasterStepsProduceEvenDimensions() {
        let expected: [(Double, AdaptiveRasterDimensions)] = [
            (0.85, .init(width: 2176, height: 1224)),
            (0.75, .init(width: 1920, height: 1080)),
            (0.67, .init(width: 1714, height: 964)),
        ]

        for (scale, dimensions) in expected {
            XCTAssertEqual(
                AdaptiveRasterGeometry.dimensions(
                    baseWidth: 2560,
                    baseHeight: 1440,
                    scale: scale
                ),
                dimensions
            )
        }
    }

    func testScaleNeverUpscalesBeyondBase() {
        XCTAssertEqual(
            AdaptiveRasterGeometry.dimensions(
                baseWidth: 1920,
                baseHeight: 1080,
                scale: 1.4
            ),
            AdaptiveRasterDimensions(width: 1920, height: 1080)
        )
    }

    func testInvalidGeometryIsRejected() {
        XCTAssertNil(
            AdaptiveRasterGeometry.dimensions(
                baseWidth: 0,
                baseHeight: 1080,
                scale: 0.85
            )
        )
        XCTAssertNil(
            AdaptiveRasterGeometry.dimensions(
                baseWidth: 1920,
                baseHeight: 1080,
                scale: .nan
            )
        )
    }
}
