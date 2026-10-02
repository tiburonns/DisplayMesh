#include "ReceiverAdaptiveController.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace displaymesh {
namespace {

constexpr std::array<double, 4> kRasterSteps{
    1.0,
    0.85,
    0.75,
    0.67,
};

bool NearlyEqual(
    double lhs,
    double rhs) noexcept {
    return std::abs(lhs - rhs) < 0.000001;
}

}  // namespace

ReceiverAdaptiveController::ReceiverAdaptiveController(
    std::uint32_t initialBitrateMbps,
    std::uint32_t targetFramesPerSecond,
    double initialRasterScale,
    std::uint32_t minimumBitrateMbps,
    std::uint32_t maximumBitrateMbps)
    : minimumBitrateMbps_(
          std::max<std::uint32_t>(
              1,
              minimumBitrateMbps)),
      maximumBitrateMbps_(
          std::max(
              minimumBitrateMbps_,
              maximumBitrateMbps)),
      bitrateMbps_(
          std::clamp(
              initialBitrateMbps,
              minimumBitrateMbps_,
              maximumBitrateMbps_)),
      rasterScale_(
          NearestRasterScale(
              initialRasterScale)),
      targetFramesPerSecond_(
          static_cast<double>(
              std::max<std::uint32_t>(
                  1,
                  targetFramesPerSecond))) {}

std::optional<ReceiverAdaptationDecision>
ReceiverAdaptiveController::Update(
    const ReceiverTelemetrySample& telemetry) {
    if (!std::isfinite(telemetry.framesPerSecond) ||
        !std::isfinite(
            telemetry.averageDecodeMilliseconds) ||
        telemetry.framesPerSecond < 0 ||
        telemetry.averageDecodeMilliseconds < 0) {
        ResetTrend();
        return std::nullopt;
    }

    if (!previousReceivedFrames_.has_value() ||
        !previousDroppedFrames_.has_value() ||
        telemetry.receivedFrames <
            *previousReceivedFrames_ ||
        telemetry.droppedFrames <
            *previousDroppedFrames_) {
        previousReceivedFrames_ =
            telemetry.receivedFrames;
        previousDroppedFrames_ =
            telemetry.droppedFrames;
        ResetTrend();
        return std::nullopt;
    }

    const auto receivedDelta =
        telemetry.receivedFrames -
        *previousReceivedFrames_;
    const auto droppedDelta =
        telemetry.droppedFrames -
        *previousDroppedFrames_;

    previousReceivedFrames_ =
        telemetry.receivedFrames;
    previousDroppedFrames_ =
        telemetry.droppedFrames;

    if (receivedDelta == 0) {
        ResetTrend();
        return std::nullopt;
    }

    const auto dropRatio =
        static_cast<double>(droppedDelta) /
        static_cast<double>(receivedDelta);
    const auto frameBudgetMilliseconds =
        1000.0 /
        targetFramesPerSecond_;
    const auto fpsRatio =
        telemetry.framesPerSecond /
        targetFramesPerSecond_;

    const auto decodeQueueDepth =
        telemetry.decodeQueueDepth.value_or(0);

    const bool severeStress =
        dropRatio >= 0.10 ||
        decodeQueueDepth >= 3 ||
        telemetry.averageDecodeMilliseconds >=
            frameBudgetMilliseconds * 1.25 ||
        fpsRatio < 0.70;

    const bool stressed =
        severeStress ||
        decodeQueueDepth >= 2 ||
        dropRatio >= 0.03 ||
        telemetry.averageDecodeMilliseconds >=
            frameBudgetMilliseconds * 0.85 ||
        fpsRatio < 0.88;

    const bool healthy =
        decodeQueueDepth <= 1 &&
        dropRatio < 0.005 &&
        telemetry.averageDecodeMilliseconds <
            frameBudgetMilliseconds * 0.55 &&
        fpsRatio >= 0.97;

    if (stressed) {
        healthySamples_ = 0;
        rasterRecoverySamples_ = 0;
        ++stressedSamples_;

        if (severeStress) {
            ++severeRasterStressSamples_;
        } else {
            severeRasterStressSamples_ = 0;
        }

        const bool shouldReduceBitrate =
            severeStress ||
            stressedSamples_ >= 2;
        const bool shouldReduceRaster =
            severeRasterStressSamples_ >= 3;

        if (!shouldReduceBitrate &&
            !shouldReduceRaster) {
            return std::nullopt;
        }

        bool changed = false;
        bool requestKeyframe = severeStress;

        if (shouldReduceBitrate) {
            stressedSamples_ = 0;
            const std::uint32_t reductionPercent =
                severeStress ? 25U : 12U;
            const auto reduced =
                std::max(
                    minimumBitrateMbps_,
                    bitrateMbps_ *
                        (100U - reductionPercent) /
                        100U);

            if (reduced < bitrateMbps_) {
                bitrateMbps_ = reduced;
                changed = true;
            }
        }

        if (shouldReduceRaster) {
            if (const auto lower =
                    LowerRasterStep(
                        rasterScale_);
                lower.has_value()) {
                rasterScale_ = *lower;
                severeRasterStressSamples_ = 0;
                requestKeyframe = true;
                changed = true;
            }
        }

        if (!changed) {
            return std::nullopt;
        }

        return ReceiverAdaptationDecision{
            bitrateMbps_,
            rasterScale_,
            requestKeyframe,
        };
    }

    severeRasterStressSamples_ = 0;

    if (healthy) {
        stressedSamples_ = 0;
        ++healthySamples_;
        ++rasterRecoverySamples_;

        bool changed = false;

        if (healthySamples_ >= 6) {
            healthySamples_ = 0;
            const auto increase =
                std::max<std::uint32_t>(
                    1,
                    bitrateMbps_ / 12U);
            const auto increased =
                std::min(
                    maximumBitrateMbps_,
                    bitrateMbps_ + increase);

            if (increased > bitrateMbps_) {
                bitrateMbps_ = increased;
                changed = true;
            }
        }

        bool requestKeyframe = false;
        const auto recoveryFloor =
            std::max(
                minimumBitrateMbps_,
                maximumBitrateMbps_ * 9U / 10U);
        const bool bitrateRecovered =
            bitrateMbps_ >= recoveryFloor;

        if (rasterRecoverySamples_ >= 12 &&
            bitrateRecovered) {
            if (const auto higher =
                    HigherRasterStep(
                        rasterScale_);
                higher.has_value()) {
                rasterScale_ = *higher;
                rasterRecoverySamples_ = 0;
                requestKeyframe = true;
                changed = true;
            }
        }

        if (!changed) {
            return std::nullopt;
        }

        return ReceiverAdaptationDecision{
            bitrateMbps_,
            rasterScale_,
            requestKeyframe,
        };
    }

    ResetTrend();
    return std::nullopt;
}

std::uint32_t
ReceiverAdaptiveController::BitrateMbps() const noexcept {
    return bitrateMbps_;
}

double
ReceiverAdaptiveController::RasterScale() const noexcept {
    return rasterScale_;
}

void ReceiverAdaptiveController::ResetTrend() noexcept {
    stressedSamples_ = 0;
    healthySamples_ = 0;
    severeRasterStressSamples_ = 0;
    rasterRecoverySamples_ = 0;
}

double ReceiverAdaptiveController::NearestRasterScale(
    double value) noexcept {
    if (!std::isfinite(value)) {
        return 1.0;
    }

    auto best = kRasterSteps.front();
    auto distance = std::abs(best - value);
    for (const auto candidate : kRasterSteps) {
        const auto candidateDistance =
            std::abs(candidate - value);
        if (candidateDistance < distance) {
            best = candidate;
            distance = candidateDistance;
        }
    }
    return best;
}

std::optional<double>
ReceiverAdaptiveController::LowerRasterStep(
    double value) noexcept {
    const auto nearest =
        NearestRasterScale(value);

    for (std::size_t index = 0;
         index < kRasterSteps.size();
         ++index) {
        if (NearlyEqual(
                kRasterSteps[index],
                nearest)) {
            if (index + 1 <
                kRasterSteps.size()) {
                return kRasterSteps[
                    index + 1];
            }
            return std::nullopt;
        }
    }

    return std::nullopt;
}

std::optional<double>
ReceiverAdaptiveController::HigherRasterStep(
    double value) noexcept {
    const auto nearest =
        NearestRasterScale(value);

    for (std::size_t index = 0;
         index < kRasterSteps.size();
         ++index) {
        if (NearlyEqual(
                kRasterSteps[index],
                nearest)) {
            if (index > 0) {
                return kRasterSteps[
                    index - 1];
            }
            return std::nullopt;
        }
    }

    return std::nullopt;
}

}  // namespace displaymesh
