#include "DmpInputRouter.h"

#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using namespace displaymesh;

namespace {

void WriteU32(
    std::array<
        std::uint8_t,
        kDmpInputSampleSize>& data,
    std::size_t offset,
    std::uint32_t value) {
    data[offset] =
        static_cast<std::uint8_t>(
            value >> 24);
    data[offset + 1] =
        static_cast<std::uint8_t>(
            value >> 16);
    data[offset + 2] =
        static_cast<std::uint8_t>(
            value >> 8);
    data[offset + 3] =
        static_cast<std::uint8_t>(
            value);
}

void WriteU64(
    std::array<
        std::uint8_t,
        kDmpInputSampleSize>& data,
    std::size_t offset,
    std::uint64_t value) {
    for (int index = 7;
         index >= 0;
         --index) {
        data[offset +
            static_cast<std::size_t>(
                7 - index)] =
            static_cast<std::uint8_t>(
                value >>
                static_cast<unsigned>(
                    index * 8));
    }
}

void WriteFloat(
    std::array<
        std::uint8_t,
        kDmpInputSampleSize>& data,
    std::size_t offset,
    float value) {
    WriteU32(
        data,
        offset,
        std::bit_cast<std::uint32_t>(
            value));
}

std::vector<std::uint8_t>
MakeValidInputPayload() {
    std::array<
        std::uint8_t,
        kDmpInputSampleSize> payload{};

    payload[0] = kDmpInputVersion;
    payload[1] =
        static_cast<std::uint8_t>(
            InputKind::Touch);
    payload[2] =
        static_cast<std::uint8_t>(
            InputPhase::Moved);
    payload[3] = 0;

    WriteU32(payload, 4, 42);
    WriteFloat(payload, 8, 0.25F);
    WriteFloat(payload, 12, 0.75F);
    WriteFloat(payload, 16, 0.50F);
    WriteFloat(payload, 20, 0.0F);
    WriteFloat(payload, 24, 0.0F);
    WriteFloat(payload, 28, 0.0F);
    WriteU64(payload, 32, 123'456);

    return std::vector<std::uint8_t>(
        payload.begin(),
        payload.end());
}

void AdvanceToStreaming(
    DmpHostSessionGate& gate) {
    std::string error;

    assert(gate.AcceptHello(error));
    assert(gate.PairingRequestSent(
        error));
    assert(gate.AcceptPairingResponse(
        true,
        error));
    assert(gate.AcceptCapabilities(
        error));
    assert(gate.AcceptPanelDescriptor(
        error));
    assert(gate.CanRouteInput());
}

void TestInputBlockedBeforeStreaming() {
    DmpHostSessionGate gate;
    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Input,
        0,
        1,
        MakeValidInputPayload(),
    };

    assert(
        !DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
    assert(!error.empty());
}

void TestValidInputRoutesWhileStreaming() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);

    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Input,
        0,
        10,
        MakeValidInputPayload(),
    };

    assert(
        DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
    assert(error.empty());
    assert(sample.contactId == 42);
    assert(sample.normalizedX == 0.25F);
    assert(sample.normalizedY == 0.75F);
    assert(sample.timestampMicros ==
        123'456);
}

void TestNonInputFrameRejected() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);

    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Telemetry,
        0,
        11,
        MakeValidInputPayload(),
    };

    assert(
        !DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
}

void TestOuterFlagsRejected() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);

    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Input,
        1,
        12,
        MakeValidInputPayload(),
    };

    assert(
        !DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
}

void TestPayloadValidationStillApplies() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);

    auto payload =
        MakeValidInputPayload();
    payload[3] = 1;

    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Input,
        0,
        13,
        payload,
    };

    assert(
        !DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
}

void TestResetImmediatelyBlocksInput() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);
    gate.Reset();

    InputSample sample{};
    std::string error;

    DmpFrame frame{
        DmpMessageType::Input,
        0,
        14,
        MakeValidInputPayload(),
    };

    assert(
        !DecodeSessionAuthorizedInput(
            frame,
            gate,
            sample,
            error));
}

}  // namespace

int main() {
    TestInputBlockedBeforeStreaming();
    TestValidInputRoutesWhileStreaming();
    TestNonInputFrameRejected();
    TestOuterFlagsRejected();
    TestPayloadValidationStillApplies();
    TestResetImmediatelyBlocksInput();
    return 0;
}
