#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace displaymesh::media {

struct H264PacketizeReport {
    bool keyframe{};
    bool insertedSps{};
    bool insertedPps{};
    std::uint32_t nalUnitCount{};
};

class H264AnnexBPacketizer {
public:
    bool Packetize(
        std::span<const std::uint8_t> annexB,
        std::uint64_t presentationTimeMicros,
        std::uint32_t durationMicros,
        std::vector<std::uint8_t>& dmpVideoPayload,
        H264PacketizeReport& report,
        std::string& error);

    void Reset() noexcept;

private:
    std::vector<std::uint8_t> sps_;
    std::vector<std::uint8_t> pps_;
};

}  // namespace displaymesh::media
