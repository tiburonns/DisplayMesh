#pragma once

#include <cstdint>
#include <optional>

namespace displaymesh {

struct ReceiverTelemetrySample {
    std::uint64_t receivedFrames{};
    std::uint64_t droppedFrames{};
    double framesPerSecond{};
    double averageDecodeMilliseconds{};
    std::optional<std::uint32_t> decodeQueueDepth;
    std::optional<std::uint32_t> presentationQueueDepth;
};

struct ReceiverTelemetryAdmissionContext {
    bool sessionStreaming{};
    bool authenticated{};
    bool generationMatches{};
};

struct ReceiverAdaptationDecision {
    std::uint32_t bitrateMbps{};
    double rasterScale{1.0};
    bool requestKeyframe{};
};

class ReceiverAdaptiveController {
public:
    ReceiverAdaptiveController(
        std::uint32_t initialBitrateMbps,
        std::uint32_t targetFramesPerSecond,
        double initialRasterScale = 1.0,
        std::uint32_t minimumBitrateMbps = 6,
        std::uint32_t maximumBitrateMbps = 120);

    std::optional<ReceiverAdaptationDecision> Update(
        const ReceiverTelemetrySample& telemetry,
        const ReceiverTelemetryAdmissionContext& context);

    std::uint32_t BitrateMbps() const noexcept;
    double RasterScale() const noexcept;

private:
    static double NearestRasterScale(double value) noexcept;
    static std::optional<double> LowerRasterStep(double value) noexcept;
    static std::optional<double> HigherRasterStep(double value) noexcept;

    static bool IsTelemetryValid(
        const ReceiverTelemetrySample& telemetry) noexcept;

    void ResetTrend() noexcept;
    void ResetBaseline() noexcept;

    std::uint32_t minimumBitrateMbps_{};
    std::uint32_t maximumBitrateMbps_{};
    std::uint32_t bitrateMbps_{};
    double rasterScale_{1.0};
    double targetFramesPerSecond_{60.0};

    std::optional<std::uint64_t> previousReceivedFrames_;
    std::optional<std::uint64_t> previousDroppedFrames_;

    std::uint32_t stressedSamples_{};
    std::uint32_t healthySamples_{};
    std::uint32_t severeRasterStressSamples_{};
    std::uint32_t rasterRecoverySamples_{};
};

}  // namespace displaymesh
