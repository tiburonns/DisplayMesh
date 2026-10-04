#include "../ReceiverAdaptiveController.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>

using namespace displaymesh;

namespace {

ReceiverTelemetrySample Telemetry(
    std::uint64_t received,
    std::uint64_t dropped,
    double fps = 60,
    double decodeMilliseconds = 3,
    std::optional<std::uint32_t> decodeQueueDepth =
        std::nullopt,
    std::optional<std::uint32_t> presentationQueueDepth =
        std::nullopt) {
    return ReceiverTelemetrySample{
        received,
        dropped,
        fps,
        decodeMilliseconds,
        decodeQueueDepth,
        presentationQueueDepth,
    };
}

void TestFirstSampleEstablishesBaseline() {
    ReceiverAdaptiveController controller(
        24,
        60);

    assert(
        !controller.Update(
            Telemetry(60, 0))
             .has_value());
    assert(
        controller.BitrateMbps() == 24);
}

void TestModerateStressNeedsHysteresis() {
    ReceiverAdaptiveController controller(
        24,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    assert(
        !controller.Update(
            Telemetry(
                120,
                2,
                50,
                15))
             .has_value());

    const auto decision =
        controller.Update(
            Telemetry(
                180,
                4,
                50,
                15));

    assert(decision.has_value());
    assert(decision->bitrateMbps == 21);
    assert(
        std::abs(
            decision->rasterScale - 1.0) <
        0.000001);
    assert(!decision->requestKeyframe);
}

void TestSevereStressReducesImmediately() {
    ReceiverAdaptiveController controller(
        40,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    const auto decision =
        controller.Update(
            Telemetry(
                120,
                8,
                35,
                24));

    assert(decision.has_value());
    assert(decision->bitrateMbps == 30);
    assert(decision->requestKeyframe);
}

void TestFullDecodeQueueIsSevere() {
    ReceiverAdaptiveController controller(
        40,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    const auto decision =
        controller.Update(
            Telemetry(
                120,
                0,
                60,
                3,
                3,
                0));

    assert(decision.has_value());
    assert(decision->bitrateMbps == 30);
    assert(decision->requestKeyframe);
}

void TestPresentationQueueStressUsesHysteresis() {
    ReceiverAdaptiveController controller(
        24,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    assert(
        !controller.Update(
            Telemetry(
                120,
                0,
                60,
                3,
                0,
                2))
             .has_value());

    const auto decision =
        controller.Update(
            Telemetry(
                180,
                0,
                60,
                3,
                0,
                2));

    assert(decision.has_value());
    assert(decision->bitrateMbps == 21);
    assert(!decision->requestKeyframe);
}

void TestFullPresentationQueueIsSevere() {
    ReceiverAdaptiveController controller(
        40,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    const auto decision =
        controller.Update(
            Telemetry(
                120,
                0,
                60,
                3,
                0,
                3));

    assert(decision.has_value());
    assert(decision->bitrateMbps == 30);
    assert(decision->requestKeyframe);
}

void TestPersistentStressStepsRasterDown() {
    ReceiverAdaptiveController controller(
        40,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    std::optional<ReceiverAdaptationDecision>
        decision;
    for (std::uint64_t index = 1;
         index <= 3;
         ++index) {
        decision =
            controller.Update(
                Telemetry(
                    60 + index * 60,
                    index * 8,
                    35,
                    24));
    }

    assert(decision.has_value());
    assert(
        std::abs(
            controller.RasterScale() -
            0.85) < 0.000001);
    assert(decision->requestKeyframe);
}

void TestHealthyLinkRecoversBitrate() {
    ReceiverAdaptiveController controller(
        12,
        60,
        1.0,
        6,
        24);

    (void)controller.Update(
        Telemetry(60, 0));

    std::optional<ReceiverAdaptationDecision>
        decision;
    for (std::uint64_t index = 1;
         index <= 6;
         ++index) {
        decision =
            controller.Update(
                Telemetry(
                    60 + index * 60,
                    0,
                    60,
                    3));
    }

    assert(decision.has_value());
    assert(decision->bitrateMbps == 13);
    assert(!decision->requestKeyframe);
}

void TestRasterRecoversAfterBitrate() {
    ReceiverAdaptiveController controller(
        24,
        60,
        0.75,
        6,
        24);

    (void)controller.Update(
        Telemetry(60, 0));

    std::optional<ReceiverAdaptationDecision>
        decision;
    for (std::uint64_t index = 1;
         index <= 12;
         ++index) {
        if (const auto next =
                controller.Update(
                    Telemetry(
                        60 + index * 60,
                        0,
                        60,
                        3));
            next.has_value()) {
            decision = next;
        }
    }

    assert(
        std::abs(
            controller.RasterScale() -
            0.85) < 0.000001);
    assert(decision.has_value());
    assert(decision->requestKeyframe);
}

void TestCounterResetIsNotCongestion() {
    ReceiverAdaptiveController controller(
        24,
        60);

    (void)controller.Update(
        Telemetry(
            600,
            20));

    assert(
        !controller.Update(
            Telemetry(
                20,
                0))
             .has_value());
    assert(
        controller.BitrateMbps() == 24);
}

void TestInvalidTelemetryIsIgnored() {
    ReceiverAdaptiveController controller(
        24,
        60);

    (void)controller.Update(
        Telemetry(60, 0));

    assert(
        !controller.Update(
            Telemetry(
                120,
                0,
                std::numeric_limits<double>::
                    quiet_NaN(),
                3))
             .has_value());
    assert(
        controller.BitrateMbps() == 24);
}

void TestRasterInitializationSnaps() {
    ReceiverAdaptiveController controller(
        24,
        60,
        0.81);

    assert(
        std::abs(
            controller.RasterScale() -
            0.85) < 0.000001);
}

}  // namespace

int main() {
    TestFirstSampleEstablishesBaseline();
    TestModerateStressNeedsHysteresis();
    TestSevereStressReducesImmediately();
    TestFullDecodeQueueIsSevere();
    TestPresentationQueueStressUsesHysteresis();
    TestFullPresentationQueueIsSevere();
    TestPersistentStressStepsRasterDown();
    TestHealthyLinkRecoversBitrate();
    TestRasterRecoversAfterBitrate();
    TestCounterResetIsNotCongestion();
    TestInvalidTelemetryIsIgnored();
    TestRasterInitializationSnaps();
    return 0;
}
