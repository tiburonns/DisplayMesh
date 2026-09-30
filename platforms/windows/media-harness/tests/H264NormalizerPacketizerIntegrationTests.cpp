#include "H264AccessUnitNormalizer.h"
#include "H264AnnexBPacketizer.h"

#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using namespace displaymesh::media;

int main() {
    H264AccessUnitNormalizer normalizer;
    H264AnnexBPacketizer packetizer;
    H264NormalizeReport normalizeReport;
    H264PacketizeReport packetizeReport;
    std::vector<std::uint8_t> normalized;
    std::vector<std::uint8_t> dmpVideoPayload;
    std::string error;

    // AVC length-prefixed SPS + PPS initializes the packetizer cache.
    const std::vector<std::uint8_t> parameterSets{
        0x00, 0x00, 0x00, 0x04,
        0x67, 0x64, 0x00, 0x1f,
        0x00, 0x00, 0x00, 0x04,
        0x68, 0xee, 0x3c, 0x80,
    };

    assert(normalizer.Normalize(
        parameterSets,
        normalized,
        normalizeReport,
        error));
    assert(normalizeReport.inputFormat ==
        H264AccessUnitFormat::AvccLengthPrefixed);

    assert(packetizer.Packetize(
        normalized,
        1,
        16'667,
        dmpVideoPayload,
        packetizeReport,
        error));

    // A later AVC length-prefixed IDR without SPS/PPS must recover using
    // the cached parameter sets and produce a valid DMP video payload.
    const std::vector<std::uint8_t> idr{
        0x00, 0x00, 0x00, 0x03,
        0x65, 0x88, 0x84,
    };

    assert(normalizer.Normalize(
        idr,
        normalized,
        normalizeReport,
        error));
    assert(packetizer.Packetize(
        normalized,
        2,
        16'667,
        dmpVideoPayload,
        packetizeReport,
        error));

    assert(packetizeReport.keyframe);
    assert(packetizeReport.insertedSps);
    assert(packetizeReport.insertedPps);
    assert(dmpVideoPayload.size() > 16);
    assert(dmpVideoPayload[0] == 0x01);
    assert(dmpVideoPayload[1] == 0x01);

    return 0;
}
