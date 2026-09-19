#include "DmpInput.h"

#include <algorithm>
#include <bit>
#include <cmath>

namespace displaymesh {
namespace {

std::uint32_t ReadU32(const std::uint8_t* bytes) {
    return (static_cast<std::uint32_t>(bytes[0]) << 24) |
           (static_cast<std::uint32_t>(bytes[1]) << 16) |
           (static_cast<std::uint32_t>(bytes[2]) << 8) |
           static_cast<std::uint32_t>(bytes[3]);
}

std::uint64_t ReadU64(const std::uint8_t* bytes) {
    std::uint64_t value = 0;
    for (int index = 0; index < 8; ++index) {
        value = (value << 8) | bytes[index];
    }
    return value;
}

float ReadFloat(const std::uint8_t* bytes) {
    return std::bit_cast<float>(ReadU32(bytes));
}

bool IsNormalized(float value) {
    return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
}

}  // namespace

bool DecodeInputSample(
    std::span<const std::uint8_t> payload,
    InputSample& output,
    std::string& error) {
    if (payload.size() != kDmpInputSampleSize) {
        error = "DMP input payload must be exactly 40 bytes";
        return false;
    }

    if (payload[0] != kDmpInputVersion) {
        error = "unsupported DMP input version";
        return false;
    }

    if (payload[1] < static_cast<std::uint8_t>(InputKind::Touch) ||
        payload[1] > static_cast<std::uint8_t>(InputKind::Pencil)) {
        error = "unsupported DMP input kind";
        return false;
    }

    if (payload[2] < static_cast<std::uint8_t>(InputPhase::Began) ||
        payload[2] > static_cast<std::uint8_t>(InputPhase::Hover)) {
        error = "unsupported DMP input phase";
        return false;
    }

    output.kind = static_cast<InputKind>(payload[1]);
    output.phase = static_cast<InputPhase>(payload[2]);
    output.flags = payload[3];
    output.contactId = ReadU32(payload.data() + 4);
    output.normalizedX = ReadFloat(payload.data() + 8);
    output.normalizedY = ReadFloat(payload.data() + 12);
    output.pressure = ReadFloat(payload.data() + 16);
    output.altitude = ReadFloat(payload.data() + 20);
    output.azimuth = ReadFloat(payload.data() + 24);
    output.barrelRoll = ReadFloat(payload.data() + 28);
    output.timestampMicros = ReadU64(payload.data() + 32);

    if (!IsNormalized(output.normalizedX) ||
        !IsNormalized(output.normalizedY)) {
        error = "DMP input coordinates are outside 0...1";
        return false;
    }

    if (!IsNormalized(output.pressure)) {
        error = "DMP input pressure is outside 0...1";
        return false;
    }

    if (!std::isfinite(output.altitude) ||
        !std::isfinite(output.azimuth) ||
        !std::isfinite(output.barrelRoll)) {
        error = "DMP stylus values must be finite";
        return false;
    }

    error.clear();
    return true;
}

}  // namespace displaymesh
