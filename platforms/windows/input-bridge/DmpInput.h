#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>

namespace displaymesh {

constexpr std::size_t kDmpInputSampleSize = 40;
constexpr std::uint8_t kDmpInputVersion = 1;

enum class InputKind : std::uint8_t {
    Touch = 1,
    Pencil = 2,
};

enum class InputPhase : std::uint8_t {
    Began = 1,
    Moved = 2,
    Ended = 3,
    Cancelled = 4,
    Hover = 5,
};

struct InputSample {
    InputKind kind{};
    InputPhase phase{};
    std::uint8_t flags{};
    std::uint32_t contactId{};
    float normalizedX{};
    float normalizedY{};
    float pressure{};
    float altitude{};
    float azimuth{};
    float barrelRoll{};
    std::uint64_t timestampMicros{};
};

bool DecodeInputSample(
    std::span<const std::uint8_t> payload,
    InputSample& output,
    std::string& error);

}  // namespace displaymesh
