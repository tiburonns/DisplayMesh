#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace displaymesh::media {

enum class H264AccessUnitFormat {
    AnnexB,
    AvccLengthPrefixed,
};

struct H264NormalizeReport {
    H264AccessUnitFormat inputFormat{
        H264AccessUnitFormat::AnnexB};
    std::uint32_t nalUnitCount{};
};

class H264AccessUnitNormalizer {
public:
    bool Normalize(
        std::span<const std::uint8_t> input,
        std::vector<std::uint8_t>& annexB,
        H264NormalizeReport& report,
        std::string& error) const;
};

}  // namespace displaymesh::media
