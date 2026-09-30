#pragma once

#define NOMINMAX
#include <Windows.h>
#include <mfidl.h>

#include "H264AccessUnitNormalizer.h"
#include "H264AnnexBPacketizer.h"

#include <string>
#include <vector>

namespace displaymesh::media {

class MftEncodedSampleProcessor {
public:
    HRESULT Process(
        IMFSample* sample,
        std::vector<std::uint8_t>& dmpVideoPayload,
        H264NormalizeReport& normalizeReport,
        H264PacketizeReport& packetizeReport,
        std::string& error) noexcept;

    void Reset() noexcept;

private:
    H264AccessUnitNormalizer normalizer_;
    H264AnnexBPacketizer packetizer_;
};

}  // namespace displaymesh::media
