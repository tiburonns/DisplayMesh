#include "DmpFrame.h"

#include <array>
#include <limits>

namespace displaymesh {
namespace {

constexpr std::array<std::uint8_t, 4> kMagic{'D', 'M', 'P', '1'};

std::uint16_t ReadU16(const std::uint8_t* bytes) {
    return static_cast<std::uint16_t>(
        (static_cast<std::uint16_t>(bytes[0]) << 8) |
        static_cast<std::uint16_t>(bytes[1]));
}

std::uint32_t ReadU32(const std::uint8_t* bytes) {
    return (static_cast<std::uint32_t>(bytes[0]) << 24) |
           (static_cast<std::uint32_t>(bytes[1]) << 16) |
           (static_cast<std::uint32_t>(bytes[2]) << 8) |
           static_cast<std::uint32_t>(bytes[3]);
}

void AppendU16(
    std::vector<std::uint8_t>& output,
    std::uint16_t value) {
    output.push_back(static_cast<std::uint8_t>(value >> 8));
    output.push_back(static_cast<std::uint8_t>(value));
}

void AppendU32(
    std::vector<std::uint8_t>& output,
    std::uint32_t value) {
    output.push_back(static_cast<std::uint8_t>(value >> 24));
    output.push_back(static_cast<std::uint8_t>(value >> 16));
    output.push_back(static_cast<std::uint8_t>(value >> 8));
    output.push_back(static_cast<std::uint8_t>(value));
}

bool ParseMessageType(
    std::uint8_t raw,
    DmpMessageType& type) {
    switch (raw) {
    case 0x01: type = DmpMessageType::Hello; return true;
    case 0x02: type = DmpMessageType::Capabilities; return true;
    case 0x03: type = DmpMessageType::PanelDescriptor; return true;
    case 0x04: type = DmpMessageType::Pairing; return true;
    case 0x10: type = DmpMessageType::Video; return true;
    case 0x20: type = DmpMessageType::Input; return true;
    case 0x30: type = DmpMessageType::Telemetry; return true;
    case 0x31: type = DmpMessageType::KeyframeRequest; return true;
    case 0x7F: type = DmpMessageType::Error; return true;
    default: return false;
    }
}

}  // namespace

std::size_t MaximumPayloadSize(DmpMessageType type) {
    switch (type) {
    case DmpMessageType::Hello: return 4U * 1024U;
    case DmpMessageType::Capabilities: return 64U * 1024U;
    case DmpMessageType::PanelDescriptor: return 16U * 1024U;
    case DmpMessageType::Pairing: return 16U * 1024U;
    case DmpMessageType::Video: return kDmpMaximumPayloadSize;
    case DmpMessageType::Input: return 40U;
    case DmpMessageType::Telemetry: return 16U * 1024U;
    case DmpMessageType::KeyframeRequest: return 0U;
    case DmpMessageType::Error: return 8U * 1024U;
    }
    return 0;
}

bool ValidatePayloadSize(
    DmpMessageType type,
    std::size_t size,
    std::string& error) {
    if (type == DmpMessageType::Input && size != 40U) {
        error = "DMP input payload must be exactly 40 bytes";
        return false;
    }

    if (type == DmpMessageType::KeyframeRequest && size != 0U) {
        error = "DMP keyframe request payload must be empty";
        return false;
    }

    const auto maximum = MaximumPayloadSize(type);
    if (size > maximum) {
        error = "DMP payload exceeds the message-specific limit";
        return false;
    }

    error.clear();
    return true;
}

DmpDecodeStatus DecodeDmpFrame(
    std::span<const std::uint8_t> buffer,
    DmpFrame& output,
    std::size_t& consumed,
    std::string& error) {
    consumed = 0;

    if (buffer.size() < kDmpHeaderSize) {
        error.clear();
        return DmpDecodeStatus::NeedMoreData;
    }

    for (std::size_t index = 0; index < kMagic.size(); ++index) {
        if (buffer[index] != kMagic[index]) {
            error = "invalid DMP frame magic";
            return DmpDecodeStatus::Error;
        }
    }

    if (buffer[4] != kDmpVersion) {
        error = "unsupported DMP frame version";
        return DmpDecodeStatus::Error;
    }

    DmpMessageType type{};
    if (!ParseMessageType(buffer[5], type)) {
        error = "unsupported DMP message type";
        return DmpDecodeStatus::Error;
    }

    const auto payloadSize =
        static_cast<std::size_t>(ReadU32(buffer.data() + 12));

    if (payloadSize > kDmpMaximumPayloadSize ||
        !ValidatePayloadSize(type, payloadSize, error)) {
        if (error.empty()) {
            error = "DMP payload exceeds the global limit";
        }
        return DmpDecodeStatus::Error;
    }

    const auto totalSize = kDmpHeaderSize + payloadSize;
    if (buffer.size() < totalSize) {
        error.clear();
        return DmpDecodeStatus::NeedMoreData;
    }

    output.type = type;
    output.flags = ReadU16(buffer.data() + 6);
    output.sequence = ReadU32(buffer.data() + 8);
    output.payload.assign(
        buffer.begin() + static_cast<std::ptrdiff_t>(kDmpHeaderSize),
        buffer.begin() + static_cast<std::ptrdiff_t>(totalSize));
    consumed = totalSize;
    error.clear();
    return DmpDecodeStatus::Complete;
}

bool EncodeDmpFrame(
    const DmpFrame& frame,
    std::vector<std::uint8_t>& output,
    std::string& error) {
    if (frame.payload.size() > kDmpMaximumPayloadSize ||
        !ValidatePayloadSize(frame.type, frame.payload.size(), error)) {
        if (error.empty()) {
            error = "DMP payload exceeds the global limit";
        }
        return false;
    }

    output.clear();
    output.reserve(kDmpHeaderSize + frame.payload.size());
    output.insert(output.end(), kMagic.begin(), kMagic.end());
    output.push_back(kDmpVersion);
    output.push_back(static_cast<std::uint8_t>(frame.type));
    AppendU16(output, frame.flags);
    AppendU32(output, frame.sequence);
    AppendU32(
        output,
        static_cast<std::uint32_t>(frame.payload.size()));
    output.insert(
        output.end(),
        frame.payload.begin(),
        frame.payload.end());
    error.clear();
    return true;
}

bool DmpSequenceTracker::Accept(
    std::uint32_t sequence,
    std::string& error) {
    if (sequence != expected_) {
        error = "unexpected DMP frame sequence";
        return false;
    }

    expected_ =
        expected_ == std::numeric_limits<std::uint32_t>::max()
        ? 0U
        : expected_ + 1U;
    error.clear();
    return true;
}

void DmpSequenceTracker::Reset() noexcept {
    expected_ = 1;
}

std::uint32_t DmpSequenceTracker::Expected() const noexcept {
    return expected_;
}

}  // namespace displaymesh
