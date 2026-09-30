import Foundation

final class ReceiverFeedbackController {
    private let targetFramesPerSecond: Double
    private let minimumBitrateMbps: Int
    private let maximumBitrateMbps: Int

    private(set) var currentBitrateMbps: Int
    private var previousDroppedFrames: UInt64?
    private var stressedSamples = 0
    private var healthySamples = 0

    init(
        initialBitrateMbps: Int,
        targetFramesPerSecond: Int
    ) {
        let initial = max(initialBitrateMbps, 1)
        currentBitrateMbps = initial
        maximumBitrateMbps = initial
        minimumBitrateMbps = min(initial, max(4, initial / 4))
        self.targetFramesPerSecond =
            Double(max(targetFramesPerSecond, 1))
    }

    func update(_ telemetry: ReceiverTelemetry) -> Int? {
        guard telemetry.isValid,
              telemetry.decodedFrames >= 30,
              telemetry.framesPerSecond > 0 else {
            rememberDropCounter(telemetry)
            return nil
        }

        let droppedDelta: UInt64
        if let previousDroppedFrames,
           telemetry.droppedFrames >= previousDroppedFrames {
            droppedDelta =
                telemetry.droppedFrames - previousDroppedFrames
        } else {
            droppedDelta = 0
        }
        previousDroppedFrames = telemetry.droppedFrames

        let frameBudgetMilliseconds =
            1_000 / targetFramesPerSecond
        let fpsRatio =
            telemetry.framesPerSecond / targetFramesPerSecond

        let severe =
            fpsRatio < 0.70
            || telemetry.averageDecodeMilliseconds
                > frameBudgetMilliseconds * 1.10
            || droppedDelta >= 4

        let stressed =
            severe
            || fpsRatio < 0.88
            || telemetry.averageDecodeMilliseconds
                > frameBudgetMilliseconds * 0.80
            || droppedDelta > 0

        let healthy =
            fpsRatio >= 0.97
            && telemetry.averageDecodeMilliseconds
                < frameBudgetMilliseconds * 0.55
            && droppedDelta == 0

        if stressed {
            healthySamples = 0
            stressedSamples += 1

            guard severe || stressedSamples >= 2 else {
                return nil
            }

            stressedSamples = 0
            let percentage = severe ? 80 : 90
            let reduced = max(
                minimumBitrateMbps,
                currentBitrateMbps * percentage / 100
            )

            guard reduced < currentBitrateMbps else {
                return nil
            }

            currentBitrateMbps = reduced
            return reduced
        }

        stressedSamples = 0

        if healthy {
            healthySamples += 1
            guard healthySamples >= 8 else { return nil }
            healthySamples = 0

            let increased = min(
                maximumBitrateMbps,
                currentBitrateMbps
                    + max(1, currentBitrateMbps / 10)
            )

            guard increased > currentBitrateMbps else {
                return nil
            }

            currentBitrateMbps = increased
            return increased
        }

        healthySamples = 0
        return nil
    }

    private func rememberDropCounter(
        _ telemetry: ReceiverTelemetry
    ) {
        if telemetry.isValid {
            previousDroppedFrames = telemetry.droppedFrames
        }
    }
}
