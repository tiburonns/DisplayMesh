import Foundation

struct ReceiverAdaptationDecision: Equatable {
    let bitrateMbps: Int
    let rasterScale: Double
    let requestKeyframe: Bool
}

struct ReceiverAdaptiveController {
    static let rasterSteps: [Double] = [1.0, 0.85, 0.75, 0.67]

    private(set) var bitrateMbps: Int
    private(set) var rasterScale: Double

    private let minimumBitrateMbps: Int
    private let maximumBitrateMbps: Int
    private let targetFramesPerSecond: Double

    private var previousReceivedFrames: UInt64?
    private var previousDroppedFrames: UInt64?
    private var stressedSamples = 0
    private var healthySamples = 0
    private var severeRasterStressSamples = 0
    private var rasterRecoverySamples = 0

    init(
        initialBitrateMbps: Int,
        initialRasterScale: Double = 1.0,
        minimumBitrateMbps: Int = 6,
        maximumBitrateMbps: Int = 120,
        targetFramesPerSecond: Int
    ) {
        self.minimumBitrateMbps = max(1, minimumBitrateMbps)
        self.maximumBitrateMbps = max(
            self.minimumBitrateMbps,
            maximumBitrateMbps
        )
        self.bitrateMbps = min(
            max(initialBitrateMbps, self.minimumBitrateMbps),
            self.maximumBitrateMbps
        )
        self.rasterScale = Self.nearestRasterScale(initialRasterScale)
        self.targetFramesPerSecond = Double(max(1, targetFramesPerSecond))
    }

    mutating func update(
        _ telemetry: ReceiverTelemetry
    ) -> ReceiverAdaptationDecision? {
        guard telemetry.framesPerSecond.isFinite,
              telemetry.averageDecodeMilliseconds.isFinite,
              telemetry.framesPerSecond >= 0,
              telemetry.averageDecodeMilliseconds >= 0 else {
            resetTrend()
            return nil
        }

        guard let previousReceivedFrames,
              let previousDroppedFrames,
              telemetry.receivedFrames >= previousReceivedFrames,
              telemetry.droppedFrames >= previousDroppedFrames else {
            self.previousReceivedFrames = telemetry.receivedFrames
            self.previousDroppedFrames = telemetry.droppedFrames
            resetTrend()
            return nil
        }

        let receivedDelta = telemetry.receivedFrames - previousReceivedFrames
        let droppedDelta = telemetry.droppedFrames - previousDroppedFrames
        self.previousReceivedFrames = telemetry.receivedFrames
        self.previousDroppedFrames = telemetry.droppedFrames

        guard receivedDelta > 0 else {
            resetTrend()
            return nil
        }

        let dropRatio = Double(droppedDelta) / Double(receivedDelta)
        let frameBudgetMilliseconds = 1_000 / targetFramesPerSecond
        let fpsRatio = telemetry.framesPerSecond / targetFramesPerSecond

        let severeStress =
            dropRatio >= 0.10
            || telemetry.averageDecodeMilliseconds
                >= frameBudgetMilliseconds * 1.25
            || fpsRatio < 0.70

        let stressed =
            severeStress
            || dropRatio >= 0.03
            || telemetry.averageDecodeMilliseconds
                >= frameBudgetMilliseconds * 0.85
            || fpsRatio < 0.88

        let healthy =
            dropRatio < 0.005
            && telemetry.averageDecodeMilliseconds
                < frameBudgetMilliseconds * 0.55
            && fpsRatio >= 0.97

        if stressed {
            healthySamples = 0
            rasterRecoverySamples = 0
            stressedSamples += 1
            if severeStress {
                severeRasterStressSamples += 1
            } else {
                severeRasterStressSamples = 0
            }

            let shouldReduceBitrate = severeStress || stressedSamples >= 2
            let shouldReduceRaster = severeRasterStressSamples >= 3

            guard shouldReduceBitrate || shouldReduceRaster else {
                return nil
            }

            var changed = false
            var requestKeyframe = severeStress

            if shouldReduceBitrate {
                stressedSamples = 0
                let reductionPercent = severeStress ? 25 : 12
                let reduced = max(
                    minimumBitrateMbps,
                    bitrateMbps * (100 - reductionPercent) / 100
                )
                if reduced < bitrateMbps {
                    bitrateMbps = reduced
                    changed = true
                }
            }

            if shouldReduceRaster,
               let lower = Self.lowerRasterStep(from: rasterScale) {
                rasterScale = lower
                severeRasterStressSamples = 0
                requestKeyframe = true
                changed = true
            }

            guard changed else { return nil }

            return ReceiverAdaptationDecision(
                bitrateMbps: bitrateMbps,
                rasterScale: rasterScale,
                requestKeyframe: requestKeyframe
            )
        }

        severeRasterStressSamples = 0

        if healthy {
            stressedSamples = 0
            healthySamples += 1
            rasterRecoverySamples += 1

            var changed = false

            if healthySamples >= 6 {
                healthySamples = 0
                let increase = max(1, bitrateMbps / 12)
                let increased = min(
                    maximumBitrateMbps,
                    bitrateMbps + increase
                )
                if increased > bitrateMbps {
                    bitrateMbps = increased
                    changed = true
                }
            }

            var requestKeyframe = false
            let bitrateRecovered =
                bitrateMbps >= max(
                    minimumBitrateMbps,
                    maximumBitrateMbps * 9 / 10
                )

            if rasterRecoverySamples >= 12,
               bitrateRecovered,
               let higher = Self.higherRasterStep(from: rasterScale) {
                rasterScale = higher
                rasterRecoverySamples = 0
                requestKeyframe = true
                changed = true
            }

            guard changed else { return nil }

            return ReceiverAdaptationDecision(
                bitrateMbps: bitrateMbps,
                rasterScale: rasterScale,
                requestKeyframe: requestKeyframe
            )
        }

        resetTrend()
        return nil
    }

    private mutating func resetTrend() {
        stressedSamples = 0
        healthySamples = 0
        severeRasterStressSamples = 0
        rasterRecoverySamples = 0
    }

    private static func nearestRasterScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return rasterSteps.min {
            abs($0 - value) < abs($1 - value)
        } ?? 1.0
    }

    private static func lowerRasterStep(from value: Double) -> Double? {
        guard let index = rasterSteps.firstIndex(of: nearestRasterScale(value)),
              index + 1 < rasterSteps.count else {
            return nil
        }
        return rasterSteps[index + 1]
    }

    private static func higherRasterStep(from value: Double) -> Double? {
        guard let index = rasterSteps.firstIndex(of: nearestRasterScale(value)),
              index > 0 else {
            return nil
        }
        return rasterSteps[index - 1]
    }
}
