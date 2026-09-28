import Foundation

struct ReceiverAdaptationDecision: Equatable {
    let bitrateMbps: Int
    let requestKeyframe: Bool
}

struct ReceiverAdaptiveController {
    private(set) var bitrateMbps: Int

    private let minimumBitrateMbps: Int
    private let maximumBitrateMbps: Int
    private let targetFramesPerSecond: Double

    private var previousReceivedFrames: UInt64?
    private var previousDroppedFrames: UInt64?
    private var stressedSamples = 0
    private var healthySamples = 0

    init(
        initialBitrateMbps: Int,
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
            stressedSamples += 1

            guard severeStress || stressedSamples >= 2 else {
                return nil
            }

            stressedSamples = 0
            let reductionPercent = severeStress ? 25 : 12
            let reduced = max(
                minimumBitrateMbps,
                bitrateMbps * (100 - reductionPercent) / 100
            )
            guard reduced < bitrateMbps else { return nil }

            bitrateMbps = reduced
            return ReceiverAdaptationDecision(
                bitrateMbps: bitrateMbps,
                requestKeyframe: severeStress
            )
        }

        if healthy {
            stressedSamples = 0
            healthySamples += 1

            guard healthySamples >= 6 else { return nil }
            healthySamples = 0

            let increase = max(1, bitrateMbps / 12)
            let increased = min(
                maximumBitrateMbps,
                bitrateMbps + increase
            )
            guard increased > bitrateMbps else { return nil }

            bitrateMbps = increased
            return ReceiverAdaptationDecision(
                bitrateMbps: bitrateMbps,
                requestKeyframe: false
            )
        }

        resetTrend()
        return nil
    }

    private mutating func resetTrend() {
        stressedSamples = 0
        healthySamples = 0
    }
}
