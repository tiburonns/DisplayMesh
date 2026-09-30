#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <string>

#include "DmpInput.h"

namespace {

void WriteU32(
    std::array<std::uint8_t, displaymesh::kDmpInputSampleSize>& data,
    std::size_t offset,
    std::uint32_t value) {
    data[offset] = static_cast<std::uint8_t>(value >> 24);
    data[offset + 1] = static_cast<std::uint8_t>(value >> 16);
    data[offset + 2] = static_cast<std::uint8_t>(value >> 8);
    data[offset + 3] = static_cast<std::uint8_t>(value);
}

void WriteFloat(
    std::array<std::uint8_t, displaymesh::kDmpInputSampleSize>& data,
    std::size_t offset,
    float value) {
    WriteU32(data, offset, std::bit_cast<std::uint32_t>(value));
}

}  // namespace

int main() {
    std::array<std::uint8_t, displaymesh::kDmpInputSampleSize> payload{};
    payload[0] = displaymesh::kDmpInputVersion;
    payload[1] = static_cast<std::uint8_t>(displaymesh::InputKind::Touch);
    payload[2] = static_cast<std::uint8_t>(displaymesh::InputPhase::Moved);
    WriteU32(payload, 4, 42);
    WriteFloat(payload, 8, 0.25F);
    WriteFloat(payload, 12, 0.75F);
    WriteFloat(payload, 16, 0.5F);
    WriteFloat(payload, 20, 0.0F);
    WriteFloat(payload, 24, 0.0F);
    WriteFloat(payload, 28, 0.0F);

    displaymesh::InputSample sample{};
    std::string error;
    assert(displaymesh::DecodeInputSample(payload, sample, error));
    assert(sample.contactId == 42);
    assert(sample.normalizedX == 0.25F);
    assert(sample.normalizedY == 0.75F);

    payload[3] = 1;
    assert(!displaymesh::DecodeInputSample(payload, sample, error));
    payload[3] = 0;

    payload[8] = 0x3f;
    payload[9] = 0x99;
    payload[10] = 0x99;
    payload[11] = 0x9a;  // 1.2F
    assert(!displaymesh::DecodeInputSample(payload, sample, error));

    return 0;
}
