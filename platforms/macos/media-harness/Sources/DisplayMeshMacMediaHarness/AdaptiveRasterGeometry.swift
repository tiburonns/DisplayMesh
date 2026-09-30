import Foundation

struct AdaptiveRasterDimensions: Equatable {
    let width: Int
    let height: Int
}

enum AdaptiveRasterGeometry {
    static func dimensions(
        baseWidth: Int,
        baseHeight: Int,
        scale: Double
    ) -> AdaptiveRasterDimensions? {
        guard baseWidth > 0,
              baseHeight > 0,
              scale.isFinite else {
            return nil
        }

        let boundedScale = min(max(scale, 0.5), 1.0)
        let width = makeEven(
            max(2, Int((Double(baseWidth) * boundedScale).rounded()))
        )
        let height = makeEven(
            max(2, Int((Double(baseHeight) * boundedScale).rounded()))
        )

        guard width > 0, height > 0 else { return nil }
        return AdaptiveRasterDimensions(width: width, height: height)
    }

    private static func makeEven(_ value: Int) -> Int {
        value - (value % 2)
    }
}
