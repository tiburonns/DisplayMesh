#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace displaymesh {

constexpr std::size_t kDmpHeaderSize = 16;
constexpr std::size_t kDmpMaximumPayloadSize = 16U * 1024U * 1024U;
constexpr std::uint8_t kDmpVersion = 1;

enum class DmpMessageType : std::uint8_t {
    Hello = 0x01,
    Capabilities = 0x02,
    PanelDescriptor = 0x03,
    Pairing = 0x04,
    Video = 0x10,
    Input = 0x20,
    Telemetry = 0x30,
    KeyframeRequest = 0x31,
    Error = 0x7F,
};

struct DmpFrame {
    DmpMessageType type{};
    std::uint16_t flags{};
    std::uint32_t sequence{};
    std::vector<std::uint8_t> payload;
};

enum class DmpDecodeStatus {
    Complete,
    NeedMoreData,
    Error,
};

std::size_t MaximumPayloadSize(DmpMessageType type);
bool ValidatePayloadSize(
    DmpMessageType type,
    std::size_t size,
    std::string& error);

DmpDecodeStatus DecodeDmpFrame(
    std::span<const std::uint8_t> buffer,
    DmpFrame& output,
    std::size_t& consumed,
    std::string& error);

bool EncodeDmpFrame(
    const DmpFrame& frame,
    std::vector<std::uint8_t>& output,
    std::string& error);

class DmpSequenceTracker {
public:
    bool Accept(std::uint32_t sequence, std::string& error);
    void Reset() noexcept;
    std::uint32_t Expected() const noexcept;

private:
    std::uint32_t expected_{1};
};

}  // namespace displaymesh
